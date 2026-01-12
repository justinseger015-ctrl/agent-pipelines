---
status: complete
priority: p1
issue_id: "003"
tags: [code-review, testing, coverage-gap, blocks-merge]
dependencies: ["002"]
---

# Regression Test Silently Skips External Prompts

## Problem Statement

The regression tests `test_prompts_use_ctx_variable()` and `test_prompts_use_status_variable()` only check files named `prompt.md` in each loop directory. Loops that use external prompts (via `prompt:` field in loop.yaml) are silently skipped.

**Why it matters:** Tests report 100% pass rate while actual coverage is incomplete. The refine-beads loop was missed entirely, allowing unmigrated code to pass review.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/tests/test_regression.sh` lines 55-72

**Current (broken):**
```bash
test_prompts_use_ctx_variable() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local prompt_file="$loop_dir/prompt.md"
    [ -f "$prompt_file" ] || continue  # SILENTLY SKIPS refine-beads!
    ...
  done
}
```

**Evidence:**
- refine-beads has `prompt: prompts/bead-refiner.md` in loop.yaml
- No `prompt.md` exists in refine-beads directory
- Test silently continues, never checking bead-refiner.md

**Impact:** False sense of test coverage. A test that doesn't test what it claims is worse than no test.

## Proposed Solutions

### Solution 1: Read prompt path from loop.yaml (Recommended)

**Pros:** Correctly finds actual prompt file regardless of location
**Cons:** Slightly more complex
**Effort:** Small
**Risk:** Low

```bash
test_prompts_use_ctx_variable() {
  for loop_dir in "$LOOPS_DIR"/*/; do
    local config_file="$loop_dir/loop.yaml"
    [ -f "$config_file" ] || continue

    local config=$(yaml_to_json "$config_file")
    local prompt_path=$(echo "$config" | jq -r '.prompt // "prompt.md"')

    # Handle relative path
    if [[ "$prompt_path" != /* ]]; then
      prompt_path="$loop_dir/$prompt_path"
    fi

    # If prompt field is just a name without extension, add .md
    if [[ "$prompt_path" != *.md ]]; then
      prompt_path="${prompt_path}.md"
    fi

    [ -f "$prompt_path" ] || { echo "Warning: prompt not found: $prompt_path"; continue; }

    local loop_name=$(basename "$loop_dir")
    local content=$(cat "$prompt_path")
    assert_contains "$content" '${CTX}' "$loop_name prompt uses \${CTX}"
  done
}
```

### Solution 2: Fail instead of skip

**Pros:** Makes missing prompts explicit failures
**Cons:** Could break on valid configs
**Effort:** Small
**Risk:** Medium

## Recommended Action

Implement Solution 1 for both `test_prompts_use_ctx_variable` and `test_prompts_use_status_variable`.

## Technical Details

**Affected files:**
- `scripts/tests/test_regression.sh` - functions at lines 55-72

## Acceptance Criteria

- [ ] Test correctly locates external prompts via loop.yaml `prompt:` field
- [ ] refine-beads prompt is actually tested (currently skipped)
- [ ] Test output shows which prompt file is being checked
- [ ] All 5 loops have their prompts verified

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Silent skips mask incomplete coverage |

## Resources

- Test file: scripts/tests/test_regression.sh
- Example of external prompt: scripts/loops/refine-beads/loop.yaml
