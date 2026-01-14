# TDD Prose v3

A one-directional, deterministic compiler from executable tests to a stable, reviewable plain-English behavior ledger, plus an agent skill that elicits requirements and turns them into high-quality tests that slot cleanly into the ledger.

---

## 1. Scope

### In scope

* **Tests → Prose** only.
* Deterministic extraction of test structure and evidence.
* Stable IDs, stable rendering, and low-churn diffs.
* Behavior-level grouping, eligibility filtering, drift detection, and coverage reporting.
* Runtime pass/fail surfaced as an **overlay** (never committed into prose).
* An agent “skill” (Claude Code + Codex) that:

  * interviews for intended functionality,
  * proposes and writes tests (with behavior anchors),
  * runs/validates,
  * then the normal compiler regenerates prose from those tests.

### Out of scope

* Prose/spec as an authority.
* Prose → tests round-trip sync.
* Scaffolding guarantees beyond “syntactically correct and aligned with project conventions.”
* Any system that claims stakeholder prose is “true” independent of executable evidence.

---

## 2. Problem

Modern workflows routinely generate or modify tests without the author fully understanding:

* what behavior is actually enforced,
* what changed behaviorally across commits,
* which areas are under-tested or overfit to internals,
* which tests are documentation-worthy vs diagnostic noise.

Code review also emphasizes code diffs over **behavior diffs**.

---

## 3. Product definition

TDD Prose is a deterministic compiler that projects a repository’s tests into a stable, modular plain-English “behavior ledger” with:

* stable behavior IDs,
* traceable links back to tests,
* eligibility filtering (stakeholder-facing vs internal),
* deterministic formatting to avoid diff churn,
* drift/coverage reports,
* optional non-authoritative LLM phrasing polish.

A separate agent skill drives new tests from user interviews; those tests become the only truth, and TDD Prose then regenerates prose from them.

---

## 4. Core invariants

1. **Single source of truth:** executable tests.
2. **Deterministic output:** identical repo state produces identical spec bytes.
3. **No run artifacts in git:** pass/fail is never written into committed prose.
4. **No LLM authority:** models may classify/phrase, never create/erase behaviors or override evidence.
5. **Conservative writes:** when identity or grouping is uncertain, mark `needs_review` and do not silently rewrite mappings.
6. **Low churn:** stable ordering, stable wrapping, stable IDs, no timestamps.

---

## 5. Repository artifacts and policy

### Committed

* `spec/**` (default) or `SPEC.md` (single-file mode)
* `.tdd-prose/config.yml`
* `.tdd-prose/mapping.snapshot.json` (recommended for team determinism)

### Not committed

* `.tdd-prose/state.sqlite` (caches, indexes, fingerprints)
* `.tdd-prose/cache/**` (AST caches, embeddings, intermediate files)
* `.tdd-prose/reports/**` (run overlays, HTML, JSON)
* lock files

### CI behavior

* rebuild local state from repo + mapping snapshot
* enforce drift rules via `/tdd-check`
* publish overlays and behavior diffs as CI artifacts / PR annotations

### Config (`.tdd-prose/config.yml`)

Example:

```yaml
spec_output: spec/
test_globs:
  - "tests/**/*.py"
exclude_globs:
  - "**/fixtures/**"
frameworks:
  - name: pytest
    collect_cmd: "pytest --collect-only --json-report"
block_rules:
  default: "{suite_path.0}"
  overrides:
    "Authentication/login": "auth.login"
eligibility:
  default: behavior
  internal_patterns:
    - "**/*_snapshot*"
anchors:
  tag: "@tdd-prose:behavior"
  allow_multiple: false
ci:
  needs_review_max: 0
  orphaned_max: 0
render:
  wrap_column: 88
```

Required fields:

* `spec_output` target directory or file
* `test_globs` for discovery
* `frameworks[*].collect_cmd` for runner metadata

Optional fields (deterministic defaults if omitted):

* `exclude_globs` to ignore fixtures/helpers
* `block_rules` overrides for block_id mapping
* `eligibility.internal_patterns` for known internal-only tests
* `anchors` syntax per language
* `ci` thresholds for `needs_review`/`orphaned`
* `render.wrap_column` for stable formatting

---

