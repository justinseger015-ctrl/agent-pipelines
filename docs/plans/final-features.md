# Final Features: Hooks, Marketplace, Pipeline Cycles

> Three features that complete agent-pipelines as a production-ready, community-driven orchestrator.

**Status:** Planning
**Author:** Harrison Wells
**Date:** 2026-01-14

---

## Overview

| Feature | What | Why |
|---------|------|-----|
| **Hooks** | Lifecycle events with shell, webhook, spawn actions | Notifications, approvals, quality gates, nested pipelines |
| **Marketplace** | Built-in + user + community workflow library | Easy discovery, sharing, growing collection of templates |
| **Pipeline Cycles** | Run entire multi-stage pipelines N times | Complex multi-agent workflows that iterate as a unit |

---

# Part 1: Hook System

## Concept

Hooks fire at pipeline lifecycle events. Each hook can run one or more actions. Actions can be fire-and-forget or blocking (await).

```yaml
hooks:
  on_session_complete:
    - type: shell
      command: "notify-send 'Pipeline ${SESSION} done!'"

    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Pipeline completed" }
```

## Hook Points

| Hook Point | When It Fires |
|------------|---------------|
| `on_session_start` | Before first iteration of entire pipeline |
| `on_iteration_start` | Before each Claude invocation |
| `on_iteration_complete` | After each successful iteration |
| `on_stage_complete` | When a pipeline stage finishes (multi-stage only) |
| `on_session_complete` | When pipeline finishes (success or max iterations) |
| `on_error` | When an iteration fails |

## Action Types

### Shell Actions

Run arbitrary shell commands.

```yaml
hooks:
  on_iteration_complete:
    # Fire-and-forget (default)
    - type: shell
      command: "./scripts/backup-progress.sh ${PROGRESS}"

    # Blocking - wait for completion
    - type: shell
      command: "./scripts/run-tests.sh"
      await: true
      timeout: 300          # seconds
      on_failure: abort     # abort | continue | retry
```

**Fields:**

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `command` | yes | - | Shell command to execute |
| `await` | no | false | Wait for completion |
| `timeout` | no | 300 | Max seconds to wait |
| `on_failure` | no | continue | What to do if command fails |
| `retries` | no | 3 | Retry attempts if `on_failure: retry` |
| `retry_delay` | no | 5 | Seconds between retries |

### Webhook Actions

Send HTTP requests for notifications or external integrations.

```yaml
hooks:
  on_session_complete:
    # Slack notification
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      method: POST
      body:
        text: ":white_check_mark: Pipeline ${SESSION} completed in ${ITERATION} iterations"

  on_stage_complete:
    # Blocking approval (human-in-the-loop)
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Plan ready for review"
        actions:
          - label: "Approve"
            callback: "${CALLBACK_URL}?action=approve"
          - label: "Reject"
            callback: "${CALLBACK_URL}?action=reject"
      await: true
      callback_port: 8765
      timeout: 86400        # 24 hours for human approval
      when: "${STAGE} == 'plan'"
```

**Fields:**

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `url` | yes | - | Webhook URL |
| `method` | no | POST | HTTP method |
| `headers` | no | {} | HTTP headers |
| `body` | no | {} | Request body (JSON) |
| `await` | no | false | Wait for callback response |
| `callback_port` | no | 8765 | Port for callback server |
| `timeout` | no | 3600 | Max seconds to wait |
| `on_timeout` | no | abort | abort or continue |

**Callback Response:**

When `await: true`, the engine starts a local HTTP server and waits for a callback. The response body becomes available as `${HOOK_RESPONSE}`.

### Spawn Actions

Launch child pipelines from within a hook.

```yaml
hooks:
  on_iteration_complete:
    # Periodic code review every 10 iterations
    - type: spawn
      pipeline: code-review
      await: true
      inputs:
        files_changed: "${CHANGED_FILES}"
        parent_session: "${SESSION}"
      when: "${ITERATION} % 10 == 0"

    # Fire-and-forget metrics collection
    - type: spawn
      pipeline: collect-metrics
      inputs:
        session: "${SESSION}"
        iteration: "${ITERATION}"
```

**Fields:**

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `pipeline` | yes | - | Pipeline or stage name to spawn |
| `inputs` | no | {} | Data passed to child pipeline |
| `await` | no | true | Wait for child to complete |
| `timeout` | no | 3600 | Max seconds to wait |
| `on_failure` | no | continue | abort, continue, or retry |

**Child Isolation:**
- Child runs in `{session_dir}/children/{hook_point}-{iteration}/`
- Child gets its own progress file
- Parent passes explicit inputs via `inputs:`
- Child outputs available as `${SPAWN_OUTPUT}` when awaited

## Conditions

Any action can have a `when:` condition.

```yaml
hooks:
  on_iteration_complete:
    # Only on first iteration
    - type: shell
      command: "./scripts/first-run.sh"
      when: "${ITERATION} == 1"

    # Every 10 iterations
    - type: spawn
      pipeline: code-review
      when: "${ITERATION} % 10 == 0"

    # Only during work stage after iteration 5
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Progress update" }
      when: "${STAGE} == 'work' && ${ITERATION} > 5"

    # On previous hook failure
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Tests failed - review needed" }
      when: "${LAST_HOOK_STATUS} == 'failed'"
```

