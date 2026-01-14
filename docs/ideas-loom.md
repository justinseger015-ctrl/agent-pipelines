# Loom Ideas - Iteration 1

*Session: loom | Generated: 2026-01-13*

## Gap Analysis

After reading the codebase and existing ideas (docs/ideas-loom-loom-ideas.md which has 15 ideas from 3 iterations), I'm focusing on underexplored areas:

1. **Prompt Engineering Drift**: The same prompts get used across iterations, but their effectiveness may degrade as context grows. No adaptation.

2. **Semantic State Tracking**: We track iterations and decisions, but not what the agent *understood* vs what we *intended*. No comprehension validation.

3. **Inter-Stage Data Contracts Are Weak**: `inputs.from` passes file paths, but there's no schema for what those files contain. Downstream stages parse blindly.

4. **No Learning From Output Quality**: Agents produce outputs, but we never score them. Good iterations look the same as mediocre ones in state.json.

5. **Missing "Ground Truth" Anchors**: Unlike Loom's emphasis on specs that serve as lookup tables, our progress files are append-only journals with no queryable structure.

6. **Cold Start Problem**: Every stage starts with zero momentum. No way to pre-warm context with relevant patterns from similar past work.

---

## Brainstorm (24 Ideas)

### Prompt Adaptation

1. **Prompt Compression Per Iteration** - As context grows, automatically summarize static prompt sections. Keep dynamic parts full.

2. **Prompt Effectiveness Scoring** - Rate how well the agent followed prompt instructions. Use this to evolve prompts over sessions.

3. **Dynamic Prompt Injection** - Based on iteration history, inject relevant tips into prompts. "Last iteration struggled with X, focus on..."

4. **Prompt Templates Per Complexity** - Simple iterations get minimal prompts. Complex ones get detailed guidance. Auto-select based on signals.

5. **Anti-Prompt**: Instructions of what NOT to do, extracted from failure patterns. "Don't re-implement authentication, use existing AuthService".

### Semantic Understanding

6. **Comprehension Checkpoints** - At key points, agent summarizes understanding. Engine validates against ground truth. Catch misunderstandings early.

7. **Intent vs Outcome Tracking** - Record what we asked, what agent understood, what it did. Surface gaps.

8. **Semantic Anchors in Progress** - Instead of prose, key facts stored as structured assertions. `{"fact": "auth uses sessions", "confidence": 0.9, "source": "iteration-3"}`.

9. **Progressive Disambiguation** - Early iterations surface ambiguities. Engine or human resolves. Later iterations work with clearer specs.

10. **Understanding Decay Detection** - Track if agent's understanding of core concepts drifts over iterations. Alert on divergence.

### Contract-Based Stages

11. **Typed Stage Outputs** - Each stage declares output schema (JSON Schema). Engine validates before passing to next stage.

12. **Stage Interface Definitions** - `expects:` and `produces:` blocks in stage.yaml. Validate at pipeline assembly time.

13. **Contract-First Pipeline Design** - Design pipelines by defining contracts between stages first, then implement stages.

14. **Graceful Degradation Contracts** - Define minimum viable output if full contract can't be met. Partial progress better than failure.

15. **Contract Version Evolution** - As stages evolve, version contracts. Pipelines specify which contract version they expect.

### Output Quality Learning

16. **Iteration Quality Scores** - Post-iteration, score output quality (0-5). Feed scores back into completion decisions.

17. **Comparative Iteration Ranking** - Rank iterations within a stage by quality. Use best ones as examples for future sessions.

18. **Quality-Based Pruning** - If iteration quality drops below threshold, discard output instead of accumulating noise.

19. **Golden Output Library** - Curate high-quality outputs as examples. New sessions get relevant golden examples in context.

20. **Regression Detection on Quality** - If quality score drops significantly from previous iteration, flag potential issue.

### Ground Truth & Queryable State

21. **Facts Database Per Session** - Structured store of discovered facts. Agents query before asserting. Prevents contradiction.

22. **Decision Tree Tracking** - Track which options were considered and why rejected. Queryable log of decision reasoning.

23. **Assertion Testing** - Agents can assert facts. Engine tests assertions against codebase. Catches hallucinations.

24. **Progressive Specification Building** - Each iteration adds to structured spec. By end, have complete machine-readable spec.

---

## Top 5 Ideas

### 1. Comprehension Checkpoints with Validation

**Loom Principle:** Specs as anchors / Prevent hallucination and drift
**Problem:** Agents receive prompts and context, but we never verify they understood correctly. Misunderstandings compound across iterations. An agent might misinterpret the goal and work productively toward the wrong thing.

**Solution:** Add comprehension checkpoints to stage prompts:

```markdown
## Step 0: Verify Understanding

Before starting work, write your understanding of:
1. The goal: [one sentence]
2. Key constraints: [bullet list]
3. Files you expect to modify: [list]

Write this to ${STATUS} under `comprehension:` field.
```

Engine validation (scripts/lib/comprehension.sh):
- Compare agent's stated goal to original goal (semantic similarity)
- Check constraints against stage config
- Flag if comprehension diverges significantly from intent

```json
// status.json (extended)
{
  "decision": "continue",
  "comprehension": {
    "goal": "Implement user authentication using sessions",
    "constraints": ["No new dependencies", "Must pass existing tests"],
    "target_files": ["src/auth/session.ts", "src/middleware/auth.ts"]
  },
  ...
}
```

**Composability:**
- Foundation for automatic prompt improvement (if agents misunderstand, fix prompts)
- Enables early-exit on fundamental misunderstanding
- Creates audit trail of what agent thought vs what was intended

**Files:**
- `scripts/lib/comprehension.sh` (new - validation logic)
- `scripts/lib/status.sh` (extend schema for comprehension block)
- Stage prompts (add comprehension step)
- Engine (call comprehension validation after status read)

---

### 2. Typed Stage Outputs with JSON Schema Validation

**Loom Principle:** Phase separation / Structured handoffs
**Problem:** Stages pass file paths with unstructured content. Downstream stages must parse and hope for the best. No validation that outputs match expectations. Silent failures when formats drift.

**Solution:** Add output schemas to stage definitions:

```yaml
# scripts/stages/improve-plan/stage.yaml
name: improve-plan
output_schema:
  type: object
  required: [plan_summary, sections, open_questions]
  properties:
    plan_summary:
      type: string
      description: One-paragraph summary of the plan
    sections:
      type: array
      items:
        type: object
        required: [title, content]
    open_questions:
      type: array
      items:
        type: string
```

