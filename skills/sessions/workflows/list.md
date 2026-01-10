# Workflow: List All Sessions

Show all running loop and pipeline sessions with their status.

## Step 1: Get Running tmux Sessions

```bash
tmux list-sessions 2>/dev/null | grep -E "^(loop-|pipeline-)" || echo "NONE"
```

## Step 2: Load State File

```bash
if [ -f .claude/loop-sessions.json ]; then
  cat .claude/loop-sessions.json | jq '.sessions'
else
  echo "No state file found"
fi
```

## Step 3: Cross-Reference and Build Table

For each session in tmux OR state file:

```bash
# Check if session is actually running
tmux has-session -t {session-name} 2>/dev/null && echo "running" || echo "stopped"
```

Build a table:

```
Running Sessions
================

| Session | Type | Loop/Pipeline | Age | Status |
|---------|------|---------------|-----|--------|
| loop-auth | loop | work | 45m | running |
| pipeline-refine | pipeline | full-refine.yaml | 2h | running |

Completed Sessions (in state file but not running)
==================================================

| Session | Type | Completed | Reason |
|---------|------|-----------|--------|
| loop-billing | loop | 2 hours ago | beads-empty |
```

## Step 4: Check for Orphaned Sessions

Sessions in tmux but NOT in our state file:

```bash
# Get tmux sessions
TMUX_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^(loop-|pipeline-)")

# Get tracked sessions
TRACKED=$(cat .claude/loop-sessions.json 2>/dev/null | jq -r '.sessions | keys[]')

# Find orphans
for sess in $TMUX_SESSIONS; do
  if ! echo "$TRACKED" | grep -q "^$sess$"; then
    echo "ORPHAN: $sess"
  fi
done
```

If orphans found, warn:
```
WARNING: Found untracked sessions. These may be from previous runs.
Consider running 'Cleanup' to handle them.
```

## Step 5: Check for Stale Sessions

Sessions running > 2 hours:

```bash
cat .claude/loop-sessions.json | jq -r '
  .sessions | to_entries[] |
  select(.value.status == "running") |
  "\(.key) \(.value.started_at)"
' | while read name started; do
  START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" "+%s" 2>/dev/null || date -d "$started" "+%s" 2>/dev/null || echo "0")
  NOW_EPOCH=$(date "+%s")
  AGE_MINS=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
  if [ $AGE_MINS -gt 120 ]; then
    echo "STALE: $name ($AGE_MINS minutes)"
  fi
done
```

If stale found:
```
WARNING: Some sessions have been running for over 2 hours.
This may indicate a stuck loop or forgotten session.
Consider monitoring them or running 'Cleanup'.
```

## Step 6: Show Summary

```
Summary
=======
Running: {X} sessions
Stale (>2h): {Y} sessions
Orphaned: {Z} sessions

Quick Commands:
  Monitor:  /loop-agents:sessions → Monitor
  Attach:   tmux attach -t {session-name}
  Kill:     tmux kill-session -t {session-name}
  Cleanup:  /loop-agents:sessions → Cleanup
```

## Step 7: Offer Actions

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Action",
    "options": [
      {"label": "Monitor a session", "description": "Peek at a specific session"},
      {"label": "Cleanup", "description": "Handle stale/orphaned sessions"},
      {"label": "Done", "description": "Just wanted to see the list"}
    ],
    "multiSelect": false
  }]
}
```

## Success Criteria

- [ ] All tmux sessions listed
- [ ] State file cross-referenced
- [ ] Age and status shown for each
- [ ] Orphaned sessions identified
- [ ] Stale sessions warned about
- [ ] Clear next actions offered
