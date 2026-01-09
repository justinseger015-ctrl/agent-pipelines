# Plan: Plan-Refinery Implementation

> "Check your beads N times, implement once."

## Overview

The plan-refinery skill provides 7 specialized Opus subagents for planning refinement. This plan covers the **execution infrastructure** needed to actually run these agents, especially the iterative `/refine` loop.

## Architecture Decision

**Question:** Script-driven loop vs. in-conversation loop vs. loop agent pattern?

**Answer:** Use the **existing loop agent pattern** with modifications:

| Aspect | Regular Loop | Refine Loop |
|--------|--------------|-------------|
| Completion signal | Beads empty | Plateau detected |
| Iterations | Until done | Fixed N or until plateau |
| State tracking | beads | JSON state file |
| Prompt | Single prompt.md | Agent-specific prompts |

**Why this approach:**
1. Reuses proven tmux + script infrastructure
2. Survives context limits (fresh claude per iteration)
3. Runs in background with monitoring
4. Desktop notifications on completion

## Components to Build

### 1. Script: `scripts/refine/refine-loop.sh`

```bash
#!/bin/bash
# Refine Loop - Iterative planning refinement
# Similar to loop.sh but with plateau detection

MODE=${1:-"beads"}           # "beads" or "plan"
MAX_ITERATIONS=${2:-10}
SESSION_NAME=${3:-"refine"}
PLAN_FILE=${4:-""}           # Required if MODE=plan

# Plateau detection state
LAST_CHANGE_COUNT=999
PLATEAU_COUNT=0
PLATEAU_THRESHOLD=2          # Stop after 2 low-change rounds

for i in $(seq 1 $MAX_ITERATIONS); do
    # Run one refinement iteration
    OUTPUT=$(./refine-once.sh "$MODE" "$SESSION_NAME" "$PLAN_FILE")

    # Parse change count from output
    CHANGE_COUNT=$(echo "$OUTPUT" | grep "CHANGES:" | cut -d: -f2)

    # Plateau detection
    if [ "$CHANGE_COUNT" -le 1 ] && [ "$LAST_CHANGE_COUNT" -le 2 ]; then
        PLATEAU_COUNT=$((PLATEAU_COUNT + 1))
    else
        PLATEAU_COUNT=0
    fi

    if [ "$PLATEAU_COUNT" -ge "$PLATEAU_THRESHOLD" ] && [ "$i" -ge 3 ]; then
        echo "🎯 PLATEAU DETECTED at iteration $i"
        record_completion "plateau" "$SESSION_NAME"
        exit 0
    fi

    LAST_CHANGE_COUNT=$CHANGE_COUNT
done
```

### 2. Script: `scripts/refine/refine-once.sh`

Single iteration runner (for testing before AFK mode):

```bash
#!/bin/bash
# Single refinement iteration

MODE=$1
SESSION_NAME=$2
PLAN_FILE=$3

# Select prompt based on mode
if [ "$MODE" = "beads" ]; then
    PROMPT_FILE="prompts/bead-refiner.md"
else
    PROMPT_FILE="prompts/plan-improver.md"
fi

# Substitute variables and run
cat "$PROMPT_FILE" \
    | sed "s|\${SESSION_NAME}|$SESSION_NAME|g" \
    | sed "s|\${PLAN_FILE}|$PLAN_FILE|g" \
    | claude --model opus --dangerously-skip-permissions 2>&1
```

### 3. Prompt Files

#### `scripts/refine/prompts/bead-refiner.md`

```markdown
# Bead Refinement Iteration

Session: ${SESSION_NAME}

## Your Task

Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully...

[Full bead-refiner prompt from sub-agents.md]

## Output Requirements

At the END of your response, output exactly:
\`\`\`
CHANGES: {number}
SUMMARY: {one-line summary of changes}
\`\`\`

This is parsed by the loop script for plateau detection.
```

#### `scripts/refine/prompts/plan-improver.md`

```markdown
# Plan Improvement Iteration

Session: ${SESSION_NAME}
Plan file: ${PLAN_FILE}

## Your Task

Carefully review this entire plan for me and come up with your best revisions...

[Full plan-improver prompt from sub-agents.md]

## Output Requirements

At the END of your response, output exactly:
\`\`\`
CHANGES: {number}
SUMMARY: {one-line summary of changes}
\`\`\`
```

#### `scripts/refine/prompts/idea-wizard.md`

```markdown
# Idea Generation

Session: ${SESSION_NAME}

## Your Task

Come up with your very best ideas for improving this project...

[Full idea-wizard prompt from sub-agents.md]

## Output Format

[Standard output format - no loop integration needed]
```

### 4. State File: `.claude/refine-sessions.json`

```json
{
  "sessions": {
    "refine-myproject": {
      "mode": "beads",
      "started_at": "2026-01-09T10:00:00Z",
      "iterations_completed": 5,
      "total_changes": 18,
      "status": "running",
      "plateau_at": null,
      "history": [
        {"iteration": 1, "changes": 5, "summary": "Added test beads"},
        {"iteration": 2, "changes": 4, "summary": "Clarified dependencies"},
        {"iteration": 3, "changes": 3, "summary": "Refined acceptance criteria"},
        {"iteration": 4, "changes": 2, "summary": "Minor wording fixes"},
        {"iteration": 5, "changes": 1, "summary": "Cosmetic tweaks"}
      ]
    }
  }
}
```

