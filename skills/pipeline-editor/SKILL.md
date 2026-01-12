---
name: pipeline-editor
description: Edit existing stages and pipelines. Use when user wants to modify loop.yaml, prompt.md, or pipeline.yaml configurations.
---

## What This Skill Does

Modifies existing stage and pipeline configurations. Conversational approach—understand what the user wants, figure out what to edit, confirm before changing.

## Natural Skill Detection

Trigger on:
- "Edit the elegance stage"
- "Change the termination strategy for..."
- "Modify the work loop to use..."
- "Update the pipeline config..."
- "Make the improve-plan stage use opus"
- `/pipeline edit`

## Philosophy

**Don't ask menu questions.** The user will tell you what they want changed. Your job is to:

1. Listen to what they want
2. Figure out which files need editing
3. Propose a plan
4. Execute after confirmation

## Intake

If the user says `/pipeline edit` without context, ask an open-ended question:

> What would you like to change?

Then listen. They might say:
- "Make the elegance stage run longer" → Edit `scripts/loops/elegance/loop.yaml`
- "Change the prompt for refine-beads" → Edit `scripts/loops/refine-beads/prompt.md`
- "Add another stage to full-refine" → Edit `scripts/pipelines/full-refine.yaml`

## Workflow

```
Step 1: UNDERSTAND
├─ Listen to what the user wants
├─ Ask clarifying questions if genuinely unclear
└─ Infer the target (stage/pipeline, which one, what property)

Step 2: INVESTIGATE
├─ Read the current configuration
├─ Understand what exists
└─ Identify exactly what needs to change

Step 3: PROPOSE PLAN
├─ "Here's what I'll change:"
├─ Show the specific edits
└─ Ask: "Does this look right?"

Step 4: EXECUTE (after confirmation)
├─ Make the edits
├─ Run lint validation
└─ Show the result
```

## Investigation

Before proposing changes, read the relevant files:

```bash
# For a stage
cat scripts/loops/{stage}/loop.yaml
cat scripts/loops/{stage}/prompt.md

# For a pipeline
cat scripts/pipelines/{name}.yaml

# To see what exists
ls scripts/loops/
ls scripts/pipelines/*.yaml
```

## Proposing Changes

Present a clear plan before editing:

```markdown
## Proposed Changes

**Target:** `scripts/loops/elegance/loop.yaml`

**Current:**
```yaml
termination:
  type: judgment
  consensus: 2
```

**After:**
```yaml
termination:
  type: judgment
  consensus: 3
```

Does this look right?
```

Only proceed after explicit confirmation.

## Validation

After making changes, always validate:

```bash
./scripts/run.sh lint loop {stage}
# or
./scripts/run.sh lint pipeline {name}.yaml
```

If validation fails, fix the issue before presenting the result.

## Editable Properties

### Stage (loop.yaml)

| Property | Description |
|----------|-------------|
| `termination.type` | queue, judgment, or fixed |
| `termination.min_iterations` | Start checking after N (judgment) |
| `termination.consensus` | Consecutive stops needed (judgment) |
| `termination.max_iterations` | Hard limit (fixed) |
| `model` | opus, sonnet, or haiku |
| `delay` | Seconds between iterations |

### Stage (prompt.md)

| Section | Notes |
|---------|-------|
| Context section | Preserve ${CTX}, ${PROGRESS}, ${STATUS} |
| Autonomy grant | Preserve the philosophy |
| Guidance | Edit task-specific instructions |
| Status template | Preserve JSON format |

### Pipeline (pipeline.yaml)

| Property | Description |
|----------|-------------|
| `stages[].loop` | Which stage to run |
| `stages[].runs` | Max iterations for this stage |
| `stages[].inputs` | Dependencies on previous stages |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| edit.md | Full editing workflow |

## Success Criteria

- [ ] Understood what user wants without menu questions
- [ ] Investigated current configuration
- [ ] Proposed clear plan with before/after
- [ ] Got explicit confirmation before editing
- [ ] Made changes and validated with lint
- [ ] Showed final result
