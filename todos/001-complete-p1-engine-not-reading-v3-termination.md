---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, architecture, bug, blocks-merge]
dependencies: []
---

# Engine Does Not Read v3 Termination Config

## Problem Statement

The engine (`scripts/engine.sh`) reads the completion strategy from the deprecated `.completion` field (v2 schema) instead of mapping from the new `.termination.type` field (v3 schema). Since all loop.yaml files have been migrated to v3 schema (no `completion` field exists), the engine defaults to `"fixed-n"` for every stage.

**Why it matters:** All loops will use the wrong termination strategy at runtime. Judgment loops won't reach consensus-based termination, queue loops won't check if beads are empty.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/engine.sh` lines 82-94

**Current code (broken):**
```bash
LOOP_COMPLETION=$(json_get "$LOOP_CONFIG" ".completion" "fixed-n")  # Line 82
LOOP_MIN_ITERATIONS=$(json_get "$LOOP_CONFIG" ".min_iterations" "1")  # Line 87
export MIN_ITERATIONS="$LOOP_MIN_ITERATIONS"  # Line 93
# MISSING: CONSENSUS is never read or exported
```

**Impact on all 5 loops:**

| Loop | Configured | Engine Reads | Result |
|------|-----------|-------------|--------|
| work | `termination.type: queue` | `.completion` (doesn't exist) | Defaults to `fixed-n` |
| improve-plan | `termination.type: judgment` | `.completion` (doesn't exist) | Defaults to `fixed-n` |
| refine-beads | `termination.type: judgment` | `.completion` (doesn't exist) | Defaults to `fixed-n` |
| elegance | `termination.type: judgment` | `.completion` (doesn't exist) | Defaults to `fixed-n` |
| idea-wizard | `termination.type: fixed` | `.completion` (doesn't exist) | Defaults to `fixed-n` (accidental match) |

**Evidence:**
- `grep "LOOP_COMPLETION" scripts/engine.sh` shows line 82 reads `.completion`
- `grep "^completion:" scripts/loops/*/loop.yaml` returns nothing (field removed)
- `validate.sh` already has correct mapping at lines 71-84, engine doesn't

## Proposed Solutions

### Solution 1: Add v3 termination mapping to engine.sh (Recommended)

**Pros:** Mirrors the mapping logic already in validate.sh, maintains backwards compatibility with v2
**Cons:** Duplicates mapping logic (should later extract to shared function)
**Effort:** Small (15-20 lines)
**Risk:** Low

```bash
# In load_stage(), replace lines 82-94 with:
local term_type=$(json_get "$LOOP_CONFIG" ".termination.type" "")
if [ -n "$term_type" ]; then
  # v3: map termination type to completion strategy
  case "$term_type" in
    queue) LOOP_COMPLETION="beads-empty" ;;
    judgment) LOOP_COMPLETION="plateau" ;;
    fixed) LOOP_COMPLETION="fixed-n" ;;
    *) LOOP_COMPLETION="$term_type" ;;
  esac
  LOOP_MIN_ITERATIONS=$(json_get "$LOOP_CONFIG" ".termination.min_iterations" "1")
  CONSENSUS=$(json_get "$LOOP_CONFIG" ".termination.consensus" "2")
else
  # v2 legacy fallback
  LOOP_COMPLETION=$(json_get "$LOOP_CONFIG" ".completion" "fixed-n")
  LOOP_MIN_ITERATIONS=$(json_get "$LOOP_CONFIG" ".min_iterations" "1")
  CONSENSUS=2
fi

export MIN_ITERATIONS="$LOOP_MIN_ITERATIONS"
export CONSENSUS="${CONSENSUS:-2}"
```

### Solution 2: Extract mapping to shared library

**Pros:** DRY - single source of truth for mapping
**Cons:** More files to modify, additional complexity
**Effort:** Medium
**Risk:** Low

Create `scripts/lib/termination.sh` with shared `get_completion_strategy()` function used by both validate.sh and engine.sh.

## Recommended Action

Implement Solution 1 immediately to unblock the v3 migration. Consider Solution 2 as follow-up cleanup.

## Technical Details

**Affected files:**
- `scripts/engine.sh` - lines 82-94 (load_stage function)

**Components affected:**
- All loop executions
- All pipeline executions

**Database changes:** None

## Acceptance Criteria

- [ ] Engine reads `.termination.type` from v3 loop configs
- [ ] Engine maps `queue` -> `beads-empty`, `judgment` -> `plateau`, `fixed` -> `fixed-n`
- [ ] Engine reads `min_iterations` from `.termination.min_iterations` for v3
- [ ] Engine exports `CONSENSUS` from `.termination.consensus`
- [ ] All existing tests pass
- [ ] New test added to verify engine loads v3 termination config correctly
- [ ] Work loop uses beads-empty completion at runtime
- [ ] Judgment loops use plateau completion at runtime

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Validation tests passed but runtime would fail |

## Resources

- PR/Commit: 43268f3 (Phase 6)
- Related: validate.sh already has correct mapping (lines 71-84)
- Implementation plan: docs/plans/v3-implementation-plan.md
