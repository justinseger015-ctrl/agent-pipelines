# Workflow: Attach to a Session

Connect to watch a session live. The user will take over their terminal.

## Step 1: List Running Sessions

```bash
tmux list-sessions 2>/dev/null | grep -E "^(loop-|pipeline-)" || echo "No sessions running"
```

If no sessions running, tell the user and stop.

## Step 2: Select Session

If multiple sessions, use AskUserQuestion to pick one.

## Step 3: Explain What Will Happen

Tell the user:

```
Attaching to {session-name} will connect your terminal to the session.

You'll see:
- Live output from the running agent
- The agent's interactions with files and tools

Controls:
- Ctrl+b, then d    - Detach (return to Claude Code)
- Ctrl+c            - WARNING: Will kill the running agent!

The session continues running after you detach.
```

## Step 4: Verify Session Still Running

```bash
tmux has-session -t {session-name} 2>/dev/null && echo "RUNNING" || echo "GONE"
```

If GONE, tell the user the session has ended.

## Step 5: Provide Attach Command

Tell the user to run:

```
To attach, run this command in a separate terminal:

  tmux attach -t {session-name}

(Claude Code cannot attach for you - you need to run this yourself)

To detach and return: Press Ctrl+b, then d
```

**Important:** Claude cannot execute `tmux attach` because it takes over the terminal. The user must run it themselves.

## Step 6: Alternative - Show Scrollback

If the user can't or doesn't want to attach, offer to show more output:

```bash
# Show more context with scrollback
tmux capture-pane -t {session-name} -p -S -500 | tail -200
```

This shows the last 200 lines from the last 500 lines of scrollback.

## Step 7: Offer to Return to Monitor

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Next",
    "options": [
      {"label": "Show more output", "description": "Display more scrollback history"},
      {"label": "Monitor instead", "description": "Go back to safe monitoring"},
      {"label": "Done", "description": "I'll attach myself"}
    ],
    "multiSelect": false
  }]
}
```

## Success Criteria

- [ ] Session validated as running
- [ ] User warned about Ctrl+c danger
- [ ] Clear attach command provided
- [ ] User understands how to detach
- [ ] Alternative scrollback option offered
