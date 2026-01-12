# Recording Mode for Agent Debugging

**Type:** feature
**Priority:** P3
**Created:** 2025-01-12
**Status:** Draft

---

## Overview

Add a recording mode to the loop agent orchestrator that captures individual agent iteration responses, tool calls, and reasoning. This enables debugging loop runs, optimizing prompts, and generating mock test data for tests.

## Problem Statement

The loop orchestrator runs autonomous multi-iteration agent workflows, but there's limited visibility into what each agent actually did during execution. Currently:

- `output.md` captures final text output but not structured data
- Tool calls and reasoning are lost
- No way to replay or analyze failed sessions
- Generating mock fixtures requires manual extraction

**Use Cases:**
1. **Debugging** - Understand why a session failed or behaved unexpectedly
2. **Prompt Optimization** - Compare responses across prompt variations
3. **Test Data Generation** - Create realistic fixtures from real executions

## Proposed Solution

### High-Level Approach

Add `--record` flag that captures Claude's full response stream (using `--output-format stream-json --verbose`) for each iteration, organizing recordings in `.claude/recordings/{session}/`.

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Recording location** | `.claude/recordings/` | Separate from runtime data in `pipeline-runs/` |
| **Directory structure** | Mirror `pipeline-runs/` hierarchy | Consistency, easy correlation |
| **Flag syntax** | `--record [--record-level LEVEL]` | Simple flag + optional level |
| **Default level** | `standard` | Balance between detail and storage |
| **Resume behavior** | Append to existing directory | Preserve partial data, use iteration numbers from state |
| **Force behavior** | Move old recordings to `.old.{timestamp}/` | Preserve data, prevent accidental loss |
| **Recording failure** | Log warning, continue session | Recording is observability, not critical path |
| **File naming** | Zero-padded 3-digit (`001`) | Match existing conventions |

### Recording Levels

| Level | Captures | Storage per Iteration | Use Case |
|-------|----------|----------------------|----------|
| `minimal` | Metadata, timing, status | ~500 bytes | Lightweight monitoring |
| `standard` | + Prompt/response hashes, errors | ~2 KB | Debugging |
| `full` | + Complete prompts and responses | ~50-200 KB | Test data generation |

## Technical Approach

### Architecture

```
run.sh                    # Parse --record flag
  └── engine.sh           # Initialize recording, call record functions
        ├── lib/record.sh # NEW: Recording functions
        └── execute_claude()
              └── tee to iteration directory
```

### File Structure

```
.claude/recordings/{session}/
├── manifest.json           # Session metadata, recording config
├── trace.jsonl             # Streaming event log (all iterations)
└── stage-00-{name}/        # Mirrors pipeline-runs structure
    └── iterations/
        └── 001/
            ├── prompt.md       # Resolved prompt sent to Claude
            ├── response.jsonl  # Stream-json output (full tool calls)
            ├── response.md     # Extracted text response
            ├── context.json    # Copy of input context
            ├── status.json     # Copy of agent's decision
            └── timing.json     # Start time, duration, exit code
```

### New Library: `scripts/lib/record.sh`

