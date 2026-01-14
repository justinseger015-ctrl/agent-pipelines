# Session Inheritance Plan

## Overview

Add the ability to start a new pipeline session with warm context inherited from a previous completed session. This solves the "cold start" problem where every session starts from scratch.

## Problem Statement

Currently:
- `--resume` continues a crashed session (same session ID)
- New sessions start completely fresh
- Learnings from previous sessions are lost
- Agents re-discover patterns that were already found

We need:
- Start NEW session with context from COMPLETED session
- Agent understands both inherited context AND new task
- Clear lineage tracking

## Glossary

| Term | Definition |
|------|------------|
| **learnings** | Key insights discovered during a session (e.g., "JWT refresh tokens need atomic rotation"). Stored in status.json as structured array. |
| **patterns** | Reusable code patterns or approaches found useful (e.g., "Error handling pattern in src/middleware"). More structural than learnings. |
| **progress_summary** | Compressed narrative of what was accomplished, extracted from progress.md. |
| **comprehension** | Agent's stated understanding of inherited context before starting work. |
| **lineage** | Chain of session inheritance (A → B → C). Stored as ordered array of ancestor session names. |
| **warnings** | Things to avoid based on previous session experience (e.g., "Don't modify X without updating Y"). |
| **decisions** | Significant choices made with rationale, queryable for future sessions. |
| **transitive inheritance** | When C inherits from B which inherited from A, C gets A's learnings through B's lineage. |
| **cumulative learnings** | Learnings from the current session combined with inherited learnings from ancestors. |

## Requirements

### Functional
1. CLI flag: `--inherit <session-name>` to specify source session
2. Pipeline config: `inherit: { from: session-name, select: [learnings, patterns] }`
3. Agent must echo understanding of inherited context before starting work
4. Support partial inheritance (just learnings, or full progress)
5. **NEW**: Discovery command: `./scripts/run.sh sessions list --completed` to find inheritable sessions
6. **NEW**: Inherited content size limit: max 8000 tokens to prevent context bloat
7. **NEW**: Support typed inheritance categories: `select: [learnings, patterns, warnings, decisions]`

### Non-Functional
1. Graceful degradation if source session doesn't exist
2. No performance impact on sessions without inheritance
3. Clear error messages for invalid inheritance targets
4. **NEW**: Backward compatibility - sessions without learnings inherit only progress_summary
5. **NEW**: Security - filter potential secrets from inherited learnings (env vars, tokens, keys)
6. **NEW**: Cycle detection - prevent circular inheritance chains (A→B→A)
7. **NEW**: Graceful JSON error handling - skip malformed status.json files without failing
8. **NEW**: Depth limit - recursive inheritance capped at 3 levels to prevent unbounded context growth
9. **NEW**: Deduplication - identical learnings from ancestor sessions appear only once
10. **NEW**: Session names must not contain commas (validated on session creation) to support lineage tracking
11. **NEW**: Cumulative inheritance - inheriting session's own learnings are combined with inherited learnings for subsequent inheritors

## Design

### CLI Interface

```bash
# Discover inheritable sessions
./scripts/run.sh sessions list --completed
# Output:
# NAME              STATUS     COMPLETED_AT          LEARNINGS
# auth-v1           complete   2026-01-12T15:30:00Z  12
# refine-payments   complete   2026-01-11T10:00:00Z  8
# bug-hunt-api      complete   2026-01-10T08:45:00Z  5

# View details of a potential inheritance source
./scripts/run.sh sessions show auth-v1 --learnings
# Output shows learnings array, patterns, decisions

# Inherit from a specific session
./scripts/run.sh ralph auth-v2 25 --inherit auth-v1

# Pipeline config
./scripts/run.sh pipeline refine.yaml my-session --inherit previous-refine
```

### Pipeline Config

```yaml
# In pipeline.yaml or stage.yaml
inherit:
  from: previous-session-name    # Required: source session
  select:                        # Optional: what to inherit (default: all)
    - learnings                  # From status.json learnings fields
    - progress                   # Full progress.md content
    - patterns                   # Discovered patterns section
  comprehension: required        # Optional: require agent to echo understanding
```

### Context.json Extension

Add `inherited` block to context.json:

