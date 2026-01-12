---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, cleanup, legacy]
dependencies: []
---

# Fixture Files Still Have Legacy PLATEAU/REASONING Output

## Problem Statement

Multiple fixture files under `scripts/loops/*/fixtures/` still contain legacy `PLATEAU:` and `REASONING:` output markers from the v2 schema. While the engine may still support these for backwards compatibility, having them in fixtures could cause confusion about what format agents should output.

**Why it matters:** Fixtures serve as examples. If fixtures show legacy format, new prompts might incorrectly copy the legacy pattern.

## Findings

**Affected files:**
- `scripts/loops/refine-beads/fixtures/default.txt`
- `scripts/loops/elegance/fixtures/default.txt`
- `scripts/loops/improve-plan/fixtures/default.txt`
- `scripts/loops/improve-plan/fixtures/iteration-1.txt`
- `scripts/loops/improve-plan/fixtures/iteration-2.txt`
- `scripts/loops/improve-plan/fixtures/iteration-3.txt`

**Evidence:**
```bash
grep -l "PLATEAU:" scripts/loops/*/fixtures/*.txt
# Returns all the above files
```

**Current fixture format (legacy):**
```
PLATEAU: false
REASONING: More improvements needed
```

**Expected v3 format:**
Fixtures should contain or create `status.json` with:
```json
{"decision": "continue", "reason": "More improvements needed"}
```

## Proposed Solutions

### Solution 1: Update fixtures to v3 format (Recommended)

**Pros:** Consistent with v3 schema, serves as correct example
**Cons:** May need to update mock.sh if it parses these
**Effort:** Small
**Risk:** Low

### Solution 2: Add status.json fixtures alongside

**Pros:** Supports both formats during transition
**Cons:** Duplication
**Effort:** Small
**Risk:** Low

## Recommended Action

Update fixtures to v3 format. Verify mock.sh handles status.json correctly.

## Technical Details

**Affected files:**
- All `scripts/loops/*/fixtures/*.txt` files

## Acceptance Criteria

- [ ] Fixture files updated to v3 status.json format
- [ ] Mock infrastructure works with v3 fixtures
- [ ] Tests using fixtures still pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Fixtures should match current schema |

## Resources

- v3 status format: docs/plans/v3-implementation-plan.md (Phase 2)
