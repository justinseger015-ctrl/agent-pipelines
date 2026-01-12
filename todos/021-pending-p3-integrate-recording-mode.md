---
status: pending
priority: p3
issue_id: "021"
tags: [feature, debugging, monitoring]
dependencies: []
---

# Integrate Recording Mode for Debugging

## Problem Statement

Recording mode exists in `mock.sh` but is not integrated into the actual engine. It could be valuable for debugging loop runs by capturing prompts and responses.

## Current State

**Existing code in mock.sh:**
- `RECORD_MODE` and `RECORD_DIR` variables
- `enable_record_mode()` - sets up recording directory
- `record_response()` - saves iteration output to file

**Not integrated:**
- No `--record` flag on run.sh or engine.sh
- Not called from execute_claude() or run_stage()
- Only saves output, not the prompt sent

## Proposed Implementation

### Option 1: Simple --record flag

Add `--record` flag to run.sh that:
1. Creates `.claude/recordings/{session}/{timestamp}/` directory
2. For each iteration, saves:
   - `iteration-N-prompt.md` - the resolved prompt sent to Claude
   - `iteration-N-response.md` - Claude's raw response
   - `iteration-N-status.json` - the status.json written by agent
3. At end, creates `summary.json` with session metadata

### Option 2: Full observability mode

More comprehensive recording:
- Context.json snapshots
- State.json progression
- Timing information
- Token usage (if available from Claude CLI)

## Acceptance Criteria

- [ ] `--record` flag added to run.sh/engine.sh
- [ ] Prompts are captured before sending to Claude
- [ ] Responses are captured after receiving from Claude
- [ ] Recording can be enabled/disabled per session
- [ ] Recorded sessions are organized by session name and timestamp

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-12 | Created task after deciding to keep recording mode | Debugging tools should be properly integrated |

## Resources

- Existing mock.sh recording functions
- engine.sh execute_claude() function
