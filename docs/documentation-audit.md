# Progress: doc-audit-5

Verify: (none)

## Codebase Patterns
(Add patterns discovered during implementation here)

---

## Iteration 1 - Documentation Audit

- File: `CLAUDE.md`
  Missing: Commands passthrough feature, full input system coverage (`inputs.from_initial`, `inputs.from_previous_iterations`, `inputs.from_parallel`) and `${CONTEXT}`/`${OUTPUT}` in the template variable table; `context.json` examples omit the `commands` and full `inputs` object.
  Recommended: Add a commands passthrough section with `context.json` examples, expand the input system section to include initial inputs + previous iterations + parallel outputs, and update the template variable list to include `${CONTEXT}` and `${OUTPUT}`.
  Priority: High
- File: `skills/pipeline-designer/SKILL.md`
  Missing: Spec format omits `context`, `commands`, and parallel blocks; provider/model list excludes Codex `o3`, `o3-mini`, `o4-mini`.
  Recommended: Expand the architecture spec format to cover `context`, `commands`, and `parallel` block structure plus the full Codex model list.
  Priority: High
- File: `skills/pipeline-designer/references/v3-system.md`
  Missing: Uses legacy `context.json` schema, `${INPUTS}` variables, and `loop:` pipeline keys; no mention of `inputs.from_initial`, `inputs.from_parallel`, or `commands` passthrough.
  Recommended: Replace with the current `context.json` structure (stage/paths/inputs/limits/commands), update variable list to match the feature reference, and switch pipeline examples to `stage:` with modern inputs.
  Priority: High
- File: `skills/pipeline-designer/workflows/questions.md`
  Missing: References `${INPUTS}` and `loop:` examples that no longer match the input system.
  Recommended: Update the Q&A snippets to show `inputs.from_stage` access via `context.json` and modern `stage:` pipeline syntax.
  Priority: Medium
- File: `skills/pipeline-creator/references/variables.md`
  Missing: Legacy `context.json` structure and `${INPUTS}` variable guidance; no `inputs.from_initial` or `from_parallel` examples; commands passthrough absent.
  Recommended: Align with the feature reference: document the full `inputs` object and `commands` passthrough, and remove `${INPUTS}` guidance in favor of `context.json` access.
  Priority: High
- File: `skills/pipeline-editor/SKILL.md`
  Missing: Editable properties omit `commands` and parallel blocks; model list for Codex omits `o3`, `o3-mini`, `o4-mini`.
  Recommended: Add `commands` to stage properties, add parallel block editing guidance, and update model list.
  Priority: Medium
- File: `scripts/pipelines/SCHEMA.md`
  Missing: Provider list is outdated (`claude-code`, `gemini`), `parallel: false` is marked unimplemented, and schema uses legacy `completion`/`loop`/`${SESSION}` variables; no commands passthrough or expanded input system.
  Recommended: Rewrite schema to match current pipeline spec: `stage:` keys, `termination` blocks, real parallel block structure, supported providers (claude/codex), `${SESSION_NAME}` variables, and `commands`/`inputs` coverage.
  Priority: High
- File: `scripts/stages/*/prompt.md` (all prompts except `scripts/stages/ralph/prompt.md` and `scripts/stages/elegance/prompt.md`)
  Missing: `${CONTEXT}` placeholder, so context injection via CLI/env/stage config is effectively ignored for most stages.
  Recommended: Add a consistent `${CONTEXT}` block near the top of each prompt template.
  Priority: Medium
- File: `scripts/stages/bug-triage/prompt.md`, `scripts/stages/elegance/prompt.md`, `scripts/stages/ralph/prompt.md`, `scripts/stages/code-review/prompt.md`, `scripts/stages/test-review/prompt.md`, `scripts/stages/test-analyzer/prompt.md`, `scripts/stages/test-planner/prompt.md`, `scripts/stages/tdd-plan-refine/prompt.md`
  Missing: Input-system guidance for stage-to-stage outputs or initial inputs, even though pipelines wire `inputs:` for these stages.
  Recommended: Add a short “Read inputs from context.json” section using `jq -r '.inputs.from_stage'` or `jq -r '.inputs.from_initial'` to ensure downstream stages consume upstream outputs.
  Priority: High