## 6. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                           TDD Prose Compiler                          │
├──────────────────────────────────────────────────────────────────────┤
│  Framework Adapters  →  TestIR  →  BehaviorGraph  →  Renderer → spec/ │
│       (AST + runner)        |            |              |             │
│                             |            |              |             │
│                        Identity + Grouping + Eligibility              │
│                             |            |                            │
│                       mapping.snapshot + state.sqlite                 │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                    Agent Skill (Claude Code / Codex)                  │
├──────────────────────────────────────────────────────────────────────┤
│  Interview → Behavior Intent → Gap Analysis → Test Plan → Write Tests │
│           (structured)        (ledger-aware)          (anchored)      │
│                      Run/Validate → Commit Tests → Recompile prose    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 7. Canonical data model

### 7.1 TestIR (framework-agnostic facts)

Emitted deterministically by adapters.

Minimal shape:

```json
{
  "framework": "jest",
  "file": "auth.test.ts",
  "file_fingerprint": "sha256:…",
  "tests": [
    {
      "test_id": "test:jest:Authentication/login:rejects invalid password:params=…:assert=…",
      "suite_path": ["Authentication", "login"],
      "name": "rejects invalid password",
      "parameters": [{"name":"case","hash":"…"}],
      "assertions": [
        {"kind":"throws","matcher":"toThrow","expected_literal":"Invalid credentials"}
      ],
      "anchors": {
        "behavior_id": "auth.login.invalid_credentials"
      },
      "locator": {"path":"auth.test.ts","start_line":9,"end_line":14}
    }
  ]
}
```

Notes:

* `anchors.behavior_id` is optional but strongly recommended for stability.
* `assertions` records “kind + matcher + trivially extractable literals.” Anything non-trivial becomes a hashed structural summary.
* `status` captures skip/xfail; skipped tests never count as evidence but appear in coverage diagnostics.

### 7.2 BehaviorGraph (behavior ledger IR)

Built deterministically from TestIR + mapping snapshot.

```json
{
  "behavior_id": "auth.login.invalid_credentials",
  "block_id": "auth.login",
  "title": "Invalid credentials",
  "evidence": [
    {"test_id":"test:jest:…", "weight":1.0}
  ],
  "fingerprint": "sha256:…",
  "eligibility": "behavior",
  "confidence": 0.92,
  "status": "ok"
}
```

Notes:

* `weight` in evidence: Strength of this test as evidence for the behavior. Default 1.0. Reduced for tests that evidence multiple behaviors (shared evidence) or parameterized tests where each case partially covers the behavior. Computed deterministically from test structure.
* `confidence`: How certain the compiler is about this behavior's identity/grouping. 1.0 = anchored explicitly; 0.8-0.99 = inferred from heuristics with high match; <0.8 = ambiguous, likely marked `needs_review`. Only used for diagnostics; does not affect rendering.
* `fingerprint`: Hash of the behavior's canonical content (title + evidence signatures). Used for incremental change detection.

### 7.3 Eligibility categories

**MVP (Phases 0-2):** Binary classification
* `behavior` (stakeholder-facing) — rendered in spec
* `internal` (everything else) — visible in coverage reports only

**Full taxonomy (Phase 3+):** Refine `internal` into subcategories for reporting:
* `diagnostic` (implementation checks, internal invariants)
* `snapshot` (golden/snapshot tests)
* `perf` (benchmarks)
* `fuzz` (property/fuzz)
* `infra` (test harness plumbing)

Default spec renders only `behavior`, while the rest stays visible in coverage and internal views.

### 7.4 Agent Interface (JSON-first)

