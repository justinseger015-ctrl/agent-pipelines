---
status: closed
priority: p2
issue_id: "007"
tags: [code-review, security, v3-refactor]
dependencies: []
resolution: fixed
---

# release_lock Does Not Verify PID Ownership

## Problem Statement

The `release_lock()` function does not verify that the current process owns the lock before releasing it. A process could inadvertently release another process's lock, potentially leading to concurrent session execution.

**Why it matters:** Could allow two sessions with the same name to run simultaneously, causing file corruption and unpredictable behavior.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/lib/lock.sh` lines 64-71

**Current code:**
```bash
release_lock() {
  local session=$1
  local lock_file="$LOCKS_DIR/${session}.lock"

  if [ -f "$lock_file" ]; then
    rm -f "$lock_file"
  fi
}
```

**Risk scenario:**
1. Process A acquires lock for session "foo"
2. Process A crashes mid-iteration
3. Process B starts with --resume, acquires lock (stale cleanup)
4. Process A's cleanup handler (if any) runs, releases lock
5. Process C can now acquire lock while B is still running

Exploitability is low but the fix is simple and makes the code more defensive.

## Proposed Solutions

### Option A: Verify PID before release (Recommended)
```bash
release_lock() {
  local session=$1
  local lock_file="$LOCKS_DIR/${session}.lock"

  if [ -f "$lock_file" ]; then
    local lock_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    if [ "$lock_pid" = "$$" ]; then
      rm -f "$lock_file"
    fi
  fi
}
```
- **Pros:** Prevents accidental release of other process's lock
- **Cons:** Slightly more overhead
- **Effort:** Small (5 minutes)
- **Risk:** None

### Option B: Silent ignore if not owner
Same as A but with warning message
- **Pros:** Visibility into ownership issues
- **Cons:** May be noisy
- **Effort:** Small
- **Risk:** None

## Recommended Action

Implement Option A. Simple, defensive, prevents subtle race conditions.

## Technical Details

- **Affected files:** `scripts/lib/lock.sh`
- **Database changes:** None
- **Component impact:** Lock release behavior

## Acceptance Criteria

- [ ] release_lock checks PID ownership before deleting
- [ ] Only owner process can release its lock
- [ ] Existing tests pass
- [ ] Add test for non-owner release attempt

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-12 | Created from security review | Defense in depth for lock management |
| 2026-01-12 | **Fixed** | Added PID ownership check before releasing lock |

## Resources

- Security sentinel agent findings