```json
{
  "session": "auth-v2",
  "iteration": 1,
  "inherited": {
    "version": "1",
    "from_session": "auth-v1",
    "from_completed_at": "2026-01-12T15:30:00Z",
    "learnings": [
      "JWT refresh tokens need atomic rotation",
      "Use httpOnly cookies for token storage"
    ],
    "patterns": [
      "Auth middleware validates before controller"
    ],
    "warnings": [
      "Don't modify session.ts:145 without updating tests"
    ],
    "decisions": [
      "Chose JWT over sessions - needed stateless scaling for microservices"
    ],
    "progress_summary": "Implemented basic JWT auth with login/logout..."
  },
  "paths": {...}
}
```

### Comprehension Checkpoint

Stage prompts should include comprehension verification:

```markdown
## Step 0: Verify Understanding

Before starting, confirm you understand:

### Inherited Context
Read inherited learnings from context.json:
```bash
jq '.inherited' ${CTX}
```

Summarize in 2-3 sentences what was learned in the previous session.

### Current Task
State in one sentence what you will accomplish this iteration.

### Key Constraints
List any constraints from inherited context that apply.
```

### Engine Changes

#### New Library: `scripts/lib/inherit.sh`

```bash
# Load inherited context from a previous session
# Usage: load_inherited_context "$source_session" "$select_options" "$max_chars" "$visited_sessions" "$depth"
# Returns: JSON object with inherited context to stdout
#
# Parameters:
#   source_session  - Name of session to inherit from (required)
#   select_options  - What to inherit: "all" or comma-separated list of: learnings,patterns,warnings,decisions,progress (default: "all")
#   max_chars       - Maximum characters in inherited content (default: 32000 ≈ 8000 tokens)
#   visited_sessions - Internal parameter for cycle detection, caller should pass "" or omit
#   depth           - Internal parameter for recursion tracking, caller should pass 0 or omit
#
# Exit codes:
#   0 - Success (including graceful degradation with empty {})
#   1 - Fatal error (source doesn't exist, invalid state.json)
#   2 - Warning (source running/incomplete, returns valid JSON but warns)
#
# Error handling:
#   - Exit 0 with empty JSON {} on recoverable errors (cycle detected, depth exceeded)
#   - Exit 1 only for unrecoverable errors (source doesn't exist, invalid state.json)
#   - Exit 2 for warnings that should continue (source running/incomplete)
#
# Note: Session names must not contain commas (used as delimiter in lineage tracking)
load_inherited_context() {
  local source_session=$1
  local select_options=${2:-"all"}
  local max_chars=${3:-32000}  # ~8000 tokens ≈ 32000 chars (4 chars/token avg)
  local visited_sessions=${4:-""}  # For cycle detection
  local depth=${5:-0}  # Track recursion depth

  local source_dir="$PROJECT_ROOT/.claude/pipeline-runs/$source_session"

  # Depth limit: prevent unbounded context growth
  local max_depth=3
  if [ "$depth" -ge "$max_depth" ]; then
    echo "Warning: Max inheritance depth ($max_depth) reached, stopping at '$source_session'" >&2
    echo "{}"
    return 0  # Return empty, don't fail
  fi

  # Cycle detection: check if we've already visited this session
  if [[ ",$visited_sessions," == *",$source_session,"* ]]; then
    echo "Warning: Circular inheritance detected - '$source_session' already in chain: $visited_sessions" >&2
    echo "{}"
    return 0  # Return empty, don't fail
  fi
  visited_sessions="${visited_sessions:+$visited_sessions,}$source_session"

  # Validate source exists
  if [ ! -d "$source_dir" ]; then
    echo "Error: Source session '$source_session' not found" >&2
    echo "Available sessions:" >&2
    ls "$PROJECT_ROOT/.claude/pipeline-runs" 2>/dev/null | head -10 >&2
    return 1
  fi

  local source_state="$source_dir/state.json"

  # Validate state.json exists and is valid JSON
  if [ ! -f "$source_state" ] || ! jq empty "$source_state" 2>/dev/null; then
    echo "Error: Source session '$source_session' has invalid/missing state.json" >&2
    return 1
  fi

  local source_status=$(jq -r '.status // "unknown"' "$source_state" 2>/dev/null)

  # Warn but continue for non-complete sessions
  case "$source_status" in
    complete|completed) ;; # OK
    running)
      echo "Warning: Source session '$source_session' is still running - inheritance may be incomplete" >&2
      ;;
    *)
      echo "Warning: Source session '$source_session' status is '$source_status', not 'complete'" >&2
      ;;
  esac

  # Extract learnings from all iteration status.json files
  # Handle invalid JSON gracefully - skip files that fail to parse
  local learnings_json
  learnings_json=$(find "$source_dir" -path "*/iterations/*/status.json" -type f 2>/dev/null | \
    while read -r file; do
      # Only process valid JSON files
      if jq -e '.' "$file" >/dev/null 2>&1; then
        jq -r '.learnings[]? // empty' "$file" 2>/dev/null
      fi
    done | \
    grep -v '^$' | \
    filter_secrets | \
    head -100 | \
    jq -R -s 'split("\n") | map(select(length > 0))')

  # Fallback to empty array if extraction failed
  [ -z "$learnings_json" ] && learnings_json="[]"

  # Extract patterns (if select includes patterns)
  local patterns_json="[]"
  if [[ "$select_options" == "all" || "$select_options" == *"patterns"* ]]; then
    patterns_json=$(find "$source_dir" -path "*/iterations/*/status.json" -type f 2>/dev/null | \
      while read -r file; do
        if jq -e '.' "$file" >/dev/null 2>&1; then
          jq -r '.patterns[]? // empty' "$file" 2>/dev/null
        fi
      done | \
      grep -v '^$' | \
      head -50 | \
      jq -R -s 'split("\n") | map(select(length > 0))')
    [ -z "$patterns_json" ] && patterns_json="[]"
  fi

  # Extract warnings (if select includes warnings)
  local warnings_json="[]"
  if [[ "$select_options" == "all" || "$select_options" == *"warnings"* ]]; then
    warnings_json=$(find "$source_dir" -path "*/iterations/*/status.json" -type f 2>/dev/null | \
      while read -r file; do
        if jq -e '.' "$file" >/dev/null 2>&1; then
          jq -r '.warnings[]? // empty' "$file" 2>/dev/null
        fi
      done | \
      grep -v '^$' | \
      head -30 | \
      jq -R -s 'split("\n") | map(select(length > 0))')
    [ -z "$warnings_json" ] && warnings_json="[]"
  fi

  # Extract decisions (if select includes decisions)
  local decisions_json="[]"
  if [[ "$select_options" == "all" || "$select_options" == *"decisions"* ]]; then
    decisions_json=$(find "$source_dir" -path "*/iterations/*/status.json" -type f 2>/dev/null | \
      while read -r file; do
        if jq -e '.' "$file" >/dev/null 2>&1; then
          jq -r '.decisions[]? // empty' "$file" 2>/dev/null
        fi
      done | \
      grep -v '^$' | \
      head -30 | \
      jq -R -s 'split("\n") | map(select(length > 0))')
    [ -z "$decisions_json" ] && decisions_json="[]"
  fi

  # Extract progress summary - take last meaningful section, not arbitrary lines
  local progress_file
  progress_file=$(find "$source_dir" -name "progress*.md" -type f 2>/dev/null | head -1)
  local progress_summary=""
  if [ -f "$progress_file" ]; then
    # Extract last 2000 chars, which is roughly 500 tokens
    progress_summary=$(tail -c 2000 "$progress_file" | filter_secrets)
  fi

  # Deduplicate arrays - identical learnings from ancestor sessions should appear only once
  # This is important when A→B→C inherits from both direct and transitive ancestors
  deduplicate_json_array() {
    local arr=$1
    echo "$arr" | jq 'unique'
  }

  learnings_json=$(deduplicate_json_array "$learnings_json")
  patterns_json=$(deduplicate_json_array "$patterns_json")
  warnings_json=$(deduplicate_json_array "$warnings_json")
  decisions_json=$(deduplicate_json_array "$decisions_json")

  # Build inherited context JSON
  jq -n \
    --arg from "$source_session" \
    --arg completed "$(jq -r '.completed_at // .updated_at // .started_at' "$source_state")" \
    --argjson learnings "$learnings_json" \
    --argjson patterns "$patterns_json" \
    --argjson warnings "$warnings_json" \
    --argjson decisions "$decisions_json" \
    --arg summary "$progress_summary" \
    --arg version "1" \
    --arg lineage "$visited_sessions" \
    '{
      version: $version,
      from_session: $from,
      from_completed_at: $completed,
      lineage: ($lineage | split(",") | map(select(length > 0))),
      learnings: $learnings,
      patterns: $patterns,
      warnings: $warnings,
      decisions: $decisions,
      progress_summary: $summary
    }'
}

# Filter potential secrets from inherited content
# Removes lines that look like they contain actual secret values
# More conservative: only filter lines with key=value or key: value patterns
# where the value looks like a secret (long alphanumeric strings, base64, etc.)
#
# Design notes:
# - Uses two-stage grep for clarity and maintainability
# - First pattern: key=value or key: value where value looks secret-like
# - Second pattern: well-known API key prefixes (platform-specific)
# - Reads stdin once into variable to avoid race conditions and allow error handling
#
# Known limitations:
# - May not catch secrets in non-standard formats
# - May false-positive on legitimate long strings (UUIDs, hashes in comments)
# - Cannot detect secrets that have been base64-encoded or obfuscated
filter_secrets() {
  # Read all input first to handle empty input gracefully
  local input
  input=$(cat)

  # If input is empty, return empty (no error)
  if [ -z "$input" ]; then
    return 0
  fi

  # Pattern explanation:
  # - Match lines with secret-like keys followed by = or :
  # - Where the value is a long string (20+ chars) of alphanumeric/base64 characters
  # - Or starts with common secret prefixes (sk-, pk-, ghp_, xoxb-, etc.)
  #
  # Note: grep -v returns exit code 1 when no lines match (all filtered), which is valid.
  # We use `|| true` to prevent pipeline failure on that case specifically.
  echo "$input" | \
    grep -v -iE '(api[_-]?key|secret|token|password|private[_-]?key|credential|auth[_-]?token|bearer|access[_-]?token)["\047]?\s*[:=]\s*["\047]?[A-Za-z0-9+/=_-]{20,}' 2>/dev/null | \
    grep -v -E '(sk-|pk-|ghp_|gho_|xoxb-|xoxa-|AKIA)[A-Za-z0-9]{16,}' 2>/dev/null || true
}
```

