#!/bin/bash
# Parallel Block Execution for Agent Pipelines
#
# Provides functions for running parallel blocks with multiple providers.
# Each provider runs stages sequentially in isolation, providers run concurrently.
#
# Functions:
#   run_parallel_provider - Run stages for a single provider (called in subshell)
#   run_parallel_block - Orchestrate parallel providers, wait, build manifest
#
# Dependencies: state.sh, context.sh, provider.sh, status.sh, resolve.sh, progress.sh

#-------------------------------------------------------------------------------
# Parallel Provider Execution
#-------------------------------------------------------------------------------

# Run stages sequentially for a single provider within a parallel block
# Called in a subshell, one per provider
# Usage: run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults_json"
# Returns: 0 on success, 1 on failure
run_parallel_provider() {
  local provider=$1
  local block_dir=$2
  local stages_json=$3
  local session=$4
  local defaults_json=$5

  local provider_dir="$block_dir/providers/$provider"
  local provider_state="$provider_dir/state.json"

  # Mark provider as running
  jq '.status = "running"' "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"

  local stage_count=$(echo "$stages_json" | jq 'length')
  local default_model=$(echo "$defaults_json" | jq -r '.model // "opus"')

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    local stage_config=$(echo "$stages_json" | jq ".[$stage_idx]")
    local stage_name=$(echo "$stage_config" | jq -r '.name')
    local stage_type=$(echo "$stage_config" | jq -r '.stage // empty')
    local stage_model=$(echo "$stage_config" | jq -r ".model // \"$default_model\"")

    # Get termination config
    local term_type=$(echo "$stage_config" | jq -r '.termination.type // "fixed"')
    local max_iters=$(echo "$stage_config" | jq -r '.termination.iterations // .termination.max // 1')
    local consensus=$(echo "$stage_config" | jq -r '.termination.consensus // 2')
    local min_iters=$(echo "$stage_config" | jq -r '.termination.min_iterations // 1')

    # Create stage directory
    local stage_dir="$provider_dir/stage-$(printf '%02d' $stage_idx)-$stage_name"
    mkdir -p "$stage_dir"

    # Load stage definition if specified
    local stage_prompt=""
    if [ -n "$stage_type" ] && type load_stage &>/dev/null; then
      load_stage "$stage_type" || return 1
      stage_prompt="$STAGE_PROMPT"
    fi

    # Initialize progress for this stage
    local progress_file="$provider_dir/progress.md"

    # Source completion strategy
    local completion_script=""
    case "$term_type" in
      queue) completion_script="${LIB_DIR:-scripts/lib}/completions/beads-empty.sh" ;;
      judgment) completion_script="${LIB_DIR:-scripts/lib}/completions/plateau.sh" ;;
      fixed) completion_script="${LIB_DIR:-scripts/lib}/completions/fixed-n.sh" ;;
    esac
    [ -f "$completion_script" ] && source "$completion_script"

    # Export for completion checks
    export MIN_ITERATIONS="$min_iters"
    export CONSENSUS="$consensus"
    export MAX_ITERATIONS="$max_iters"

    # Track stage history for plateau detection
    local stage_history="[]"

    for iter in $(seq 1 $max_iters); do
      local iter_dir="$stage_dir/iterations/$(printf '%03d' $iter)"
      mkdir -p "$iter_dir"

      # Build stage config for context generation with parallel_scope
      local ctx_config=$(jq -n \
        --arg id "$stage_name" \
        --arg name "$stage_name" \
        --argjson index "$stage_idx" \
        --arg loop "$stage_type" \
        --argjson max_iterations "$max_iters" \
        --arg scope_root "$provider_dir" \
        --arg pipeline_root "$(dirname "$(dirname "$block_dir")")" \
        '{
          id: $id,
          name: $name,
          index: $index,
          loop: $loop,
          max_iterations: $max_iterations,
          parallel_scope: {
            scope_root: $scope_root,
            pipeline_root: $pipeline_root
          }
        }')

      # Generate context.json
      local context_file
      if type generate_context &>/dev/null; then
        context_file=$(generate_context "$session" "$iter" "$ctx_config" "$provider_dir")
      else
        # Fallback: create basic context file
        context_file="$iter_dir/context.json"
        echo "$ctx_config" > "$context_file"
      fi
      local status_file="$iter_dir/status.json"

      # Build variables for prompt resolution
      local vars_json=$(jq -n \
        --arg session "$session" \
        --arg iteration "$iter" \
        --arg index "$((iter - 1))" \
        --arg progress "$progress_file" \
        --arg context_file "$context_file" \
        --arg status_file "$status_file" \
        '{session: $session, iteration: $iteration, index: $index, progress: $progress, context_file: $context_file, status_file: $status_file}')

      # Resolve prompt
      local resolved_prompt=""
      if [ -n "$stage_prompt" ] && type resolve_prompt &>/dev/null; then
        resolved_prompt=$(resolve_prompt "$stage_prompt" "$vars_json")
      else
        resolved_prompt="$stage_prompt"
      fi

      # Update provider state
      jq --argjson iter "$iter" --arg stage "$stage_name" \
        '.iteration = $iter | .current_stage_name = $stage' \
        "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"

      # Export status file path for mock mode
      export MOCK_STATUS_FILE="$status_file"
      export MOCK_ITERATION="$iter"
      export MOCK_PROVIDER="$provider"

      # Execute agent
      local output=""
      local exit_code=0
      set +e
      if type execute_agent &>/dev/null; then
        output=$(execute_agent "$provider" "$resolved_prompt" "$stage_model")
        exit_code=$?
      else
        # Mock mode fallback for testing
        output="Mock output for $provider $stage_name iteration $iter"
        exit_code=0
      fi
      set -e

      if [ $exit_code -ne 0 ]; then
        jq --arg err "Exit code $exit_code" '.status = "failed" | .error = $err' \
          "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"
        return 1
      fi

      # Save output
      [ -n "$output" ] && echo "$output" > "$iter_dir/output.md"

      # Create default status if not written
      if [ ! -f "$status_file" ]; then
        if type create_error_status &>/dev/null; then
          create_error_status "$status_file" "Agent did not write status.json"
        else
          # Fallback: create default continue status
          echo '{"decision": "continue", "reason": "default", "summary": "mock iteration"}' > "$status_file"
        fi
      fi

      # Validate status
      if type validate_status &>/dev/null && ! validate_status "$status_file"; then
        create_error_status "$status_file" "Agent wrote invalid status.json"
      fi

      # Extract status for history and completion check
      local history_entry
      if type status_to_history_json &>/dev/null; then
        history_entry=$(status_to_history_json "$status_file")
      else
        history_entry=$(jq -c '{decision: .decision, reason: .reason}' "$status_file" 2>/dev/null || echo '{"decision":"continue"}')
      fi
      stage_history=$(echo "$stage_history" | jq --argjson entry "$history_entry" '. + [$entry]')

      # Update provider state iteration completed
      jq --argjson iter "$iter" '.iteration_completed = $iter' \
        "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"

      # Check completion (for judgment/plateau termination)
      if [ "$term_type" = "judgment" ]; then
        # Filter history for this stage only and check plateau
        local stage_history_count=$(echo "$stage_history" | jq 'length')
        if [ "$stage_history_count" -ge "$min_iters" ]; then
          local stop_count=$(echo "$stage_history" | jq '[.[] | select(.decision == "stop")] | length')
          local recent_stops=$(echo "$stage_history" | jq --argjson n "$consensus" '.[-($n):] | [.[] | select(.decision == "stop")] | length')
          if [ "$recent_stops" -ge "$consensus" ]; then
            break  # Plateau reached
          fi
        fi
      fi
    done

    # Record stage completion in provider state
    local term_reason="max_iterations"
    if [ "$term_type" = "judgment" ]; then
      local recent_stops=$(echo "$stage_history" | jq --argjson n "$consensus" '.[-($n):] | [.[] | select(.decision == "stop")] | length')
      [ "$recent_stops" -ge "$consensus" ] && term_reason="plateau"
    elif [ "$term_type" = "fixed" ]; then
      term_reason="fixed"
    fi

    local final_iter=$(jq -r '.iteration_completed // 0' "$provider_state")
    jq --arg name "$stage_name" --argjson iters "$final_iter" --arg reason "$term_reason" \
      '.stages += [{"name": $name, "iterations": $iters, "termination_reason": $reason}]' \
      "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"

    # Reset iteration counters for next stage
    jq '.iteration = 0 | .iteration_completed = 0' \
      "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"
  done

  # Mark provider complete
  jq '.status = "complete"' "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"

  return 0
}