```bash
# Environment variables
RECORD_MODE="${CLAUDE_LOOP_RECORD:-off}"
RECORD_LEVEL="${CLAUDE_LOOP_RECORD_LEVEL:-standard}"
RECORD_DIR=""

# Initialize recording for a session
init_recording() {
  local session=$1
  is_recording || return 0

  RECORD_DIR="$PROJECT_ROOT/.claude/recordings/$session"
  mkdir -p "$RECORD_DIR"

  # Write manifest.json
  jq -n \
    --arg session "$session" \
    --arg level "$RECORD_LEVEL" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg git_hash "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
    '{session: $session, level: $level, started_at: $started, git_commit: $git_hash}' \
    > "$RECORD_DIR/manifest.json"
}

# Record iteration start
record_iteration_start() {
  local iteration=$1
  local stage_dir=$2
  is_recording || return 0

  local iter_dir="$RECORD_DIR/$stage_dir/iterations/$(printf '%03d' $iteration)"
  mkdir -p "$iter_dir"

  # Create timing.json with start time
  echo "{\"started_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$iter_dir/timing.json"

  echo "$iter_dir"
}

# Record prompt (before execution)
record_prompt() {
  local iter_dir=$1
  local prompt=$2
  is_recording || return 0

  if [ "$RECORD_LEVEL" = "full" ]; then
    echo "$prompt" > "$iter_dir/prompt.md"
  else
    # Just record hash for standard/minimal
    local hash=$(echo "$prompt" | sha256sum | cut -d' ' -f1)
    jq --arg h "$hash" '. + {prompt_hash: $h}' "$iter_dir/timing.json" > "$iter_dir/timing.json.tmp"
    mv "$iter_dir/timing.json.tmp" "$iter_dir/timing.json"
  fi
}

# Record response (after execution)
record_response() {
  local iter_dir=$1
  local response_file=$2
  local status_file=$3
  local context_file=$4
  local exit_code=$5
  is_recording || return 0

  # Copy status.json and context.json
  [ -f "$status_file" ] && cp "$status_file" "$iter_dir/status.json"
  [ -f "$context_file" ] && cp "$context_file" "$iter_dir/context.json"

  if [ "$RECORD_LEVEL" = "full" ]; then
    # Copy full response
    cp "$response_file" "$iter_dir/response.md"
  fi

  # Update timing.json with completion data
  local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq --arg end "$end_time" --argjson exit "$exit_code" \
    '. + {completed_at: $end, exit_code: $exit}' \
    "$iter_dir/timing.json" > "$iter_dir/timing.json.tmp"
  mv "$iter_dir/timing.json.tmp" "$iter_dir/timing.json"

  # Append to trace.jsonl
  jq -nc \
    --arg ts "$end_time" \
    --argjson iter "$iteration" \
    --argjson exit "$exit_code" \
    '{timestamp: $ts, iteration: $iter, exit_code: $exit}' \
    >> "$RECORD_DIR/trace.jsonl"
}

# Check if recording is enabled
is_recording() {
  [ "$RECORD_MODE" = "1" ] || [ "$RECORD_MODE" = "true" ] || [ "$RECORD_MODE" = "on" ]
}
```

### Integration Points

**1. In `run.sh` (argument parsing):**
```bash
# scripts/run.sh:~50 (after existing flag parsing)
--record)
  export CLAUDE_LOOP_RECORD=1
  shift
  ;;
--record-level)
  export CLAUDE_LOOP_RECORD_LEVEL="$2"
  shift 2
  ;;
```

**2. In `engine.sh` (session initialization):**
```bash
# scripts/engine.sh:~80 (after sourcing libraries)
source "$SCRIPT_DIR/lib/record.sh"

# After session directory creation
init_recording "$session"
```

**3. In `engine.sh` `run_stage()` (iteration loop):**
```bash
# scripts/engine.sh:~240 (before execute_claude)
local record_iter_dir=$(record_iteration_start "$i" "$stage_dir")
record_prompt "$record_iter_dir" "$resolved_prompt"

# After execute_claude and status.json written
record_response "$record_iter_dir" "$output_file" "$status_file" "$context_file" "$exit_code"
```

## Acceptance Criteria

### Functional Requirements

- [ ] `--record` flag added to run.sh, enables recording mode
- [ ] `--record-level {minimal|standard|full}` configures detail level
- [ ] `CLAUDE_LOOP_RECORD=1` environment variable enables recording
- [ ] Recordings saved to `.claude/recordings/{session}/` directory
- [ ] Prompts captured before sending to Claude (full level)
- [ ] Responses captured after receiving from Claude (full level)
- [ ] status.json and context.json copied to recording directory
- [ ] manifest.json created with session metadata
- [ ] trace.jsonl contains streaming event log
- [ ] Recording can be enabled/disabled per session
- [ ] `--resume` appends to existing recordings (uses state iteration numbers)
- [ ] `--force` moves existing recordings to `.old.{timestamp}/`

