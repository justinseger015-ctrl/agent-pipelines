---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, migration, incomplete, blocks-merge]
dependencies: []
---

# refine-beads Prompt Not Migrated to v3 Variables

## Problem Statement

The `refine-beads` loop uses an external prompt file (`prompts/bead-refiner.md`) which was NOT updated to use v3 variables. The commit message claims "Update all 4 prompts" but this prompt was missed because it's at a non-standard path.

**Why it matters:** The refine-beads stage will reference undefined or deprecated template variables, causing incorrect context resolution.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/loops/refine-beads/prompts/bead-refiner.md`

**Current (broken):**
- Line 3: `Session: ${SESSION_NAME}` (should also have `Read context from: ${CTX}`)
- Line 4: `Progress file: ${PROGRESS_FILE}` (should be `${PROGRESS}`)
- Line 16: `cat ${PROGRESS_FILE}` (should be `cat ${PROGRESS}`)
- Lines 81-85: Still contains legacy PLATEAU/REASONING output block

**Why the test didn't catch it:**
The regression test `test_prompts_use_ctx_variable()` in `test_regression.sh` only checks for files named `prompt.md`:
```bash
local prompt_file="$loop_dir/prompt.md"
[ -f "$prompt_file" ] || continue  # Silently skips refine-beads!
```

**Evidence:**
- `grep -n "PROGRESS_FILE" scripts/loops/refine-beads/prompts/bead-refiner.md` shows legacy variable
- `grep -n "CTX" scripts/loops/refine-beads/prompts/bead-refiner.md` returns nothing

## Proposed Solutions

### Solution 1: Update bead-refiner.md to v3 variables (Recommended)

**Pros:** Completes the migration, consistent with other prompts
**Cons:** None
**Effort:** Small
**Risk:** Low

Changes needed:
1. Add `Read context from: ${CTX}` header
2. Replace `${PROGRESS_FILE}` with `${PROGRESS}`
3. Remove legacy PLATEAU/REASONING output block (lines 81-85)

### Solution 2: Also fix test coverage gap

**Pros:** Prevents similar issues in future
**Cons:** Additional work
**Effort:** Small
**Risk:** Low

Update test to read actual prompt path from loop.yaml:
```bash
local config=$(yaml_to_json "$loop_dir/loop.yaml")
local prompt_path=$(echo "$config" | jq -r '.prompt // "prompt.md"')
local prompt_file="$loop_dir/$prompt_path"
```

## Recommended Action

Implement both solutions together.

## Technical Details

**Affected files:**
- `scripts/loops/refine-beads/prompts/bead-refiner.md`
- `scripts/tests/test_regression.sh` (to fix coverage gap)

**Also check:**
- `scripts/loops/refine-beads/prompts/plan-improver.md` - may also need migration

## Acceptance Criteria

- [ ] bead-refiner.md uses `${CTX}` variable
- [ ] bead-refiner.md uses `${PROGRESS}` instead of `${PROGRESS_FILE}`
- [ ] bead-refiner.md uses `${STATUS}` variable
- [ ] Legacy PLATEAU/REASONING output block removed
- [ ] Regression test updated to check external prompts
- [ ] Test passes for refine-beads loop

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | External prompts need different test strategy |

## Resources

- PR/Commit: 43268f3 (Phase 6)
- Loop config: scripts/loops/refine-beads/loop.yaml (references `prompt: prompts/bead-refiner.md`)