#### Changes to `scripts/lib/context.sh`

In `generate_context()`, add inherited context:

```bash
# After line ~95, before building final JSON
local inherited_json="{}"
if [ -n "$INHERIT_FROM" ]; then
  inherited_json=$(load_inherited_context "$INHERIT_FROM" "$INHERIT_SELECT")
  if [ $? -ne 0 ]; then
    echo "Warning: Failed to load inherited context, continuing without" >&2
    inherited_json="{}"
  fi
fi

# Add to jq command: --argjson inherited "$inherited_json"
# Add to JSON output: inherited: $inherited
```

#### Session Name Validation (scripts/lib/session.sh)

Add validation to prevent comma-containing session names:

```bash
# Validate session name for inheritance compatibility
# Session names must not contain commas (used as lineage delimiter)
validate_session_name() {
  local name=$1
  if [[ "$name" == *","* ]]; then
    echo "Error: Session name '$name' contains comma, which is not allowed (used as lineage delimiter)" >&2
    return 1
  fi
  # Also validate no path traversal
  if [[ "$name" == *"/"* || "$name" == *".."* ]]; then
    echo "Error: Session name '$name' contains invalid characters (/ or ..)" >&2
    return 1
  fi
  return 0
}
```

#### Changes to `scripts/engine.sh`

