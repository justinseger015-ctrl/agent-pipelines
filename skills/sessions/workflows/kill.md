# Workflow: Kill a Session

Terminate a running session and clean up its state.

## Step 1: List Running Sessions

```bash
tmux list-sessions 2>/dev/null | grep -E "^(loop-|pipeline-)" || echo "NONE"
```

If no sessions running, tell the user and stop.

## Step 2: Select Session

If multiple sessions, use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Which session do you want to kill?",
    "header": "Session",
    "options": [
      {"label": "loop-auth", "description": "Running for 45 minutes"},
      {"label": "pipeline-refine", "description": "Running for 2 hours"}
    ],
    "multiSelect": false
  }]
}
```

## Step 3: Confirm Termination

```json
{
  "questions": [{
    "question": "Are you sure you want to kill '{session-name}'? This will stop any running work immediately.",
    "header": "Confirm",
    "options": [
      {"label": "Yes, kill it", "description": "Terminate the session now"},
      {"label": "No, keep it", "description": "Don't terminate"}
    ],
    "multiSelect": false
  }]
}
```

If "No", return to main menu.

## Step 4: Capture Final State

Before killing, capture what was happening:

```bash
# Capture last output for debugging
tmux capture-pane -t {session-name} -p > /tmp/session-{session-name}-final.txt 2>/dev/null

echo "Final output saved to /tmp/session-{session-name}-final.txt"
```

## Step 5: Kill the Session

```bash
tmux kill-session -t {session-name}
```

Verify it's gone:

```bash
tmux has-session -t {session-name} 2>/dev/null && echo "FAILED TO KILL" || echo "KILLED"
```

## Step 6: Update State File

```bash
if [ -f .claude/loop-sessions.json ]; then
  # Update status to 'killed' instead of removing
  cat .claude/loop-sessions.json | jq --arg name "{session-name}" \
    --arg killed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.sessions[$name].status = "killed" |
     .sessions[$name].killed_at = $killed' > .claude/loop-sessions.json.tmp
  mv .claude/loop-sessions.json.tmp .claude/loop-sessions.json
fi
```

## Step 7: Check for Incomplete Work

For loops, check if there are remaining beads:

```bash
if [[ "{session-name}" == loop-* ]]; then
  SESSION_TAG="${{session-name}#loop-}"
  REMAINING=$(bd ready --label="loop/$SESSION_TAG" 2>/dev/null | wc -l)
  if [ "$REMAINING" -gt 0 ]; then
    echo "NOTE: There are still $REMAINING beads remaining for this session"
    echo "View with: bd ready --label=loop/$SESSION_TAG"
  fi
fi
```

For pipelines, check what stage it was on:

```bash
if [[ "{session-name}" == pipeline-* ]]; then
  SESSION_TAG="${{session-name}#pipeline-}"
  if [ -f ".claude/pipeline-runs/$SESSION_TAG/state.json" ]; then
    echo "Pipeline state at termination:"
    cat ".claude/pipeline-runs/$SESSION_TAG/state.json" | jq '{
      current_stage: .current_stage,
      completed_stages: .completed_stages,
      status: .status
    }'
  fi
fi
```

## Step 8: Show Confirmation

```
Session killed: {session-name}

State file updated.
Final output saved to: /tmp/session-{session-name}-final.txt

{If remaining beads:}
NOTE: {N} beads still remain. To restart work:
  /loop-agents:sessions → Start Loop → work → {session-name}

{If partial pipeline:}
NOTE: Pipeline was on stage {X} of {Y}. Stages 1-{X-1} are complete.
To restart from the beginning:
  /loop-agents:sessions → Start Pipeline
```

## Step 9: Offer Next Actions

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Next",
    "options": [
      {"label": "View final output", "description": "See what was happening when killed"},
      {"label": "Restart session", "description": "Start the same loop/pipeline again"},
      {"label": "List sessions", "description": "See other running sessions"},
      {"label": "Done", "description": "Finished"}
    ],
    "multiSelect": false
  }]
}
```

## Success Criteria

- [ ] Session confirmed before killing
- [ ] Final output captured
- [ ] tmux session terminated
- [ ] State file updated with killed status
- [ ] User informed of remaining work (if any)
- [ ] Clear restart instructions provided