**Supported operators:**
- Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Modulo: `%`
- Boolean: `&&`, `||`

## Environment Variables

All actions receive context via environment:

| Variable | Description |
|----------|-------------|
| `SESSION` | Session name |
| `STAGE` | Current stage name |
| `NEXT_STAGE` | Next stage name (empty if last) |
| `ITERATION` | Current iteration (1-based) |
| `MAX_ITERATIONS` | Maximum iterations configured |
| `PROGRESS` | Path to progress file |
| `STATUS` | Path to status.json |
| `CTX` | Path to context.json |
| `LAST_DECISION` | Previous iteration's decision |
| `LAST_HOOK_STATUS` | Previous action's result: `success` or `failed` |
| `CHANGED_FILES` | Files modified this iteration |
| `STAGE_OUTPUTS` | Collected outputs from current stage |
| `ERROR` | Error message (only in `on_error` hook) |
| `TIMESTAMP` | Current ISO 8601 timestamp |
| `CALLBACK_URL` | Auto-generated callback URL for webhooks |
| `HOOK_RESPONSE` | Response from previous await webhook |
| `SPAWN_OUTPUT` | Output from previous await spawn |

## Configuration Locations

### Per-Stage

```yaml
# scripts/stages/ralph/stage.yaml
name: ralph
description: Work through beads

termination:
  type: queue

hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/backup.sh"
```

### Per-Pipeline

```yaml
# scripts/pipelines/full-workflow.yaml
name: full-workflow
description: Complete workflow with approvals

stages:
  - name: plan
    stage: improve-plan
    runs: 5
  - name: work
    stage: ralph
    runs: 25

hooks:
  on_stage_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Stage ${STAGE} complete, moving to ${NEXT_STAGE}" }
```

### Global

```yaml
# ~/.config/agent-pipelines/hooks.yaml
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Pipeline ${SESSION} finished"

  on_error:
    - type: webhook
      url: "${PAGERDUTY_WEBHOOK}"
      body:
        text: "Pipeline ${SESSION} failed: ${ERROR}"
```

### Disable Global Hooks

```yaml
# In stage.yaml or pipeline.yaml
disable_global_hooks: true
```

## Common Patterns

### Pattern 1: Slack Notification on Complete

```yaml
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: ":white_check_mark: ${SESSION} completed in ${ITERATION} iterations"
```

### Pattern 2: Human Approval Gate Between Stages

```yaml
hooks:
  on_stage_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Plan ready for ${SESSION}"
        blocks:
          - type: actions
            elements:
              - type: button
                text: "Approve"
                url: "${CALLBACK_URL}?action=approve"
              - type: button
                text: "Reject"
                url: "${CALLBACK_URL}?action=reject"
      await: true
      timeout: 86400
      on_timeout: abort
      when: "${STAGE} == 'plan'"
```

### Pattern 3: Periodic Code Review

```yaml
hooks:
  on_iteration_complete:
    - type: spawn
      pipeline: code-review
      await: true
      inputs:
        files: "${CHANGED_FILES}"
      when: "${ITERATION} % 10 == 0"
```

### Pattern 4: Quality Gate with Fallback

```yaml
hooks:
  on_iteration_complete:
    # Run tests
    - type: shell
      command: "./scripts/run-tests.sh"
      await: true
      on_failure: continue

    # If tests failed, ask human
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Tests failed - manual review needed"
        actions:
          - label: "Ignore and Continue"
            callback: "${CALLBACK_URL}?action=continue"
          - label: "Abort Pipeline"
            callback: "${CALLBACK_URL}?action=abort"
      await: true
      when: "${LAST_HOOK_STATUS} == 'failed'"
```

### Pattern 5: Backup + Metrics (Fire-and-Forget)

```yaml
hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/backup-progress.sh"

    - type: shell
      command: "./scripts/collect-metrics.sh"

    - type: webhook
      url: "${METRICS_ENDPOINT}"
      body:
        session: "${SESSION}"
        iteration: "${ITERATION}"
```

## Implementation

### New Files

```
scripts/lib/
├── hooks.sh           # Main hook execution
├── callback.sh        # Webhook callback server
└── spawn.sh           # Child pipeline spawning
```

### Engine Integration

```bash
# In engine.sh run_stage()

# Session start
execute_hooks "on_session_start" "$hooks_config"

while should_continue; do
  # Iteration start
  execute_hooks "on_iteration_start" "$hooks_config"

  # Run Claude
  if run_claude; then
    execute_hooks "on_iteration_complete" "$hooks_config"
  else
    execute_hooks "on_error" "$hooks_config"
  fi
done

# Stage complete (multi-stage)
execute_hooks "on_stage_complete" "$hooks_config"

# Session complete
execute_hooks "on_session_complete" "$hooks_config"
```

### Core Functions

