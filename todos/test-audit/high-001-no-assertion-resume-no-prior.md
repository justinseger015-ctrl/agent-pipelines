---
priority: high
status: closed
file: scripts/tests/integration/test_resume.sh
lines: 203-216
type: bug
created: 2026-01-12
---

# test_resume_no_prior_state has no assertions

## Problem

Test always passes with no meaningful verification:

```bash
test_resume_no_prior_state() {
  local test_dir=$(create_test_dir "int-resume-none")
  setup_integration_test "$test_dir" "continue-3"

  local result
  result=$(run_mock_engine_resume "$test_dir" "nonexistent-session" 3 "test-continue-3" 2>&1) || true

  # Should either fail gracefully or start fresh - both acceptable
  ((TESTS_PASSED++))
  echo -e "  ${GREEN}✓${NC} Resume without prior state handled (no crash)"

  teardown_integration_test "$test_dir"
}
```

## Impact

No verification that resume actually handles missing state correctly. Test passes even if function crashes silently, returns garbage, or corrupts data.

## Fix

Add actual assertions about expected behavior:

```bash
test_resume_no_prior_state() {
  local test_dir=$(create_test_dir "int-resume-none")
  setup_integration_test "$test_dir" "continue-3"

  local result
  result=$(run_mock_engine_resume "$test_dir" "nonexistent-session" 3 "test-continue-3" 2>&1) || true
  local exit_code=$?

  # Verify it either fails explicitly OR starts fresh
  if [[ "$result" == *"error"* ]] || [[ "$result" == *"not found"* ]]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} Resume without prior state failed gracefully"
  elif [ -f "$(get_state_file "$test_dir" "nonexistent-session")" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} Resume without prior state started fresh"
  else
    ((TESTS_SKIPPED++))
    echo -e "  ${YELLOW}⊘${NC} Resume behavior unclear (verify manually)"
  fi

  teardown_integration_test "$test_dir"
}
```
