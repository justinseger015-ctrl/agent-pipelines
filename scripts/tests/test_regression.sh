#!/bin/bash
# Regression tests for v3 migration
# Verifies all stages use v3 schema and prompts use new variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"

LOOPS_DIR="$SCRIPT_DIR/loops"

#-------------------------------------------------------------------------------
# Stage Definition Tests (v3 schema)
#-------------------------------------------------------------------------------

test_work_stage_v3_schema() {
  local config=$(yaml_to_json "$LOOPS_DIR/work/loop.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  assert_eq "queue" "$term_type" "work stage uses termination.type=queue"
}

test_improve_plan_stage_v3_schema() {
  local config=$(yaml_to_json "$LOOPS_DIR/improve-plan/loop.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "improve-plan uses termination.type=judgment"
  assert_eq "2" "$consensus" "improve-plan requires consensus=2"
}

test_elegance_stage_v3_schema() {
  local config=$(yaml_to_json "$LOOPS_DIR/elegance/loop.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "elegance uses termination.type=judgment"
  assert_eq "2" "$consensus" "elegance requires consensus=2"
}

test_idea_wizard_stage_v3_schema() {
  local config=$(yaml_to_json "$LOOPS_DIR/idea-wizard/loop.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  assert_eq "fixed" "$term_type" "idea-wizard uses termination.type=fixed"
}

test_refine_beads_stage_v3_schema() {
  local config=$(yaml_to_json "$LOOPS_DIR/refine-beads/loop.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "refine-beads uses termination.type=judgment"
  assert_eq "2" "$consensus" "refine-beads requires consensus=2"
}

#-------------------------------------------------------------------------------
# Prompt Variable Tests (v3 variables)
#-------------------------------------------------------------------------------

test_prompts_use_ctx_variable() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local prompt_file="$loop_dir/prompt.md"
    [ -f "$prompt_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local content=$(cat "$prompt_file")
    assert_contains "$content" '${CTX}' "$loop_name prompt uses \${CTX}"
  done
}

test_prompts_use_status_variable() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local prompt_file="$loop_dir/prompt.md"
    [ -f "$prompt_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local content=$(cat "$prompt_file")
    assert_contains "$content" '${STATUS}' "$loop_name prompt uses \${STATUS}"
  done
}

test_no_deprecated_output_parse() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local config_file="$loop_dir/loop.yaml"
    [ -f "$config_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local content=$(cat "$config_file")
    assert_not_contains "$content" "output_parse" "$loop_name has no deprecated output_parse"
  done
}

test_no_deprecated_completion_field() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local config_file="$loop_dir/loop.yaml"
    [ -f "$config_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local config=$(yaml_to_json "$config_file")
    local old_completion=$(echo "$config" | jq -r '.completion // empty')
    # Old completion field should be empty (v3 uses termination block)
    assert_eq "" "$old_completion" "$loop_name has no deprecated completion field"
  done
}

#-------------------------------------------------------------------------------
# Deprecated Code Removal Tests
#-------------------------------------------------------------------------------

test_parse_sh_marked_deprecated() {
  local parse_file="$SCRIPT_DIR/lib/parse.sh"
  if [ -f "$parse_file" ]; then
    local content=$(cat "$parse_file")
    assert_contains "$content" "DEPRECATED" "parse.sh is marked as deprecated"
  else
    skip_test "parse.sh does not exist (already removed)"
  fi
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "work stage v3 schema" test_work_stage_v3_schema
run_test "improve-plan stage v3 schema" test_improve_plan_stage_v3_schema
run_test "elegance stage v3 schema" test_elegance_stage_v3_schema
run_test "idea-wizard stage v3 schema" test_idea_wizard_stage_v3_schema
run_test "refine-beads stage v3 schema" test_refine_beads_stage_v3_schema
run_test "Prompts use CTX variable" test_prompts_use_ctx_variable
run_test "Prompts use STATUS variable" test_prompts_use_status_variable
run_test "No deprecated output_parse" test_no_deprecated_output_parse
run_test "No deprecated completion field" test_no_deprecated_completion_field
run_test "parse.sh marked deprecated" test_parse_sh_marked_deprecated

test_summary
