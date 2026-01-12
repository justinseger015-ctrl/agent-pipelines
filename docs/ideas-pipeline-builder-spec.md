# Ideas from pipeline-builder-spec - Iteration 1

> Focus: Ideas to improve the pipeline-builder skills and the experience of creating custom pipelines

---

### 1. Stage Catalog with Live Preview

**Problem:** Users creating pipelines must understand what existing stages do by reading YAML and prompt files. There's no quick way to browse available stages, see examples of their output, or understand their tradeoffs.

**Solution:** Build a stage catalog accessible via `/pipeline catalog`:
- Interactive list showing all stages in `scripts/loops/`
- For each stage: description, termination strategy, model recommendation
- "Example output" showing a real iteration result from that stage
- Recommendation tags: "good for planning", "high-quality output", "fast"
- Can be invoked mid-conversation: "Show me stages that use judgment termination"

**Why now:** The pipeline-builder spec introduces automatic stage selection by the architecture agent. That agent needs a rich understanding of stage capabilities to recommend well. A catalog becomes the source of truth for both humans and agents.

---

### 2. Prompt Composability via Template Includes

**Problem:** The pipeline-builder creates stage prompts from scratch, leading to inconsistency. Every new stage reinvents the "read context" and "write status" patterns. Copy-paste errors accumulate. Best practices diverge.

**Solution:** Add template includes for common patterns:
```markdown
# My Custom Stage

${include:preamble/autonomy-grant.md}

## Your Mission
[Custom content here]

${include:patterns/read-context.md}
${include:patterns/write-status.md}
```
Include library in `scripts/lib/templates/`:
- `autonomy-grant.md` - "This is not a checklist task..." paragraph
- `read-context.md` - Standard cat/jq commands
- `write-status.md` - JSON schema and decision guide
- `subagent-guidance.md` - When and how to spawn subagents

**Why now:** The Stage Creator Agent in the spec will generate many prompts. Includes ensure consistency without requiring the agent to memorize boilerplate. Humans benefit equally when hand-crafting stages.

---

### 3. Pipeline Visualization Command

**Problem:** Multi-stage pipelines are defined in YAML but understanding the flow requires mental parsing. Users can't quickly see: stage order, data flow between stages, estimated iteration counts, or cost implications.

**Solution:** Add `./scripts/run.sh viz {pipeline}` that generates:
- ASCII art showing stage sequence and data flow
- Annotations with iteration counts and models per stage
- Estimated token usage range (min/max based on history)
- Dependency arrows showing `inputs.from` relationships
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  improve-plan   │────▶│  refine-beads   │────▶│    elegance     │
│  5 iters, opus  │     │  5 iters, opus  │     │  3 iters, opus  │
│  ~50k tokens    │     │  ~40k tokens    │     │  ~30k tokens    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Why now:** The pipeline-builder spec introduces complex multi-stage architectures. Visualization bridges the gap between YAML configuration and human understanding. Critical for reviewing architecture agent recommendations.

---

### 4. Confidence Scoring for Architecture Recommendations

**Problem:** The architecture agent returns a recommendation, but users don't know how confident it is. Was this the obvious choice or a toss-up between three options? Should the user ask clarifying questions or trust it?

**Solution:** Add confidence scoring to architecture agent output:
```yaml
recommendation:
  confidence: 0.85  # 0-1 scale
  confidence_breakdown:
    termination_strategy: 0.95  # Very clear this should be judgment
    stage_count: 0.70           # Could be 2 or 3 stages
    model_selection: 0.90       # Opus clearly needed
  areas_of_uncertainty:
    - "Unclear if refine-beads should run before or after elegance"
    - "User's tolerance for cost vs quality tradeoff unknown"
```
Display to user: "I'm 85% confident in this architecture. Key uncertainty: stage ordering."

**Why now:** The spec positions the architecture agent as mandatory before confirmation. Confidence scoring helps users decide whether to accept immediately or probe further. Transparent AI decision-making builds trust.

---

### 5. Stage A/B Testing Framework

**Problem:** Users can't empirically compare different stage configurations. Does 3-consensus outperform 2-consensus? Is Sonnet good enough for this task? Currently: guess and hope.

**Solution:** Add A/B testing support:
```bash
./scripts/run.sh ab-test \
  --config-a "elegance-3consensus.yaml" \
  --config-b "elegance-2consensus.yaml" \
  --trials 5 \
  --session-prefix "elegance-ab"
```
- Runs both configurations N times with identical inputs
- Records: iterations-to-complete, token usage, output quality (via LLM eval)
- Generates comparison report with statistical significance
- Stores results in `.claude/ab-tests/` for future reference

**Why now:** The pipeline-builder empowers users to create custom stages with arbitrary configurations. Without measurement, they can't optimize. A/B testing turns pipeline design from art into science.

---

## Ideas from pipeline-builder-spec - Iteration 2

> Focus: Operational reliability, cost control, and production-readiness for pipeline execution

---

### 6. Human-in-the-Loop Checkpoints

**Problem:** Once a pipeline starts, it runs to completion with no opportunity for human intervention. A user can't review stage outputs before the next stage begins. This is risky for expensive pipelines or when early stages might go off-track.