Stage prompts updated to write structured output to output.md as fenced JSON block:
```markdown
```json
{
  "plan_summary": "...",
  "sections": [...],
  "open_questions": [...]
}
```
```

Engine validation flow:
1. After iteration completes, find JSON block in output.md
2. Validate against stage's output_schema
3. If invalid, mark iteration as partial_success or error
4. Store validated JSON in iterations/NNN/output.json for easy downstream consumption

**Composability:**
- Enables contract-first pipeline design
- Downstream stages get typed inputs, not raw text
- Foundation for automatic output transformation between stages
- Enables output quality scoring on structural completeness

**Files:**
- `scripts/lib/schema.sh` (new - JSON schema validation)
- Stage YAML schema (add output_schema field)
- `scripts/engine.sh` (validate output after iteration)
- Stage prompts (add structured output instructions)
- `scripts/lib/context.sh` (include parsed outputs in context.json)

---

### 3. Facts Database with Query Interface

**Loom Principle:** Discovery over reinvention / Specs as lookup tables
**Problem:** Each iteration rediscovers facts about the codebase. Progress files accumulate prose but aren't queryable. Agent in iteration 10 can't efficiently ask "what authentication method did we decide on in iteration 3?"

**Solution:** Per-session facts database with typed entries:

```yaml
# .claude/pipeline-runs/{session}/facts.yaml
facts:
  - id: auth-method
    category: decision
    value: session-based
    rationale: "JWT adds complexity, sessions sufficient for MVP"
    source: iteration-3
    confidence: 0.95

  - id: user-model-location
    category: codebase
    value: src/models/user.ts
    source: iteration-1
    confidence: 1.0

  - id: no-new-deps
    category: constraint
    value: true
    source: initial
```

Agent can query facts in prompt:
```markdown
## Available Facts
Query the facts database for decisions already made:
```bash
./scripts/run.sh facts query ${SESSION} --category=decision
```

Use this BEFORE making decisions to avoid re-litigating settled questions.
```

Scripts:
- `./scripts/run.sh facts add <session> <category> <id> <value>`
- `./scripts/run.sh facts query <session> [--category=X]`
- `./scripts/run.sh facts check <session> <assertion>` - validates assertion against known facts

**Composability:**
- Foundation for cross-session fact inheritance
- Enables contradiction detection (new fact conflicts with existing)
- Facts can be promoted to global patterns
- Quality scoring can factor in fact utilization

**Files:**
- `scripts/lib/facts.sh` (new - CRUD operations on facts.yaml)
- `scripts/run.sh` (add facts subcommand)
- Stage prompts (add facts query instructions)
- `scripts/lib/context.sh` (include relevant facts in context.json)

---

### 4. Dynamic Prompt Injection Based on Iteration History

**Loom Principle:** Context window efficiency / Minimize sliding with targeted content
**Problem:** Every iteration gets the same static prompt. But iteration 10 has very different needs than iteration 1. Agent might be struggling with something—we see this in status.json—but the next agent gets no guidance about it.

**Solution:** Engine injects dynamic tips into prompts based on iteration history:

```yaml
# stage.yaml (new field)
dynamic_prompts:
  triggers:
    - condition: last_iteration.errors.length > 0
      inject: |
        ## Previous Iteration Errors
        The previous iteration encountered errors: ${LAST_ERRORS}
        Pay special attention to avoiding these issues.

    - condition: iterations_without_progress >= 2
      inject: |
        ## Progress Warning
        The last ${STALLED_COUNT} iterations made limited progress.
        Consider a different approach or ask for help.

    - condition: productivity.similarity_to_last > 0.9
      inject: |
        ## Repetition Detected
        Output is very similar to previous iteration.
        Try a substantially different approach.
```

Engine flow:
1. Before iteration, analyze history from state.json
2. Evaluate dynamic_prompts triggers
3. Inject matching content into prompt before resolution
4. Agent receives context-aware guidance

**Composability:**
- Works with productivity scoring (use scores as trigger conditions)
- Can inject relevant facts from facts database
- Can inject learnings from similar past sessions
- Foundation for self-improving prompts

**Files:**
- `scripts/lib/dynamic.sh` (new - trigger evaluation, injection)
- Stage YAML schema (add dynamic_prompts block)
- `scripts/lib/resolve.sh` (integrate dynamic injection before resolution)
- `scripts/engine.sh` (call dynamic injection in run_stage)

---

### 5. Quality-Based Output Pruning

**Loom Principle:** Context window efficiency / Prevent compaction drift from accumulated noise
**Problem:** Every iteration's output gets saved and potentially fed to future iterations. But some iterations produce low-quality output—maybe the agent went down a wrong path, produced boilerplate, or just spun. This noise accumulates in context.

**Solution:** Score iteration outputs and prune low-quality ones from future context:

Post-iteration scoring (can be heuristic or LLM-based):
```json
// iterations/005/quality.json
{
  "score": 2.5,  // 0-5 scale
  "factors": {
    "novelty": 1.5,      // How different from previous iterations
    "actionability": 4.0, // Did it make concrete changes?
    "coherence": 3.0,     // Was output well-structured?
    "goal_alignment": 2.0 // Did it advance the goal?
  },
  "include_in_context": false  // Low score = excluded
}
```

Engine behavior:
- Score each iteration output after completion
- Iterations below threshold (e.g., 2.5) get flagged `include_in_context: false`
- Context generation (context.sh) respects this flag
- Full outputs still saved for forensics, just not passed to future agents

Quality scoring options:
- Heuristic: word count, diff size, unique content ratio
- LLM-based: quick Haiku pass to evaluate against criteria
- Hybrid: heuristic screening, LLM for borderline cases

**Composability:**
- Works with progressive summarization (prune before summarize)
- Enables quality trend tracking per session
- Foundation for model escalation (low quality triggers Opus)
- Can feed into productivity scoring for termination decisions

**Files:**
- `scripts/lib/quality.sh` (new - scoring logic)
- `scripts/lib/context.sh` (filter by quality flag)
- `scripts/engine.sh` (call quality scoring after iteration)
- Stage YAML (optional quality_threshold setting)

---

## Themes for Future Iterations

- **Prompt Evolution**: Using comprehension and quality data to automatically improve prompts
- **Cross-Pipeline Learning**: Facts and patterns shared across different pipelines
- **Adaptive Stage Routing**: Skip stages or add extra iterations based on quality/comprehension
- **Agent Self-Assessment**: Agents score their own confidence, engine validates
- **Failure Pattern Library**: Common failure modes with mitigation strategies

---

# Loom Ideas - Iteration 2