```bash
# scripts/lib/hooks.sh

execute_hooks() {
  local hook_point=$1
  local hooks_config=$2

  # Get actions for this hook point
  local actions=$(yq -o=json ".hooks.$hook_point" "$hooks_config")

  echo "$actions" | jq -c '.[]?' | while read -r action; do
    local action_type=$(echo "$action" | jq -r '.type')
    local condition=$(echo "$action" | jq -r '.when // "true"')

    # Evaluate condition
    if ! eval_condition "$condition"; then
      continue
    fi

    case "$action_type" in
      shell)   execute_shell_action "$action" ;;
      webhook) execute_webhook_action "$action" ;;
      spawn)   execute_spawn_action "$action" ;;
    esac

    local status=$?
    export LAST_HOOK_STATUS=$([[ $status -eq 0 ]] && echo "success" || echo "failed")

    # Handle failure
    if [[ $status -ne 0 ]]; then
      local on_failure=$(echo "$action" | jq -r '.on_failure // "continue"')
      [[ "$on_failure" == "abort" ]] && return 1
    fi
  done
}

execute_shell_action() {
  local action=$1
  local command=$(echo "$action" | jq -r '.command')
  local should_await=$(echo "$action" | jq -r '.await // false')
  local timeout_sec=$(echo "$action" | jq -r '.timeout // 300')

  # Resolve variables
  command=$(resolve_variables "$command")

  if [[ "$should_await" == "true" ]]; then
    timeout "$timeout_sec" bash -c "$command"
  else
    bash -c "$command" &
  fi
}

execute_webhook_action() {
  local action=$1
  local url=$(echo "$action" | jq -r '.url')
  local method=$(echo "$action" | jq -r '.method // "POST"')
  local body=$(echo "$action" | jq -c '.body // {}')
  local should_await=$(echo "$action" | jq -r '.await // false')

  # Resolve variables
  url=$(resolve_variables "$url")
  body=$(resolve_variables "$body")

  # Send webhook
  curl -s -X "$method" "$url" \
    -H "Content-Type: application/json" \
    -d "$body"

  # If await, start callback server
  if [[ "$should_await" == "true" ]]; then
    local port=$(echo "$action" | jq -r '.callback_port // 8765')
    local timeout_sec=$(echo "$action" | jq -r '.timeout // 3600')
    await_callback "$port" "$timeout_sec"
  fi
}

execute_spawn_action() {
  local action=$1
  local pipeline=$(echo "$action" | jq -r '.pipeline')
  local inputs=$(echo "$action" | jq -c '.inputs // {}')
  local should_await=$(echo "$action" | jq -r '.await // true')

  local child_dir="$SESSION_DIR/children/${HOOK_POINT}-${ITERATION}"
  mkdir -p "$child_dir"

  # Write inputs for child
  echo "$inputs" | resolve_variables > "$child_dir/inputs.json"

  if [[ "$should_await" == "true" ]]; then
    ./scripts/engine.sh \
      --session-dir "$child_dir" \
      --pipeline "$pipeline" \
      --inputs "$child_dir/inputs.json"

    if [[ -f "$child_dir/output.json" ]]; then
      export SPAWN_OUTPUT=$(cat "$child_dir/output.json")
    fi
  else
    ./scripts/engine.sh \
      --session-dir "$child_dir" \
      --pipeline "$pipeline" \
      --inputs "$child_dir/inputs.json" &
  fi
}
```

### Configuration Resolution & Precedence

1. **Discovery order** mirrors the stage resolver (`scripts/lib/resolve.sh`): user config (`~/.config/agent-pipelines/hooks.yaml`) → pipeline definition → stage definition. Build `resolve_hooks_config` inside `scripts/lib/hooks.sh` to:
   - Load each source with `yq`, gracefully skipping missing files.
   - Merge hook arrays per hook point (`jq -s 'add'`) so stage-scoped hooks run first, pipeline hooks second, globals last.
   - Respect `disable_global_hooks: true` (from stage or pipeline) and `disable_pipeline_hooks` if a stage wants to run without pipeline-level hooks.
2. **Engine wiring:** After `load_stage` / `load_pipeline` run inside `scripts/engine.sh`, call `resolve_hooks_config` once and pass the result (or tmp file path) through `run_stage`, `run_pipeline_stages`, and each lifecycle event so `execute_hooks` does not re-read YAML every iteration.
3. **Variable expansion:** Reuse `resolve_prompt` helpers for `${VAR}` interpolation inside hook fields and `when` conditions so hooks see the same context surface area as prompts.

### Observability & Testing Plan

- Add `log_hook_action "$hook_point" "$action_name" "$status"` in `scripts/lib/hooks.sh`, writing structured lines to `${SESSION_DIR}/logs/hooks.log` and echoing short messages for real-time feedback.
- Persist the latest hook status to `status.json.hooks` using `scripts/lib/status.sh` so resumptions know whether a blocking gate failed or is still waiting.
- Create `scripts/tests/test_hooks.sh` that runs a mock stage via `MOCK_MODE=true`, asserting shell hooks append to a temp file, `when` clauses short-circuit correctly, and await webhooks honor timeouts using a local `nc -l` server fixture.
- Document a manual verification recipe:
  ```bash
  ./scripts/run.sh loop ralph demo --foreground --no-tmux
  tail -f .claude/pipeline-runs/demo/logs/hooks.log
  ```
  Once hooks stabilize, move these steps into `scripts/README.md`.