### Non-Functional Requirements

- [ ] Recording does not block session on disk errors (logs warning, continues)
- [ ] Recording adds <100ms overhead per iteration
- [ ] File permissions match existing `.claude/` conventions (user-only)
- [ ] `.claude/recordings/` added to .gitignore

### Quality Gates

- [ ] Unit tests for recording functions in `scripts/tests/test_record.sh`
- [ ] Integration test: record a 3-iteration session, verify all files created
- [ ] Help text updated: `./scripts/run.sh --help` shows --record flags
- [ ] CLAUDE.md updated with recording section

## TDD Implementation Approach

**Philosophy:** Write tests first, then implement just enough code to pass. Each phase starts with failing tests.

### Test Structure

Create `scripts/tests/test_record.sh` following existing test patterns:

```bash
#!/bin/bash
# Recording mode tests - verify recording capture works correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/record.sh"

#-------------------------------------------------------------------------------
# is_recording() Tests
#-------------------------------------------------------------------------------

test_is_recording_false_by_default() {
  unset CLAUDE_LOOP_RECORD
  assert_false "$(is_recording && echo true || echo false)" "Recording off by default"
}

test_is_recording_enabled_with_env_var() {
  export CLAUDE_LOOP_RECORD=1
  assert_true "$(is_recording && echo true || echo false)" "Recording on with CLAUDE_LOOP_RECORD=1"
  unset CLAUDE_LOOP_RECORD
}

test_is_recording_enabled_with_true() {
  export CLAUDE_LOOP_RECORD=true
  assert_true "$(is_recording && echo true || echo false)" "Recording on with CLAUDE_LOOP_RECORD=true"
  unset CLAUDE_LOOP_RECORD
}

#-------------------------------------------------------------------------------
# init_recording() Tests
#-------------------------------------------------------------------------------

test_init_recording_creates_directory() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"

  assert_dir_exists "$test_dir/.claude/recordings/test-session" "Recording directory created"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

test_init_recording_creates_manifest() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"

  local manifest="$test_dir/.claude/recordings/test-session/manifest.json"
  assert_file_exists "$manifest" "manifest.json created"
  assert_json_field "$manifest" ".session" "test-session" "session field correct"
  assert_json_field_exists "$manifest" ".started_at" "started_at field exists"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

test_init_recording_noop_when_disabled() {
  local test_dir=$(create_test_dir)
  unset CLAUDE_LOOP_RECORD
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"

  assert_file_not_exists "$test_dir/.claude/recordings/test-session/manifest.json" "No manifest when disabled"

  cleanup_test_dir "$test_dir"
  unset PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# record_iteration_start() Tests
#-------------------------------------------------------------------------------

test_record_iteration_start_creates_iter_dir() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir=$(record_iteration_start 1 "stage-00-work")

  assert_dir_exists "$iter_dir" "Iteration directory created"
  assert_contains "$iter_dir" "iterations/001" "Zero-padded iteration number"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

test_record_iteration_start_creates_timing_json() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir=$(record_iteration_start 1 "stage-00-work")

  assert_file_exists "$iter_dir/timing.json" "timing.json created"
  assert_json_field_exists "$iter_dir/timing.json" ".started_at" "started_at field exists"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# record_prompt() Tests
#-------------------------------------------------------------------------------

test_record_prompt_full_level() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export CLAUDE_LOOP_RECORD_LEVEL=full
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir=$(record_iteration_start 1 "stage-00-work")
  record_prompt "$iter_dir" "This is the test prompt content"

  assert_file_exists "$iter_dir/prompt.md" "prompt.md created in full mode"
  local content=$(cat "$iter_dir/prompt.md")
  assert_contains "$content" "test prompt content" "Prompt content saved"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD CLAUDE_LOOP_RECORD_LEVEL PROJECT_ROOT
}

test_record_prompt_standard_level_saves_hash() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export CLAUDE_LOOP_RECORD_LEVEL=standard
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir=$(record_iteration_start 1 "stage-00-work")
  record_prompt "$iter_dir" "This is the test prompt content"

  assert_file_not_exists "$iter_dir/prompt.md" "prompt.md NOT created in standard mode"
  assert_json_field_exists "$iter_dir/timing.json" ".prompt_hash" "Hash saved in timing.json"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD CLAUDE_LOOP_RECORD_LEVEL PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# record_response() Tests
#-------------------------------------------------------------------------------

test_record_response_copies_status_and_context() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir=$(record_iteration_start 1 "stage-00-work")

  # Create mock files
  local mock_status="$test_dir/status.json"
  local mock_context="$test_dir/context.json"
  local mock_response="$test_dir/output.md"
  echo '{"decision": "continue"}' > "$mock_status"
  echo '{"session": "test"}' > "$mock_context"
  echo "Agent response here" > "$mock_response"

  record_response "$iter_dir" "$mock_response" "$mock_status" "$mock_context" 0

  assert_file_exists "$iter_dir/status.json" "status.json copied"
  assert_file_exists "$iter_dir/context.json" "context.json copied"
  assert_json_field "$iter_dir/timing.json" ".exit_code" "0" "exit_code recorded"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

test_record_response_appends_to_trace() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"
  local iter_dir1=$(record_iteration_start 1 "stage-00-work")
  local iter_dir2=$(record_iteration_start 2 "stage-00-work")

  # Create mock files
  echo '{"decision": "continue"}' > "$test_dir/status.json"
  echo "Response" > "$test_dir/output.md"

  record_response "$iter_dir1" "$test_dir/output.md" "$test_dir/status.json" "" 0
  record_response "$iter_dir2" "$test_dir/output.md" "$test_dir/status.json" "" 0

  local trace_lines=$(wc -l < "$test_dir/.claude/recordings/test-session/trace.jsonl")
  assert_eq "2" "$trace_lines" "Two lines in trace.jsonl"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# Error Handling Tests
#-------------------------------------------------------------------------------

test_recording_failure_does_not_break_session() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  init_recording "test-session"

  # Make recording dir read-only to simulate write failure
  chmod 555 "$test_dir/.claude/recordings/test-session"

  # This should not exit with error
  local exit_code=0
  record_iteration_start 1 "stage-00-work" 2>/dev/null || exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$test_dir/.claude/recordings/test-session"

  # Should either succeed (created before chmod) or fail gracefully
  # Key: script should not exit
  assert_eq "0" "0" "Script continued after recording failure"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# Resume and Force Tests
#-------------------------------------------------------------------------------

test_init_recording_resume_preserves_existing() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  # Create existing recording
  mkdir -p "$test_dir/.claude/recordings/test-session/stage-00-work/iterations/001"
  echo '{"existing": true}' > "$test_dir/.claude/recordings/test-session/manifest.json"

  # Resume should NOT overwrite
  init_recording "test-session" "resume"

  assert_json_field "$test_dir/.claude/recordings/test-session/manifest.json" ".existing" "true" "Existing manifest preserved"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

test_init_recording_force_moves_existing() {
  local test_dir=$(create_test_dir)
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  # Create existing recording
  mkdir -p "$test_dir/.claude/recordings/test-session"
  echo '{"old": true}' > "$test_dir/.claude/recordings/test-session/manifest.json"

  # Force should move old and create new
  init_recording "test-session" "force"

  # Old should be moved
  local old_dirs=$(ls -d "$test_dir/.claude/recordings/test-session.old."* 2>/dev/null | wc -l)
  assert_eq "1" "$old_dirs" "Old recording moved to .old.*"

  # New should be fresh
  assert_json_field_exists "$test_dir/.claude/recordings/test-session/manifest.json" ".started_at" "New manifest created"

  cleanup_test_dir "$test_dir"
  unset CLAUDE_LOOP_RECORD PROJECT_ROOT
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo "Recording Mode Tests"
echo "===================="

run_test "is_recording false by default" test_is_recording_false_by_default
run_test "is_recording enabled with env var" test_is_recording_enabled_with_env_var
run_test "is_recording enabled with true" test_is_recording_enabled_with_true
run_test "init_recording creates directory" test_init_recording_creates_directory
run_test "init_recording creates manifest" test_init_recording_creates_manifest
run_test "init_recording noop when disabled" test_init_recording_noop_when_disabled
run_test "record_iteration_start creates iter dir" test_record_iteration_start_creates_iter_dir
run_test "record_iteration_start creates timing.json" test_record_iteration_start_creates_timing_json
run_test "record_prompt full level" test_record_prompt_full_level
run_test "record_prompt standard level saves hash" test_record_prompt_standard_level_saves_hash
run_test "record_response copies status and context" test_record_response_copies_status_and_context
run_test "record_response appends to trace" test_record_response_appends_to_trace
run_test "recording failure does not break session" test_recording_failure_does_not_break_session
run_test "init_recording resume preserves existing" test_init_recording_resume_preserves_existing
run_test "init_recording force moves existing" test_init_recording_force_moves_existing

test_summary
```

