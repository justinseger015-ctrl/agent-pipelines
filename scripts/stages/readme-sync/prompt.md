# README Sync

Read context from: ${CTX}
Progress file: ${PROGRESS}
Output file: ${OUTPUT_PATH}
Iteration: ${ITERATION}

## Your Task

Analyze the codebase and identify functionality that is implemented but missing, under-documented, or outdated in the README. Then update the README directly.

### Step 1: Gather Context

```bash
cat ${PROGRESS}
cat ${OUTPUT_PATH} 2>/dev/null || echo "First iteration"
```

### Step 2: Analyze Codebase vs README

Read the current README:
```bash
cat README.md
```

Then explore the codebase to find implemented features:
- Commands in `commands/`
- Stages in `scripts/stages/`
- Skills in `skills/`
- Pipelines in `scripts/pipelines/`
- Library functions in `scripts/lib/`
- Configuration patterns

For each feature found, check:
1. Is it mentioned in the README?
2. Is the documentation accurate and current?
3. Is there enough detail for a new user?
4. Are there examples?

### Step 3: Identify Gaps

Look for:
- **Missing features** - Implemented but not documented
- **Outdated info** - README says X, code does Y
- **Under-explained** - Mentioned but lacks detail
- **Missing examples** - Feature exists but no usage shown
- **Missing rationale** - What it does but not why it's useful

### Step 4: Update README Directly

Make the actual edits to README.md. Write as if features were always there (not "we added X"). Include:
- Clear descriptions
- Usage examples
- Why it's useful
- How it connects to other features

### Step 5: Document Changes

Write to ${OUTPUT_PATH}:

```markdown
## README Sync - Iteration ${ITERATION}

### Changes Made
- [List of sections added/updated]

### Gaps Remaining
- [What still needs work for next iteration]
```

### Step 6: Update Progress & Write Status

Append summary to progress file, then write to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Updated README in iteration ${ITERATION}",
  "summary": "What sections you updated",
  "work": {"items_completed": [], "files_touched": ["README.md", "${OUTPUT_PATH}"]},
  "errors": []
}
```

## Guidelines

- Write documentation users would actually want to read
- Be concise but complete
- Include real examples, not placeholders
- Iteration 2+ should cover different areas or go deeper
- Don't repeat work from previous iterations (check output file)