---

# Part 2: Marketplace

## Concept

The marketplace is a library of stages and pipelines:

1. **Built-in** - Ships with agent-pipelines, maintained by us
2. **User** - Your own creations, stored locally
3. **Community** - Contributed templates, also ships with the tool (via PRs)

```
scripts/
├── stages/              # Built-in stages
│   ├── ralph/
│   ├── improve-plan/
│   ├── elegance/
│   └── ...
├── pipelines/           # Built-in pipelines
│   ├── refine.yaml
│   └── bug-hunt.yaml
└── marketplace/         # Community-contributed
    ├── README.md
    ├── stages/
    │   ├── twitter-review/
    │   ├── security-audit/
    │   └── ...
    └── pipelines/
        ├── full-feature.yaml
        └── ...

~/.config/agent-pipelines/
├── stages/              # User's own stages
│   └── my-custom-review/
└── pipelines/           # User's own pipelines
    └── my-workflow.yaml
```

## Commands

### Browse Available

```bash
# List all available stages (built-in + marketplace + user)
./scripts/run.sh marketplace

# Or with subcommand
./scripts/run.sh marketplace list

# Filter by type
./scripts/run.sh marketplace list stages
./scripts/run.sh marketplace list pipelines

# Search
./scripts/run.sh marketplace search "review"
./scripts/run.sh marketplace search --tag=security
```

**Output:**
```
BUILT-IN STAGES
  ralph             Work through beads queue
  improve-plan      Iterative plan refinement
  elegance          Code elegance review
  bug-discovery     Fresh-eyes bug exploration
  refine-tasks      Task refinement

MARKETPLACE STAGES
  twitter-review    Code review from viral Twitter prompt (@clever_dev)
  security-audit    OWASP-focused security review
  doc-generator     Generate documentation from code

YOUR STAGES
  my-custom-review  My personalized review workflow

BUILT-IN PIPELINES
  refine.yaml       5+5 plan → task iterations
  bug-hunt.yaml     Discover → triage → fix

MARKETPLACE PIPELINES
  full-feature.yaml Complete feature workflow with approvals

YOUR PIPELINES
  my-workflow.yaml  My custom workflow
```

### View Details

```bash
./scripts/run.sh marketplace info elegance

# Output:
# NAME: elegance
# TYPE: stage
# SOURCE: built-in
#
# DESCRIPTION:
#   Code elegance review with focus on simplicity and clarity
#
# TERMINATION:
#   type: judgment
#   consensus: 2
#   max: 5
#
# USAGE:
#   ./scripts/run.sh elegance my-session 5
```

### Import from URL

```bash
# Import a stage from GitHub
./scripts/run.sh marketplace import https://github.com/user/repo/tree/main/stages/cool-review

# Import from a gist
./scripts/run.sh marketplace import https://gist.github.com/user/abc123

# Import with custom name
./scripts/run.sh marketplace import https://... --as my-review

# Import from raw files
./scripts/run.sh marketplace import https://raw.githubusercontent.com/.../stage.yaml
```

**What happens:**
1. Fetches `stage.yaml` and `prompt.md` from URL
2. Validates structure
3. Saves to `~/.config/agent-pipelines/stages/{name}/`
4. Available immediately via `./scripts/run.sh {name} ...`

### Create from Prompt

The Twitter workflow: see a cool prompt, turn it into a stage.

```bash
# Interactive mode
./scripts/run.sh marketplace create

# From clipboard/text
./scripts/run.sh marketplace create --from-prompt "You are an expert code reviewer..."

# From file
./scripts/run.sh marketplace create --from-file ~/prompts/review.md
```

**What happens:**
1. Takes the prompt text as input
2. Uses Claude to analyze and generate:
   - `stage.yaml` with appropriate name, description, termination strategy
   - `prompt.md` with proper template variables
3. Asks user to confirm/edit
4. Saves to `~/.config/agent-pipelines/stages/{name}/`

**Prompt for stage generation:**
```markdown
You are helping create an agent-pipelines stage from a user's prompt.

Given this prompt:
"""
{user_prompt}
"""

Generate:

1. A stage.yaml:
   - name: kebab-case, descriptive
   - description: one sentence
   - termination:
     - Use `type: fixed` for simple prompts (default 5 iterations)
     - Use `type: judgment` for iterative refinement prompts

2. A prompt.md that:
   - Starts with the user's original prompt intent
   - Adds template variables: ${CTX}, ${PROGRESS}, ${STATUS}
   - Includes instructions to read context.json
   - Includes instructions to write status.json with decision

Output as two fenced code blocks: ```yaml for stage.yaml, ```markdown for prompt.md
```

### Fork and Customize

```bash
# Copy a built-in stage to customize
./scripts/run.sh marketplace fork elegance my-elegance

# Output:
# Copied to ~/.config/agent-pipelines/stages/my-elegance/
# Edit with: vim ~/.config/agent-pipelines/stages/my-elegance/prompt.md
```

