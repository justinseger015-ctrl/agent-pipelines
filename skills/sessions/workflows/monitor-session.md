# Workflow: Monitor Session

Peek at session output without attaching (non-interactive view).

<required_reading>
**Read these reference files NOW:**
1. references/commands.md
</required_reading>

<process>
## Step 1: Get Session Name

If session name not provided, list available and ask:

```bash
# Get running sessions
sessions=$(tmux list-sessions 2>/dev/null | grep -E "^loop-" | cut -d: -f1 | sed 's/^loop-//')

if [ -z "$sessions" ]; then
    echo "No running sessions to monitor."
    exit 0
fi
```

Use AskUserQuestion if multiple sessions:

```json
{
  "questions": [{
    "question": "Which session do you want to monitor?",
    "header": "Session",
    "options": [
      {"label": "auth", "description": "work - iteration 5/25"},
      {"label": "billing", "description": "improve-plan - iteration 3/5"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Verify Session Exists

```bash
if ! tmux has-session -t "loop-${session}" 2>/dev/null; then
    echo "Session '${session}' is not running."

    # Check if it completed or crashed
    if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
        status=$(jq -r .status ".claude/pipeline-runs/${session}/state.json")
        echo "Status: ${status}"

        if [ "$status" = "complete" ]; then
            echo "Session completed. View results:"
            echo "  cat .claude/pipeline-runs/${session}/progress-${session}.md"
        elif [ "$status" = "failed" ]; then
            echo "Session failed. Resume with:"
            echo "  ./scripts/run.sh {type} ${session} {max} --resume"
        fi
    fi
    exit 1
fi
```

## Step 3: Capture Current Output

```bash
# Capture last 50 lines of tmux pane
tmux capture-pane -t "loop-${session}" -p | tail -50
```

## Step 4: Show Status Context

Before the output, show session context:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SESSION: auth
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Type:      work
Iteration: 5/25
Status:    running
Started:   2025-01-10 10:00:00 (2h 15m ago)

Last 50 lines of output:
─────────────────────────────────────────────────────────────
[tmux capture output here]
─────────────────────────────────────────────────────────────
```

### Get Status from State File

```bash
if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    jq '{
        session,
        loop_type,
        iteration,
        status,
        started_at
    }' ".claude/pipeline-runs/${session}/state.json"
fi
```

## Step 5: Check for Beads Progress (Work Sessions)

For work sessions, show beads status:

```bash
# Check remaining beads
remaining=$(bd ready --label="loop/${session}" 2>/dev/null | wc -l)
completed=$(bd list --label="loop/${session}" --status=closed 2>/dev/null | wc -l)

echo "Beads: ${completed} completed, ${remaining} remaining"
```

## Step 6: Provide Next Actions

```
Actions:
  • Attach (live): tmux attach -t loop-${session}  (Ctrl+b, d to detach)
  • Refresh:       tmux capture-pane -t loop-${session} -p | tail -50
  • Status:        ./scripts/run.sh status ${session}
  • Kill:          tmux kill-session -t loop-${session}
```
</process>

<success_criteria>
Monitor session workflow is complete when:
- [ ] Session name obtained (from arg or user selection)
- [ ] Session existence verified
- [ ] Status context shown (type, iteration, runtime)
- [ ] Current output captured and displayed
- [ ] Beads progress shown (for work sessions)
- [ ] Next actions provided
</success_criteria>
