# Plan: Review Loop Implementation

> "Find bugs before users do."

## Overview

The review loop runs multiple specialized code review agents in sequence, each looking for different categories of bugs. Unlike the refine loop (plateau detection) or work loop (beads empty), the review loop runs a fixed set of review perspectives and aggregates findings.

## The Three Loop Agents

| Loop | Purpose | Completion Signal |
|------|---------|-------------------|
| **Refine Loop** | Iterative planning refinement | Plateau detected |
| **Work Loop** | Implementation from beads | Beads empty |
| **Review Loop** | Multi-perspective bug finding | All reviewers complete |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      REVIEW LOOP                            │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Security   │  │ Performance │  │    Logic    │         │
│  │  Sentinel   │  │   Oracle    │  │  Analyzer   │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          ▼                                  │
│                   ┌─────────────┐                           │
│                   │  Findings   │                           │
│                   │ Aggregator  │                           │
│                   └──────┬──────┘                           │
│                          │                                  │
│                          ▼                                  │
│                   ┌─────────────┐                           │
│                   │   Triage    │                           │
│                   │  & Dedup    │                           │
│                   └─────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## Review Agents (Perspectives)

### 1. Security Sentinel

**Focus:** OWASP Top 10, injection, auth, secrets, data exposure

**Prompt:**
```
You are a security-focused code reviewer. Analyze the code for vulnerabilities:

SCOPE: {files_or_diff}

SECURITY CHECKLIST:
1. **Injection Flaws**
   - SQL injection (raw queries, string concatenation)
   - Command injection (shell execution, exec calls)
   - XSS (unescaped output, innerHTML, dangerouslySetInnerHTML)
   - Template injection

2. **Authentication & Authorization**
   - Missing auth checks on sensitive endpoints
   - Broken access control (IDOR, privilege escalation)
   - Insecure session management
   - Weak password handling

3. **Sensitive Data**
   - Hardcoded secrets, API keys, passwords
   - Secrets in logs or error messages
   - Unencrypted sensitive data
   - PII exposure

4. **Input Validation**
   - Missing validation on user input
   - Type coercion vulnerabilities
   - Path traversal

5. **Dependencies**
   - Known vulnerable packages
   - Outdated security-critical deps

OUTPUT FORMAT:
## Security Review: {scope}

### Critical (Immediate Action Required)
| File:Line | Vulnerability | Risk | Fix |
|-----------|---------------|------|-----|
| {location} | {type} | {impact} | {remediation} |

### High (Fix Before Deploy)
...

### Medium (Fix Soon)
...

### Low (Technical Debt)
...

### Clean Areas
{areas that passed security review}

FINDINGS_COUNT: {total_issues}
CRITICAL_COUNT: {critical_count}
```

### 2. Performance Oracle

**Focus:** Algorithmic complexity, N+1 queries, memory leaks, blocking operations

**Prompt:**
```
You are a performance-focused code reviewer. Analyze for performance issues:

SCOPE: {files_or_diff}

PERFORMANCE CHECKLIST:
1. **Algorithmic Complexity**
   - O(n²) or worse in loops
   - Unnecessary nested iterations
   - Missing early exits
   - Inefficient data structures

2. **Database & I/O**
   - N+1 query patterns
   - Missing indexes (from query patterns)
   - Large unbounded queries
   - Missing pagination
   - Synchronous I/O in hot paths

3. **Memory**
   - Unbounded caches/buffers
   - Memory leaks (unclosed resources)
   - Large object allocations in loops
   - Missing cleanup/disposal

4. **Concurrency**
   - Blocking operations on main thread
   - Missing async/await
   - Race conditions
   - Lock contention

5. **Caching**
   - Missing caching opportunities
   - Cache invalidation issues
   - Over-caching (stale data)

OUTPUT FORMAT:
## Performance Review: {scope}

### Critical (Will Cause Outages)
| File:Line | Issue | Impact | Fix |
|-----------|-------|--------|-----|
| {location} | {type} | {expected impact} | {optimization} |

### High (User-Visible Slowness)
...

### Medium (Inefficient but Acceptable)
...

### Optimization Opportunities
{optional improvements that aren't bugs}

FINDINGS_COUNT: {total_issues}
CRITICAL_COUNT: {critical_count}
```

### 3. Logic Analyzer

**Focus:** Business logic bugs, edge cases, error handling, state management