- File: `scripts/stages/ralph/prompt.md`, `scripts/stages/test-review/prompt.md`
  Missing: Commands passthrough usage; tests are referenced generically or hardcoded rather than sourced from `.commands` in `context.json`.
  Recommended: Replace hardcoded test invocations with `jq -r '.commands.test' ${CTX}` patterns and document optional `format/types/lint` commands.
  Priority: High

## Iteration 2 - Documentation Audit

- File: `skills/pipeline-creator/SKILL.md`
  Missing: Stage creation/spec guidance omits `context`, `commands`, and input/parallel block requirements; model options imply only Claude and don't mention Codex models.
  Recommended: Expand spec expectations and stage-creator prompt to include provider + full Codex model list, `context`, `commands`, and `inputs`/parallel block fields.
  Priority: High
- File: `skills/pipeline-creator/workflows/create.md`
  Missing: Spec validation and stage templates only require `model` with `{opus|sonnet|haiku}`; no guidance for provider selection, `context`, `commands`, initial inputs, or parallel blocks.
  Recommended: Update spec checklist and templates to cover provider + Codex model options, `context`/`commands`, and `inputs` (`from_initial`, `from_stage`, `from_parallel`) including parallel block assembly.
  Priority: High
- File: `skills/pipeline-designer/workflows/build.md`
  Missing: Requirements summary and presentation template omit provider choice, commands passthrough, context injection, initial inputs, and parallel block design; model preference only lists Claude options.
  Recommended: Add prompts and architecture fields for provider/model (Codex list), `context`, command passthrough needs, `inputs` (including parallel outputs), and parallel block structure.
  Priority: Medium
- File: `scripts/stages/improve-plan/prompt.md`
  Missing: Input system guidance; prompt relies on filesystem search instead of `inputs.from_initial`/`inputs.from_stage`/`inputs.from_parallel` in `context.json`.
  Recommended: Add a context-driven input section using `jq -r '.inputs.from_initial[]' ${CTX}` and `inputs.from_stage`/`from_parallel` before scanning the repo.
  Priority: High
- File: `scripts/stages/tdd-create-beads/prompt.md`
  Missing: Pipeline inputs and commands passthrough guidance; plan discovery is hardcoded to `plans/*.md`, and test instructions don't reference `.commands` in `context.json`.
  Recommended: Read plan files via `inputs.from_initial`/`inputs.from_stage` and use `jq -r '.commands.test' ${CTX}` when available for test execution.
  Priority: High

## Iteration 3 - Documentation Audit

- File: `commands/ralph.md`
  Missing: No mention of provider/model/context overrides or initial inputs; test guidance doesn't reference `context.json` command passthrough.
  Recommended: Add an advanced options section covering `--provider`, `--model`, `--context`, `--input` and note that validation should use `.commands.*` from `context.json` when configured.
  Priority: Medium
- File: `commands/sessions.md`
  Missing: Session start examples omit provider/model/context overrides and initial input files.
  Recommended: Add optional flag examples (`--provider`, `--model`, `--context`, `--input`) so users can leverage provider selection and input injection when starting sessions.
  Priority: Medium
- File: `commands/refine.md`
  Missing: Assumes plans live in `docs/plans/` and doesn't mention `--input` or `--context` overrides.
  Recommended: Mention `--input` for plan files and document provider/model/context overrides for refine runs.
  Priority: Medium
- File: `commands/monitor.md`
  Missing: State tree ignores parallel block directories and `context.json` `inputs`/`commands` fields.
  Recommended: Update the “What Gets Checked” tree and validation checklist to include `parallel-*` provider directories and verify `inputs`/`commands` in `context.json`.
  Priority: Medium
- File: `skills/monitor/SKILL.md`
  Missing: Key files/health checks don’t cover parallel block layout or `context.json` `inputs`/`commands` fields.
  Recommended: Expand the monitored file tree and health checks to include `parallel-*` directories and validation of `inputs`/`commands`.
  Priority: Medium