Parse `--inherit` flag:

```bash
# In flag parsing section (around line 634)
INHERIT_FROM=""
INHERIT_SELECT="all"
for arg in "$@"; do
  case "$arg" in
    --inherit=*) INHERIT_FROM="${arg#*=}" ;;
    --inherit) INHERIT_NEXT=true ;;
    *)
      if [ "$INHERIT_NEXT" = true ]; then
        INHERIT_FROM="$arg"
        INHERIT_NEXT=false
      else
        ARGS+=("$arg")
      fi
      ;;
  esac
done

export INHERIT_FROM
export INHERIT_SELECT
```

#### Changes to `scripts/run.sh`

Pass `--inherit` flag through to engine:

```bash
# In loop) and pipeline) cases, pass INHERIT flags
```

### Multi-Stage Pipeline Interaction

When a multi-stage pipeline uses `--inherit`:

1. **External inheritance applies to all stages** - The inherited context is available to every stage in the pipeline
2. **Internal stage outputs are separate** - Stage 2 gets stage 1's outputs via `inputs.from`, NOT via inheritance
3. **Inherited context is static** - Set once at pipeline start, doesn't change as stages complete
4. **Cumulative learnings** - When the pipeline completes, its final state.json contains:
   - All learnings from all stages in the pipeline
   - The inherited context lineage is preserved in metadata