*Session: loom | Generated: 2026-01-13*

## Focus: Observability, Attended-First, and Scaling Patterns

Iteration 1 focused on pins/specs, contracts, and quality scoring. This iteration explores:
- **Observability** - Real-time visibility into loop health
- **Attended-First** - Patterns for observation before scaling
- **Scaling Levels** - Moving between manual, unattended, and orchestrated

## Gap Analysis (Iteration 2)

1. **No Real-Time Visibility**: You can `tmux attach` but there's no dashboard. No metrics on iteration velocity, error rates, or output patterns.

2. **Attended→Unattended Transition Is Manual**: Loom emphasizes observing before scaling. We jump straight to unattended with `--dangerously-skip-permissions`.

3. **No Learning From Failure Patterns**: When loops fail, we lose the lesson. No systematic capture of "what went wrong" for future sessions.

4. **Weak Phase Separation Enforcement**: Planning and implementation stages exist but there's no hard boundary. An "improve-plan" iteration could accidentally implement.

5. **No Escalation Path**: When a loop struggles (multiple errors, low quality), there's no automatic escalation—either to human, to Opus, or to a different strategy.

6. **Missing Linkage Enforcement**: Loom emphasizes file:line references over abstract descriptions. Our prompts don't enforce this.

---

## Brainstorm (22 Ideas)

### Observability

1. **Live Dashboard** - Web UI showing all active pipelines, current iteration, recent status decisions, error rates.

2. **Metrics Emission** - Each iteration emits structured metrics (duration, decision, files_touched count, errors). Store in metrics.jsonl.

3. **Velocity Tracking** - Track iterations per hour, items completed per iteration. Detect slowdowns automatically.

4. **Health Scoring** - Composite score of loop health: error rate, decision consistency, output diversity.

5. **Alert System** - Notify when loop stalls, error rate spikes, or consensus can't be reached.

6. **Iteration Replay** - View exactly what context each iteration received and what it produced. Debug time-travel.

### Attended-First Patterns

7. **Observation Mode** - `--observe` flag runs first N iterations interactively, requiring human approval of each decision.

8. **Dry-Run Iteration** - Run a mock iteration showing what context would be generated without actually invoking Claude.

9. **Staged Permission Escalation** - Start with minimal permissions, engine requests escalation as patterns prove safe.

10. **Confidence-Gated Autonomy** - Agent reports confidence score. High confidence = autonomous. Low confidence = human review.

11. **Breakpoint Iterations** - Mark certain iterations as breakpoints. Pipeline pauses for human review before continuing.

12. **Session Recording** - Record full session for later playback. "Watch" mode that replays at 10x speed.

### Scaling Levels

13. **Automatic Model Escalation** - Start with Sonnet/Haiku. Escalate to Opus when iteration quality drops or errors spike.

14. **Pipeline Forking** - If unsure which approach to take, fork into parallel pipelines, merge best results.

15. **Hierarchical Orchestration** - Supervisor agent monitors multiple pipeline sessions, intervenes when needed.

16. **Cross-Session Work Stealing** - If one session finishes, steal work from another's queue.

17. **Resource-Aware Scheduling** - Track API costs per session. Throttle expensive sessions if budget exceeded.

### Phase Separation Enforcement

18. **Mode Guards** - Stages declare `mode: planning` or `mode: implementation`. Engine validates no code writes in planning mode.

19. **Tool Restrictions Per Stage** - Planning stages can only Read/Glob/Grep. Implementation stages get Write/Edit/Bash.

20. **Output Validation by Mode** - Planning outputs must be markdown. Implementation outputs must touch code files.

21. **Explicit Phase Transitions** - Pipeline must pass through explicit "plan approved" gate before implementation starts.

22. **Linkage Validator** - Scan outputs for file:line references. Flag outputs that are too abstract.

---

## Top 5 Ideas

### 1. Metrics Dashboard with Health Scoring

**Loom Principle:** Attended-first / Know when loops are working vs stuck
**Problem:** Running pipelines are black boxes. You can `tmux attach` to see raw output, but there's no way to quickly assess:
- Is this loop making progress?
- What's the error rate?
- Should I intervene?
- How does this session compare to similar ones?

**Solution:** Structured metrics collection with a health dashboard:

**Metrics Collection** (after each iteration):
```json
// .claude/pipeline-runs/{session}/metrics.jsonl
{"iteration": 1, "duration_sec": 45, "decision": "continue", "files_touched": 3, "items_completed": 1, "errors": 0, "timestamp": "..."}
{"iteration": 2, "duration_sec": 62, "decision": "continue", "files_touched": 1, "items_completed": 0, "errors": 1, "timestamp": "..."}
```

**Health Scoring Algorithm**:
```bash
health_score = (
  0.3 * (1 - error_rate) +           # Error rate factor
  0.3 * progress_rate +               # Items completed / iteration
  0.2 * decision_consistency +        # Not flip-flopping continue/stop
  0.2 * (1 - repetition_rate)        # Output diversity
)
```

**Dashboard Command**:
```bash
./scripts/run.sh dashboard         # Opens web UI at localhost:3456
./scripts/run.sh metrics auth      # CLI summary of session metrics
./scripts/run.sh health auth       # Single health score + breakdown
```

**Alert Integration**:
```yaml
# In pipeline.yaml or global config
alerts:
  health_threshold: 0.4           # Alert if health drops below
  error_rate_threshold: 0.3       # Alert if > 30% error rate
  notify: ["desktop", "slack"]    # Notification channels
```

**Composability:**
- Foundation for automatic escalation (low health → Opus or human)
- Enables session comparison across time
- Can trigger dynamic prompt injection based on metrics
- Feed into quality-based termination decisions

**Files:**
- `scripts/lib/metrics.sh` (new - metrics collection and aggregation)
- `scripts/engine.sh` (emit metrics after each iteration)
- `scripts/run.sh` (add dashboard, metrics, health subcommands)
- `scripts/dashboard/` (new directory - simple web server + HTML)

---

### 2. Observation Mode with Staged Permission Escalation

**Loom Principle:** Attended-first / Observe loops before scaling to unattended
**Problem:** We jump directly to `--dangerously-skip-permissions` for unattended operation. But Loom emphasizes observing first to:
- Verify the loop is working correctly
- Catch issues early before 25 iterations of mistakes
- Build confidence in the stage's behavior

**Solution:** Three-tier observation system:

