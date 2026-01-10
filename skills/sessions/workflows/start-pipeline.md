# Workflow: Start a Pipeline

Start a multi-stage pipeline in a tmux background session.

## Step 1: Discover Available Pipelines

```bash
ls scripts/pipelines/*.yaml 2>/dev/null || echo "No pipelines found"
```

If pipelines exist, show what's available. Common pipelines:
- `quick-refine.yaml` - 3+3 iterations (improve-plan → refine-beads)
- `full-refine.yaml` - 5+5 iterations (standard)
- `deep-refine.yaml` - 8+8 iterations (thorough)
- Any custom pipelines

If no pipelines exist, tell the user:
```
No pipelines found in scripts/pipelines/

To create a pipeline, use the pipeline-builder skill:
  /loop-agents:pipeline-builder

Or create a pipeline YAML manually in scripts/pipelines/
```

## Step 2: Select Pipeline

Use AskUserQuestion with discovered pipelines:

```json
{
  "questions": [{
    "question": "Which pipeline do you want to run?",
    "header": "Pipeline",
    "options": [
      {"label": "quick-refine", "description": "Fast 3+3 iteration refinement"},
      {"label": "full-refine", "description": "Standard 5+5 iteration refinement"},
      {"label": "deep-refine", "description": "Thorough 8+8 iteration refinement"}
    ],
    "multiSelect": false
  }]
}
```

Adapt options based on what actually exists. If they choose "Other", ask which file.

## Step 3: Get Session Name

```json
{
  "questions": [{
    "question": "What should we call this pipeline session?",
    "header": "Session Name",
    "options": [
      {"label": "Let me type a name", "description": "I'll provide a custom session name"}
    ],
    "multiSelect": false
  }]
}
```

Session name rules:
- Lowercase letters and hyphens only
- No spaces
- Examples: `auth-refine`, `billing-plan`, `api-design`

The tmux session will be `pipeline-{session-name}`.

## Step 4: Check for Conflicts

```bash
# Check if session already exists
tmux has-session -t pipeline-{session-name} 2>/dev/null && echo "EXISTS" || echo "AVAILABLE"
```

If EXISTS:
```json
{
  "questions": [{
    "question": "A session named 'pipeline-{session-name}' already exists. What should we do?",
    "header": "Conflict",
    "options": [
      {"label": "Attach to existing", "description": "Connect to the running session"},
      {"label": "Kill and restart", "description": "Stop existing and start fresh"},
      {"label": "Choose different name", "description": "I'll pick another name"}
    ],
    "multiSelect": false
  }]
}
```

## Step 5: Validate Prerequisites

```bash
# Check pipeline file exists
PIPELINE_FILE="scripts/pipelines/{pipeline-name}.yaml"
test -f "$PIPELINE_FILE" && echo "OK" || echo "MISSING: $PIPELINE_FILE"

# Check run script exists
test -f scripts/run.sh && echo "OK" || echo "MISSING: scripts/run.sh"

# Check pipeline references valid loops
# Parse stages and verify each loop exists
python3 -c "
import yaml
with open('$PIPELINE_FILE') as f:
    p = yaml.safe_load(f)
for stage in p.get('stages', []):
    loop = stage.get('loop')
    if loop:
        import os
        if not os.path.isdir(f'scripts/loops/{loop}'):
            print(f'MISSING: scripts/loops/{loop}/')
"
```

If anything is missing, warn the user and stop.

## Step 6: Show Pipeline Summary

Read the pipeline and display what will run:

```bash
python3 -c "
import yaml
with open('scripts/pipelines/{pipeline-name}.yaml') as f:
    p = yaml.safe_load(f)
print(f\"Pipeline: {p.get('name', 'unnamed')}\")
print(f\"Description: {p.get('description', 'No description')}\")
print()
print('Stages:')
for i, stage in enumerate(p.get('stages', []), 1):
    loop = stage.get('loop', 'inline')
    runs = stage.get('runs', 1)
    name = stage.get('name', f'stage-{i}')
    print(f'  {i}. {name}: {loop} x {runs} iterations')
"
```

## Step 7: Start the Session

```bash
# Get absolute path
PROJECT_PATH="$(pwd)"

# Start detached tmux session
tmux new-session -d -s "pipeline-{session-name}" -c "$PROJECT_PATH" \
  "./scripts/run.sh pipeline {pipeline-name}.yaml {session-name}"
```

## Step 8: Verify Session Started

```bash
sleep 1
tmux has-session -t pipeline-{session-name} 2>/dev/null && echo "RUNNING" || echo "FAILED"
```

If FAILED:
```bash
tmux capture-pane -t pipeline-{session-name} -p 2>/dev/null || echo "Session failed to start"
```

## Step 9: Update State File

```bash
mkdir -p .claude

if [ -f .claude/loop-sessions.json ]; then
  EXISTING=$(cat .claude/loop-sessions.json)
else
  EXISTING='{"sessions":{}}'
fi

echo "$EXISTING" | jq --arg name "pipeline-{session-name}" \
  --arg type "pipeline" \
  --arg pipeline_file "{pipeline-name}.yaml" \
  --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg path "$PROJECT_PATH" \
  '.sessions[$name] = {
    "type": $type,
    "pipeline_file": $pipeline_file,
    "started_at": $started,
    "project_path": $path,
    "status": "running"
  }' > .claude/loop-sessions.json
```

## Step 10: Show Success Message

```
Pipeline started: pipeline-{session-name}

Pipeline: {pipeline-name}.yaml
Stages: [list stages from summary]

Quick commands:
  Monitor:  tmux capture-pane -t pipeline-{session-name} -p | tail -50
  Attach:   tmux attach -t pipeline-{session-name}
  Detach:   Ctrl+b, then d
  Kill:     tmux kill-session -t pipeline-{session-name}

Progress tracking:
  State:    cat .claude/pipeline-runs/{session-name}/state.json
  Stages:   ls .claude/pipeline-runs/{session-name}/

The pipeline is running in the background. Use 'Monitor' to check progress.
```

## Success Criteria

- [ ] Pipeline file exists and is valid
- [ ] All referenced loops exist
- [ ] Session name collected (lowercase, hyphens)
- [ ] No naming conflicts (or resolved)
- [ ] tmux session started successfully
- [ ] State file updated with session info
- [ ] User shown monitoring instructions
