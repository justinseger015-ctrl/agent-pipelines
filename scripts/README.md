# Loop Scripts

Autonomous execution through the universal loop engine.

## Architecture

```
scripts/
├── loops/                     # Loop engine + loop types
│   ├── engine.sh              # Universal loop runner
│   ├── run.sh                 # Convenience wrapper
│   ├── config.sh              # Loop configuration loader
│   ├── lib/                   # Shared utilities
│   ├── completions/           # Stopping conditions
│   │   ├── beads-empty.sh
│   │   ├── plateau.sh
│   │   └── fixed-n.sh
│   ├── work/                  # Loop type: implementation
│   ├── improve-plan/          # Loop type: plan refinement
│   ├── refine-beads/          # Loop type: bead refinement
│   └── idea-wizard/           # Loop type: idea generation
│
└── pipelines/                 # Pipeline engine + definitions
    ├── run.sh                 # Pipeline runner
    ├── lib/                   # Parsing, resolution, providers
    ├── SCHEMA.md              # Pipeline schema reference
    ├── quick-refine.yaml      # 3+3 iterations
    ├── full-refine.yaml       # 5+5 iterations
    └── deep-refine.yaml       # 8+8 iterations
```

## Usage

### Running Loops

```bash
PLUGIN_DIR=".claude/loop-agents"

# Work loop - implement tasks from beads
$PLUGIN_DIR/scripts/loops/run.sh work my-feature 25

# Plan refinement - improve docs/plans/
$PLUGIN_DIR/scripts/loops/run.sh improve-plan my-session 5

# Bead refinement - improve bead quality
$PLUGIN_DIR/scripts/loops/run.sh refine-beads my-session 5

# Idea generation - brainstorm improvements
$PLUGIN_DIR/scripts/loops/run.sh idea-wizard ideas 3
```

### Running in Background (tmux)

```bash
SESSION_NAME="auth"
PLUGIN_DIR=".claude/loop-agents"

# Start work loop in background
tmux new-session -d -s "loop-$SESSION_NAME" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/loops/run.sh work $SESSION_NAME 25"

# Monitor
tmux capture-pane -t "loop-$SESSION_NAME" -p | tail -20

# Attach (Ctrl+b d to detach)
tmux attach -t "loop-$SESSION_NAME"

# Kill
tmux kill-session -t "loop-$SESSION_NAME"
```

### Running Pipelines

```bash
# Refine plans then beads
$PLUGIN_DIR/scripts/pipelines/run.sh $PLUGIN_DIR/scripts/pipelines/full-refine.yaml my-session

# Quick pass
$PLUGIN_DIR/scripts/pipelines/run.sh $PLUGIN_DIR/scripts/pipelines/quick-refine.yaml my-session

# Thorough pass
$PLUGIN_DIR/scripts/pipelines/run.sh $PLUGIN_DIR/scripts/pipelines/deep-refine.yaml my-session
```

### Pipeline Format

Pipelines can reference existing loop types or define inline prompts:

```yaml
# Reference existing loop types
stages:
  - name: improve-plan
    loop: improve-plan    # Uses loops/improve-plan/prompt.md
    runs: 5

  - name: refine-beads
    loop: refine-beads
    runs: 5

# Or define inline prompts
stages:
  - name: custom-review
    runs: 4
    perspectives: [security, performance, clarity, testing]
    prompt: |
      Review from ${PERSPECTIVE} perspective.
      Write to ${OUTPUT}
```

## Loop Types

| Type | Stops When | Use Case |
|------|------------|----------|
| `work` | All beads complete | Implementing tasks |
| `improve-plan` | 2 agents agree it's ready | Plan refinement |
| `refine-beads` | 2 agents agree it's ready | Bead quality |
| `idea-wizard` | Fixed iterations | Idea generation |

## Creating New Loop Types

```bash
mkdir -p scripts/loops/my-loop
```

Create `loop.yaml`:
```yaml
name: my-loop
description: What this loop does
completion: plateau  # beads-empty, plateau, all-items
delay: 3
```

Create `prompt.md`:
```markdown
# My Loop Agent

Session: ${SESSION_NAME}
Progress: ${PROGRESS_FILE}

## Instructions
...
```

## Output Files

Progress and state files are created in YOUR project:

```
.claude/
├── loop-progress/
│   └── progress-{session}.txt   # Accumulated learnings
├── loop-state-{session}.json    # Iteration history
└── loop-completions.json        # Completion notifications
```

## Multi-Session Support

Run multiple loops simultaneously:

```bash
# Different features in parallel
tmux new-session -d -s "loop-auth" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/loops/run.sh work auth 25"

tmux new-session -d -s "loop-api" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/loops/run.sh work api 25"
```

Each session has:
- Separate beads (`loop/auth` vs `loop/api`)
- Separate progress file
- Separate state file
- No conflicts