**Tier 1: Interactive Mode** (`--observe N`):
```bash
./scripts/run.sh ralph auth 25 --observe 3
```
- First 3 iterations run with human approval required
- After each iteration: show status.json, ask "Continue? [y/n/edit]"
- After N observed iterations, prompt: "Grant autonomous permission? [y/n]"

**Tier 2: Breakpoint Mode** (`--breakpoints`):
```bash
./scripts/run.sh ralph auth 25 --breakpoints "5,10,15"
```
- Runs autonomously but pauses at specified iterations
- Human reviews progress, can adjust parameters or abort

**Tier 3: Autonomous with Guardrails**:
```yaml
# stage.yaml
guardrails:
  max_errors_before_pause: 3     # Pause after 3 consecutive errors
  min_health_score: 0.3          # Pause if health drops below
  max_runtime_seconds: 3600      # Hard stop after 1 hour
  require_human_for:             # Actions that need approval
    - delete_files
    - modify_config
```

Engine implements staged escalation:
1. New stages start in observation mode by default
2. After N successful iterations without intervention, suggest autonomous
3. Track "trust level" per stage based on historical behavior
4. Higher trust = more autonomy granted

**Composability:**
- Works with metrics dashboard (metrics inform when to grant autonomy)
- Integrates with quality scoring (low quality = reduce autonomy)
- Can be per-user or per-stage trust levels
- Foundation for multi-user collaborative pipelines

**Files:**
- `scripts/lib/observe.sh` (new - observation mode logic)
- `scripts/lib/guardrails.sh` (new - runtime guardrail checking)
- `scripts/engine.sh` (integrate observation and guardrail checks)
- Stage YAML schema (add guardrails block)
- `scripts/run.sh` (add --observe, --breakpoints flags)

---

### 3. Failure Pattern Library with Automatic Mitigation

**Loom Principle:** Discovery over reinvention / Learn from past failures
**Problem:** When a loop fails or struggles, we lose the lesson. The same failure mode might hit the next session. Examples:
- Agent keeps editing the same file repeatedly without making progress
- Stage can't find expected files due to path assumptions
- Consensus never reached because agents interpret "done" differently

**Solution:** Systematic capture and application of failure patterns:

**Failure Detection** (run after each iteration):
```python
patterns = [
    {"id": "edit_loop", "detect": "same file edited in 3+ consecutive iterations", "mitigation": "inject anti-repetition prompt"},
    {"id": "path_miss", "detect": "file not found errors in status.json", "mitigation": "inject path discovery step"},
    {"id": "scope_creep", "detect": "files_touched growing >20% per iteration", "mitigation": "inject focus reminder"},
    {"id": "stalled", "detect": "items_completed=0 for 3+ iterations", "mitigation": "escalate to human or Opus"},
]
```

**Failure Library** (shared across sessions):
```yaml
# .claude/failures/library.yaml
patterns:
  - id: edit_loop
    description: Agent edits same file repeatedly without progress
    symptoms:
      - Same file in files_touched for 3+ iterations
      - status.summary mentions same topic repeatedly
    mitigations:
      - type: prompt_injection
        content: "You've been editing ${FILE} for several iterations. Step back and reconsider the approach."
      - type: escalation
        to: human
        after: 5_occurrences
    occurrences: 12
    last_seen: 2026-01-12

  - id: hallucinated_file
    description: Agent references files that don't exist
    symptoms:
      - Files in target_files or files_touched that fail `test -f`
    mitigations:
      - type: prompt_injection
        content: "IMPORTANT: Verify files exist before referencing them. Use ls/find first."
    occurrences: 8
```

**Application Flow**:
1. After each iteration, run failure detection
2. If pattern detected, log occurrence and apply mitigation
3. Mitigations applied in order: prompt injection → parameter change → escalation
4. Track mitigation success rate (did it help?)

**Learning Loop**:
- New patterns can be added manually or detected automatically (clustering similar failures)
- Successful mitigations get higher priority
- Failed mitigations get flagged for human review

**Composability:**
- Works with dynamic prompt injection (mitigations inject prompts)
- Feeds into health scoring (failure rate impacts health)
- Cross-session learning (library is global)
- Foundation for self-healing pipelines

**Files:**
- `scripts/lib/failures.sh` (new - detection and mitigation logic)
- `.claude/failures/library.yaml` (global failure pattern library)
- `scripts/engine.sh` (call failure detection after each iteration)
- Stage prompts (may get automatic mitigation injections)

---

### 4. Mode Guards with Tool Restrictions

**Loom Principle:** Phase separation / Keep planning and implementation separate
**Problem:** We have planning stages (`improve-plan`) and implementation stages (`ralph`), but there's no enforcement. A "planning" iteration could accidentally:
- Write code when it should only be analyzing
- Create files when it should only be proposing
- Execute commands when it should only be reading

This violates Loom's principle of keeping planning and implementation in separate context windows.

**Solution:** Explicit mode declarations with tool restrictions:

**Mode Declaration in Stage Config**:
```yaml
# scripts/stages/improve-plan/stage.yaml
name: improve-plan
mode: planning

# Mode-specific restrictions
restrictions:
  planning:
    allowed_tools: [Read, Glob, Grep, WebFetch]
    forbidden_patterns:
      - Write to src/
      - Edit *.ts, *.js, *.py
      - Bash commands that modify files
    output_must_be: markdown

  implementation:
    allowed_tools: all
    forbidden_patterns: []
    output_may_include: code

  review:
    allowed_tools: [Read, Glob, Grep]
    forbidden_patterns:
      - Any file modification
    output_must_be: markdown
```

**Engine Enforcement**:
1. Before iteration, inject mode context into prompt
2. After iteration, validate output against mode rules
3. Detect tool usage from conversation (hooks can intercept)
4. Flag or fail iterations that violate mode restrictions

**Mode Guard Prompt Injection**:
```markdown
## Mode: Planning

This is a PLANNING stage. You must NOT:
- Write or edit code files
- Run commands that modify the filesystem
- Create new files

You MAY:
- Read and analyze files
- Search for patterns
- Document findings in markdown

Violations will cause the iteration to fail.
```

**Validation Output**:
```json
// iterations/003/mode_check.json
{
  "mode": "planning",
  "violations": [
    {"type": "forbidden_write", "path": "src/auth.ts", "severity": "error"}
  ],
  "passed": false
}
```

**Composability:**
- Enforces Loom's phase separation at runtime
- Can audit historical sessions for mode violations
- Foundation for trust scoring (clean mode record = higher trust)
- Works with observation mode (violations trigger human review)