#-------------------------------------------------------------------------------
# Parallel Block Orchestration
#-------------------------------------------------------------------------------

# Run a parallel block: spawn providers, wait for all, build manifest
# Usage: run_parallel_block "$stage_idx" "$block_config" "$defaults" "$state_file" "$run_dir" "$session"
# Returns: 0 on success, 1 on any provider failure
run_parallel_block() {
  local stage_idx=$1
  local block_config=$2
  local defaults=$3
  local state_file=$4
  local run_dir=$5
  local session=$6

  # Parse block config
  local block_name=$(echo "$block_config" | jq -r '.name // empty')
  local providers=$(echo "$block_config" | jq -r '.parallel.providers | join(" ")')
  local stages_json=$(echo "$block_config" | jq -c '.parallel.stages')
  local stage_names=$(echo "$stages_json" | jq -r '.[].name' | tr '\n' ' ')

  # Initialize block directory
  local block_dir
  if type init_parallel_block &>/dev/null; then
    block_dir=$(init_parallel_block "$run_dir" "$stage_idx" "$block_name" "$providers")
  else
    # Fallback: create manually
    local idx_fmt=$(printf '%02d' "$stage_idx")
    local block_dir_name="parallel-${idx_fmt}-${block_name:-block}"
    block_dir="$run_dir/$block_dir_name"
    mkdir -p "$block_dir"
    for p in $providers; do
      mkdir -p "$block_dir/providers/$p"
    done
  fi

  # Initialize provider states
  for provider in $providers; do
    if type init_provider_state &>/dev/null; then
      init_provider_state "$block_dir" "$provider" "$session"
    else
      # Fallback: create basic state
      mkdir -p "$block_dir/providers/$provider"
      echo '{"status": "pending", "stages": [], "iteration": 0, "iteration_completed": 0}' > "$block_dir/providers/$provider/state.json"
      echo "# Progress: $session ($provider)" > "$block_dir/providers/$provider/progress.md"
    fi
  done

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "running"
  fi

  echo ""
  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ Parallel Block: ${block_name:-parallel-$stage_idx}"
  echo "│ Providers: $providers"
  echo "│ Stages: $stage_names"
  echo "└──────────────────────────────────────────────────────────────"
  echo ""

  # Track provider PIDs for parallel execution
  declare -A provider_pids
  local any_failed=false

  # Spawn subshell for each provider
  for provider in $providers; do
    (
      # Export necessary functions and vars for subshell
      export MOCK_MODE MOCK_FIXTURES_DIR STAGES_DIR LIB_DIR PROJECT_ROOT
      # Run provider stages sequentially
      run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults"
    ) &
    provider_pids[$provider]=$!
    echo "  Started $provider (PID ${provider_pids[$provider]})"
  done

  # Wait for all providers
  local failed_providers=""
  for provider in $providers; do
    local pid=${provider_pids[$provider]}
    if ! wait "$pid"; then
      any_failed=true
      failed_providers="$failed_providers $provider"
      echo "  ✗ $provider failed"
    else
      echo "  ✓ $provider complete"
    fi
  done

  # Handle failure
  if [ "$any_failed" = true ]; then
    echo ""
    echo "  Parallel block failed. Failed providers:$failed_providers"
    if type update_stage &>/dev/null; then
      update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "failed"
    fi
    return 1
  fi

  # Build manifest on success
  if type write_parallel_manifest &>/dev/null; then
    write_parallel_manifest "$block_dir" "${block_name:-parallel}" "$stage_idx" "$stage_names" "$providers"
  fi

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "complete"
  fi

  echo ""
  echo "  Parallel block complete. Manifest written to $block_dir/manifest.json"

  return 0
}

# Export functions for use in subshells
export -f run_parallel_provider run_parallel_block 2>/dev/null || true
