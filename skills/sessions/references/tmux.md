# tmux Command Reference

Complete reference for tmux commands used in session management.

## Session Management

### Create Sessions

```bash
# Create detached session (runs in background)
tmux new-session -d -s SESSION_NAME -c WORKING_DIR "COMMAND"

# Example: Start a work loop
tmux new-session -d -s loop-auth -c "$(pwd)" "./scripts/run.sh loop work auth 50"

# Example: Start a pipeline
tmux new-session -d -s pipeline-refine -c "$(pwd)" "./scripts/run.sh pipeline full-refine.yaml auth"
```

**Flags:**
- `-d` - Detach immediately (don't attach terminal)
- `-s NAME` - Session name
- `-c DIR` - Working directory
- Last argument is the command to run

### Check If Session Exists

```bash
tmux has-session -t SESSION_NAME 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"
```

### List Sessions

```bash
# All sessions
tmux list-sessions

# Just names
tmux list-sessions -F "#{session_name}"

# Filter to our sessions
tmux list-sessions -F "#{session_name}" | grep -E "^(loop-|pipeline-)"

# With creation time
tmux list-sessions -F "#{session_name}|#{session_created}"
```

### Kill Sessions

```bash
# Kill specific session
tmux kill-session -t SESSION_NAME

# Kill all sessions matching pattern (be careful!)
tmux list-sessions -F "#{session_name}" | grep "^loop-" | xargs -I {} tmux kill-session -t {}
```

## Viewing Output

### Capture Pane Content

```bash
# Capture visible content (what you'd see if attached)
tmux capture-pane -t SESSION_NAME -p

# Last N lines
tmux capture-pane -t SESSION_NAME -p | tail -50

# With scrollback history (S = start line, negative = scrollback)
tmux capture-pane -t SESSION_NAME -p -S -500

# Last 100 lines from scrollback
tmux capture-pane -t SESSION_NAME -p -S -500 | tail -100
```

**Important:** `capture-pane` is safe - it doesn't attach or interfere with the running process.

### Attach to Session (Interactive)

```bash
# Attach (takes over your terminal)
tmux attach -t SESSION_NAME

# Attach read-only (can't type, just watch)
tmux attach -t SESSION_NAME -r
```

**Detaching:**
- `Ctrl+b`, then `d` - Detach and leave session running
- `Ctrl+c` - **KILLS THE RUNNING PROCESS** (don't use unless intentional)

## Window and Pane Info

```bash
# Get active pane dimensions
tmux display -t SESSION_NAME -p "#{pane_width}x#{pane_height}"

# Get pane contents as of now
tmux capture-pane -t SESSION_NAME -p

# Check if pane has a running command
tmux list-panes -t SESSION_NAME -F "#{pane_current_command}"
```

## Session Information

```bash
# Session creation time (Unix timestamp)
tmux display -t SESSION_NAME -p "#{session_created}"

# Session activity time (last interaction)
tmux display -t SESSION_NAME -p "#{session_activity}"

# Is session attached?
tmux display -t SESSION_NAME -p "#{session_attached}"
```

## Environment and Working Directory

```bash
# Get session's current working directory
tmux display -t SESSION_NAME -p "#{pane_current_path}"

# Get environment variables (complex)
tmux show-environment -t SESSION_NAME
```

## Common Patterns

### Start and Verify

```bash
# Start
tmux new-session -d -s loop-myfeature -c "$(pwd)" "./scripts/run.sh loop work myfeature 25"

# Wait a moment
sleep 1

# Verify running
tmux has-session -t loop-myfeature 2>/dev/null && echo "Started" || echo "Failed"
```

### Safe Monitoring Loop

```bash
# Watch output every 5 seconds without attaching
while true; do
  clear
  echo "=== $(date) ==="
  tmux capture-pane -t loop-myfeature -p | tail -30
  sleep 5
done
```

### Check Multiple Sessions

```bash
for sess in $(tmux list-sessions -F "#{session_name}" | grep "^loop-"); do
  echo "--- $sess ---"
  tmux capture-pane -t "$sess" -p | tail -5
  echo
done
```

### Clean Exit Detection

The session ends when the command completes. Check with:

```bash
# Session gone = command finished
if ! tmux has-session -t SESSION_NAME 2>/dev/null; then
  echo "Session completed"
  # Check exit status in our state files
fi
```

## Troubleshooting

### Session Won't Start

```bash
# Check if tmux server is running
tmux list-sessions 2>/dev/null || echo "No tmux server"

# Start a test session to verify tmux works
tmux new-session -d -s test echo "hello" && tmux kill-session -t test
```

### Can't Capture Output

```bash
# Session might not have a pane yet
tmux list-panes -t SESSION_NAME

# Wait for pane to be created
sleep 2
tmux capture-pane -t SESSION_NAME -p
```

### Session Crashed

```bash
# Session gone unexpectedly - check for logs
# Our scripts log to .claude/loop-progress/

# Check system logs
tail -50 /var/log/system.log | grep -i tmux
```

## Key Bindings (When Attached)

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach from session |
| `Ctrl+b [` | Enter scroll mode (use arrows/PgUp/PgDn) |
| `q` | Exit scroll mode |
| `Ctrl+b :` | tmux command prompt |
| `Ctrl+b ?` | List all key bindings |

**WARNING:** `Ctrl+c` sends SIGINT to the running process - this will KILL your agent!
