# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Loop Agents is a [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code. It runs autonomous, multi-iteration agent workflows in tmux sessions. Each iteration spawns a fresh Claude instance that reads accumulated progress to maintain context without degradation.

**Core philosophy:** Fresh agent per iteration prevents context degradation. Two-agent consensus prevents premature stopping. Planning tokens are cheaper than implementation tokens.

**Everything is a pipeline.** A "loop" is just a single-stage pipeline. The unified engine treats all executions the same way.

## Commands

```bash
# Run a single-stage pipeline (3 equivalent ways)
./scripts/run.sh work auth 25                    # Shortcut: type session max
./scripts/run.sh loop work auth 25               # Explicit: loop type session max
./scripts/run.sh pipeline --single-stage work auth 25  # Engine syntax

# Run a multi-stage pipeline
./scripts/run.sh pipeline full-refine.yaml my-session

# Force start (override existing session lock)
./scripts/run.sh work auth 25 --force

# Resume a crashed/failed session
./scripts/run.sh work auth 25 --resume

# Check session status
./scripts/run.sh status auth

# List available stages and pipelines
./scripts/run.sh
```

Dependencies: `jq`, `claude`, `tmux`, `bd` (beads CLI)

## Skills

Skills are Claude Code extensions in `skills/`. Each provides specialized workflows.

| Skill | Invocation | Purpose |
|-------|------------|---------|
| **sessions** | `/loop-agents:sessions` | Start/manage pipelines in tmux |
| **plan-refinery** | `/plan-refinery` | Iterative planning with Opus subagents |
| **create-prd** | `/loop-agents:create-prd` | Generate PRDs through adaptive questioning |
| **create-tasks** | `/loop-agents:create-tasks` | Break PRD into executable beads |
| **pipeline-builder** | `/loop-agents:pipeline-builder` | Create custom stages and pipelines |

### Skill Structure

Each skill in `skills/{name}/` contains:
- `SKILL.md` - Skill definition with intake, routing, and success criteria
- `workflows/` - Step-by-step workflow files
- `references/` - Supporting documentation

## Slash Commands

Commands in `commands/` provide user-facing interfaces.

| Command | Usage | Description |
|---------|-------|-------------|
| `/loop` | `/loop`, `/loop status`, `/loop attach NAME` | Orchestration hub: plan, status, management |
| `/work` | `/work`, `/work auth` | Launch work pipelines |
| `/refine` | `/refine`, `/refine quick`, `/refine deep` | Run refinement pipelines |
| `/ideate` | `/ideate`, `/ideate 3` | Generate improvement ideas |

## Architecture

**Everything is a pipeline.** The unified engine (`engine.sh`) runs all sessions the same way. A single-stage pipeline is what we colloquially call a "loop."

```
scripts/
├── engine.sh                 # Unified pipeline engine
├── run.sh                    # Entry point (converts all commands to pipeline calls)
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # JSON iteration history + crash recovery
│   ├── progress.sh           # Accumulated context files
│   ├── resolve.sh            # Template variable resolution
│   ├── parse.sh              # Claude output parsing
│   ├── notify.sh             # Desktop notifications + logging
│   ├── lock.sh               # Session locking (prevents duplicates)
│   ├── heartbeat.sh          # Crash detection via periodic heartbeats
│   └── completions/          # Stopping strategies
│       ├── beads-empty.sh    # Stop when no beads remain
│       ├── plateau.sh        # Stop when 2 agents agree
│       ├── fixed-n.sh        # Stop after N iterations
│       └── all-items.sh      # Stop after processing items
├── loops/                    # Stage definitions (single-stage pipeline configs)
│   ├── work/                 # Implementation (beads-empty)
│   ├── improve-plan/         # Plan refinement (plateau)
│   ├── refine-beads/         # Bead refinement (plateau)
│   └── idea-wizard/          # Ideation (fixed-n)
└── pipelines/                # Multi-stage pipeline configs
    └── *.yaml

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

## Core Concepts

### Pipelines

**Everything is a pipeline.** A pipeline runs one or more stages, each with its own prompt and completion strategy.

- **Single-stage pipeline** (aka "loop"): One stage that iterates until completion
- **Multi-stage pipeline**: Multiple stages chained together, outputs flow between stages

All sessions run in `.claude/pipeline-runs/{session}/` with unified state tracking.

### Stages

A stage = prompt template + completion strategy. Stages are defined in `scripts/loops/{name}/`. Each iteration:
1. Resolves template variables (`${SESSION}`, `${ITERATION}`, `${PROGRESS_FILE}`, etc.)
2. Executes Claude with resolved prompt
3. Parses output for structured fields
4. Updates state file with results
5. Checks completion condition → stop or continue

### State vs Progress Files

**State file** (`.claude/pipeline-runs/{session}/state.json`): JSON tracking iteration history for completion checks and crash recovery
```json
{
  "session": "auth",
  "iteration": 5,
  "iteration_completed": 4,
  "iteration_started": "2025-01-10T10:05:00Z",
  "status": "running",
  "history": [{"plateau": false}, {"plateau": true}]
}
```

**Progress file** (`.claude/pipeline-runs/{session}/progress-{session}.md`): Markdown with accumulated learnings. Fresh Claude reads this each iteration to maintain context.

**Lock file** (`.claude/locks/{session}.lock`): JSON preventing concurrent sessions with the same name. Contains PID, session name, start time, and heartbeat timestamp for crash detection.
```json
{
  "session": "auth",
  "pid": 12345,
  "started_at": "2025-01-10T10:00:00Z",
  "heartbeat": "2025-01-10T10:05:30Z",
  "heartbeat_epoch": 1736503530
}
```

### Completion Strategies

| Strategy | Implementation | Used By |
|----------|----------------|---------|
| `beads-empty` | Checks `bd ready --label=loop/{session}` returns 0 | work stage |
| `plateau` | Requires 2 consecutive agents to output `PLATEAU: true` | improve-plan, refine-beads |
| `fixed-n` | Runs exactly N iterations | idea-wizard |
| `all-items` | Processes each item in a list | batch processing |

### Multi-Stage Pipelines

Chain stages together. Each stage's outputs become `${INPUTS}` for the next:
```yaml
name: full-refine
description: Refine plan then beads
stages:
  - name: plan
    loop: improve-plan
    runs: 5
  - name: beads
    loop: refine-beads
    runs: 5