### Share

```bash
# Generate shareable output
./scripts/run.sh marketplace share my-custom-review

# Options:
# 1. Copy to clipboard (stage.yaml + prompt.md)
# 2. Create GitHub gist
# 3. Output import command

# Output:
# Share this command:
#   ./scripts/run.sh marketplace import https://gist.github.com/...
#
# Or tweet:
#   "Built a Claude Code pipeline for code reviews!
#    Try it: ./scripts/run.sh marketplace import https://...
#    #ClaudeCode #AgentPipelines"
```

### Contribute to Marketplace

```bash
# Submit your stage to the official marketplace
./scripts/run.sh marketplace contribute my-custom-review

# What happens:
# 1. Validates stage structure
# 2. Adds attribution metadata
# 3. Opens GitHub PR to agent-pipelines/marketplace/
```

## Stage Package Format

A shareable stage is a directory with:

```
my-stage/
├── stage.yaml      # Required: config with metadata
├── prompt.md       # Required: the prompt template
├── README.md       # Optional: usage instructions
└── examples/       # Optional: example inputs/outputs
```

### stage.yaml Schema

```yaml
# Required fields
name: my-stage
description: One sentence describing what this stage does

termination:
  type: judgment      # fixed, judgment, or queue
  consensus: 2        # for judgment
  max: 5              # max iterations

# Optional metadata (for marketplace)
version: 1.0.0
author:
  name: Harrison Wells
  twitter: "@hwells"
  github: "hwells4"

tags: [review, security, quality]

# Attribution for derivatives
based_on:
  name: original-stage
  author: "@original_author"
  url: "https://..."

# Requirements
requires:
  min_version: "0.5.0"    # agent-pipelines version
  commands: [git, jq]      # CLI tools needed
```

### prompt.md Template

```markdown
# My Stage

You are [role description].

## Context

Read the context file for session information:
\`\`\`bash
cat ${CTX}
\`\`\`

Read previous progress:
\`\`\`bash
cat ${PROGRESS}
\`\`\`

## Your Task

[Main instructions here]

## Output

When done, write your status:
\`\`\`bash
cat > ${STATUS} << 'EOF'
{
  "decision": "continue",
  "reason": "Why you made this decision",
  "summary": "What you accomplished",
  "work": {
    "items_completed": [],
    "files_touched": []
  }
}
EOF
\`\`\`

Use "stop" when [stopping criteria].
```

## Implementation

### New Files

```
scripts/
├── lib/
│   ├── marketplace.sh    # Core marketplace functions
│   └── packages.sh       # Package discovery and validation
└── marketplace/          # Community contributions directory
    ├── README.md
    ├── stages/
    └── pipelines/
```

### Core Functions

```bash
# scripts/lib/marketplace.sh

# List all available stages/pipelines
marketplace_list() {
  local type=${1:-all}  # stages, pipelines, or all

  echo "BUILT-IN STAGES"
  ls scripts/stages/ | while read stage; do
    local desc=$(yq -r '.description' "scripts/stages/$stage/stage.yaml")
    printf "  %-18s %s\n" "$stage" "$desc"
  done

  echo ""
  echo "MARKETPLACE STAGES"
  if [[ -d scripts/marketplace/stages ]]; then
    ls scripts/marketplace/stages/ | while read stage; do
      local desc=$(yq -r '.description' "scripts/marketplace/stages/$stage/stage.yaml")
      printf "  %-18s %s\n" "$stage" "$desc"
    done
  fi

  echo ""
  echo "YOUR STAGES"
  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-pipelines/stages"
  if [[ -d "$user_dir" ]]; then
    ls "$user_dir" | while read stage; do
      local desc=$(yq -r '.description' "$user_dir/$stage/stage.yaml")
      printf "  %-18s %s\n" "$stage" "$desc"
    done
  fi
}

# Import stage from URL
marketplace_import() {
  local url=$1
  local name=${2:-$(basename "$url")}
  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-pipelines/stages"
  local target_dir="$user_dir/$name"

  mkdir -p "$target_dir"

  # Handle different URL types
  if [[ "$url" == *"github.com"*"/tree/"* ]]; then
    # GitHub directory - convert to raw URLs
    local raw_base=$(echo "$url" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|/tree/|/|')
    curl -sL "$raw_base/stage.yaml" > "$target_dir/stage.yaml"
    curl -sL "$raw_base/prompt.md" > "$target_dir/prompt.md"
  elif [[ "$url" == *"gist.github"* ]]; then
    # Gist - fetch raw content
    local gist_id=$(echo "$url" | grep -oE '[a-f0-9]{32}')
    curl -sL "https://gist.githubusercontent.com/raw/$gist_id/stage.yaml" > "$target_dir/stage.yaml"
    curl -sL "https://gist.githubusercontent.com/raw/$gist_id/prompt.md" > "$target_dir/prompt.md"
  else
    # Direct URL
    curl -sL "$url" > "$target_dir/stage.yaml"
  fi

  # Validate
  if ! validate_stage "$target_dir"; then
    rm -rf "$target_dir"
    echo "Error: Invalid stage format"
    return 1
  fi

  echo "Installed: $name"
  echo "Run with: ./scripts/run.sh $name <session> <iterations>"
}

# Create stage from prompt text
marketplace_create() {
  local prompt_text=$1
  local name=$2

  # Use Claude to generate stage files
  local result=$(claude --print "
Given this prompt:
'''
$prompt_text
'''

Generate a stage.yaml and prompt.md for agent-pipelines.
Output as JSON: {\"stage_yaml\": \"...\", \"prompt_md\": \"...\", \"suggested_name\": \"...\"}
")

  local suggested_name=$(echo "$result" | jq -r '.suggested_name')
  name=${name:-$suggested_name}

  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-pipelines/stages"
  local target_dir="$user_dir/$name"

  mkdir -p "$target_dir"
  echo "$result" | jq -r '.stage_yaml' > "$target_dir/stage.yaml"
  echo "$result" | jq -r '.prompt_md' > "$target_dir/prompt.md"

  echo "Created: $target_dir"
  echo ""
  echo "Review and edit:"
  echo "  $target_dir/stage.yaml"
  echo "  $target_dir/prompt.md"
  echo ""
  echo "Run with: ./scripts/run.sh $name <session> <iterations>"
}

# Fork a stage for customization
marketplace_fork() {
  local source=$1
  local target=$2
  local source_dir=$(find_stage "$source")
  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-pipelines/stages"
  local target_dir="$user_dir/$target"

  cp -r "$source_dir" "$target_dir"

  # Update name in stage.yaml
  yq -i ".name = \"$target\"" "$target_dir/stage.yaml"
  yq -i ".based_on.name = \"$source\"" "$target_dir/stage.yaml"

  echo "Forked to: $target_dir"
}
```

