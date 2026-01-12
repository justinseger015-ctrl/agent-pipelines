---
description: Launch autonomous work loops to implement beads
---

# /work

Runs the work pipeline: agents autonomously pick beads, implement them, verify with tests, commit, and close. Continues until all beads are complete or max iterations reached.

**Runtime:** ~5-10 min per bead

## Usage

```
/work                # Start work loop (auto-detects session)
/work auth           # Work loop for 'auth' session beads
/work status         # Check running work loops
/work attach NAME    # Watch live (Ctrl+b d to detach)
/work kill NAME      # Stop a work loop
```

## How It Works

Each iteration:
1. Pick highest-priority ready bead (`bd ready --label=loop/{session}`)
2. Implement the task
3. Run tests, type checks, linting
4. Commit changes and close the bead
5. Repeat until queue empty

## Termination

**Queue-based** - stops when `bd ready --label=loop/{session}` returns empty. All beads complete = done.

## Iteration Formula

`(number of beads × 1.5) + 3` rounded up. Generous buffer for retries.

## Monitoring

```bash
# Remaining beads
bd ready --label=loop/{session}

# Watch live
tmux attach -t loop-{session}

# Progress file
cat .claude/pipeline-runs/{session}/progress-{session}.md
```