**Files:**
- `scripts/lib/modes.sh` (new - mode validation logic)
- Stage YAML schema (add mode and restrictions fields)
- `scripts/engine.sh` (inject mode context, validate post-iteration)
- Stage prompts (auto-inject mode guard content)

---

### 5. Linkage Validator with Concrete Reference Scoring

**Loom Principle:** Linkage over format / Plans reference exact file:line locations
**Problem:** Loom emphasizes that good plans reference concrete code locations, not abstract descriptions. Our prompts don't enforce or measure this. Agents can produce vague outputs like:
- "Update the authentication system" (where?)
- "Fix the bug in the API" (which file? which line?)
- "The user model needs changes" (src/models/user.ts:45 would be better)

**Solution:** Score and enforce concrete references in outputs:

**Reference Extraction**:
```python
# Parse output for references
patterns = [
    r'`([^`]+\.(?:ts|js|py|rb|go|rs))(?::(\d+))?`',  # `file.ts:123`
    r'([^\s]+\.(?:ts|js|py|rb|go|rs)):(\d+)',          # file.ts:123
    r'in `([^`]+)`',                                    # in `file.ts`
]

# Validate references exist
for ref in extracted_refs:
    if not path.exists(ref.file):
        mark_invalid(ref)
    if ref.line and not line_exists(ref.file, ref.line):
        mark_stale(ref)
```

**Linkage Score** (0-100):
```json
// iterations/003/linkage.json
{
  "total_claims": 15,              // Statements about code
  "concrete_refs": 11,             // With file paths
  "with_line_numbers": 8,          // With file:line
  "verified_exist": 10,            // References that resolve
  "linkage_score": 73,             // (concrete_refs / total_claims) * bonus_for_lines
  "abstract_claims": [
    "The authentication system needs updating",
    "Error handling is insufficient"
  ]
}
```

**Enforcement Options**:
```yaml
# stage.yaml
linkage:
  min_score: 60                    # Fail iteration if below
  require_line_numbers: true       # Must include :line for code refs
  warn_abstract: true              # Log warnings for abstract claims
  auto_resolve: true               # Attempt to find file:line for abstract refs
```

**Auto-Resolution**:
When agent makes abstract claim, engine can attempt to resolve:
1. Search codebase for relevant files
2. Find likely line numbers based on content matching
3. Inject resolved references into next iteration's context

**Composability:**
- Feeds into quality scoring (linkage score as quality factor)
- Works with facts database (file:line refs become facts)
- Enables automated PR descriptions (concrete refs → good descriptions)
- Foundation for code impact analysis

**Files:**
- `scripts/lib/linkage.sh` (new - reference extraction and validation)
- Stage YAML schema (add linkage block)
- `scripts/engine.sh` (call linkage validation after iteration)
- `scripts/lib/quality.sh` (incorporate linkage score)

---

## Themes for Future Iterations

Explored in iteration 1: Specs as anchors, Context efficiency, Phase separation

Explored in iteration 2: Observability, Attended-first, Failure learning, Mode enforcement

**Remaining Loom areas to explore:**
- **Economic optimization**: Cost tracking per session, budget-aware scheduling
- **Team collaboration**: Multiple humans observing same pipeline, handoff protocols
- **Autonomous product decisions**: Feature flags, A/B testing from pipelines
- **Hierarchical orchestration**: Supervisor agents, cross-pipeline coordination
- **Long-horizon planning**: Sessions that span days with checkpoint/resume

---

# Loom Ideas - Iteration 3

*Session: loom | Generated: 2026-01-13*

## Focus: Economic Optimization, Hierarchical Orchestration, and Long-Horizon Patterns

Iterations 1-2 covered specs/contracts, observability, and attended-first patterns. This iteration explores:
- **Economic Model** - Loom's insight that ~$10/hour fundamentally changes how we think about iteration
- **Hierarchical Coordination** - Supervisor patterns for managing multiple pipelines
- **Long-Horizon Work** - Sessions spanning hours/days with proper checkpoint/resume
- **Composable Primitives** - Building blocks that enable more complex orchestration

## Gap Analysis (Iteration 3)

1. **No Cost Awareness**: We don't track API costs per iteration, session, or pipeline. Can't optimize for cost/value ratio. Loom emphasizes that $10/hour economics change the calculus.

2. **Single-Session Tunnel Vision**: Each pipeline runs in isolation. No way for a supervisor to coordinate multiple concurrent sessions, share discoveries, or allocate resources.

3. **No Work Decomposition Strategy**: When a task is too complex for a single session, we manually split it. No automated decomposition into parallel workstreams with coordination.

4. **Missing "Cheap Planning, Expensive Implementation" Pattern**: Loom emphasizes planning tokens are cheaper than implementation tokens. We don't enforce different token budgets or model tiers per phase.

5. **No Memory Across Sessions**: Each new session starts cold. Previous sessions' discoveries, patterns, and learnings aren't accessible. Loom's "discovery over reinvention" breaks down across sessions.

6. **Checkpoint Granularity Is Coarse**: We checkpoint at iteration boundaries only. Long iterations can't be resumed mid-work if they crash.

7. **No Resource Contention Management**: Multiple pipelines can spawn simultaneously, competing for API quota, hitting rate limits, or exhausting budget without coordination.

---

## Brainstorm (25 Ideas)

### Economic Optimization

1. **Token Metering Per Iteration** - Track input/output tokens per iteration. Calculate cost using model pricing.

2. **Budget Caps with Graceful Degradation** - Set max budget per session. When approaching limit, switch to cheaper models or stop gracefully.

3. **Cost-Per-Value Scoring** - Track what each dollar accomplished (items completed, files touched, quality score). Optimize for ROI not raw throughput.

4. **Model Tier Strategy** - Configure model selection per phase: Haiku for exploration, Sonnet for planning, Opus for implementation.

5. **Iteration Cost Prediction** - Based on history, predict cost of next iteration. Alert if prediction exceeds threshold.

6. **Token Budget Allocation** - Allocate token budget across stages. Planning gets 20%, implementation gets 80%.

7. **Batch vs Stream Trade-offs** - Some stages benefit from batching (cheaper per token). Others need streaming (lower latency). Configure per stage.

### Hierarchical Orchestration

8. **Supervisor Agent** - Meta-agent that monitors multiple pipelines, redistributes work, handles failures.

9. **Work Queue Federation** - Shared queue across pipelines. When one session finishes, it can pull from another's queue.

10. **Discovery Broadcasting** - When one session discovers something significant (a bug, a pattern), broadcast to sibling sessions.

11. **Resource Broker** - Centralized component that manages API quota across all active sessions. Prevents thundering herd.

12. **Pipeline Dependencies** - Declare that pipeline B depends on pipeline A's output. Supervisor enforces sequencing.

13. **Consensus Across Sessions** - For critical decisions, require multiple independent sessions to agree (not just multiple iterations within one session).

### Long-Horizon Patterns

14. **Checkpoint Serialization** - Serialize full session state to a resumable checkpoint. Not just iteration number, but full context.

15. **Progress Summarization at Checkpoints** - When checkpointing, generate a compressed summary of progress. Enables longer runs without context bloat.

16. **Day Boundaries** - Special handling for sessions that span days. Morning checkpoint, evening resume, with human review.

17. **Incremental Goal Decomposition** - Start with high-level goal. Each phase decomposes it further. Track goal tree, not just task list.

18. **Dependency-Aware Work Ordering** - Track dependencies between work items. Ensure blockers are resolved before dependents start.

19. **Session Inheritance** - New session can inherit context from completed session. "Continue where this left off."

### Cross-Session Memory

20. **Pattern Library** - Curate discovered patterns (not just failures) for reuse across sessions. "Last time we did X, we used approach Y."

21. **Entity Resolution** - Track entities (files, functions, concepts) across sessions. "This is the same AuthService we worked on in session-3."

22. **Decision Archive** - Record significant decisions with rationale. Queryable across sessions. "Why did we choose JWT over sessions?"

23. **Skill Extraction** - When a session solves a novel problem, extract the solution as a reusable skill/prompt.

### Composable Primitives

24. **Pipeline Combinators** - Combine pipelines: sequence(A, B), parallel(A, B), race(A, B, first_wins), retry(A, 3).

25. **Stage Adapters** - Transform outputs between stages. Adapter from improve-plan output to refine-tasks input.

---

## Top 5 Ideas

### 1. Cost-Aware Pipeline Execution with Token Metering

**Loom Principle:** Economic Model - ~$10/hour fundamentally changes iteration economics
**Problem:** We run pipelines blind to cost. A 25-iteration ralph session might cost $50 or $5—we don't know until the invoice arrives. Can't make informed decisions about:
- When to use expensive models (Opus) vs cheaper (Haiku)
- Whether more iterations are worth the cost
- How to optimize total value delivered per dollar
- Budget allocation across competing priorities

**Solution:** Per-iteration token metering with budget controls:

**Token Metering** (hooks into provider.sh):
```bash
# After each Claude invocation, capture token usage
capture_tokens() {
  local response_file=$1
  local tokens_in=$(jq -r '.usage.input_tokens // 0' "$response_file")
  local tokens_out=$(jq -r '.usage.output_tokens // 0' "$response_file")

  # Log to metrics
  echo "{\"tokens_in\": $tokens_in, \"tokens_out\": $tokens_out, \"model\": \"$MODEL\"}" >> "$METRICS_FILE"
}
```

**Cost Calculation** (scripts/lib/cost.sh):
```bash
# Model pricing (per 1M tokens)
declare -A PRICES=(
  ["opus:in"]=15.00 ["opus:out"]=75.00
  ["sonnet:in"]=3.00 ["sonnet:out"]=15.00
  ["haiku:in"]=0.25 ["haiku:out"]=1.25
)

calculate_cost() {
  local tokens_in=$1 tokens_out=$2 model=$3
  local cost_in=$(echo "scale=6; $tokens_in * ${PRICES[$model:in]} / 1000000" | bc)
  local cost_out=$(echo "scale=6; $tokens_out * ${PRICES[$model:out]} / 1000000" | bc)
  echo "$(echo "$cost_in + $cost_out" | bc)"
}
```

**Budget Configuration** (in stage.yaml or pipeline.yaml):
```yaml
budget:
  max_cost_usd: 25.00           # Hard cap for this pipeline
  warn_at_percent: 75           # Alert when 75% consumed
  degradation_strategy: "downgrade_model"  # or "reduce_iterations" or "stop"

  # Model tier strategy
  model_tiers:
    planning: haiku             # Cheap exploration
    refinement: sonnet          # Balanced
    implementation: opus        # Full power for actual work
```

**Cost-Per-Value Tracking** (extension to status.json):
```json
{
  "decision": "continue",
  "cost": {
    "tokens_in": 12500,
    "tokens_out": 3200,
    "cost_usd": 0.31,
    "cumulative_cost_usd": 4.72
  },
  "value": {
    "items_completed": 2,
    "quality_score": 4.2
  },
  "cost_per_value": 0.155  // $0.155 per item completed
}
```

**Composability:**
- Foundation for budget-aware scheduling (don't start expensive session if budget exhausted)
- Enables cost comparison across pipeline types
- Feeds into ROI dashboards
- Works with model tier strategy (auto-downgrade when budget tight)

**Files:**
- `scripts/lib/cost.sh` (new - token metering, cost calculation)
- `scripts/lib/provider.sh` (hook token capture after invocations)
- Stage/pipeline YAML schema (add budget block)
- `scripts/engine.sh` (check budget before each iteration)
- Status.json schema (add cost block)

---

### 2. Supervisor Agent for Multi-Pipeline Coordination

**Loom Principle:** Hierarchical orchestration / Scaling beyond single sessions
**Problem:** We can run multiple pipelines concurrently, but they're isolated islands:
- No shared awareness of discoveries
- No coordinated resource allocation
- No way to redistribute work when one finishes early
- No intelligent handling of cross-pipeline dependencies

This limits scaling. Running 5 isolated pipelines is just 5x cost, not 5x value.

**Solution:** Supervisor agent that orchestrates multiple child pipelines:

**Supervisor Architecture:**
```yaml
# .claude/supervisor/config.yaml
supervisor:
  check_interval: 60            # Seconds between health checks
  max_concurrent_pipelines: 3   # Resource constraint
  shared_discoveries: true      # Broadcast findings
  work_stealing: true           # Redistribute on completion

pipelines:
  - name: auth-feature
    priority: high
    budget: 15.00

  - name: refactor-payments
    priority: medium
    budget: 10.00
    depends_on: auth-feature    # Wait for auth to complete

  - name: bug-hunt
    priority: low
    budget: 5.00
    can_steal_from: [auth-feature, refactor-payments]
```

**Supervisor Commands:**
```bash
./scripts/run.sh supervisor start                   # Start supervisor
./scripts/run.sh supervisor status                  # Show all pipelines
./scripts/run.sh supervisor add <pipeline> <args>   # Add pipeline to supervisor
./scripts/run.sh supervisor stop                    # Gracefully stop all
```

**Discovery Broadcasting:**
```json
// When a pipeline discovers something significant
{
  "type": "discovery",
  "source": "auth-feature",
  "category": "bug",
  "message": "Found race condition in session validation",
  "file": "src/auth/session.ts:145",
  "broadcast_to": ["refactor-payments", "bug-hunt"]
}
```

Receiving pipelines get this injected into their next iteration's context.

**Work Stealing:**
```bash
# When auth-feature completes with unfinished beads
supervisor_redistribute() {
  local source=$1 target=$2

  # Find remaining beads from source
  bd list --label="pipeline/$source" --status=open | while read bead; do
    # Retag to target pipeline
    bd update "$bead" --label="pipeline/$target"
  done
}
```

**Health Aggregation:**
```json
// Supervisor state
{
  "status": "running",
  "pipelines": [
    {"name": "auth-feature", "status": "running", "iteration": 12, "health": 0.85},
    {"name": "bug-hunt", "status": "waiting", "waiting_on": "auth-feature"},
    {"name": "refactor-payments", "status": "paused", "paused_reason": "budget_exceeded"}
  ],
  "total_cost": 23.45,
  "discoveries_broadcast": 7
}
```

**Composability:**
- Enables "pipeline of pipelines" patterns
- Foundation for autonomous project management
- Works with cost metering (supervisor enforces global budget)
- Integrates with observation mode (human reviews supervisor decisions)

**Files:**
- `scripts/supervisor.sh` (new - supervisor logic)
- `scripts/lib/broadcast.sh` (new - discovery broadcasting)
- `.claude/supervisor/` (new directory - supervisor state)
- `scripts/run.sh` (add supervisor subcommand)
- Documentation for supervisor patterns

---

### 3. Session Inheritance with Context Compression

**Loom Principle:** Discovery over reinvention / Memory across sessions
**Problem:** Each session starts from zero. If session-1 discovered that "authentication uses JWT with refresh tokens" and session-2 needs to extend authentication, it rediscovers this from scratch. We lose:
- Decisions made and why
- Patterns discovered
- Code locations explored
- Lessons learned

This violates Loom's "discovery over reinvention" principle at the session boundary.

**Solution:** Session inheritance with automatic context compression:

**Inheritance Declaration:**
```yaml
# When starting a new session
session:
  name: auth-extend
  inherits_from:
    - session: auth-initial
      select: discoveries       # What to inherit
    - session: bug-hunt-auth
      select: [discoveries, patterns]
```

**Inheritance Types:**
```yaml
select:
  discoveries:    # Facts discovered about the codebase
    - "JWT tokens stored in httpOnly cookies"
    - "Refresh token rotation every 7 days"

  patterns:       # Code patterns found useful
    - "Error handling pattern in src/middleware"
    - "Service factory pattern in src/services"

  decisions:      # Decisions made with rationale
    - "Chose sessions over JWT because..."

  warnings:       # Things to avoid
    - "Don't modify session.ts:145 without updating tests"

  context:        # Compressed context from progress file
    # Auto-summarized if over threshold
```

**Context Compression** (scripts/lib/inherit.sh):
```bash
# Compress progress file for inheritance
compress_for_inheritance() {
  local progress_file=$1
  local max_tokens=${2:-4000}

  # Use Haiku for cost-effective summarization
  claude --model haiku \
    --prompt "Summarize this session progress for inheritance by a new session. Focus on: discoveries, decisions, patterns found, warnings. Max $max_tokens tokens." \
    < "$progress_file"
}
```

**Inheritance Injection:**
```markdown
## Inherited Context

### From session: auth-initial
**Key Discoveries:**
- Authentication uses JWT with refresh tokens (src/auth/jwt.ts)
- Session validation happens in middleware (src/middleware/auth.ts:45-89)
- User model is in src/models/user.ts

**Decisions Made:**
- JWT over sessions: needed stateless scaling for microservices
- Refresh rotation: 7 days based on security audit

### From session: bug-hunt-auth
**Warnings:**
- Race condition exists in token refresh (partially fixed)
- Don't use req.user before validateSession middleware
```

**Automatic Inheritance Suggestions:**
```bash
# When starting a session, suggest relevant ancestors
suggest_inheritance() {
  local session_name=$1

  # Find sessions with similar names or labels
  find .claude/pipeline-runs -name "state.json" -exec jq -r '.session' {} \; | \
    grep -i "${session_name%%-*}" | \
    head -5
}
```

**Composability:**
- Works with Facts Database (facts are primary inheritance vehicle)
- Enables "project memory" - collective learnings across all sessions
- Foundation for skill extraction (repeated patterns become skills)
- Integrates with supervisor (supervisor can mandate inheritance)

**Files:**
- `scripts/lib/inherit.sh` (new - inheritance and compression logic)
- `scripts/lib/context.sh` (inject inherited context into context.json)
- Session config schema (add inherits_from block)
- `.claude/inheritance/` (cached compressed contexts)

---

### 4. Model Tier Strategy with Adaptive Selection

**Loom Principle:** Planning tokens are cheaper than implementation tokens
**Problem:** We use the same model for all iterations regardless of task complexity. But Loom observes that planning should be cheap (explore many possibilities) while implementation should be thorough (get it right). Current system:
- Uses Opus for everything (expensive)
- Or uses Sonnet for everything (may miss nuance)
- No adaptation based on iteration type or session phase

**Solution:** Configurable model tiers with adaptive selection:

**Tier Configuration** (in stage.yaml):
```yaml
model_strategy:
  default: sonnet

  tiers:
    exploration:
      model: haiku
      when: iteration <= 2        # First iterations are exploratory

    refinement:
      model: sonnet
      when: 2 < iteration <= 5

    implementation:
      model: opus
      when: iteration > 5 and has_concrete_plan

    recovery:
      model: opus
      when: consecutive_errors >= 2  # Escalate on failures
```

**Adaptive Selection Logic** (scripts/lib/model.sh):
```bash
select_model() {
  local stage_config=$1
  local iteration=$2
  local history=$3  # JSON array of previous iterations

  # Check explicit tier rules
  local tier=$(evaluate_tier_conditions "$stage_config" "$iteration" "$history")

  # Check for recovery escalation
  local errors=$(echo "$history" | jq '[.[-3:][] | select(.error)] | length')
  if [ "$errors" -ge 2 ]; then
    tier="recovery"
  fi

  # Get model for tier
  local model=$(jq -r ".model_strategy.tiers.$tier.model // .model_strategy.default" <<< "$stage_config")
  echo "$model"
}
```

**Stage-Type Defaults:**
```yaml
# Default model strategies by stage type
stage_type_defaults:
  planning:
    default: haiku
    implementation_threshold: never   # Never use Opus for planning

  refinement:
    default: sonnet
    escalate_on_stall: true

  implementation:
    default: opus
    fallback_on_budget: sonnet

  review:
    default: sonnet
    escalate_for_security: opus       # Opus for security-sensitive reviews
```

**Budget-Aware Degradation:**
```bash
# If budget is tight, auto-downgrade
apply_budget_constraints() {
  local model=$1
  local remaining_budget=$2
  local estimated_cost=$3

  if [ "$(echo "$remaining_budget < $estimated_cost * 2" | bc)" -eq 1 ]; then
    # Less than 2 iterations of budget left, downgrade
    case "$model" in
      opus) echo "sonnet" ;;
      sonnet) echo "haiku" ;;
      *) echo "$model" ;;
    esac
  else
    echo "$model"
  fi
}
```

**Model Selection Logging:**
```json
// In iteration metrics
{
  "iteration": 7,
  "model_selected": "opus",
  "selection_reason": "implementation tier (iteration > 5, has_concrete_plan)",
  "alternatives_considered": ["sonnet (budget concern)", "haiku (exploration)"],
  "budget_remaining": 12.50
}
```

**Composability:**
- Works directly with cost metering (budget constraints trigger downgrades)
- Enables quality/cost optimization experiments
- Foundation for A/B testing different strategies
- Integrates with supervisor (supervisor can override per-session)

**Files:**
- `scripts/lib/model.sh` (new - model selection logic)
- Stage YAML schema (add model_strategy block)
- `scripts/lib/provider.sh` (use selected model)
- `scripts/engine.sh` (call model selection before each iteration)

---

### 5. Pipeline Combinators for Composable Workflows

**Loom Principle:** Composability / Building blocks that combine cleanly
**Problem:** Current pipeline composition is limited to linear sequences. But real workflows need:
- Parallel execution (run A and B concurrently)
- Racing (run A and B, use first result)
- Conditional branching (if A fails, try B)
- Retry with backoff (try A up to 3 times)
- Fan-out/fan-in (split work, merge results)

Without combinators, we hard-code these patterns in individual pipelines.

**Solution:** First-class pipeline combinators:

**Combinator Syntax** (in pipeline.yaml):
```yaml
name: robust-feature
description: Feature implementation with fallbacks