Example: Pipeline `refine.yaml` with `--inherit previous-auth`
```
Stage 1 (improve-plan): Has access to previous-auth's learnings
Stage 2 (refine-tasks): Has access to previous-auth's learnings + Stage 1 outputs
```

**Note**: Stages within a pipeline don't inherit from each other - they use `inputs.from`. Inheritance is for cross-session context.

### Prompt Template Updates

Add to standard stage prompt template:

```markdown
## Inherited Context (if applicable)

Check for inherited context:
```bash
inherited=$(jq '.inherited // empty' ${CTX})
if [ -n "$inherited" ] && [ "$inherited" != "{}" ]; then
  echo "=== Inherited from: $(echo $inherited | jq -r '.from_session') ==="
  echo "Learnings:"
  echo $inherited | jq -r '.learnings[]'
  echo ""
  echo "Summary:"
  echo $inherited | jq -r '.progress_summary'
fi
```

If inherited context exists, acknowledge it before starting:
1. What was accomplished in the previous session?
2. What learnings apply to this iteration?
3. What will you do differently based on this knowledge?
```

## Implementation Phases

**Note**: Phase order changed from original - learnings schema is a prerequisite for useful inheritance.

### Phase 1: Status.json Schema Extension (Prerequisite)
1. Expand status.json schema with `learnings` and `patterns` arrays
2. Update existing stage prompts to write learnings
3. Document learnings format in CLAUDE.md
4. Add backward compatibility: sessions without learnings still work

**Why first**: Without learnings in status.json, inheritance has nothing to inherit except raw progress text.

### Phase 2: Core Inheritance
1. Create `scripts/lib/inherit.sh` with `load_inherited_context()` and `filter_secrets()`
2. Modify `scripts/lib/context.sh` to include inherited block
3. Add `--inherit` flag parsing to engine.sh and run.sh
4. Add `inherit:` config support in stage/pipeline YAML
5. Add `./scripts/run.sh sessions list --completed` for discovery

### Phase 3: Comprehension Checkpoint
1. Update stage prompt template with inheritance acknowledgment
2. Add optional `comprehension: required` config
3. Engine validates comprehension in status.json if required
4. **Enforcement behavior**:
   - If `comprehension: required` and agent writes comprehension block → proceed normally
   - If `comprehension: required` and comprehension missing → log to iteration's `validation.json`, emit desktop notification, continue
   - If `comprehension: optional` or unset → no validation
   - Warnings surfaced in `./scripts/run.sh status <session>` output

**Validation output format** (iterations/NNN/validation.json):
```json
{
  "comprehension_check": {
    "required": true,
    "present": false,
    "warning": "Agent did not acknowledge inherited context"
  },
  "timestamp": "2026-01-13T10:00:00Z"
}
```

### Phase 4: Lineage Tracking
1. Add `parent_session` field to state.json
2. Track inheritance chain for debugging
3. Add `./scripts/run.sh lineage <session>` command
4. **Recursive inheritance**: Follow lineage chain up to 3 levels deep

### Phase 5: Version Migration (Future)
1. Inherited context includes `version` field (starting at "1")
2. When loading inherited context, check version compatibility
3. **Version upgrade strategy**:
   - v1→v2: Automatic migration handled in `load_inherited_context`
   - Unknown versions: Warn and extract what we can, don't fail
   - No downgrades needed (newer code can always read older formats)
4. Breaking changes require incrementing version and adding migration logic

## Success Criteria

