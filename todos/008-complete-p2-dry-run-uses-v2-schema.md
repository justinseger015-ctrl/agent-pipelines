---
status: complete
priority: p2
issue_id: "008"
tags: [code-review, documentation, stale]
dependencies: []
---

# dry_run_loop Function Uses Stale v2 Field Names

## Problem Statement

The `dry_run_loop()` function in validate.sh still references v2 fields (`completion`, `output_parse`, `min_iterations`) and displays them. This function provides user-facing dry-run output that now shows incorrect/missing information for v3 loops.

**Why it matters:** Users running `./scripts/run.sh dry-run loop work test` will see outdated or missing configuration information.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/lib/validate.sh` lines 419-493

**Current code reads:**
```bash
local completion=$(json_get "$config" ".completion" "")
local output_parse=$(json_get "$config" ".output_parse" "")
local min_iterations=$(json_get "$config" ".min_iterations" "")
```

**Should read for v3:**
```bash
local term_type=$(json_get "$config" ".termination.type" "")
local consensus=$(json_get "$config" ".termination.consensus" "")
local min_iterations=$(json_get "$config" ".termination.min_iterations" "")
```

**Output currently shows:**
```
Completion: (empty for v3 configs)
```

**Should show:**
```
Termination: judgment (consensus: 2, min_iterations: 2)
```

## Proposed Solutions

### Solution 1: Update dry_run_loop for v3 schema (Recommended)

**Pros:** Correct user-facing output
**Cons:** Additional maintenance
**Effort:** Small
**Risk:** Low

### Solution 2: Remove dry_run_loop

**Pros:** Less code to maintain
**Cons:** Users lose preview capability
**Effort:** Small
**Risk:** Medium (feature removal)

## Recommended Action

Implement Solution 1 - update to show v3 termination info.

## Technical Details

**Affected files:**
- `scripts/lib/validate.sh` lines 419-493

## Acceptance Criteria

- [ ] dry_run_loop reads v3 termination fields
- [ ] Output shows termination type, consensus, min_iterations
- [ ] Falls back to v2 fields for legacy configs

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | User-facing tools need to stay current with schema |

## Resources

- Function location: scripts/lib/validate.sh
- v3 schema: docs/plans/v3-implementation-plan.md