```

Available pipelines: `quick-refine.yaml` (3+3), `full-refine.yaml` (5+5), `deep-refine.yaml` (8+8)

## Template Variables

| Variable | Description |
|----------|-------------|
| `${SESSION}` / `${SESSION_NAME}` | Session name |
| `${ITERATION}` | 1-based iteration number |
| `${INDEX}` | 0-based iteration index |
| `${PROGRESS}` / `${PROGRESS_FILE}` | Path to progress file |
| `${OUTPUT}` | Path to write output (multi-stage pipelines) |
| `${INPUTS}` | Previous stage outputs (multi-stage pipelines) |
| `${INPUTS.stage-name}` | Named stage outputs (multi-stage pipelines) |

## Creating a New Stage

Stages are single-stage pipeline definitions. Create one to add a new pipeline type.

1. Create directory: `scripts/loops/{name}/`
2. Add `loop.yaml`:
```yaml
name: my-stage
description: What this stage does
completion: plateau      # beads-empty, plateau, fixed-n, all-items
delay: 3                 # seconds between iterations
min_iterations: 1        # for plateau: start checking after this many
output_parse: plateau:PLATEAU reasoning:REASONING  # extract from output
```
3. Add `prompt.md` with template using variables above
4. Run verification: `./scripts/run.sh lint loop {name}`

## Recommended Workflow

**Feature implementation flow:**
1. `/loop plan` or `/loop-agents:create-prd` → Gather requirements, save to `docs/plans/`
2. `/loop-agents:create-tasks` → Break PRD into beads tagged `loop/{session}`
3. `/refine` → Run refinement pipeline (default: 5+5 iterations)
4. `/work` → Run work pipeline until all beads complete

## Key Patterns

**Fresh agent per iteration**: Avoids context degradation. Each Claude reads the progress file for accumulated context.

**Two-agent consensus** (plateau): Prevents single-agent blind spots. Both must independently confirm completion.

**Beads integration**: Work stage uses `bd` CLI to list/claim/close tasks. Beads are tagged with `loop/{session}`.

**Session isolation**: Each session has separate beads (`loop/{session}` label), progress file, state file, and tmux session.

## Debugging

```bash
# Watch a running pipeline
tmux attach -t loop-{session}

# Check pipeline state
cat .claude/pipeline-runs/{session}/state.json | jq

# View progress file
cat .claude/pipeline-runs/{session}/progress-{session}.md

# Check remaining beads
bd ready --label=loop/{session}

# Kill a stuck pipeline
tmux kill-session -t loop-{session}

# Check session status (active, failed, completed)
./scripts/run.sh status {session}
```

### Crash Recovery

Sessions automatically detect and recover from crashes (API timeouts, network issues, SIGKILL).

**When a session crashes**, you'll see:
```
Session 'auth' failed at iteration 5/25
Last successful iteration: 4
Error: Claude process terminated unexpectedly
Run with --resume to continue from iteration 5
```

**To resume:**
```bash
./scripts/run.sh work auth 25 --resume
```

**How crash detection works:**
1. Heartbeat updates every 30s during iteration execution
2. On startup, engine checks: lock exists + PID dead + stale heartbeat = crashed
3. State file tracks `iteration_started` and `iteration_completed` for precise resume

### Session Locks

Locks prevent running duplicate sessions with the same name. They are automatically released when a session ends normally or its process dies.

```bash
# List active locks
ls .claude/locks/

# View lock details (PID, start time, heartbeat)
cat .claude/locks/{session}.lock | jq

# Check if a session is locked
test -f .claude/locks/{session}.lock && echo "locked" || echo "available"

# Clear a stale lock manually (only if process is dead)
rm .claude/locks/{session}.lock

# Force start despite existing lock
./scripts/run.sh work my-session 10 --force
```

**When you see "Session is already running":**
1. Check if the PID in the lock file is still alive: `ps -p <pid>`
2. If alive, the session is running - attach or kill it first
3. If dead, the lock is stale - use `--resume` to continue or `--force` to restart

## Environment Variables

Pipelines export:
- `CLAUDE_LOOP_AGENT=1` - Always true inside a pipeline
- `CLAUDE_LOOP_SESSION` - Current session name
- `CLAUDE_LOOP_TYPE` - Current stage type
