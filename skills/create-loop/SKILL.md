# Create Loop Skill

Create new loop agent types quickly and easily.

## Usage

```
/loop-agents:create-loop <name>
```

## Workflow

1. Ask for loop name if not provided
2. Ask about completion strategy:
   - **beads-empty**: Stop when no beads remain (like work loop)
   - **plateau**: Stop when changes slow down (like refine loop)
   - **fixed-n**: Run exactly N iterations
   - **all-items**: Iterate through a list of items (like review loop)

3. Ask about output parsing:
   - None needed
   - Parse CHANGES/SUMMARY (for plateau detection)
   - Parse FINDINGS/CRITICAL (for review aggregation)
   - Custom parsing

4. Generate loop configuration:
   - `scripts/loops/<name>/loop.yaml`
   - `scripts/loops/<name>/prompt.md` or `prompts/` directory

5. Provide next steps

## Instructions

When the user runs `/loop-agents:create-loop`, help them create a new loop type.

### Step 1: Get Loop Name

If not provided as argument, ask:
```
What should this loop be called? (e.g., "scraper", "writer", "tester")
```

### Step 2: Completion Strategy

Ask the user:
```
How should this loop know when to stop?

1. **beads-empty** - Stop when no beads remain for this session
2. **plateau** - Stop when output shows diminishing changes (good for refinement)
3. **fixed-n** - Run exactly N iterations (good for batch processing)
4. **all-items** - Iterate through a list of items (good for multi-perspective tasks)
```

### Step 3: Output Parsing

If they chose plateau or need aggregation, ask:
```
What should be parsed from each iteration's output?

1. None - No parsing needed
2. CHANGES/SUMMARY - For plateau detection (output "CHANGES: N" and "SUMMARY: text")
3. FINDINGS/CRITICAL - For review aggregation (output "FINDINGS_COUNT: N")
4. Custom - I'll specify my own keys
```

### Step 4: Generate Files

Create the loop configuration based on their answers.

**loop.yaml template:**
```yaml
# {Name} Loop - {Description}
# {Completion explanation}

name: {name}
description: {user-provided or inferred description}
completion: {strategy}
{additional config based on strategy}
delay: 3
{output_parse if needed}
```

**prompt.md template:**
```markdown
# {Name} Agent

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

## Your Task

{Main task description}

## Steps

1. {Step 1}
2. {Step 2}
...

## Output Requirements

{If parsing needed:}
At the END of your response, output:
\`\`\`
{PARSED_KEY}: {value}
\`\`\`
```

### Step 5: Next Steps

Tell the user:
```
Created loop type: {name}

Files created:
- scripts/loops/{name}/loop.yaml
- scripts/loops/{name}/prompt.md

To run this loop:
  ./scripts/loop-engine/run.sh {name} [session_name] [max_iterations]

To customize:
- Edit the prompt in scripts/loops/{name}/prompt.md
- Adjust settings in scripts/loops/{name}/loop.yaml
```

## Completion Strategy Details

### beads-empty
- Best for: Implementation tasks where beads track work
- Config: `check_before: true`
- Checks `bd ready --label=loop/$SESSION_NAME` before each iteration

### plateau
- Best for: Refinement tasks where quality improves over iterations
- Config:
  ```yaml
  plateau_threshold: 2    # Stop after 2 low-change rounds
  min_iterations: 3       # Don't stop before 3 iterations
  low_change_max: 1       # What counts as "low change"
  ```
- Requires output parsing: `output_parse: changes:CHANGES summary:SUMMARY`

### fixed-n
- Best for: Batch processing, scheduled runs
- Config: Just set `max_iterations` when running
- No special output needed

### all-items
- Best for: Multi-perspective tasks (reviews, multi-agent)
- Config:
  ```yaml
  items: item1 item2 item3
  ```
- Creates `prompts/{item}.md` for each item
- Iterates through items in order