## Implementation Phases (TDD)

### Phase 1: Core Recording Infrastructure

**Step 1: Write failing tests first**
```bash
# Run tests (they will fail - lib/record.sh doesn't exist)
./scripts/tests/test_record.sh
```

**Step 2: Implement minimal code to pass tests**

1. Create `scripts/lib/record.sh` with:
   - `is_recording()` - check if enabled
   - `init_recording()` - create directory and manifest
   - `record_iteration_start()` - create iteration directory
   - `record_prompt()` - save prompt based on level
   - `record_response()` - save response, update trace

2. Run tests until green:
   - `test_is_recording_*` tests pass
   - `test_init_recording_*` tests pass
   - `test_record_iteration_start_*` tests pass
   - `test_record_prompt_*` tests pass
   - `test_record_response_*` tests pass

**Files to create:**
- `scripts/tests/test_record.sh` (write first, will fail)
- `scripts/lib/record.sh` (implement to make tests pass)

### Phase 2: Flag Parsing Integration

**Step 1: Write integration test**

Add to `scripts/tests/test_engine_integration.sh`:
```bash
test_record_flag_enables_recording() {
  # Test that --record flag sets CLAUDE_LOOP_RECORD=1
  local output=$(./scripts/run.sh work test 1 --record --dry-run 2>&1)
  assert_contains "$output" "CLAUDE_LOOP_RECORD=1" "Recording env var set"
}
```

