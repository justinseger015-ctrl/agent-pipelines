# Agent Pipelines

A Claude Code plugin for autonomous, multi-stage workflows that run overnight.

## Install

```bash
claude plugin marketplace add https://github.com/hwells4/agent-pipelines
claude plugin install agent-pipelines@dodo-digital
```

**Dependencies:** `tmux`, `jq`, `bd` (beads CLI)

## What It Does

Agent Pipelines chains together stages—each with its own prompt and stopping condition—to build complex autonomous workflows. Stages iterate with fresh Claude instances, avoiding the context degradation that kills long-running agents.

```
Plan (5 iterations)  →  Refine Tasks (5 iterations)  →  Implement (until done)
      ↓                        ↓                              ↓
  judgment stop            judgment stop                  queue empty
```

A single stage is a [Ralph loop](https://ghuntley.com/ralph/). Agent Pipelines extends Ralph with:

- **Multi-stage chaining** — output from one stage feeds the next
- **Three termination strategies** — fixed count, consensus judgment, or queue empty
- **Crash recovery** — resume from the last completed iteration
- **Session management** — run multiple pipelines in parallel via tmux

## Workflow

```
/sessions plan  →  /refine  →  /ralph  →  done
```

| Command | Purpose |
|---------|---------|
| `/sessions plan` | Turn feature ideas into PRD + tasks |
| `/refine` | Improve plan and tasks until two agents agree they're ready |
| `/ralph` | Implement tasks one by one until the queue is empty |
| `/pipeline` | Design and create custom stages |

Each session runs in tmux. Start one, close your laptop, check back tomorrow.

## Built-in Pipelines

| Pipeline | What it does |
|----------|--------------|
| `quick-refine` | 3 plan iterations → 3 task iterations |
| `full-refine` | 5 plan iterations → 5 task iterations |
| `deep-refine` | 8 plan iterations → 8 task iterations |

## Built-in Stages

| Stage | Stops when | Purpose |
|-------|------------|---------|
| `work` | N iterations | Implement tasks from beads |
| `improve-plan` | 2 agents agree | Refine PRD until quality plateaus |
| `refine-beads` | 2 agents agree | Split/merge tasks until ready |
| `elegance` | 2 agents agree | Hunt unnecessary complexity |
| `idea-wizard` | N iterations | Brainstorm and rank ideas |
| `research-plan` | 2 agents agree | Web research to improve plans |

## Philosophy

Long-running agents degrade. The longer the conversation, the worse the output. Context windows fill with debugging tangents and stale information.

Agent Pipelines fixes this by resetting context each iteration. A progress file carries forward only what matters—patterns discovered, work completed, learnings captured. Iteration 50 is as sharp as iteration 1.

For subjective quality decisions, two-agent consensus prevents premature stopping. One agent might think the plan is done; the second catches what's missing.

---

**Full reference:** [CLAUDE.md](CLAUDE.md) — architecture, configuration, template variables, testing framework

**Creating custom stages:** [scripts/pipelines/SCHEMA.md](scripts/pipelines/SCHEMA.md)

## License

MIT
