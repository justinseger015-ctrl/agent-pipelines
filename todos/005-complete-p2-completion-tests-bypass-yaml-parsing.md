---
status: complete
priority: p2
issue_id: "005"
tags: [code-review, testing, integration-gap]
dependencies: ["001"]
---

# Completion Strategy Tests Bypass YAML Parsing

## Problem Statement

Tests for completion strategies set environment variables like `MIN_ITERATIONS` and `CONSENSUS` directly rather than reading them from loop configurations. This means the actual YAML-to-environment-variable flow is never tested.

**Why it matters:** Tests could pass while the actual YAML parsing for these values is broken - which is exactly what happened with the engine not reading v3 termination config.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/tests/test_completions.sh`

**Current approach:**
```bash
# Line 25-26 - values are hardcoded
export MIN_ITERATIONS=2
export CONSENSUS=2
```

**What should happen at runtime:**
1. Engine reads loop.yaml
2. Engine extracts `.termination.min_iterations` and `.termination.consensus`
3. Engine exports these as environment variables
4. Completion strategy reads from environment

**Gap:** Step 2-3 is never tested. Tests go directly from hardcoded values to step 4.

## Proposed Solutions

### Solution 1: Add integration tests for config loading (Recommended)

**Pros:** Tests the actual flow, catches real bugs like #001
**Cons:** More complex setup
**Effort:** Medium
**Risk:** Low

Create `test_engine_config_loading.sh`:
```bash
test_engine_loads_judgment_consensus() {
  local loop_yaml=$(cat scripts/loops/improve-plan/loop.yaml)
  local config=$(echo "$loop_yaml" | yaml_to_json)

  # Simulate load_stage logic
  local term_type=$(json_get "$config" ".termination.type" "")
  local consensus=$(json_get "$config" ".termination.consensus" "")

  assert_eq "judgment" "$term_type" "improve-plan has termination.type=judgment"
  assert_eq "2" "$consensus" "improve-plan has consensus=2"
}
```

### Solution 2: Add validation that exported values match config

**Pros:** Catches mismatches between config and runtime
**Cons:** Partial coverage
**Effort:** Small
**Risk:** Low

## Recommended Action

Implement Solution 1 as part of fixing #001. When updating engine.sh to read v3 config, also add tests that verify the config -> environment variable flow.

## Technical Details

**Affected files:**
- `scripts/tests/test_completions.sh`
- New: `scripts/tests/test_engine_config.sh` (suggested)

## Acceptance Criteria

- [ ] Tests verify engine reads `.termination.consensus` from loop.yaml
- [ ] Tests verify engine reads `.termination.min_iterations` from loop.yaml
- [ ] Tests verify exported environment variables match config values
- [ ] Tests would fail if engine hardcoded wrong defaults

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Unit tests that bypass integration points miss real bugs |

## Resources

- Test file: scripts/tests/test_completions.sh
- Engine config loading: scripts/engine.sh lines 82-94
- Related issue: #001 (engine not reading v3 termination)