**Step 2: Implement flag parsing**

1. Add `--record` and `--record-level` to `run.sh`
2. Export `CLAUDE_LOOP_RECORD` and `CLAUDE_LOOP_RECORD_LEVEL`
3. Pass to engine.sh

**Files to modify:**
- `scripts/tests/test_engine_integration.sh` (~10 lines)
- `scripts/run.sh` (~15 lines: flag parsing, help text)

### Phase 3: Engine Integration

**Step 1: Write integration test**

```bash
test_engine_records_iteration() {
  local test_dir=$(create_test_dir)
  export MOCK_MODE=true
  export CLAUDE_LOOP_RECORD=1
  export PROJECT_ROOT="$test_dir"

  # Run 2-iteration session with mock
  ./scripts/run.sh work test-record 2

  # Verify recording files created
  assert_dir_exists "$test_dir/.claude/recordings/test-record"
  assert_file_exists "$test_dir/.claude/recordings/test-record/manifest.json"
  assert_dir_exists "$test_dir/.claude/recordings/test-record/stage-00-work/iterations/001"

  cleanup_test_dir "$test_dir"
}
```

**Step 2: Integrate into engine.sh**

1. Source `lib/record.sh`
2. Call `init_recording()` after session init
3. Call `record_iteration_start()` before execute_claude
4. Call `record_prompt()` after resolve_prompt
5. Call `record_response()` after status.json written