### 5. Integration with run-loop Skill

**Option A: Extend run-loop skill**
- Add "Refine" option to intake
- Route to refine-specific workflows
- Share tmux/state infrastructure

**Option B: Separate refine-loop skill** (Recommended)
- Dedicated skill for refinement loops
- Cleaner separation of concerns
- Can import shared utilities

### 6. Commands Integration

#### `/refine` command flow:

```
User: /refine

1. Check for beads vs plan
2. Ask: "Run in foreground or background?"
   - Foreground: Run in current session (orchestrator pattern)
   - Background: Start tmux session (script pattern)

3a. Foreground:
    - Loop in conversation
    - Good for 3-5 iterations
    - User sees progress live

3b. Background:
    - tmux new-session -d -s refine-NAME ...
    - User can detach and come back
    - Good for 6-10+ iterations
```

#### `/ideate` command flow:

```
User: /ideate

1. Gather context (beads or codebase)
2. Spawn single Opus agent (idea-wizard prompt)
3. Display results
4. Offer: "Add to beads?" / "Save to file?"

No loop needed - single shot.
```

## Directory Structure

```
scripts/refine/
├── refine-loop.sh           # Main loop runner
├── refine-once.sh           # Single iteration (test mode)
├── prompts/
│   ├── bead-refiner.md      # Bead refinement prompt
│   ├── plan-improver.md     # Plan improvement prompt
│   ├── idea-wizard.md       # Idea generation prompt
│   ├── context-loader.md    # Context loading prompt
│   ├── post-context.md      # Post-context review prompt
│   ├── synthesizer.md       # Plan synthesis prompt
│   └── robot-mode.md        # Robot mode design prompt
└── README.md                # Quick usage guide
```

## Implementation Phases

### Phase 1: Core Loop Infrastructure
1. Create `scripts/refine/` directory
2. Implement `refine-loop.sh` with plateau detection
3. Implement `refine-once.sh` for testing
4. Create bead-refiner prompt with CHANGES output
5. Create plan-improver prompt with CHANGES output
6. Test single iteration manually

### Phase 2: State Management
1. Create state file schema
2. Add state updates to scripts
3. Add completion recording
4. Add desktop notifications

### Phase 3: Skill Integration
1. Update `/refine` command to offer foreground/background
2. Add background mode workflow to plan-refinery skill
3. Add monitoring commands (peek, attach, kill)
4. Test full loop in tmux

### Phase 4: Additional Agents
1. Create prompt files for all 7 agents
2. Add `/ideate` as single-shot command
3. Add `/plan-refinery synthesize` workflow
4. Add `/plan-refinery robot` workflow

### Phase 5: Polish
1. Progress visualization
2. Cumulative change tracking
3. Fresh session recommendations
4. Integration with calibration (decision traces)

## Key Design Decisions

### 1. Plateau Detection Algorithm

```python
# Plateau = 2+ consecutive rounds with ≤1 change each
# Only trigger after minimum 3 iterations

if changes <= 1 and last_changes <= 2:
    plateau_count += 1
else:
    plateau_count = 0

if plateau_count >= 2 and iteration >= 3:
    PLATEAU_DETECTED
```

### 2. Output Parsing

Each agent prompt MUST end with:
```
CHANGES: {number}
SUMMARY: {one-line}
```

Script parses with:
```bash
CHANGES=$(echo "$OUTPUT" | grep "^CHANGES:" | cut -d: -f2 | tr -d ' ')
```

### 3. Foreground vs Background

| Mode | Use When | Implementation |
|------|----------|----------------|
| Foreground | Quick refinement (3-5 iterations) | Orchestrator spawns Task agents sequentially |
| Background | Deep refinement (6-10+ iterations) | tmux + script + fresh claude per iteration |

### 4. Fresh Session Recommendation

When plateau detected after only 3-4 iterations, suggest:
```
⚠️ Plateau detected early (iteration 4)
💡 Consider starting a fresh CC session for new perspective:
   /plan-refinery context → /plan-refinery review
```

## Success Criteria

- [ ] `refine-once.sh` runs single iteration successfully
- [ ] `refine-loop.sh` detects plateau and stops
- [ ] State file tracks iteration history
- [ ] Desktop notification on completion
- [ ] `/refine` command works in foreground mode
- [ ] `/refine` command works in background mode (tmux)
- [ ] `/ideate` runs idea-wizard successfully
- [ ] All 7 agent prompts created and tested
- [ ] Integration with existing run-loop patterns

## Open Questions

1. **Foreground iteration limit?**
   - Opus context is large but finite
   - Maybe cap foreground at 5 iterations, force background for more?

2. **Plan file mutation?**
   - plan-improver proposes changes
   - Auto-apply or require confirmation?
   - Git commit between iterations?

3. **Cross-agent workflows?**
   - idea-wizard → beads → refine-loop
   - Should this be a single command or user-orchestrated?

## Next Steps

1. Create `scripts/refine/` directory structure
2. Implement `refine-once.sh` with bead-refiner prompt
3. Test single iteration
4. Implement `refine-loop.sh` with plateau detection
5. Test full loop
6. Integrate with commands
