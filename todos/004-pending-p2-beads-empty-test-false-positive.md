---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, testing, false-positive]
dependencies: []
---

# beads-empty Test Uses Nonexistent Session (False Positive)

## Problem Statement

The test `test_beads_empty_checks_error_status` in test_completions.sh uses a nonexistent session name to avoid actually calling `bd`. This means it's not testing the real beads-empty logic at all - the test passes regardless of the actual implementation.

**Why it matters:** This test provides false confidence. It could pass even if the error-status check was completely removed from beads-empty.sh.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/tests/test_completions.sh` lines 130-149

**Current (problematic):**
```bash
test_beads_empty_checks_error_status() {
  ...
  # Even if beads are empty, error status should not complete
  # (This test assumes bd is not available or returns empty)
  check_completion "nonexistent-session-xyz" "$state_file" "$status_file" >/dev/null 2>&1
  ...
}
```

**Problem:** Using a nonexistent session means:
1. The `bd ready --label=loop/nonexistent-session-xyz` returns empty (no beads)
2. The test relies on implicit behavior rather than explicit verification
3. If error status check is removed, test still passes (bd returns empty = complete)

## Proposed Solutions

### Solution 1: Mock the bd command (Recommended)

**Pros:** Tests actual logic path, explicit control over inputs
**Cons:** Requires mock infrastructure
**Effort:** Medium
**Risk:** Low

```bash
test_beads_empty_checks_error_status() {
  local tmp=$(create_test_dir)
  local state_file="$tmp/state.json"
  local status_file="$tmp/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "error", "reason": "Test error"}' > "$status_file"

  # Mock bd to return empty (simulating no remaining beads)
  bd() { return 0; }  # No output = empty queue
  export -f bd

  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"
  check_completion "test-session" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset -f bd
  cleanup_test_dir "$tmp"

  assert_eq "1" "$result" "beads-empty should NOT complete when status=error"
}
```

### Solution 2: Add explicit assertion comment

**Pros:** Documents the limitation
**Cons:** Doesn't fix the false positive
**Effort:** Small
**Risk:** None

## Recommended Action

Implement Solution 1 to properly mock the bd command and test the actual error-status check logic.

## Technical Details

**Affected files:**
- `scripts/tests/test_completions.sh` - lines 130-149

## Acceptance Criteria

- [ ] Test explicitly mocks bd command behavior
- [ ] Test verifies error status prevents completion even with empty queue
- [ ] Test would fail if error-status check was removed from beads-empty.sh

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Tests should verify actual code paths, not rely on implicit behavior |

## Resources

- Test file: scripts/tests/test_completions.sh
- Completion strategy: scripts/lib/completions/beads-empty.sh