### Stage Resolution Order

When looking for a stage, check in order:

1. User stages: `~/.config/agent-pipelines/stages/{name}/`
2. Marketplace stages: `scripts/marketplace/stages/{name}/`
3. Built-in stages: `scripts/stages/{name}/`

This allows users to override built-in stages with customizations.

## CLI Wiring & UX Details

- Extend `scripts/run.sh` with a `marketplace` top-level command that sources `scripts/lib/marketplace.sh`. Support subcommands (`list`, `info`, `import`, `create`, `fork`, `share`, `contribute`); default to `list` when omitted.
- Reuse the global flag parsing at the top of `run.sh`. Marketplace commands should ignore stage-session args but accept `--json` to emit machine-readable listings for future UI integrations.
- Update `show_help` output to mention marketplace usage and point to `scripts/marketplace/README.md` for fuller documentation.

## Metadata & Validation

- Marketplace packages add a lightweight `metadata.json` capturing `source`, `tags`, `author`, and optional `version`. `marketplace info` prints this alongside the stage description so attribution is baked into the UX.
- Enhance `scripts/lib/validate.sh` with `validate_stage_dir "$path"` / `validate_pipeline_file "$file"` helpers invoked by both `import` and `share`. Fail fast if `stage.yaml` is missing `name`, `description`, or `termination`.
- Persist install receipts under `~/.config/agent-pipelines/marketplace/index.json` (map name → source URL + install time) so future `update`/`remove` commands have a basis.

## Tests & Fixtures

- Add `scripts/tests/fixtures/marketplace/` with representative stage/pipeline directories used by both `list` and `fork` tests.
- Create `scripts/tests/test_marketplace.sh` that:
  1. Overrides `PATH` to stub `curl` during import.
  2. Verifies that `marketplace fork` copies files and rewrites `.name` while refusing to overwrite unless `--force` is passed.
  3. Confirms resolution order precedence by loading one stage name present in all three directories and asserting the user copy wins.

---

# Part 3: Pipeline Cycles

## Concept

Run an entire multi-stage pipeline as a repeatable unit. Instead of:

```
Stage A (5×) → Stage B (3×) → Stage C (10×)
```

You can do:

```
[Stage A → Stage B → Stage C] × 5 cycles
```

## Use Case: Bug Hunt Cycles

```yaml
name: bug-hunt-cycles
description: Find bugs, design fixes, implement - repeat

cycles: 5  # Run the whole pipeline 5 times

stages:
  - name: discover
    stage: bug-discovery
    runs: 3

  - name: design
    stage: elegance
    runs: 2

  - name: fix
    stage: ralph
    runs: 5
```

**What happens:**

```
Cycle 1: discover(3) → design(2) → fix(5)
Cycle 2: discover(3) → design(2) → fix(5)
Cycle 3: discover(3) → design(2) → fix(5)
Cycle 4: discover(3) → design(2) → fix(5)
Cycle 5: discover(3) → design(2) → fix(5)
```

Each cycle can find new bugs (fresh discovery), design elegant fixes, and implement them.

## Pipeline as Stage

Another approach: reference a pipeline from within a pipeline.

