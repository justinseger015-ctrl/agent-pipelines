# Test Planner

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}
Session: ${SESSION_NAME}

## Your Task

You are converting the test gap analysis into actionable beads/tasks. Each bead should be a specific, implementable test that can be picked up by a developer or work pipeline.

### Step 1: Load Analysis

Read the progress file with scanner findings and analysis:
```bash
cat ${PROGRESS}
```

### Step 2: Check Existing Beads

See what test-related beads already exist:
```bash
bd list --status=open 2>/dev/null | grep -i test || echo "No existing test beads"
```

### Step 3: Create Beads

For each prioritized recommendation, create a bead using this format:

```bash
bd create \
  --title="Add unit tests for [function/module]" \
  --type=task \
  --priority=[0-4] \
  --label="testing" \
  --label="pipeline/${SESSION_NAME}"
```

**Priority mapping:**
- P0 (Critical): Security-sensitive, core business logic
- P1 (High): Frequently changed code, integration points
- P2 (Medium): Standard coverage gaps
- P3 (Low): Edge cases, utilities
- P4 (Backlog): Nice-to-have improvements

**Title conventions:**
- `Add unit tests for UserAuth.validateToken()`
- `Add integration tests for payment API`
- `Add error handling tests for FileProcessor`
- `Add edge case tests for DateParser.parse()`

### Step 4: Create Beads by Priority

Work through the prioritized list:

**Immediate Priority (P0-P1):**
```bash
# Example - adapt to actual findings
bd create --title="Add unit tests for [critical function]" --type=task --priority=0 --label="testing" --label="pipeline/${SESSION_NAME}"
```

**Short-term Priority (P2):**
```bash
bd create --title="Add tests for [module]" --type=task --priority=2 --label="testing" --label="pipeline/${SESSION_NAME}"
```

**Backlog (P3-P4):**
```bash
bd create --title="Add edge case tests for [function]" --type=task --priority=3 --label="testing" --label="pipeline/${SESSION_NAME}"
```

### Step 5: Add Dependencies (if applicable)

If some tests depend on others (e.g., integration tests need unit tests first):
```bash
bd dep add [integration-bead-id] [unit-test-bead-id]
```

### Step 6: Create Summary

Update the progress file with a summary of created beads:

```markdown
## Iteration ${ITERATION} - Test Planning Complete

### Beads Created

| Bead ID | Title | Priority | Dependencies |
|---------|-------|----------|--------------|
| beads-xxx | Add unit tests for Auth | P0 | None |
| beads-yyy | Add integration tests for API | P1 | beads-xxx |

### Total: X beads created
- P0 (Critical): X
- P1 (High): X
- P2 (Medium): X
- P3-P4 (Backlog): X

### Next Steps
Run `/ralph` or `./scripts/run.sh work ${SESSION_NAME}-tests 25` to implement these tests.
```

### Step 7: Write Status

After creating beads, write your status to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "All test tasks have been created as beads",
  "summary": "Created X beads for missing tests: Y critical, Z high priority, W medium/low",
  "work": {
    "items_completed": ["Created test coverage beads"],
    "files_touched": []
  },
  "errors": []
}
```

**Note:** This stage always runs once and stops. The output is a set of beads ready for implementation.

### Quality Checklist

Before finishing, verify:
- [ ] Each bead has a clear, specific title
- [ ] Priority reflects actual risk/impact
- [ ] Labels include both "testing" and "pipeline/${SESSION_NAME}"
- [ ] No duplicate beads created
- [ ] Dependencies are set correctly