- File: `skills/sessions/SKILL.md`
  Missing: Start-session guidance omits provider/model/context overrides and initial input flags.
  Recommended: Add `--provider`, `--model`, `--context`, and `--input` options in quick start and validation sections.
  Priority: Medium
- File: `scripts/pipelines/design-refine.yaml`
  Missing: Uses legacy `loop:` keys and `defaults` structure instead of current `stage:` schema.
  Recommended: Update to the modern pipeline schema (`stage:`) and align with current input/command conventions.
  Priority: High

## Iteration 4 - Documentation Audit

- File: `CLAUDE.md`
  Missing: Provider section omits the full Codex model roster (`o3`, `o3-mini`, `o4-mini`) and the `CODEX_MODEL` environment variable.
  Recommended: Add a short Codex model table plus `CODEX_MODEL` to the provider/env var coverage so provider selection matches the feature reference.
  Priority: Medium
- File: `skills/pipeline-editor/SKILL.md`
  Missing: Prompt editing guidance only calls out `${CTX}`, `${PROGRESS}`, `${STATUS}` and omits `${CONTEXT}`/`${OUTPUT}`, so context injection and output path placeholders can be dropped.
  Recommended: Update the prompt.md preservation list to include `${CONTEXT}` and `${OUTPUT}` alongside the other v3 variables.
  Priority: Medium
- File: `commands/ideate.md`, `commands/robot-mode.md`, `commands/readme-sync.md`
  Missing: No advanced options for provider/model overrides, context injection, or initial inputs.
  Recommended: Add an “Advanced options” section that documents `--provider`, `--model`, `--context`, and `--input` (plus env var equivalents) for these pipelines.
  Priority: Medium
- File: `scripts/stages/research-plan/prompt.md`
  Missing: Hardcoded plan paths (`tdd-prose-plan.md`, `plans/*.md`) ignore `inputs.from_initial`/`inputs.from_stage` in `context.json`.
  Recommended: Add a context-driven plan discovery step that reads `inputs.from_initial` (or stage inputs) before falling back to filesystem search.
  Priority: High
- File: `scripts/stages/idea-wizard/prompt.md`, `scripts/stages/idea-wizard-loom/prompt.md`
  Missing: Ideation prompts never reference `inputs.from_initial`/`inputs.from_stage`, so CLI `--input` context is ignored.
  Recommended: Add a short “Read inputs from context.json” section and incorporate those files into the ideation brief.
  Priority: Medium

## Iteration 5 - Documentation Audit

- File: `docs/research/parallel-blocks-feature.md`
  Missing: Feature reference file is absent, so the canonical parallel-blocks behavior/spec can’t be validated.
  Recommended: Restore or relocate the reference document (and update links) so audits can cite the authoritative spec.
  Priority: High
- File: `commands/sessions.md`
  Missing: Session resource list ignores parallel block layout (`parallel-*` dirs, provider subtrees, `manifest.json`/`resume.json`).
  Recommended: Expand the resource tree with parallel block directories and per-provider progress/state locations.
  Priority: Medium
- File: `skills/sessions/SKILL.md`
  Missing: Session resources section omits parallel block directories and provider-specific progress/state/manifest files.
  Recommended: Add the parallel-block resource layout (`parallel-*`, `manifest.json`, provider subdirs) to keep guidance current.
  Priority: Medium
- File: `scripts/stages/robot-mode/prompt.md`
  Missing: No guidance to read `inputs.from_initial` or `inputs.from_stage`, so `--input` or upstream outputs are ignored.
  Recommended: Add a “Read inputs from context.json” step that ingests `.inputs.from_initial` and `.inputs.from_stage` before analysis.
  Priority: Medium
- File: `scripts/stages/readme-sync/prompt.md`
  Missing: Input system is ignored; prompt never reads `.inputs.from_initial` or `.inputs.from_stage` for injected docs.
  Recommended: Add a context-driven input section that reads `context.json` inputs before repo scans.
  Priority: Medium
- File: `CLAUDE.md`
  Missing: Template variables omit `${OUTPUT_PATH}` even though stages still use `output_path`.
  Recommended: Add `${OUTPUT_PATH}` to the legacy variables table with a note about `stage.yaml` `output_path`.
  Priority: Low