```yaml
name: meta-pipeline
description: Run bug-fix pipeline multiple times

stages:
  - name: setup
    stage: improve-plan
    runs: 3

  - name: bug-cycles
    pipeline: bug-hunt.yaml    # Instead of stage:, use pipeline:
    runs: 5                     # Run the entire pipeline 5 times

  - name: final-review
    stage: elegance
    runs: 3
```

## Cycle-Aware Context

Each cycle gets its own context, but can reference previous cycles:

```json
// context.json
{
  "cycle": 3,
  "total_cycles": 5,
  "previous_cycles": [
    {
      "cycle": 1,
      "stages": ["discover", "design", "fix"],
      "summary": "Fixed auth bug, 3 files changed"
    },
    {
      "cycle": 2,
      "stages": ["discover", "design", "fix"],
      "summary": "Fixed validation bug, 2 files changed"
    }
  ]
}
```

Agents can read this to understand what was accomplished in previous cycles.

## Cycle Termination Strategies

### Fixed Cycles

```yaml
cycles: 5  # Always run 5 cycles
```

### Judgment Cycles

```yaml
cycles:
  type: judgment
  min: 2              # At least 2 cycles
  max: 10             # At most 10 cycles
  consensus: 2        # 2 consecutive "no more bugs" to stop
```

The final stage of each cycle reports whether more cycles are needed:

```json
// status.json from last stage of cycle
{
  "decision": "continue",
  "cycle_complete": true,
  "more_cycles_needed": false,  // Indicates this is the last cycle needed
  "reason": "No new bugs found in discovery phase"
}
```

### Queue Cycles

```yaml
cycles:
  type: queue
  queue_command: "bd ready --label=bugs"  # Stop when queue empty
```

## Directory Structure

```
.claude/pipeline-runs/{session}/
├── cycle-1/
│   ├── stage-00-discover/
│   │   └── iterations/
│   ├── stage-01-design/
│   │   └── iterations/
│   └── stage-02-fix/
│       └── iterations/
├── cycle-2/
│   ├── stage-00-discover/
│   ├── stage-01-design/
│   └── stage-02-fix/
├── cycle-3/
│   └── ...
├── progress-{session}.md     # Accumulated across all cycles
└── state.json                # Tracks current cycle + stage
```

## State Tracking

```json
// state.json
{
  "session": "bug-hunt",
  "cycle": 3,
  "total_cycles": 5,
  "stage": "design",
  "stage_index": 1,
  "iteration": 2,
  "status": "running",
  "cycle_history": [
    {"cycle": 1, "completed": true, "bugs_fixed": 2},
    {"cycle": 2, "completed": true, "bugs_fixed": 1}
  ]
}
```

## Implementation

### Engine Changes

```bash
# In engine.sh

run_pipeline_with_cycles() {
  local config=$1
  local session=$2
  local cycles=$(yq -r '.cycles // 1' "$config")

  # Handle object vs number
  if [[ "$cycles" =~ ^[0-9]+$ ]]; then
    local cycle_type="fixed"
    local max_cycles=$cycles
  else
    local cycle_type=$(yq -r '.cycles.type' "$config")
    local max_cycles=$(yq -r '.cycles.max // 10' "$config")
  fi

  for ((cycle=1; cycle<=max_cycles; cycle++)); do
    export CYCLE=$cycle
    export TOTAL_CYCLES=$max_cycles

    local cycle_dir="$SESSION_DIR/cycle-$cycle"
    mkdir -p "$cycle_dir"

    # Run all stages in this cycle
    run_pipeline_stages "$config" "$cycle_dir"

    # Check cycle termination
    if [[ "$cycle_type" == "judgment" ]]; then
      if should_stop_cycles; then
        break
      fi
    elif [[ "$cycle_type" == "queue" ]]; then
      local queue_cmd=$(yq -r '.cycles.queue_command' "$config")
      if [[ -z "$($queue_cmd)" ]]; then
        break
      fi
    fi
  done
}
```

### Context Generation

```bash
# Add cycle info to context.json
generate_cycle_context() {
  local cycle=$1

  # Get previous cycle summaries
  local previous_cycles="[]"
  for ((c=1; c<cycle; c++)); do
    local summary=$(cat "$SESSION_DIR/cycle-$c/summary.json" 2>/dev/null || echo '{}')
    previous_cycles=$(echo "$previous_cycles" | jq ". + [$summary]")
  done

  jq -n \
    --argjson cycle "$cycle" \
    --argjson total "$TOTAL_CYCLES" \
    --argjson prev "$previous_cycles" \
    '{
      cycle: $cycle,
      total_cycles: $total,
      previous_cycles: $prev
    }'
}
```

### Data Model & Persistence

- Extend `scripts/lib/state.sh` so `state.json` tracks `cycle`, `total_cycles`, and a `cycle_history` array. Each cycle continues to live inside `${SESSION_DIR}/cycle-${cycle}` with its own `context.json`, `progress.md`, and `status.json`, keeping resumptions simple.
- When a stage writes `status.json` with `summary` keys, copy a condensed record to `${SESSION_DIR}/cycle-${cycle}/summary.json`. Subsequent cycles call `generate_cycle_context` to read these summaries and expose them via `${CTX}`.
- Add `${SESSION_DIR}/logs/cycles.log` lines like `Cycle 2/5 complete: 12 iterations, bugs fixed=3` for human traceability.