# Sequential (default)
stages:
  - sequence:
      - stage: improve-plan
        runs: 5
      - stage: refine-tasks
        runs: 3

  # Parallel execution
  - parallel:
      - stage: implement-frontend
        runs: 10
      - stage: implement-backend
        runs: 10
      wait: all          # "all" or "any"

  # Race: first to complete wins
  - race:
      - stage: approach-a
        runs: 5
      - stage: approach-b
        runs: 5
      winner_continues: true

  # Retry with backoff
  - retry:
      stage: deploy
      attempts: 3
      backoff: [30, 60, 120]  # seconds between retries

  # Conditional
  - conditional:
      if: "quality_score > 0.8"
      then:
        stage: release
      else:
        stage: additional-review
        runs: 3
```

**Combinator Implementations** (scripts/lib/combinators.sh):
```bash
run_parallel() {
  local stages=$1  # JSON array
  local wait_mode=$2  # "all" or "any"

  local pids=()

  # Launch all stages
  echo "$stages" | jq -c '.[]' | while read stage; do
    run_stage "$stage" &
    pids+=($!)
  done

  case "$wait_mode" in
    all)
      # Wait for all to complete
      for pid in "${pids[@]}"; do wait $pid; done
      ;;
    any)
      # Wait for first to complete, kill others
      wait -n
      for pid in "${pids[@]}"; do kill $pid 2>/dev/null; done
      ;;
  esac
}

