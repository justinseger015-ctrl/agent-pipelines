---
status: complete
priority: p2
issue_id: "006"
tags: [code-review, testing, coverage-gap]
dependencies: []
---

# No End-to-End Engine Integration Tests

## Problem Statement

There are no tests that actually run `engine.sh` even with mocked Claude. Tests simulate iteration behavior manually rather than testing the real engine logic. The implementation plan mentions `test_engine_integration.sh` (Phase 6 Step 0.4) but this file was not created.

**Why it matters:** Critical engine behaviors are untested:
- Engine correctly sourcing the completion strategy
- Engine correctly calling `mark_iteration_started` and `mark_iteration_completed`
- Engine correctly generating and passing context.json to prompts
- Engine correctly saving output snapshots to iterations/NNN/output.md
- Engine correctly creating error status when agent doesn't write status.json

## Findings

**Missing file:** `scripts/tests/test_engine_integration.sh`

**Implementation plan reference:**
> Phase 6 Step 0.4: Create Engine Integration Tests
> These tests run the engine with mock responses to verify file creation

**Current state:** Phase 3 tests (`test_engine_snapshots.sh`) test helper functions in isolation but never exercise `run_stage` or `run_pipeline`.

**Evidence:**
```bash
ls scripts/tests/test_engine*.sh
# Only shows test_engine_snapshots.sh, no test_engine_integration.sh
```

## Proposed Solutions

### Solution 1: Create test_engine_integration.sh (Recommended)

**Pros:** Tests actual engine behavior, catches real integration bugs
**Cons:** Requires robust mock infrastructure
**Effort:** Medium-Large
**Risk:** Medium (mock infrastructure needs to be reliable)

See implementation plan Phase 6 Step 0.4 for test structure.

### Solution 2: Document manual testing requirements

**Pros:** Acknowledges limitation
**Cons:** Doesn't improve automated coverage
**Effort:** Small
**Risk:** Low

## Recommended Action

Create test_engine_integration.sh following the implementation plan. If mock infrastructure is insufficient, mark tests as skip with clear explanation.

## Technical Details

**Files to create:**
- `scripts/tests/test_engine_integration.sh`

**Key test scenarios:**
1. Engine creates output snapshot after iteration
2. Engine creates error status when agent doesn't write status.json
3. Engine preserves agent's status (doesn't overwrite with error)
4. Engine correctly sources completion strategy based on termination type

## Acceptance Criteria

- [ ] test_engine_integration.sh exists
- [ ] Tests exercise run_stage with mock Claude
- [ ] Tests verify context.json is generated
- [ ] Tests verify output snapshots are saved
- [ ] Tests verify status.json handling (agent writes vs engine creates error)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Implementation plan specified this but it wasn't created |

## Resources

- Implementation plan: docs/plans/v3-implementation-plan.md (Phase 6 Step 0.4)
- Mock infrastructure: scripts/lib/mock.sh
- Engine: scripts/engine.sh
