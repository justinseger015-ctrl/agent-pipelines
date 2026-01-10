#!/bin/bash
set -e

# Pipeline Orchestrator - Run multi-stage pipelines
# Usage: run.sh <pipeline.yaml> [session_name]
#
# Executes pipelines defined in YAML format:
# - Parses pipeline definition
# - Runs each stage sequentially
# - Passes data between stages via ${INPUTS.stage-name}
# - Supports completion strategies (plateau, fixed runs)

PIPELINE_FILE=${1:?"Usage: run.sh <pipeline.yaml> [session_name]"}

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
LOOPS_DIR="$SCRIPT_DIR/../loops"

# Check dependencies
for cmd in jq claude; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Missing required command: $cmd" >&2
    case "$cmd" in
      jq) echo "  Install: brew install jq" >&2 ;;
      claude) echo "  Install: npm install -g @anthropic-ai/claude-code" >&2 ;;
    esac
    exit 1
  fi
done

# Check for YAML parser (yq or python3 with PyYAML)
if ! command -v yq &>/dev/null; then
  if ! python3 -c "import yaml" &>/dev/null 2>&1; then
    echo "Error: Need yq or python3 with PyYAML for YAML parsing" >&2
    echo "  Install yq: brew install yq" >&2
    echo "  Or install PyYAML: pip3 install pyyaml" >&2
    exit 1
  fi
fi

# Resolve pipeline file path
if [ ! -f "$PIPELINE_FILE" ]; then
  if [ -f ".claude/pipelines/${PIPELINE_FILE}" ]; then
    PIPELINE_FILE=".claude/pipelines/${PIPELINE_FILE}"
  elif [ -f ".claude/pipelines/${PIPELINE_FILE}.yaml" ]; then
    PIPELINE_FILE=".claude/pipelines/${PIPELINE_FILE}.yaml"
  else
    echo "Error: Pipeline not found: $PIPELINE_FILE" >&2
    exit 1
  fi
fi

# Source libraries
source "$SCRIPT_DIR/lib/parse.sh"
source "$SCRIPT_DIR/lib/resolve.sh"
source "$SCRIPT_DIR/lib/providers.sh"

# Parse pipeline
parse_pipeline "$PIPELINE_FILE"

# Generate session name if not provided
PIPELINE_NAME=$(get_pipeline_value "name")
SESSION_NAME=${2:-"${PIPELINE_NAME}-$(date +%Y%m%d-%H%M%S)"}

# Set up run directory
RUN_DIR="$PROJECT_ROOT/.claude/pipeline-runs/$SESSION_NAME"
mkdir -p "$RUN_DIR"

# Copy pipeline definition for reference
cp "$PIPELINE_FILE" "$RUN_DIR/pipeline.yaml"

# Initialize state
STATE_FILE="$RUN_DIR/state.json"
jq -n --arg pipeline "$PIPELINE_NAME" --arg session "$SESSION_NAME" --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{pipeline: $pipeline, session: $session, started_at: $started, status: "running", current_stage: 0, stages: []}' \
  > "$STATE_FILE"

# Export for variable resolution
export PROJECT_ROOT SESSION_NAME RUN_DIR

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Pipeline Orchestrator                                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Pipeline: $PIPELINE_NAME"
echo "║  Session:  $SESSION_NAME"
echo "║  Run dir:  $RUN_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get defaults
DEFAULT_MODEL=$(get_pipeline_value "defaults.model" "sonnet")
DEFAULT_PROVIDER=$(get_pipeline_value "defaults.provider" "claude-code")

# Execute each stage
STAGE_COUNT=$(get_stage_count)

