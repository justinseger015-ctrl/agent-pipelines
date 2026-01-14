#!/bin/bash
# Tests for engine prompt resolution
# Ensures stages that specify nested prompt paths (e.g., prompts/custom.md)
# can be executed without crashing the engine.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/mock.sh"

#-------------------------------------------------------------------------------
# Test: Stage with nested prompt path runs successfully
#-------------------------------------------------------------------------------
test_stage_runs_with_nested_prompt_path() {
  local test_dir
  test_dir=$(create_test_dir "prompt-path")
  local stage_name="prompt-path"
  local stage_dir="$test_dir/stages/$stage_name"
  mkdir -p "$stage_dir/prompts"
  mkdir -p "$stage_dir/fixtures"

  # Stage config references prompts/custom.md
  cat > "$stage_dir/stage.yaml" << 'EOF'
name: prompt-path
description: Stage fixture for prompt resolution tests

termination:
  type: fixed
  iterations: 1

delay: 0
prompt: prompts/custom.md
EOF

  # Custom prompt lives inside prompts/ subdirectory
  cat > "$stage_dir/prompts/custom.md" << 'EOF'
# Prompt Path Test

Iteration: ${ITERATION}
Progress: ${PROGRESS}
EOF

  # Minimal mock fixtures
  cat > "$stage_dir/fixtures/default.txt" << 'EOF'
Mock response for nested prompt path.
EOF

  cat > "$stage_dir/fixtures/status.json" << 'EOF'
{
  "decision": "continue",
  "reason": "Test fixture decision",
  "summary": "Iteration completed"
}
EOF

  enable_mock_mode "$stage_dir/fixtures"

  local session="prompt-path-test"
  (
    export PROJECT_ROOT="$test_dir"
    export STAGES_DIR="$test_dir/stages"
    export MOCK_MODE=true
    "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$stage_name" "$session" 1 >/dev/null
  )
  local exit_code=$?

  assert_eq 0 "$exit_code" "Engine should run stage with nested prompt path"

  local state_file="$test_dir/.claude/pipeline-runs/$session/state.json"
  assert_file_exists "$state_file" "State file should exist after running nested prompt stage"

  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Prompt Resolution Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_test "Stages handle nested prompt paths" test_stage_runs_with_nested_prompt_path

test_summary