**Prompt:**
```
You are a logic-focused code reviewer. Analyze for correctness bugs:

SCOPE: {files_or_diff}

LOGIC CHECKLIST:
1. **Edge Cases**
   - Null/undefined handling
   - Empty collections
   - Boundary conditions (off-by-one)
   - Zero/negative values
   - Maximum values/overflow

2. **Error Handling**
   - Unhandled exceptions
   - Silent failures (catch and ignore)
   - Missing error propagation
   - Inconsistent error formats

3. **State Management**
   - Invalid state transitions
   - Stale state usage
   - Missing state cleanup
   - Race conditions in state updates

4. **Business Logic**
   - Incorrect calculations
   - Missing validation
   - Wrong operator (< vs <=, && vs ||)
   - Inverted conditions

5. **Data Integrity**
   - Missing transactions
   - Partial updates on failure
   - Inconsistent data states

OUTPUT FORMAT:
## Logic Review: {scope}

### Critical (Data Corruption/Loss)
| File:Line | Bug | Scenario | Fix |
|-----------|-----|----------|-----|
| {location} | {description} | {when it triggers} | {solution} |

### High (Incorrect Behavior)
...

### Medium (Edge Case Failures)
...

### Suspicious Patterns
{code that looks wrong but may be intentional}

FINDINGS_COUNT: {total_issues}
CRITICAL_COUNT: {critical_count}
```

### 4. Code Quality Reviewer

**Focus:** Maintainability, clarity, patterns, technical debt

**Prompt:**
```
You are a code quality reviewer. Analyze for maintainability issues:

SCOPE: {files_or_diff}

QUALITY CHECKLIST:
1. **Clarity**
   - Unclear naming
   - Missing/misleading comments
   - Complex conditionals
   - Magic numbers/strings

2. **Structure**
   - Functions too long (>50 lines)
   - Too many parameters (>4)
   - Deep nesting (>3 levels)
   - Mixed responsibilities

3. **Patterns**
   - Inconsistent with codebase patterns
   - Anti-patterns (god objects, spaghetti)
   - Copy-paste duplication
   - Missing abstractions

4. **Testing**
   - Untestable code (hidden dependencies)
   - Missing test coverage for critical paths
   - Brittle tests (implementation-coupled)

5. **Documentation**
   - Missing API documentation
   - Outdated comments
   - Missing error documentation

OUTPUT FORMAT:
## Quality Review: {scope}

### High (Significant Maintainability Risk)
| File:Line | Issue | Impact | Suggestion |
|-----------|-------|--------|------------|

### Medium (Should Refactor)
...

### Low (Nice to Have)
...

### Positive Patterns
{good practices observed}

FINDINGS_COUNT: {total_issues}
```

### 5. Concurrency Auditor

**Focus:** Race conditions, deadlocks, thread safety, async correctness

**Prompt:**
```
You are a concurrency specialist. Analyze for threading and async issues:

SCOPE: {files_or_diff}

CONCURRENCY CHECKLIST:
1. **Race Conditions**
   - Shared mutable state without synchronization
   - Check-then-act patterns
   - Non-atomic compound operations
   - Unsafe lazy initialization

2. **Deadlocks**
   - Lock ordering violations
   - Nested locks
   - Async deadlocks (blocking on async)

3. **Async Correctness**
   - Missing await
   - Fire-and-forget without error handling
   - Async void (except event handlers)
   - Incorrect cancellation handling

4. **Thread Safety**
   - Non-thread-safe collections in concurrent context
   - Unsafe singleton patterns
   - Mutable statics

5. **Resource Management**
   - Connection pool exhaustion
   - Semaphore leaks
   - Timer leaks

OUTPUT FORMAT:
## Concurrency Review: {scope}

### Critical (Race Condition/Deadlock)
| File:Line | Issue | Trigger Scenario | Fix |
|-----------|-------|------------------|-----|

### High (Thread Safety Issue)
...

### Medium (Async Correctness)
...

FINDINGS_COUNT: {total_issues}
CRITICAL_COUNT: {critical_count}
```

### 6. API Contract Reviewer

**Focus:** API design, backwards compatibility, contract violations

**Prompt:**
```
You are an API contract reviewer. Analyze for API issues:

SCOPE: {files_or_diff}

API CHECKLIST:
1. **Breaking Changes**
   - Removed endpoints/methods
   - Changed signatures
   - Changed response formats
   - Changed error codes

2. **Contract Violations**
   - Missing required fields
   - Type mismatches
   - Inconsistent naming
   - Missing validation

3. **Design Issues**
   - Inconsistent with existing API patterns
   - Missing versioning
   - Poor error messages
   - Missing pagination

4. **Documentation**
   - Undocumented endpoints
   - Incorrect documentation
   - Missing examples

OUTPUT FORMAT:
## API Review: {scope}

### Breaking Changes (Critical)
| Endpoint/Method | Change | Impact | Migration Path |
|-----------------|--------|--------|----------------|

### Contract Issues
...

### Design Concerns
...

FINDINGS_COUNT: {total_issues}
BREAKING_COUNT: {breaking_count}
```

