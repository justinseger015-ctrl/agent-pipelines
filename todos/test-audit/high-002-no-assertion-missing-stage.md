---
priority: high
status: closed
file: scripts/tests/integration/test_multi_stage.sh
lines: 252-276
type: bug
created: 2026-01-12
---

# test_multi_stage_handles_missing_stage has no assertions

## Problem

Test always passes with no verification of actual behavior:

```bash
test_multi_stage_handles_missing_stage() {
  # ... setup ...

  local result
  result=$(run_mock_pipeline "$test_dir" "$test_dir/.claude/pipelines/broken.yaml" "test-missing" 2>&1) || true

  # Either it fails explicitly or handles gracefully - both are acceptable
  ((TESTS_PASSED++))
  echo -e "  ${GREEN}✓${NC} Missing stage handled (no crash)"

  teardown_integration_test "$test_dir"
}
```

## Impact

No verification that missing stage is actually detected. Test passes even if:
- Pipeline silently continues with wrong stage
- Error message is unhelpful
- State is left corrupted

## Fix

Add assertions about expected error handling:

```bash
test_multi_stage_handles_missing_stage() {
  # ... setup ...

  local result
  result=$(run_mock_pipeline "$test_dir" "$test_dir/.claude/pipelines/broken.yaml" "test-missing" 2>&1)
  local exit_code=$?

  # Should fail with clear error message
  if [ "$exit_code" -ne 0 ]; then
    if [[ "$result" == *"not found"* ]] || [[ "$result" == *"missing"* ]] || [[ "$result" == *"error"* ]]; then
      ((TESTS_PASSED++))
      echo -e "  ${GREEN}✓${NC} Missing stage detected with clear error"
    else
      ((TESTS_FAILED++))
      echo -e "  ${RED}✗${NC} Missing stage failed but error unclear"
    fi
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} Missing stage should fail, but exit code was 0"
  fi

  teardown_integration_test "$test_dir"
}
```
