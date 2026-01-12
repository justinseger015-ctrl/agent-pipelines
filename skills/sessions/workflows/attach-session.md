# Workflow: Attach to Session

Connect to a running session to watch live output. This is read-only observation.

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
    echo "No running sessions to attach to."
    exit 0
fi
```

Use AskUserQuestion if multiple sessions:

```json
{
  "questions": [{
    "question": "Which session do you want to attach to?",
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
if ! tmux has-session -t "pipeline-${session}" 2>/dev/null; then
    echo "Session '${session}' is not running."

    # Check state for context
    if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
        status=$(jq -r .status ".claude/pipeline-runs/${session}/state.json")
        echo "Session status: ${status}"

        if [ "$status" = "complete" ] || [ "$status" = "failed" ]; then
            echo ""
            echo "This session has ended. To view results:"
            echo "  cat .claude/pipeline-runs/${session}/progress-${session}.md"
        fi
    fi
    exit 1
fi
```

## Step 3: Provide Attach Instructions

**IMPORTANT:** Claude cannot execute tmux attach directly in this context. Provide clear instructions for the user to run manually.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ATTACH TO SESSION: ${session}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Run this command in your terminal:

  tmux attach -t pipeline-${session}

Once attached:
  • You're watching live output (read-only)
  • The loop agent is running autonomously
  • DO NOT type or interact - it may interfere

To detach (leave session running):
  Press: Ctrl+b, then d

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Step 4: Show Current State Before Attach

Give context about what they'll see:

```bash
# Get current state
if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    echo "Current state:"
    jq '{
        type: .loop_type,
        iteration: .iteration,
        status: .status,
        started: .started_at
    }' ".claude/pipeline-runs/${session}/state.json"
fi

# Show last few lines as preview
echo ""
echo "Recent output preview:"
tmux capture-pane -t "pipeline-${session}" -p | tail -10
```

## Step 5: Explain What They'll See

```
What to expect:
  • Each iteration shows the agent working on tasks
  • Look for "Iteration N complete" markers
  • Progress is saved to: .claude/pipeline-runs/${session}/progress-${session}.md
  • State tracked in: .claude/pipeline-runs/${session}/state.json

If session seems stuck:
  • Check iteration progress over time
  • Sessions > 2 hours may indicate issues
  • Consider: /agent-pipelines:sessions kill ${session}
```
</process>

<success_criteria>
Attach session workflow is complete when:
- [ ] Session name obtained
- [ ] Session existence verified
- [ ] Clear attach command provided
- [ ] Detach instructions given (Ctrl+b, d)
- [ ] Current state shown as preview
- [ ] User understands this is read-only observation
</success_criteria>
