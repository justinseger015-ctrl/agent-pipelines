# Agent Pipelines

Run Claude in a loop until the job is done.

Long-running agents suffer context degradation—quality drops as conversation grows. Agent Pipelines fixes this with [Ralph loops](https://ghuntley.com/ralph/): each iteration spawns a fresh Claude that reads a progress file. Iteration 50 is as sharp as iteration 1.

## Components

| Component | Count |
|-----------|-------|
| Commands | 7 |
| Skills | 7 |
| Stages | 8 |
| Pipelines | 3 |

## Installation

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/hwells4/agent-pipelines

# Install the plugin
claude plugin install agent-pipelines@dodo-digital
```

### Dependencies

| Dependency | Purpose | Install |
|------------|---------|---------|
| [tmux](https://github.com/tmux/tmux) | Background execution | `brew install tmux` |
| [beads](https://github.com/steveyegge/beads) | Task management | `brew install steveyegge/tap/bd` |
| [jq](https://github.com/jqlang/jq) | JSON parsing | `brew install jq` |

## What is a Pipeline?

A pipeline runs Claude iteratively until a termination condition is met. Each iteration:

1. **Fresh agent** reads the progress file (accumulated context)
2. **Does work** (implements, refines, reviews—whatever the stage defines)
3. **Writes status** (`continue`, `stop`, or `error`)
4. **Engine decides** whether to run another iteration

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Iteration 1 │ ──► │ Iteration 2 │ ──► │ Iteration 3 │ ──► ...
│ Fresh Claude│     │ Fresh Claude│     │ Fresh Claude│
│ Reads progress    │ Reads progress    │ Reads progress
│ Does work   │     │ Does work   │     │ Writes "stop"
│ Updates progress  │ Updates progress  │ Loop terminates
└─────────────┘     └─────────────┘     └─────────────┘
```

### Termination Strategies

| Type | Stops when | Use for |
|------|------------|---------|
| `fixed` | N iterations complete | Implementation, brainstorming |
| `judgment` | N agents agree to stop | Refinement, review |
| `queue` | Task queue empties | Task-driven workflows |

### Chaining Stages

Pipelines can chain multiple stages. Each stage's output becomes input for the next:

```yaml
# pipelines/full-refine.yaml
name: full-refine
stages:
  - name: improve-plan
    stage: improve-plan
    runs: 5                    # Refine the plan 5 times

  - name: refine-beads
    stage: refine-beads
    runs: 5                    # Then refine the tasks 5 times
    inputs:
      from: improve-plan       # Uses output from previous stage
```

**Fan-out pattern** — run the same prompt from multiple perspectives:

```yaml
stages:
  - name: review
    runs: 4
    perspectives:
      - security
      - performance
      - maintainability
      - testing
    prompt: |
      Review from ${PERSPECTIVE} perspective.
      Write to ${OUTPUT}

  - name: synthesize
    runs: 1
    prompt: |
      Combine all reviews: ${INPUTS.review}
```

## Commands

| Command | Description |
|---------|-------------|
| `/sessions` | Orchestration hub: start, status, attach, kill |
| `/ralph` | Quick-start work loop with beads |
| `/refine` | Run refinement pipelines (plan + beads) |
| `/ideate` | Generate improvement ideas |
| `/pipeline` | Design, create, and edit stages |
| `/robot-mode` | Audit CLI for agent-friendliness |
| `/readme-sync` | Sync README with codebase |

### Session Management

```bash
/sessions              # Interactive menu
/sessions status       # Check all running loops
/sessions attach NAME  # Watch live (Ctrl+b, d to detach)
/sessions kill NAME    # Stop a session
/sessions plan         # Plan a new feature (PRD → tasks)
```

## Skills

Skills provide specialized workflows for planning and pipeline management.

| Skill | Invocation | Description |
|-------|------------|-------------|
| `sessions` | `/sessions` | Start/manage pipelines in tmux |
| `plan-refinery` | `/plan-refinery` | Iterative planning with Opus subagents |
| `create-prd` | `/agent-pipelines:create-prd` | Generate PRDs through adaptive questioning |
| `create-tasks` | `/agent-pipelines:create-tasks` | Break PRD into executable beads |
| `pipeline-designer` | `/pipeline` | Design new pipeline architectures |
| `pipeline-creator` | `/pipeline create` | Create stage.yaml and prompt.md files |
| `pipeline-editor` | `/pipeline edit` | Modify existing stages and pipelines |

## Built-in Stages

| Stage | Termination | Description |
|-------|-------------|-------------|
| `work` | fixed | Classic Ralph loop—implement tasks from beads |
| `improve-plan` | judgment | Refine PRD until two agents agree it's ready |
| `refine-beads` | judgment | Split/merge/fix tasks until two agents agree |
| `elegance` | judgment | Hunt unnecessary complexity in codebase |
| `idea-wizard` | fixed | Brainstorm 20-30 ideas, score by impact/effort |
| `research-plan` | judgment | Web research to validate and improve plans |
| `readme-sync` | fixed | Compare codebase to README, fill gaps |
| `robot-mode` | fixed | Audit CLI for agent-friendliness |

## Built-in Pipelines

| Pipeline | Stages | Description |
|----------|--------|-------------|
| `quick-refine` | 3+3 | Fast validation of plan and tasks |
| `full-refine` | 5+5 | Standard refinement depth |
| `deep-refine` | 8+8 | Thorough refinement for complex features |

Run with `/refine`:
```bash
/refine quick    # 3+3 iterations
/refine          # 5+5 iterations (default)
/refine deep     # 8+8 iterations
```

## Example Workflows

### Implement a Feature

```
/sessions plan  →  describe feature  →  PRD + tasks created  →  loop runs  →  done
```

1. **Plan**: `/sessions plan` or `/agent-pipelines:create-prd`
2. **Create tasks**: `/agent-pipelines:create-tasks`
3. **Refine** (optional): `/refine`
4. **Implement**: `/ralph`

### Refine an Existing Plan

```bash
/refine full my-feature    # Runs improve-plan (5x) then refine-beads (5x)
```

### Generate Ideas

```bash
/ideate 3    # Run idea-wizard 3 times for diverse perspectives
```

### Audit for Agent-Friendliness

```bash
/robot-mode my-cli    # 3 iterations analyzing CLI output
```

---

## Building Custom Stages

A stage is a prompt plus a termination strategy. That's it.

```yaml
# scripts/stages/bugfix/stage.yaml
name: bugfix
description: Fix bugs iteratively until tests pass
termination:
  type: judgment
  consensus: 2
delay: 3
```

```bash
/pipeline    # Interactive stage creation
```

The framework handles iteration, state, crash recovery, and knowing when to stop.

---

## Architecture

```
scripts/
├── engine.sh                 # Unified pipeline engine
├── run.sh                    # CLI entry point
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # Iteration history + crash recovery
│   ├── progress.sh           # Accumulated context files
│   ├── context.sh            # context.json generation
│   ├── status.sh             # status.json validation
│   ├── resolve.sh            # Template variable resolution
│   ├── notify.sh             # Desktop notifications
│   ├── lock.sh               # Session locking
│   ├── validate.sh           # Lint and dry-run
│   ├── test.sh               # Test framework
│   ├── mock.sh               # Mock execution
│   └── completions/          # Termination strategies
│       ├── beads-empty.sh    # type: queue
│       ├── plateau.sh        # type: judgment
│       └── fixed-n.sh        # type: fixed
├── stages/                   # Stage definitions
└── pipelines/                # Multi-stage pipeline configs

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

## Stage Configuration

### Fixed Termination

```yaml
name: work
termination:
  type: fixed
  iterations: 25           # Optional default (CLI can override)
delay: 3
```

### Judgment Termination

```yaml
name: improve-plan
termination:
  type: judgment
  min_iterations: 2        # Don't check consensus before this
  consensus: 2             # Consecutive stops needed
delay: 2
```

### Optional Fields

```yaml
prompt: prompts/custom.md           # Custom prompt path (default: prompt.md)
output_path: docs/output-${SESSION}.md  # Direct output to specific file
```

## Template Variables

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to context.json |
| `${PROGRESS}` | Path to progress file |
| `${STATUS}` | Path to write status.json |
| `${ITERATION}` | 1-based iteration number |
| `${SESSION_NAME}` | Session name |
| `${OUTPUT}` | Output path (multi-stage) |
| `${INPUTS}` | Previous stage outputs |
| `${PERSPECTIVE}` | Current perspective (fan-out) |

## Status Format

Agents write `status.json` at the end of each iteration:

```json
{
  "decision": "continue",
  "reason": "Found more work",
  "summary": "Implemented auth middleware",
  "work": {
    "items_completed": ["beads-abc123"],
    "files_touched": ["src/auth.ts"]
  },
  "errors": []
}
```

## Session Management

### Locking

Locks prevent duplicate sessions. Auto-released on completion or process death.

```bash
ls .claude/locks/                              # List locks
./scripts/run.sh status {session}              # Check status
./scripts/run.sh work my-session 10 --force    # Override lock
```

### Crash Recovery

```bash
./scripts/run.sh work auth 25 --resume    # Continue from last checkpoint
```

## Validation

```bash
./scripts/run.sh lint                     # Lint all stages and pipelines
./scripts/run.sh lint loop work           # Lint specific stage
./scripts/run.sh dry-run loop work auth   # Preview execution
```

## Debugging

```bash
tmux attach -t pipeline-{session}         # Watch live
cat .claude/pipeline-runs/{session}/state.json | jq
cat .claude/pipeline-runs/{session}/progress-{session}.md
bd ready --label=pipeline/{session}       # Check remaining tasks
```

## Limitations

Loops run locally in tmux. If your machine sleeps, they pause. Use a keep-awake utility for overnight runs.

## License

MIT