## Loop Execution Modes

### Mode 1: Full Review (All Perspectives)

Run all 6 reviewers sequentially:
```bash
./review-loop.sh full path/to/files
```

### Mode 2: Quick Review (Critical Only)

Run only Security + Logic + Performance:
```bash
./review-loop.sh quick path/to/files
```

### Mode 3: Single Perspective

Run one specific reviewer:
```bash
./review-loop.sh security path/to/files
./review-loop.sh performance path/to/files
```

### Mode 4: Diff Review

Review only changed files (git diff):
```bash
./review-loop.sh diff HEAD~1
./review-loop.sh diff main
```

## Script Design

### `scripts/review/review-loop.sh`

```bash
#!/bin/bash
set -e

MODE=${1:-"full"}
SCOPE=${2:-"."}
SESSION_NAME=${3:-"review-$(date +%Y%m%d-%H%M)"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINDINGS_DIR="$SCRIPT_DIR/findings/$SESSION_NAME"
mkdir -p "$FINDINGS_DIR"

# Select reviewers based on mode
case $MODE in
  "full")
    REVIEWERS="security performance logic quality concurrency api"
    ;;
  "quick")
    REVIEWERS="security logic performance"
    ;;
  "security"|"performance"|"logic"|"quality"|"concurrency"|"api")
    REVIEWERS="$MODE"
    ;;
  "diff")
    # Get changed files from git diff
    SCOPE=$(git diff --name-only $SCOPE | tr '\n' ' ')
    REVIEWERS="security logic performance"
    ;;
  *)
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac

echo "🔍 Starting Review Loop"
echo "📋 Mode: $MODE"
echo "📁 Scope: $SCOPE"
echo "👥 Reviewers: $REVIEWERS"
echo ""

TOTAL_FINDINGS=0
CRITICAL_FINDINGS=0

for reviewer in $REVIEWERS; do
  echo "═══════════════════════════════════════"
  echo "    Running: $reviewer"
  echo "═══════════════════════════════════════"

  # Run reviewer
  OUTPUT=$(cat "$SCRIPT_DIR/prompts/$reviewer.md" \
    | sed "s|\${SCOPE}|$SCOPE|g" \
    | claude --model opus --dangerously-skip-permissions 2>&1 \
    | tee "$FINDINGS_DIR/$reviewer.md")

  # Parse findings count
  FINDINGS=$(echo "$OUTPUT" | grep "^FINDINGS_COUNT:" | cut -d: -f2 | tr -d ' ')
  CRITICAL=$(echo "$OUTPUT" | grep "^CRITICAL_COUNT:" | cut -d: -f2 | tr -d ' ' || echo "0")

  TOTAL_FINDINGS=$((TOTAL_FINDINGS + FINDINGS))
  CRITICAL_FINDINGS=$((CRITICAL_FINDINGS + CRITICAL))

  echo "  📊 Findings: $FINDINGS (Critical: $CRITICAL)"
  echo ""
done

# Aggregate findings
echo "═══════════════════════════════════════"
echo "    Aggregating Findings"
echo "═══════════════════════════════════════"

./aggregate-findings.sh "$FINDINGS_DIR"

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  REVIEW LOOP COMPLETE                     ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Total Findings: $TOTAL_FINDINGS"
echo "║  Critical:       $CRITICAL_FINDINGS"
echo "║                                                          ║"
echo "║  Detailed reports: $FINDINGS_DIR/                         ║"
echo "║  Summary:         $FINDINGS_DIR/summary.md                ║"
echo "╚══════════════════════════════════════════════════════════╝"
```

### `scripts/review/aggregate-findings.sh`

Deduplicates and prioritizes findings from all reviewers:

```bash
#!/bin/bash
FINDINGS_DIR=$1

# Concatenate all findings
cat "$FINDINGS_DIR"/*.md > "$FINDINGS_DIR/all-findings.md"

# Run aggregation agent
cat prompts/aggregator.md \
  | sed "s|\${FINDINGS_DIR}|$FINDINGS_DIR|g" \
  | claude --model opus --dangerously-skip-permissions \
  > "$FINDINGS_DIR/summary.md"
```

### Aggregator Prompt