run_race() {
  local stages=$1
  local winner=""

  # Run in parallel, track first to reach stop decision
  # ... (similar to parallel but with winner detection)
}

run_retry() {
  local stage=$1
  local attempts=$2
  local backoff=$3  # JSON array

  for ((i=0; i<attempts; i++)); do
    if run_stage "$stage"; then
      return 0
    fi

    local delay=$(echo "$backoff" | jq -r ".[$i] // 60")
    sleep "$delay"
  done

  return 1
}
```

**Result Merging** (for parallel and race):
```yaml
# How to merge outputs from parallel stages
merge:
  strategy: concatenate    # or "select_best" or "custom"

  # For select_best
  score_by: quality_score

  # For custom
  custom_script: scripts/merge-outputs.sh
```

**Combinator Visualization:**
```bash
./scripts/run.sh pipeline visualize complex-pipeline.yaml

# Output:
# ┌─────────────┐
# │ improve-plan│
# └──────┬──────┘
#        │
# ┌──────┴──────┐
# │   parallel  │
# ├─────┬───────┤
# │front│ back  │
# └─────┴───────┘
#        │
# ┌──────┴──────┐
# │    retry    │
# │   deploy    │
# └─────────────┘
```

**Composability:**
- This IS composability - combinators compose with each other
- Works with supervisor (supervisor can launch combinator pipelines)
- Enables complex workflows without custom scripting
- Foundation for pipeline templates (common combinator patterns)

**Files:**
- `scripts/lib/combinators.sh` (new - combinator implementations)
- Pipeline YAML schema (extend for combinator syntax)
- `scripts/engine.sh` (dispatch to combinator runners)
- `scripts/run.sh` (add visualize subcommand)

---

## Summary: Iteration 3 Themes

**Economic Optimization:**
- Cost metering enables informed decisions about model selection and iteration counts
- Budget caps prevent runaway spending
- Cost-per-value tracking optimizes for ROI not throughput

**Hierarchical Orchestration:**
- Supervisor pattern enables scaling beyond single sessions
- Discovery broadcasting prevents redundant work
- Resource brokering prevents contention

**Long-Horizon Patterns:**
- Session inheritance preserves learnings across boundaries
- Context compression keeps inherited context manageable
- Model tier strategy applies right tool for each phase

**Composable Primitives:**
- Pipeline combinators enable complex workflows from simple building blocks
- Parallel, race, retry, conditional patterns are first-class
- Result merging handles multi-path outputs

**Key Insight from Loom:**
The $10/hour economic model means we should optimize for value per dollar, not just task completion. Cheap exploration (Haiku) enables more possibilities. Expensive implementation (Opus) ensures quality where it matters. The supervisor pattern enables us to treat pipelines as resources to be orchestrated, not isolated executions.
