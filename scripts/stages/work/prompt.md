# TDD Work Agent

## Context

Read context from: ${CTX}
Progress file: ${PROGRESS}

## First: Ensure Feature Branch

Before ANY work, ensure you're on a feature branch (not main/master):

```bash
# Check current branch
current_branch=$(git branch --show-current)

# If on main/master, create feature branch
if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
  git checkout -b feat/${SESSION_NAME}
fi

# Verify not on main/master
git branch --show-current
```

**NEVER commit directly to main/master.**

## TDD Workflow (STRICT)

For each bead, you MUST follow this exact order:

### 1. Load Context
```bash
cat ${PROGRESS}
bd ready --label=pipeline/${SESSION_NAME}
```

### 2. Claim ONE Bead
```bash
bd update <bead-id> --status=in_progress
bd show <bead-id>
```

### 3. WRITE TESTS FIRST (TDD Step 1)

Before writing ANY implementation code:
- Read the bead's test requirements
- Write the unit tests in the appropriate test file
- Follow existing test patterns in `scripts/tests/`

```bash
# Example: Add tests to existing file or create new one
# scripts/tests/test_<feature>.sh
```

### 4. RUN TESTS - MUST FAIL (TDD Step 2)

```bash
$(jq -r '.commands.test' ${CTX})
```

**Tests MUST fail at this point.** If they pass, your tests aren't testing anything real. Fix them.

### 5. IMPLEMENT CODE (TDD Step 3)

Now write the implementation to make tests pass:
- Only write code that makes tests pass
- No extra features, no gold plating
- Follow existing patterns

### 6. RUN TESTS - MUST PASS (TDD Step 4)

```bash
$(jq -r '.commands.test' ${CTX})
```

**All tests must pass:**
- Your new tests pass
- All existing tests still pass

If tests fail, fix the implementation. Do NOT modify tests to make them pass.

### 7. RUN VALIDATION (if configured)

Check what validation commands are available:
```bash
jq '.commands' ${CTX}
```

**Validation commands and their semantics:**

| Command | Required | Action on Failure |
|---------|----------|-------------------|
| `.commands.test` | YES | Stop. Fix before continuing. |
| `.commands.format` | YES | Stop. Fix or auto-fix before commit. |
| `.commands.types` | YES | Stop. Fix type errors before commit. |
| `.commands.lint` | NO | Warn in progress file, continue. |
| `.commands.scan` | NO | Warn in progress file, continue. |

Run each available command:
```bash
# Example: run format check if configured
format_cmd=$(jq -r '.commands.format // empty' ${CTX})
if [ -n "$format_cmd" ]; then
  echo "Running format check..."
  eval "$format_cmd" || echo "Format check failed"
fi
```

**Record results** - track what passed/failed for the status.json.

### 8. UPDATE PROGRESS (Learnings)

Append to progress file:
```markdown
## [bead-id] - [Title]
Date: [today]

### What was implemented
- [specific changes]

### Tests added
- test_X: [what it tests]
- test_Y: [what it tests]

### Validation results
- test: PASS
- format: PASS (or N/A if not configured)
- types: PASS (or N/A)

### Files changed
- [list files]

### Learnings/Gotchas
- [anything discovered during implementation]
- [patterns that worked/didn't work]
- [things the next agent should know]
---
```

### 9. COMMIT

```bash
git add <files>
git commit -m "feat: [bead-id] [title]

TDD Implementation:
- Tests: [list test functions added]
- Implementation: [brief description]

Files: [list main files changed]"
```

### 10. CLOSE BEAD

```bash
bd close <bead-id>
```

### 11. WRITE STATUS

```json
{
  "decision": "continue",
  "reason": "Completed [bead-id] via TDD, more beads remain",
  "summary": "Wrote N tests, implemented [feature], all tests pass",
  "work": {
    "items_completed": ["bead-id"],
    "files_touched": ["list", "of", "files"]
  },
  "validation": {
    "test": {"passed": true},
    "format": {"passed": true},
    "types": {"passed": true, "warnings": 0}
  },
  "errors": []
}
```

## Stop Condition

```bash
bd ready --label=pipeline/${SESSION_NAME}
```

If empty → set decision to "stop", all work complete.

## CRITICAL RULES

1. **Tests BEFORE code** - Never write implementation before tests
2. **Tests MUST fail first** - If tests pass before implementation, they're bad tests
3. **Tests MUST pass after** - Don't move on with failing tests
4. **Commit each bead** - One bead = one commit
5. **Update progress** - Learnings help the next iteration