**Files to modify:**
- `scripts/tests/test_engine_integration.sh` (~20 lines)
- `scripts/engine.sh` (~25 lines: source lib, call functions in run_stage)

### Phase 4: Resume and Force Handling

**Step 1: Tests already written**
- `test_init_recording_resume_preserves_existing`
- `test_init_recording_force_moves_existing`

**Step 2: Implement in record.sh**

1. Accept mode parameter in `init_recording()`
2. Detect existing recording directory
3. Resume: skip manifest creation if exists
4. Force: move existing to `.old.{timestamp}/`

**Files to modify:**
- `scripts/lib/record.sh` (~30 lines)

### Phase 5: Error Handling

**Step 1: Test already written**
- `test_recording_failure_does_not_break_session`

**Step 2: Implement graceful failure**

1. Wrap all file operations in error handling
2. Log warning to stderr on failure
3. Continue session execution

**Files to modify:**
- `scripts/lib/record.sh` (~15 lines)

### Phase 6: Documentation

**Tasks:**
1. Update CLAUDE.md with recording section
2. Update run.sh help text
3. Add `.claude/recordings/` to .gitignore

**Files to modify:**
- `CLAUDE.md` (~30 lines: new "Recording Mode" section)
- `.gitignore` (~2 lines)
- `scripts/run.sh` (help text already done in Phase 2)

## Test Execution Commands

```bash
# Run all recording tests
./scripts/tests/test_record.sh

# Run specific test
./scripts/tests/test_record.sh test_init_recording_creates_directory

# Run all tests (including recording)
./scripts/run.sh test

# Run with verbose output
TEST_VERBOSE=true ./scripts/tests/test_record.sh
```

## Future Considerations

### Not In Scope (Future Work)

1. **Replay mode** - Re-run session using recorded responses (mock mode integration)
2. **Recording diff** - Compare recordings between sessions
3. **Auto-cleanup** - Purge recordings older than N days
4. **Recording viewer** - TUI for browsing recordings
5. **Tool call extraction** - Parse stream-json to extract individual tool calls
6. **Token/cost tracking** - Extract usage data from Claude response

### Migration Path

- Existing `mock.sh` `RECORD_MODE` and `record_response()` remain separate (different use case: fixtures vs debugging)
- Future: Could add `./scripts/run.sh convert-to-fixtures {session}` command

## Security Considerations

**Warnings:**
- Recordings may contain sensitive data (API keys, passwords, PII if in prompts)
- `.claude/recordings/` should be added to `.gitignore`
- Consider sanitization for environments with strict compliance requirements

**Mitigations:**
- File permissions: 600 (user-only read/write)
- Not committed to git by default
- Documentation warns about sensitive data

## Dependencies & Prerequisites

- None - feature is additive
- Uses existing libraries: `state.sh`, `context.sh`

## References

### Internal References

- Existing mock.sh recording functions: `scripts/lib/mock.sh:377-404`
- Engine execute_claude function: `scripts/engine.sh:136-153`
- Run_stage iteration loop: `scripts/engine.sh:197-326`
- State management patterns: `scripts/lib/state.sh`
- Context generation: `scripts/lib/context.sh`
- Status handling: `scripts/lib/status.sh`

### External References

- [OpenTelemetry AI Agent Observability](https://opentelemetry.io/blog/2025/ai-agent-observability/)
- [Langfuse Tracing Data Model](https://langfuse.com/docs/observability/data-model)
- [VCR.py Cassette Pattern](https://vcrpy.readthedocs.io/en/latest/usage.html)
- [Claude CLI --output-format docs](https://code.claude.com/docs/en/cli-reference)

### Related Work

- Todo: `todos/021-pending-p3-integrate-recording-mode.md`