for stage_idx in $(seq 0 $((STAGE_COUNT - 1))); do
  STAGE_NAME=$(get_stage_value "$stage_idx" "name")
  STAGE_RUNS=$(get_stage_value "$stage_idx" "runs" "1")
  STAGE_MODEL=$(get_stage_value "$stage_idx" "model" "$DEFAULT_MODEL")
  STAGE_PROVIDER=$(get_stage_value "$stage_idx" "provider" "$DEFAULT_PROVIDER")
  STAGE_COMPLETION=$(get_stage_value "$stage_idx" "completion" "")
  STAGE_DESC=$(get_stage_value "$stage_idx" "description" "")
  STAGE_PARALLEL=$(get_stage_value "$stage_idx" "parallel" "false")
  STAGE_LOOP=$(get_stage_value "$stage_idx" "loop" "")

  # If using a loop type, load its config and prompt
  USING_LOOP=""
  if [ -n "$STAGE_LOOP" ]; then
    if load_loop_type "$STAGE_LOOP"; then
      USING_LOOP="$STAGE_LOOP"
      # Inherit completion strategy from loop if not specified
      [ -z "$STAGE_COMPLETION" ] && [ -n "$LOOP_COMPLETION" ] && STAGE_COMPLETION="$LOOP_COMPLETION"
      # Inherit model from loop if not specified in stage or defaults
      [ "$STAGE_MODEL" = "$DEFAULT_MODEL" ] && [ -n "$LOOP_MODEL" ] && STAGE_MODEL="$LOOP_MODEL"
    else
      echo "Error: Failed to load loop type: $STAGE_LOOP" >&2
      exit 1
    fi
  fi

  # Create stage output directory
  STAGE_DIR="$RUN_DIR/stage-$((stage_idx + 1))-$STAGE_NAME"
  mkdir -p "$STAGE_DIR"

  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ Stage $((stage_idx + 1))/$STAGE_COUNT: $STAGE_NAME"
  [ -n "$STAGE_DESC" ] && echo "│ $STAGE_DESC"
  [ -n "$USING_LOOP" ] && echo "│ Loop: $USING_LOOP"
  echo "│ Runs: $STAGE_RUNS | Model: $STAGE_MODEL"
  [ -n "$STAGE_COMPLETION" ] && echo "│ Completion: $STAGE_COMPLETION"
  [ "$STAGE_PARALLEL" = "true" ] && echo "│ ⚠️  parallel: true not yet implemented (runs sequentially)"
  echo "└──────────────────────────────────────────────────────────────"
  echo ""

  # Update state
  update_state_stage "$STATE_FILE" "$stage_idx" "$STAGE_NAME" "running"

  # Get prompt template - from loop or inline
  if [ -n "$USING_LOOP" ]; then
    PROMPT_TEMPLATE="$LOOP_PROMPT"
  else
    PROMPT_TEMPLATE=$(get_stage_prompt "$stage_idx")
  fi
  PERSPECTIVES=$(get_stage_array "$stage_idx" "perspectives")
  PROGRESS_FILE="$STAGE_DIR/progress.md"

  # Run iterations
  for run_idx in $(seq 0 $((STAGE_RUNS - 1))); do
    echo "  Iteration $((run_idx + 1))/$STAGE_RUNS..."

    # Determine output file
    if [ "$STAGE_RUNS" -eq 1 ]; then
      OUTPUT_FILE="$STAGE_DIR/output.md"
    else
      OUTPUT_FILE="$STAGE_DIR/run-$run_idx.md"
    fi

    # Get perspective for this run
    PERSPECTIVE=$(get_array_item "$PERSPECTIVES" "$run_idx")

    # Resolve all variables in prompt
    RESOLVED_PROMPT=$(resolve_prompt "$PROMPT_TEMPLATE" "$stage_idx" "$run_idx" "$PERSPECTIVE" "$OUTPUT_FILE" "$PROGRESS_FILE")

    # Execute via provider
    OUTPUT=$(execute_prompt "$RESOLVED_PROMPT" "$STAGE_PROVIDER" "$STAGE_MODEL" "$OUTPUT_FILE") || true

    # Check completion strategy
    if [ -n "$STAGE_COMPLETION" ]; then
      if check_stage_completion "$STAGE_COMPLETION" "$OUTPUT" "$STAGE_DIR" "$run_idx"; then
        echo "  ✓ Completion condition met after $((run_idx + 1)) iterations"
        break
      fi
    fi

    # Brief pause between iterations
    [ "$run_idx" -lt "$((STAGE_RUNS - 1))" ] && sleep 2
  done

  # Update state
  update_state_stage "$STATE_FILE" "$stage_idx" "$STAGE_NAME" "complete"

  echo ""
done

# Mark pipeline complete
jq --arg completed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.status = "complete" | .completed_at = $completed' \
  "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PIPELINE COMPLETE                                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Pipeline: $PIPELINE_NAME"
echo "║  Session:  $SESSION_NAME"
echo "║  Stages:   $STAGE_COUNT"
echo "║  Output:   $RUN_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
