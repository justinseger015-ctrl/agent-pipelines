# Workflow: Edit Configuration

Modify existing stage or pipeline configurations through conversation.

## Philosophy

**Don't ask menu questions.** Listen, investigate, propose, confirm, execute.

## Step 1: Understand

Listen to what the user wants. If they said `/pipeline edit` with no context:

> What would you like to change?

Otherwise, parse their request. Examples:

| User Says | Target | Property |
|-----------|--------|----------|
| "Make elegance run for 10 iterations" | `scripts/loops/elegance/loop.yaml` | `termination.max_iterations` |
| "Change improve-plan to use opus" | `scripts/loops/improve-plan/loop.yaml` | `model` |
| "Edit the refine-beads prompt" | `scripts/loops/refine-beads/prompt.md` | content |
| "Add a stage to full-refine" | `scripts/pipelines/full-refine.yaml` | `stages[]` |

If genuinely unclear, ask a clarifying question. But try to infer first.

## Step 2: Investigate

Read the current configuration:

```bash
# For stages
cat scripts/loops/{stage}/loop.yaml
cat scripts/loops/{stage}/prompt.md

# For pipelines
cat scripts/pipelines/{name}.yaml

# To see what exists
ls scripts/loops/
ls scripts/pipelines/*.yaml
```

Understand:
- What currently exists
- What specifically needs to change
- Any constraints or dependencies

## Step 3: Propose Plan

Present a clear before/after:

```markdown
## Proposed Changes

**Target:** `scripts/loops/elegance/loop.yaml`

**Current:**
```yaml
model: sonnet
termination:
  type: judgment
  consensus: 2
```

**After:**
```yaml
model: opus
termination:
  type: judgment
  consensus: 2
```

**Why:** You asked to use opus for the elegance stage.

Does this look right?
```

For prompt changes, show the specific section being modified.

For pipeline changes, show the stages array before/after.

**Wait for explicit confirmation before proceeding.**

## Step 4: Execute

After user confirms:

1. Make the edits using the Edit tool
2. Run validation:

```bash
./scripts/run.sh lint loop {stage}
# or
./scripts/run.sh lint pipeline {name}.yaml
```

3. If validation fails, fix and re-validate
4. Show the result:

```markdown
## Done

Updated `scripts/loops/elegance/loop.yaml`:
- Changed `model` from `sonnet` to `opus`

Validation: Passed
```

## Handling Ambiguity

If the user's request could mean multiple things:

**Bad:** Ask a menu question
**Good:** Make your best guess and confirm

Example:
> User: "Make the work stage faster"
>
> You: I'll reduce the delay between iterations from 3 seconds to 1 second.
> This will make the work stage cycle faster. Does that sound right,
> or did you mean something else by "faster"?

## Handling Multiple Changes

If the user wants several changes:

1. Propose all changes together
2. Get one confirmation for the batch
3. Execute all changes
4. Validate once at the end

## Success Criteria

- [ ] Understood request without menu questions
- [ ] Read current configuration
- [ ] Proposed clear plan with before/after
- [ ] Got explicit confirmation
- [ ] Made changes
- [ ] Validation passed
- [ ] Showed final result