1. Can start new session with `--inherit previous-session`
2. Agent receives inherited learnings in context.json
3. Agent acknowledges inherited context before starting work
4. Graceful degradation if source session missing/incomplete
5. No performance impact on sessions without inheritance

## Open Questions (with Proposed Answers)

1. **Should inheritance be recursive?** (inherit from a session that inherited?)
   - **Proposed**: Yes, up to 3 levels deep. Prevents runaway chains while enabling useful lineage.
   - **Implementation**: `load_inherited_context` follows `parent_session` recursively, merging learnings.

2. **How to handle conflicting learnings from multiple inherited sessions?**
   - **Proposed**: Not supported in v1. Single-session inheritance only.
   - **Future**: If needed, tag learnings with source session and let agent resolve conflicts.

3. **Should we support inheriting from multiple sessions?**
   - **Proposed**: Not in v1. Adds complexity without clear use case.
   - **Alternative**: Use lineage - if A→B→C, C gets learnings from both A and B through recursion.

4. **What's the maximum age for inherited sessions before they're stale?**
   - **Proposed**: No automatic staleness. User decides relevance.
   - **Alternative**: Add `--inherit-max-age 7d` flag if needed later.

5. **How to accurately count tokens for the 8000 token limit?**
   - **Proposed**: Use character approximation (4 chars ≈ 1 token). Simple, no dependencies.
   - **Alternative**: Shell out to `tiktoken` if installed, fall back to char approximation.
   - **Decision**: Character approximation is sufficient for v1. Token counting is model-specific anyway.

## Testing Strategy

### Unit Tests (scripts/tests/test_inherit.sh)

**Setup**: Create mock session directories in temp location before each test.

```bash
# Test fixture helper
setup_mock_session() {
  local name=$1 status=$2
  local dir="$TEST_RUNS_DIR/$name"
  mkdir -p "$dir/stage-00-test/iterations/001"
  echo '{"status": "'$status'", "started_at": "2026-01-01T00:00:00Z"}' > "$dir/state.json"
  echo '{"decision": "stop", "learnings": ["test learning 1"]}' > "$dir/stage-00-test/iterations/001/status.json"
  echo "# Progress" > "$dir/progress-$name.md"
}
```

1. `test_inherit_from_complete_session` - Happy path with mock session
2. `test_inherit_from_missing_session` - Should return exit code 1
3. `test_inherit_from_running_session` - Should warn to stderr, return valid JSON
4. `test_inherit_secret_filtering` - Verify `API_KEY=sk-123...` stripped, normal text preserved
5. `test_inherit_empty_learnings` - Mock session with no learnings[] array
6. `test_inherit_large_session` - Mock with >100 learnings, verify truncation
7. `test_inherit_circular_detection` - A→B→A should return empty, not infinite loop
8. `test_inherit_invalid_json` - Malformed status.json files should be skipped
9. `test_inherit_depth_limit` - A→B→C→D should stop at depth 3, not follow D
10. `test_inherit_deduplication` - Same learning in A and B should appear once in C
11. `test_inherit_lineage_tracking` - Verify lineage array contains all ancestors
12. `test_filter_secrets_preserves_normal` - Ensure non-secret text passes through unchanged
13. `test_filter_secrets_edge_cases` - Empty input, single line, unicode content
14. `test_session_name_validation` - Reject session names containing commas

### Integration Tests
1. Start session with `--inherit`, verify context.json contains inherited block
2. Run 2-iteration pipeline, verify learnings written to status.json
3. Chain: A→B inheritance, verify B has A's learnings
4. **NEW**: Chain A→B→C (3 levels), verify C has merged learnings from A and B
5. **NEW**: Comprehension validation - verify validation.json created when comprehension missing
6. **NEW**: Discovery command - verify `sessions list --completed` shows sessions with learnings count
7. **NEW**: Concurrent access - verify two sessions can inherit from same source safely (read-only)

### Manual Verification
1. Run ralph session, capture learnings
2. Start new session with `--inherit`, confirm agent acknowledges context

## References

- loop-agents-qba (this feature bead)
- loop-agents-xhs (Comprehension Checkpoints bead)
- docs/ideas-loom.md (Cold start problem analysis - see Iteration 3, Idea #3)
- CASS research (Dicklesworthstone's session search)