```markdown
# Findings Aggregator

You have the output from multiple code reviewers in ${FINDINGS_DIR}/.

YOUR TASK:
1. Read all findings files
2. Deduplicate (same issue reported by multiple reviewers)
3. Prioritize by severity (Critical > High > Medium > Low)
4. Group by file/component
5. Create actionable summary

OUTPUT FORMAT:
## Code Review Summary

### Critical Issues (Fix Immediately)
| # | File:Line | Issue | Found By | Action |
|---|-----------|-------|----------|--------|
| 1 | {loc} | {issue} | {reviewers} | {fix} |

### High Priority
...

### Medium Priority
...

### By Component
#### {component_name}
- {issue 1}
- {issue 2}

### Statistics
- Total unique issues: {count}
- Critical: {count}
- High: {count}
- Files affected: {count}

### Recommended Fix Order
1. {critical issue 1} - {why first}
2. {critical issue 2}
...
```

## Directory Structure

```
scripts/review/
├── review-loop.sh           # Main loop runner
├── review-once.sh           # Single reviewer (test mode)
├── aggregate-findings.sh    # Dedup and prioritize
├── prompts/
│   ├── security.md          # Security Sentinel prompt
│   ├── performance.md       # Performance Oracle prompt
│   ├── logic.md             # Logic Analyzer prompt
│   ├── quality.md           # Code Quality prompt
│   ├── concurrency.md       # Concurrency Auditor prompt
│   ├── api.md               # API Contract prompt
│   └── aggregator.md        # Findings aggregation prompt
├── findings/                # Output directory
│   └── {session}/
│       ├── security.md
│       ├── performance.md
│       ├── logic.md
│       ├── quality.md
│       ├── concurrency.md
│       ├── api.md
│       └── summary.md
└── README.md
```

## Commands Integration

### `/review` command

```
/review              # Full review of changed files (git diff)
/review full         # All 6 reviewers on entire codebase
/review quick        # Security + Logic + Performance only
/review security     # Single perspective
/review path/to/file # Review specific file
```

### Integration with Work Loop

After work loop completes, automatically trigger review:

```bash
# In loop.sh, after "All tasks complete!"
if [ "$AUTO_REVIEW" = "1" ]; then
  echo "🔍 Starting automatic code review..."
  ../review/review-loop.sh quick
fi
```

## Implementation Phases

### Phase 1: Core Infrastructure
1. Create `scripts/review/` directory
2. Implement `review-once.sh` single reviewer runner
3. Create security.md prompt (highest value)
4. Create logic.md prompt
5. Test single reviewer

### Phase 2: Full Loop
1. Implement `review-loop.sh` multi-reviewer loop
2. Create performance.md prompt
3. Create remaining prompts (quality, concurrency, api)
4. Implement `aggregate-findings.sh`
5. Create aggregator.md prompt

### Phase 3: Integration
1. Create `/review` command
2. Add diff mode for reviewing changes
3. Integration with work loop (auto-review)
4. tmux background mode

### Phase 4: Polish
1. HTML report generation
2. Integration with GitHub PR comments
3. Baseline management (ignore known issues)
4. Custom rule configuration

## The Three Loops Together

```
┌─────────────────────────────────────────────────────────────┐
│                    DEVELOPMENT CYCLE                        │
│                                                             │
│  ┌──────────────┐                                           │
│  │   /ideate    │  Generate improvement ideas               │
│  └──────┬───────┘                                           │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │   /refine    │  Iterative planning until plateau         │
│  │  (5-10x)     │  "Check your beads N times"               │
│  └──────┬───────┘                                           │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │    /loop     │  Implementation until beads empty         │
│  │  (N tasks)   │  "Work through the plan"                  │
│  └──────┬───────┘                                           │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │   /review    │  Multi-perspective bug finding            │
│  │  (6 agents)  │  "Find bugs before users do"              │
│  └──────┬───────┘                                           │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │    Done!     │  Ship with confidence                     │
│  └──────────────┘                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Success Criteria

- [ ] `review-once.sh` runs single reviewer successfully
- [ ] `review-loop.sh` runs all reviewers in sequence
- [ ] Output parsing extracts FINDINGS_COUNT correctly
- [ ] Aggregator deduplicates findings
- [ ] Summary is actionable and prioritized
- [ ] `/review` command works for diff mode
- [ ] Full review completes in reasonable time (<10 min)
- [ ] Integration with work loop auto-review

## Open Questions

1. **Parallel vs Sequential?**
   - Could run reviewers in parallel (faster)
   - Sequential gives each reviewer full context
   - Decision: Start sequential, add parallel option later

2. **Scope granularity?**
   - Full codebase vs changed files vs single file
   - Decision: Default to changed files (git diff)

3. **Findings persistence?**
   - How long to keep findings?
   - Baseline for ignoring known issues?
   - Decision: Keep per-session, add baseline feature later

4. **GitHub Integration?**
   - Post findings as PR comments?
   - Decision: Future enhancement