**Solution:** Add checkpoint configuration to pipeline definitions:
```yaml
stages:
  - name: architecture-design
    loop: design
    runs: 5
    checkpoint: true  # Pause after this stage

  - name: implementation
    loop: work
    runs: 10
```
When a checkpoint is reached:
- Engine pauses and notifies user (terminal + desktop notification)
- User reviews outputs from completed stage
- Commands: `./scripts/run.sh continue {session}` or `./scripts/run.sh abort {session}`
- Optional: `--unattended` flag skips all checkpoints

**Why now:** The pipeline-builder enables users to create arbitrary multi-stage pipelines. Some will be expensive (many iterations with Opus). Checkpoints let users validate early stages before committing to full execution. Production pipelines need this.

---

### 7. Token Budget Allocation

**Problem:** Users set max_iterations per stage but have no way to control total token spend. A 5-stage pipeline could consume $50 in tokens before anyone notices. Cost overruns are only discovered after the fact.

**Solution:** Add budget configuration at pipeline and stage levels:
```yaml
name: expensive-pipeline
budget:
  total_tokens: 500000        # Hard cap for entire pipeline
  per_stage: 100000           # Default per-stage cap
  alert_threshold: 0.8        # Warn at 80% usage

stages:
  - name: complex-analysis
    loop: analyze
    budget:
      tokens: 200000          # Override: this stage gets more
```
Runtime behavior:
- Engine tracks token usage from Claude API responses
- Pause and notify when alert_threshold reached
- Hard stop when budget exhausted (graceful termination)
- After pipeline: show token usage breakdown by stage

**Why now:** The pipeline-builder democratizes complex pipeline creation. Users who don't understand token economics will create expensive configurations. Budget guardrails prevent surprise bills. Essential for team adoption.

---

### 8. Stage Output Caching and Replay

**Problem:** Re-running a pipeline means re-doing all stages from scratch. If you want to tweak stage 3 of a 4-stage pipeline, you must run stages 1-2 again. This wastes tokens and time, especially for deterministic early stages.

**Solution:** Add caching infrastructure:
```bash
# Cache stage outputs (stored in .claude/cache/)
./scripts/run.sh pipeline full-refine.yaml my-session --cache

# Replay with cached stage 1, re-run stages 2+
./scripts/run.sh pipeline full-refine.yaml my-session --from-stage=2

# Invalidate specific stage cache
./scripts/run.sh cache clear my-session stage-1
```
Cache format:
- `.claude/cache/{session}/{stage}/output.json` - Serialized stage outputs
- `.claude/cache/{session}/{stage}/inputs.hash` - Hash of inputs (for cache invalidation)
- Auto-invalidate when stage config or inputs change

**Why now:** The pipeline-builder encourages experimentation with multi-stage configurations. Without caching, every experiment re-runs everything. Caching enables rapid iteration on later stages while preserving expensive early-stage work.

---

### 9. Stage Timeout Configuration

**Problem:** A stage can run indefinitely if an agent gets stuck or the judgment termination never reaches consensus. There's no safety valve. A stuck pipeline silently consumes resources until someone notices.

**Solution:** Add timeout configuration:
```yaml
name: my-stage
termination:
  type: judgment
  timeout:
    per_iteration: 300       # 5 minutes per iteration
    total: 1800              # 30 minutes for entire stage
    action: error            # 'error' | 'force_stop' | 'notify'
```
Timeout behavior:
- `error`: Mark stage as failed, pipeline stops
- `force_stop`: Write `decision: stop` and continue (graceful degradation)
- `notify`: Alert user but keep running

Also add pipeline-level timeout:
```yaml
name: my-pipeline
timeout: 7200  # 2 hours total
```

**Why now:** The pipeline-builder creates stages that may behave unexpectedly. Runaway iterations are a real risk with judgment termination (what if agents never agree?). Timeouts are table-stakes for production reliability.

---

### 10. One-Click Stage Cloning with Variants

**Problem:** Users often want "elegance but stricter" or "refine-beads but for security". Currently they must manually copy files, modify YAML, edit prompts. This friction discourages customization.

**Solution:** Add clone command with variant configuration:
```bash
# Clone a stage with modifications
./scripts/run.sh stage clone elegance elegance-strict \
  --consensus=3 \
  --min-iterations=5 \
  --model=opus

# Interactive clone (asks what to change)
./scripts/run.sh stage clone work work-security
```
For complex modifications:
```yaml
# .claude/stage-variants/elegance-strict.yaml
base: elegance
changes:
  termination:
    consensus: 3
    min_iterations: 5
  prompt:
    prepend: |
      IMPORTANT: Be extremely strict in your evaluation.
      Reject any code that is merely "good enough".
```
Benefits:
- Preserves relationship to base stage (for updates)
- Diff-based tracking of customizations
- Can list all variants: `./scripts/run.sh stage list --variants`

**Why now:** The pipeline-builder's architecture agent recommends existing stages. Users will want to tweak them. Making customization frictionless multiplies the value of each base stage. Variants are the extension mechanism.

---
