---
status: pending
priority: p3
issue_id: "011"
tags: [code-review, cleanup, dead-code]
dependencies: []
---

# Delete Unused all-items.sh Completion Strategy

## Problem Statement

The file `scripts/lib/completions/all-items.sh` exists but has no corresponding v3 termination type mapping. No loop uses it, and the CLAUDE.md documentation was updated to remove `all-items` from the termination strategies table.

**Why it matters:** Dead code clutters the codebase and may confuse developers who think it's available.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/lib/completions/all-items.sh`

**Evidence:**
- No loop.yaml has `completion: all-items` or `termination.type: all-items`
- CLAUDE.md termination table doesn't list it
- validate.sh v3 mapping doesn't include it:
  ```bash
  case "$term_type" in
    queue) strategy="beads-empty" ;;
    judgment) strategy="plateau" ;;
    fixed) strategy="fixed-n" ;;
    # No all-items mapping
  esac
  ```

## Proposed Solutions

### Solution 1: Delete all-items.sh (Recommended)

**Pros:** Clean up dead code
**Cons:** None if unused
**Effort:** Trivial
**Risk:** Verify no hidden usage first

### Solution 2: Add v3 termination type for it

**Pros:** Preserves existing functionality
**Cons:** YAGNI - no current use case
**Effort:** Small
**Risk:** Low

## Recommended Action

Verify nothing uses it, then delete.

```bash
grep -r "all-items" scripts/
# Should only show the file itself
```

## Technical Details

**Affected files:**
- `scripts/lib/completions/all-items.sh` (delete)

## Acceptance Criteria

- [ ] Verified no loop or pipeline uses all-items
- [ ] File deleted
- [ ] Tests still pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | YAGNI - delete unused code |