### Engine & CLI Wiring

- Update `scripts/engine.sh` so `run_pipeline` detects `cycles` in the YAML and dispatches to `run_pipeline_with_cycles`. Provide CLI overrides (`./scripts/run.sh pipeline bug-hunt.yaml bugs --cycles 3`) by exporting `PIPELINE_OVERRIDE_CYCLES` that `engine.sh` checks before reading YAML.
- Ensure `run_pipeline_stages` accepts a target session dir argument (`cycle_dir`) so artifacts stay isolated. `status.sh` should aggregate cycle data when printing `./scripts/run.sh status <session>`.
- Resume behavior: when `state.json.status="running"` and `cycle` < `total_cycles`, the engine resumes from the recorded cycle/stage/iteration without restarting earlier cycles.

### Testing & Fixtures

- Add `scripts/tests/test_cycles.sh` with a mock two-stage pipeline + `cycles: 2` to assert that:
  - Cycle directories contain stage subfolders with progress files,
  - `previous_cycles` has content before cycle 2 begins,
  - `status` output lists both cycles.
- Build fixtures under `scripts/tests/fixtures/cycles/` containing lightweight pipeline YAML + fake stage scripts so tests don't shell out to real Claude calls.

---

# Implementation Roadmap

## Phase 1: Core Hook System

**Files to create:**
- `scripts/lib/hooks.sh` (executor + config merge)
- `scripts/lib/callback.sh` (local HTTP server for approvals)
- `scripts/tests/test_hooks.sh`

**Engine & CLI updates:**
- Source `hooks.sh` and `callback.sh` from `scripts/engine.sh`.
- Thread a resolved hooks config (JSON or temp file path) through `run_stage`, `run_pipeline_stages`, and the iteration loop.
- Optionally add `--hooks <file>` to `scripts/run.sh` for targeted testing.

**Deliverables:**
- Shell actions with await/timeouts/retries
- `when` conditions + env propagation
- Hook execution log + regression test

## Phase 2: Marketplace Foundation

**Files to create:**
- `scripts/lib/marketplace.sh`
- `scripts/lib/packages.sh`
- `scripts/tests/test_marketplace.sh`
- `scripts/marketplace/README.md`
- `scripts/marketplace/stages/` (empty, committed dir)

**Commands:**
- `./scripts/run.sh marketplace [list]`
- `./scripts/run.sh marketplace info <name>`
- `./scripts/run.sh marketplace fork <source> <target>`

**Deliverables:**
- Stage/pipeline discovery across built-in + marketplace + user dirs
- Info command that surfaces metadata/termination
- Fork flow with overwrite protection

## Phase 3: Marketplace Import/Create

**Commands:**
- `./scripts/run.sh marketplace import <url>`
- `./scripts/run.sh marketplace create [--from-prompt|--from-file]`
- `./scripts/run.sh marketplace share <name>`

**Stage resolution:**
- User stages → Marketplace stages → Built-in stages (implemented in `packages.sh`)

**Deliverables:**
- Import flow with validation + metadata
- Prompt-to-stage generation w/ confirmation step
- Share/export command that emits gist-ready bundles
- Regression coverage for import/create paths

## Phase 4: Pipeline Cycles

**Engine changes:**
- Add `cycles:` support to pipeline.yaml
- Cycle-aware state tracking
- Cycle context generation
- Resume + status integration

**Deliverables:**
- Fixed cycle count execution
- Cycle state persisted per subdirectory
- Previous cycle context injection
- CLI override/flags + status reporting

## Phase 5: Advanced Hooks

**Features:**
- Webhook actions
- Callback server for approvals
- Spawn actions (nested pipelines)
- Global hooks configuration
- Hook status surfaced via `./scripts/run.sh status <session>`

## Phase 6: Advanced Cycles

**Features:**
- Judgment-based cycle termination
- Queue-based cycle termination
- Pipeline-as-stage (nested pipelines)

---

# Success Criteria

## Hooks

- [ ] Shell hook fires on iteration complete
- [ ] Await blocks until command completes
- [ ] Conditions filter hook execution correctly
- [ ] Slack notification works on session complete
- [ ] Human approval gate pauses pipeline
- [ ] `scripts/tests/test_hooks.sh` passes locally and in CI

## Marketplace

- [ ] `marketplace` command lists all available stages
- [ ] Can fork a stage and customize it
- [ ] Can import stage from GitHub URL
- [ ] Can create stage from prompt text
- [ ] User stages take precedence over built-in
- [ ] `./scripts/run.sh test marketplace` covers list/import/fork

## Pipeline Cycles

- [ ] Can run pipeline 5 times with `cycles: 5`
- [ ] Each cycle gets isolated directory
- [ ] Progress accumulates across cycles
- [ ] Previous cycle context available to agents
- [ ] Judgment-based cycles stop on consensus
- [ ] `./scripts/run.sh status <session>` shows per-cycle progress
- [ ] `scripts/tests/test_cycles.sh` passes
