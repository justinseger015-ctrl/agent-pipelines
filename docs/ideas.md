# Ideas

## Ideas from ideate-20260110 - Iteration 1

### 1. Debug Mode with Verbose Logging
**Problem:** When loops fail or behave unexpectedly, there's no easy way to trace what's happening. You have to manually inspect state files, progress files, and tmux output separately.

**Solution:** Add a `--debug` flag to `run.sh` that enables:
- Timestamped logging to a dedicated log file per session
- Prints resolved prompts before sending to Claude
- Shows completion strategy decision logic
- Logs all state file mutations
- Outputs Claude's full response (not just parsed fields)

**Why now:** The system is complex enough that debugging is becoming painful. Adding this early prevents hours of future frustration and makes the system more accessible to contributors.

---

### 2. Auto-Resume Crashed Sessions
**Problem:** If Claude crashes mid-iteration (API timeout, network blip, SIGKILL), the session is left in a broken state. The user has to manually figure out where it stopped and restart.

**Solution:** Add crash recovery to `engine.sh`:
- Store "iteration_started" timestamp in state before each iteration
- On startup, check for incomplete iterations (started but not finished)
- Offer to resume from last successful iteration
- Add `--resume` flag to explicitly continue a previous session

**Why now:** As loops get longer (50+ iterations), crashes become more costly. Recovery is essential for production use.

---

### 3. Dry Run Mode
**Problem:** Users can't preview what a loop or pipeline will do before running it. This makes it risky to try new configurations or debug prompt templates.

**Solution:** Add `--dry-run` flag that:
- Resolves all template variables and prints the prompt
- Shows which completion strategy would be used
- Lists expected state/progress file locations
- For pipelines, shows the full stage sequence with models
- Does NOT execute Claude or modify any files

**Why now:** The system has many configuration options now. A dry run lets users safely experiment without consuming Claude credits or polluting their project state.

---

### 4. Manual Approval Gates in Pipelines
**Problem:** Some workflows need human review between stages. For example, you might want to review an improved plan before creating beads from it.

**Solution:** Add a new stage type: `gate`
```yaml
stages:
  - name: improve-plan
    loop: improve-plan
    runs: 5
  - name: review
    type: gate
    message: "Review the plan in docs/plan.md. Continue?"
  - name: create-beads
    loop: refine-beads
    runs: 5
```
Gates pause the pipeline and wait for user confirmation (desktop notification + tmux prompt).

**Why now:** This unlocks more sophisticated human-in-the-loop workflows, which are critical for high-stakes tasks where full autonomy is risky.

---

### 5. Session Cost Tracking
**Problem:** Users have no visibility into how much each loop/pipeline costs. Long-running sessions can burn through significant Claude credits without awareness.

**Solution:** Track and report costs per session:
- Parse Claude CLI output for token usage (if available) or estimate from prompt/response lengths
- Store cumulative tokens in state file
- Show running total in iteration output
- Report final cost summary on completion
- Add `--budget` flag to halt if cost exceeds threshold

**Why now:** As adoption grows and loops get more ambitious, cost visibility becomes essential. Users need to understand the economics before running 50-iteration loops.

---