> *Pattern inspired by [beads](https://github.com/steveyegge/beads): agents consume structured JSON, not prose.*

The BehaviorGraph is the primary agent interface. All queries support `--json` output:

```bash
# Full graph export
tddprose behaviors --json

# Filtered views for focused context
tddprose behaviors --json --filter orphaned
tddprose behaviors --json --filter needs-review
tddprose behaviors --json --filter weak-evidence

# Ready-to-implement behaviors (actionable gaps)
tddprose ready --json
```

Output format:

```json
{
  "behaviors": [...],
  "stats": {
    "total": 42,
    "orphaned": 2,
    "needs_review": 3,
    "weak_evidence": 5
  },
  "generated_at": "2025-01-15T10:00:00Z"
}
```

This enables:
- Agents query "what can I implement?" without parsing markdown
- Focused context windows (filter to actionable items only)
- Deterministic queries without text interpretation

### 7.5 Behavior Dependencies (Phase 3+ / Agent Skill)

> **Note:** This is an agent skill feature, not core compiler. The compiler reads tests; it cannot infer inter-behavior dependencies. Dependencies must be declared by agents or humans.

Behaviors can relate to other behaviors:

```json
{
  "behavior_id": "auth.session.refresh",
  "depends_on": ["auth.login.valid_credentials"],
  "related_to": ["auth.logout"],
  "evidence": [...]
}
```

Dependency types:
- **depends_on**: Prerequisite behaviors (must be implemented first)
- **related_to**: Cross-references without ordering
- **evidenced_by**: Tests that prove this behavior (already captured in `evidence`)

The `tddprose ready` command uses dependency graph to show only behaviors whose prerequisites are satisfied—analogous to `bd ready` in beads.

**Implementation timing:** Add in Phase 3 when agent skill needs to order work.

---

## 8. Stable identity strategy

### 8.1 test_id derivation (deterministic)

Derived from normalized:

* framework
* suite path segments
* test name
* parameterization signature
* assertion structure signature (matcher kinds + structural hash)
* optional anchor tag overrides (preferred)

Goal: unchanged intent keeps the same `test_id` under formatting and minor refactors.

### 8.2 behavior_id derivation (deterministic, anchor-first)

Priority order:

1. explicit anchor in test: `@tdd-prose:behavior auth.login.invalid_credentials`
2. mapping snapshot explicit binding
3. deterministic heuristic from suite segments + normalized test name phrase
4. if ambiguous: mint a new behavior_id but mark `needs_review`

### 8.3 mapping snapshot (team determinism)

A small committed JSON file that stores:

* behavior definitions (IDs + canonical titles)
* evidence bindings (behavior_id ↔ test_id set)
* approved aliases (old test_id → new test_id)
* approved block assignments
* provenance flags: `human_approved` vs `auto_accepted`

This converts probabilistic continuity decisions into deterministic future builds.

### 8.4 Content-hash fingerprints (Phase 3+ / Agent Skill)

> *Pattern from [beads](https://github.com/steveyegge/beads): content-addressable IDs enable parallel agent work without coordination.*

> **Note:** This is an agent skill feature. The core compiler uses `behavior_id` for determinism. Content hashes add value when agents create behaviors in parallel—not needed for Phases 0-2.

Each behavior maintains a `content_hash` computed from canonical content:

```python
content_hash = sha256(
    block_id +
    canonical_title +
    sorted(evidence_test_ids) +
    eligibility
)
```

This enables:
- **Parallel agent creation**: Agents can propose new behaviors without ID conflicts
- **Change detection**: Modified behaviors have different hashes
- **Merge safety**: Concurrent edits to different behaviors never conflict on IDs

The `behavior_id` remains human-readable (`auth.login.invalid_credentials`), while `content_hash` provides the collision-resistant fingerprint for change tracking.

**Implementation timing:** Add in Phase 3 when agent skill enables parallel behavior creation.

---

## 9. Spec format (generated prose)

### 9.1 Owned regions

Each block has:

* generated region (compiler owns, overwrites)
* manual notes region (human owns, preserved verbatim)

Example:

```md
## Login Flow
<!-- tdd-prose:block id=auth.login -->
<!-- tdd-prose:status ok -->
<!-- tdd-prose:generated-begin -->

The login system enforces these outcomes:

- **Invalid credentials**: Incorrect password and unknown email produce the same generic error.
- **Valid credentials**: Correct credentials create a session token.

<!-- tdd-prose:generated-end -->

<!-- tdd-prose:manual-begin -->
Notes: Lockout rules are tenant-configurable.
<!-- tdd-prose:manual-end -->
```

### 9.2 Status values

* `ok` aligned with current tests
* `stale` mapping or grouping needs regeneration (should be rare if compiler runs)
* `needs_review` ambiguity detected (identity/grouping conflict)
* `orphaned` behavior has no evidence
* `excluded` behavior exists but filtered by eligibility/tier

No timestamps in spec. Any “last sync” belongs in local state and CI artifacts.

---

## 10. Compiler pipeline

### 10.1 Indexing

* discover test files via config globs
* parse via AST using **tree-sitter** (py-tree-sitter bindings)
  * pre-compiled wheels for all platforms, no native dependencies
  * language grammars: tree-sitter-python, tree-sitter-typescript, tree-sitter-javascript
  * extraction pattern: `node.child_by_field_name()` for test function/method metadata
* runner enumeration to capture dynamic/param tests:

  * pytest: **pytest-json-report** with `--json-report --collect-only` (provides `collectors` array)
  * jest/vitest: built-in `--json` output (provides `testResults` array with test metadata)
  * fallback: parse `--collect-only` text output with regex (less reliable)
* reconcile runner nodeids with static locators via file path + function name matching

### 10.2 Build BehaviorGraph

* map tests to behaviors:

  * anchor-first
  * snapshot bindings
  * deterministic heuristics
* group behaviors into blocks:

  * primarily suite path → domain blocks
  * configurable remapping rules

### 10.3 Eligibility classification

> **MVP (Phases 0-2):** Use binary classification only (`behavior` vs `internal`). The detailed rules below apply to Phase 3+ when refining `internal` into subcategories.

Deterministic rules first:

* snapshot test detection (snapshot matchers, files, naming) → `snapshot`
* perf/fuzz conventions (benchmark decorators, property-based test markers) → `perf`/`fuzz`
* high-mock / interaction-only signatures → `diagnostic`
* test harness setup/teardown → `infra`
* everything else without explicit anchor → `internal` (MVP) or classifier-suggested category (Phase 3+)

Optional local model classifier can refine borderline cases, but cannot override anchored category.

### 10.4 Deterministic rendering

* stable ordering: block_id, then behavior_id
* fixed wrap column
* stable bullet style
* normalized headings

### 10.5 Incremental planner

* detect changed files via git diff or hashes
* reparse only changed test files
* update impacted behaviors/blocks only
* re-render only impacted blocks

Exit condition: no-op run produces zero spec diffs.

### 10.6 Failure handling and edge cases

Deterministic rules when inputs are messy:

* syntax errors or unsupported test files → mark `parse_error`, keep last-known behaviors, fail `/tdd-check` in CI
* runner vs AST mismatch → mark `needs_review` with diagnostics; keep AST locators but runner names
* parameterized tests → each case becomes evidence entry; shared anchor applies to all cases
* skipped/xfail → excluded from evidence but reported as inactive coverage
* dynamic test names → fall back to runner-collected name and hash suffix; mark `needs_review`
* multiple anchors on a test → shared evidence with reduced weight; error if anchors map to conflicting blocks
* duplicate `test_id` → require explicit anchor or snapshot alias; otherwise fail `/tdd-check`
* deleted tests → behaviors become `orphaned`, never auto-removed

---

## 11. Drift checks and coverage

### 11.1 `/tdd-check`

Deterministic verification:

* spec blocks malformed (missing tags / broken owned regions)
* mapping snapshot references missing tests/behaviors
* anchor collisions (same behavior_id claimed by incompatible tests)
* ambiguous remaps requiring review
* adapter/runner mismatch

CI mode returns non-zero if:

* `needs_review` exists
* `orphaned` behaviors exceed threshold
* excluded categories violate policy (configurable)

### 11.2 `/tdd-coverage`

Reports:

* behaviors by eligibility tier
* orphan tests (not surfaced in ledger tier)
* weak evidence behaviors (single brittle test, flaky signature)
* domains with low density of stakeholder-facing behaviors

Outputs:

* human readable
* JSON for PR annotations/dashboards

### 11.3 Diagnostics artifacts

* `.tdd-prose/reports/diagnostics.json` with parse errors, mismatches, skipped/xfail inventory
* `.tdd-prose/reports/behavior-diff.json` for stable machine-readable diffs
* severity mapping (`info`/`warn`/`error`) with deterministic exit codes

---

## 12. Runtime "working vs not working" overlay

### Requirement

Behavior ledger must reflect truth without diff churn.

### Strategy

* consume test results from any framework:
  * **Preferred:** CTRF (Common Test Report Format) - cross-framework JSON standard
  * **Native formats:** JUnit XML, pytest-json-report JSON, Jest JSON
  * CTRF adapters exist for Jest, Vitest, pytest, and most major frameworks
* map results: test nodeid → test_id → behavior_id
* generate overlays as artifacts:

  * `tdd-prose.report.json` (internal format)
  * `tdd-prose.ctrf.json` (CTRF-compatible, for tooling interop)
  * optional HTML report
  * PR annotations (summary + top failing behaviors)

Never write pass/fail into `spec/**`.

### Implementation Note

CTRF provides a unified schema regardless of test framework. Using it as the internal format simplifies:
- Multi-framework repos (single overlay format)
- CI tooling (CTRF has GitHub Actions integration)
- Future integrations (any tool that reads CTRF works automatically)

---

## 13. LLM use (optional, bounded)

### Allowed roles

* phrase polishing for generated bullets
* borderline eligibility classification
* alias suggestions (identity continuity) when tests move/rename
* grouping suggestions when suite structure is chaotic

### Disallowed roles

* inventing behaviors not evidenced
* deleting behaviors
* changing behavior_id or test_id
* overriding anchors
* writing spec outside generated regions

### Controls

* temperature 0
* strict JSON schema outputs
* canonicalization pass after model output
* hard fallback templates if schema fails

### Implementation: Local Models via Ollama

**Recommended models (all Apache 2.0, run locally via `ollama run`):**

| Task | Model | Size | Rationale |
|------|-------|------|-----------|
| Eligibility classification | `qwen3:0.6b` | 0.6B | Fast, simple categorical task |
| Eligibility classification (fallback) | `tinyllama` | 1.1B | Lower capability but faster |
| Phrase polishing | `qwen3:4b` | 4B | Needs reasoning for natural phrasing |
| Alias suggestions | `phi3:mini` | 3.8B | Good at reasoning about renames |

**Integration pattern (from qmd):**
- Use `node-llama-cpp` for TypeScript or `ollama` CLI for shell scripts
- All model calls are synchronous, single-request (no streaming needed)
- Cache results in sqlite keyed by input hash
- Hard timeout: 5s for classification, 15s for phrase polishing
- Fallback: if model unavailable or times out, use template-based output

---

## 14. Agent Skill: interview → high-quality tests (Claude Code + Codex)

This is separate from the compiler. Its job is to produce tests that:

* follow repo conventions,
* include explicit behavior anchors,
* fit the ledger’s block structure,
* close coverage gaps intentionally.

### 14.1 Inputs it uses

* current BehaviorGraph (from compiler output)
* `/tdd-coverage` gap report
* repo test patterns (fixtures, factories, helpers)
* a structured interview transcript (captured as data, not authoritative)

### 14.2 Outputs it produces

* new/updated tests (the only truth)
* anchors embedded in tests:

  * comment tags, decorators, or helper wrappers
* optional local notes (not required, not authoritative)

### 14.3 Interview product: Behavior Intent (structured)

The skill converts an interview into a machine-usable intent file:

```json
{
  "domain": "auth.login",
  "behaviors": [
    {
      "behavior_id": "auth.login.invalid_credentials",
      "given": "a user provides an incorrect password",
      "when": "they submit the login form",
      "then": "the system responds with a generic invalid-credentials error"
    }
  ],
  "constraints": {
    "security": ["do not reveal account existence"],
    "logging": ["no PII in logs"]
  }
}
```

This file is a planning artifact. It does not generate prose. It drives test authoring.

### 14.4 Gap-aware planning

Before writing tests:

* compare intended behaviors against existing BehaviorGraph
* classify each intent as:

  * already covered
  * partially covered (weak evidence)
  * uncovered
  * conflicts with existing behavior (requires explicit decision)

### 14.5 Test authoring mechanics

* choose target framework + location using repo conventions
* reuse existing factories/helpers
* generate tests with anchors:

  * `@tdd-prose:behavior auth.login.invalid_credentials`
* keep assertions explicit and extractable when possible
* avoid “interaction-only” tests unless explicitly desired

### 14.6 Validation gates (deterministic)

The skill runs:

* typecheck/lint/format (project standard)
* targeted test run (new/changed files) when feasible
* if validation fails: modify tests until passing or stop with a deterministic failure report

### 14.7 Integration loop

1. skill writes tests
2. tests run
3. compiler regenerates BehaviorGraph + `spec/**`
4. behavior diff summary produced for review

This preserves the one-direction truth model.

### 14.8 Skill interface surface (conceptual)

Expose as commands/tools usable by Claude Code and Codex:

Compiler commands:

* `tddprose sync --diff|--apply`
* `tddprose check`
* `tddprose coverage`
* `tddprose report --from <junit.xml|json>`

Authoring commands:

* `tddprose interview` (guided intake)
* `tddprose intent validate` (schema + conflict checks)
* `tddprose plan` (gap-aware test plan)
* `tddprose write --apply` (writes anchored tests)
* `tddprose validate` (runs gates)

Agent-first query commands:

* `tddprose behaviors --json [--filter ...]` (BehaviorGraph export)
* `tddprose ready --json` (actionable gaps with satisfied dependencies)

### 14.9 MCP Server Integration (Phase 3+ Enhancement)

> *Pattern from [FastMCP](https://github.com/jlowin/fastmcp): decorator-based dual CLI/MCP interface.*

> **Note:** MCP is a thin wrapper over CLI. Build CLI first; MCP can be added in one day once CLI exists. This is a Phase 3+ enhancement, not MVP.

TDD Prose tools should work both as CLI commands and as MCP tools for AI assistants. FastMCP enables this with minimal wrapping:

**Core pattern (shared implementation):**

```python
# tddprose/tools.py - Pure functions, no I/O dependencies
def behaviors_query(filter: str = None, json_output: bool = True) -> dict:
    """Query BehaviorGraph with optional filtering."""
    graph = load_behavior_graph()
    if filter:
        graph = apply_filter(graph, filter)
    return graph.to_dict() if json_output else graph.to_markdown()

def ready_query() -> dict:
    """Return behaviors ready for implementation (dependencies satisfied)."""
    graph = load_behavior_graph()
    return [b for b in graph.behaviors if b.is_ready()]
```

**MCP exposure (decorator layer):**

```python
# tddprose/mcp_server.py
from fastmcp import FastMCP
from .tools import behaviors_query, ready_query

mcp = FastMCP("TDD Prose")

@mcp.tool
def tddprose_behaviors(filter: str = None) -> dict:
    """Query the behavior ledger. Filters: orphaned, needs-review, weak-evidence."""
    return behaviors_query(filter=filter, json_output=True)

@mcp.tool
def tddprose_ready() -> dict:
    """List behaviors ready for implementation (no blocking dependencies)."""
    return ready_query()

@mcp.resource("behaviors://{behavior_id}")
def get_behavior(behavior_id: str) -> dict:
    """Fetch a specific behavior by ID."""
    return load_behavior(behavior_id)
```

**CLI exposure (thin wrapper):**

```python
# tddprose/cli.py
import click
from .tools import behaviors_query, ready_query

@click.command()
@click.option('--filter', help='Filter: orphaned, needs-review, weak-evidence')
@click.option('--json', is_flag=True)
def behaviors(filter, json):
    result = behaviors_query(filter=filter, json_output=json)
    click.echo(format_output(result, json))
```

**Transport configuration:**

- **STDIO** (default): For Claude Desktop integration via `claude_desktop_config.json`
- **SSE/HTTP**: For web-based AI assistants or remote usage

**Installation for Claude Desktop:**

```json
{
  "mcpServers": {
    "tdd-prose": {
      "command": "uv",
      "args": ["run", "fastmcp", "run", "tddprose/mcp_server.py"]
    }
  }
}
```

**Error handling:**

- Use `ToolError` for agent-facing errors (invalid filter, missing behavior)
- Mask internal exceptions in production (`mask_error_details=True`)
- Return structured error objects, not strings

This dual pattern means:
- Developers use `tddprose behaviors --json` from terminal
- Claude Code uses the same logic via MCP tools
- No code duplication between interfaces

### 14.10 Session Protocol (Optional Enhancement)

> *Pattern from [beads](https://github.com/steveyegge/beads): structured session phases with checkpoints enable recovery and context management.*

> **Note:** This is an optional enhancement for production agent skill. MVP can use simpler "re-run interview on failure" model. Session recovery matters when interviews are expensive; for most use cases, starting over is acceptable.

Agent skill sessions follow explicit phases with checkpoints:

```
.tdd-prose/session/
├── intake.json          # Interview transcript + parsed intents
├── plan.json            # Gap analysis + test plan
├── implementation/      # In-progress test files
│   └── *.test.ts
├── validation.json      # Gate results (lint, test, compile)
└── state.json           # Current phase + resume point
```

**Phase transitions:**

1. **intake** → Captures behavior intents from interview
   - Checkpoint: `intake.json` written
   - Resume: Skip interview, use existing intents

2. **plan** → Gap analysis against BehaviorGraph
   - Checkpoint: `plan.json` with classified intents
   - Resume: Skip analysis, use existing plan

3. **implement** → Write tests with anchors
   - Checkpoint: Files in `implementation/`
   - Resume: Continue from last written file

4. **validate** → Run gates until passing
   - Checkpoint: `validation.json` with results
   - Resume: Retry failed validations

5. **commit** → Apply tests, regenerate prose
   - Final: Move files to repo, delete session state

**Session commands:**

```bash
# Start new session
tddprose session start

# Resume crashed/interrupted session
tddprose session resume

# Abort and clean up
tddprose session abort
```

This enables:
- **Crash recovery**: Resume from last checkpoint, not restart
- **Context management**: Each phase loads only relevant state
- **Audit trail**: Session directory shows exact agent workflow

---

## 15. Security and safety

* local-only mode supported (no model calls)
* allowlist paths for any model context
* redact secrets before any model input
* treat repo content as untrusted input (prompt injection hardening)
* `--no-runner` mode for untrusted repos; runner collection uses a scrubbed env and no network
* schema-validated model outputs only
* no network exfiltration by default

---

## 16. Performance and scalability

* incremental parsing and rendering
* AST caches keyed by:

  * compiler version
  * adapter version
  * toolchain versions
  * config hash
* embeddings (if used) cached locally; never required for determinism
* large repos: parallel parse per file, bounded concurrency

---

## 17. Implementation phases and exit criteria

> **Simplification note:** Consolidated from 6 phases to 4. Original phases 0-2 merged into "Core Compiler," original phases 3-5 merged into "CI & Agent."

### Phase 0 — Deterministic Spine

**Goal:** Prove the core loop works end-to-end with one language.

Deliver:
* TestIR schema + pytest adapter (AST via py-tree-sitter + tree-sitter-python)
* Deterministic renderer with owned regions
* Stable ordering/wrapping rules
* Local sqlite cache + locking

Exit criteria:
* Identical inputs → identical spec bytes
* No-op run produces no diffs
* Touches only impacted blocks
* Safe in pre-commit hooks (no loops)

### Phase 1 — BehaviorGraph + Team Determinism

**Goal:** Make output stable across team members and refactors.

Deliver:
* Anchored behavior_id flow (`@tdd-prose:behavior` comments)
* mapping.snapshot format + merge stability
* Binary eligibility: `behavior` vs `internal`
* Incremental change detection (git diff or hashes)

Exit criteria:
* Refactors do not churn IDs when anchors exist
* Team determinism holds via committed snapshot
* New team member gets identical output from fresh clone

### Phase 2 — CI Integration + Coverage

**Goal:** Make TDD Prose useful in CI pipelines.

Deliver:
* `/tdd-check` — drift detection, mapping integrity, anchor collisions
* `/tdd-coverage` — gap report, orphan tests, weak evidence
* `/tdd-report` — overlay from test results (CTRF preferred)
* PR annotations with behavior diff summaries

Exit criteria:
* CI gates on `needs_review` count
* Pass/fail visible in overlays without spec churn
* PR reviewers see behavior-level change summaries

### Phase 3 — Agent Skill + Expansion

**Goal:** Enable AI assistants to write tests that land cleanly in ledger.

Deliver:
* Structured intent capture (interview → behavior intent JSON)
* Gap-aware test planning against BehaviorGraph
* Anchored test generation aligned to repo conventions
* Validation gates (lint, typecheck, test run)
* Multi-framework expansion: Jest/Vitest, RSpec, Go test
* `--json` output for all commands
* Behavior dependencies + content-hash fingerprints
* Optional: Session protocol, MCP server integration

Exit criteria:
* Agent skill reliably produces tests that land cleanly in ledger
* Newly generated tests produce stable behavior entries on compile
* Consistent ledger behavior across languages/frameworks

---

## 18. Design decisions that matter

* One-directional truth model: tests are truth; prose is projection.
* Behavior anchors in tests are the stability lever; inference is a fallback.
* Mapping snapshot is the team-scale determinism lever; local sqlite is only cache.
* Runtime truth is an overlay artifact, never committed prose.
* Agent skill writes tests, not specs; compiler writes specs, not tests.

---

## 19. Validation strategy

* unit tests for adapters, mapping, and renderer (golden spec fixtures)
* integration fixtures per framework (pytest, jest/vitest) with deterministic outputs
* regression fixtures for mapping snapshot migrations and alias handling
* CLI smoke tests for `sync`, `check`, `coverage`, `report` in CI
