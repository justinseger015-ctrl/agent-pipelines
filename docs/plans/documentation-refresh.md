# Documentation & Command Surface Refresh Plan

**Status:** Draft  
**Author:** Assistant (per Harrison request)  
**Goal:** Ship an intuitive, minimal set of Claude Code commands plus aligned documentation/skills so new users can discover, run, and manage pipelines without memorizing legacy entry points.

---

## Context

- README / commands reference `/sessions`, `/refine`, `/ralph`, `/pipeline`, but the actual “universal launch” UX lives under `/start`. Users must guess which verb launches vs manages vs debugs loops.
- Multiple command docs repeat the same workflows (`/start` vs `/ralph`), increasing drift.
- Marketplace/library UX is coming soon; docs need a place to point users when they want to browse stages/pipelines.
- Specialized subagents (pipeline-architect, stage-creator, pipeline-assembler) are already defined but not surfaced “by name” in user-facing commands.

---

## Target Command Set

| Command | Purpose | Skill(s) | Notes |
|---------|---------|----------|-------|
| `/run` *(alias `/start`)* | Launch or resume any stage/pipeline with smart defaults, discovery, and natural language parsing | `skills/start` | absorb `/ralph`, `/refine` flows as presets; keep resume + provider overrides |
| `/runs manage` *(alias `/sessions`)* | List/status/stop/cleanup sessions | `skills/sessions` | `/runs start` can just call `/run` so there’s one mental model |
| `/runs watch` *(alias `/monitor`)* | Attach, validate state, watch iterations, health check | `skills/monitor` | highlight difference between administer vs actively debug |
| `/pipelines design` | Design, edit, or learn about pipelines/stages | `skills/pipeline-designer`, `skills/pipeline-editor`, `skills/pipeline-creator` | route with verbs “design”, “edit”, “learn”; note which subagent will be invoked |
| `/plan studio` | Planning workbench (PRDs, bead creation, plan refinement, idea generation) | `skills/create-prd`, `skills/create-tasks`, `skills/plan-refinery` | gives one entry point for planning/ideation workflows |
| `/library` *(or `/catalog`)* | Browse/search stages & pipelines (built-in + future marketplace) | new lightweight discovery skill | eventually extends to marketplace install/import |

---

## Documentation Tasks

1. **README**
   - Update the "Commands" table to list the six verbs above, each with 1-line purpose + quick example.
   - Add a short “Command Cheat Sheet” linking to the relevant `commands/*.md`.
   - Mention `/library` in the marketplace overview section once marketplace lands.

2. **Command Docs (`commands/`)**
   - Rename `commands/start.md` → `commands/run.md` (update front matter + headings).
   - Deprecate `/ralph`, `/refine`, `/monitor` docs by converting them to references pointing back to `/run` and `/runs watch` (or remove once plugin command aliases are updated).
   - Update `/sessions` doc to `/runs-manage.md` (or keep filename but change top-level heading to `/runs manage`) and show subcommands consistent with the new naming.
   - Add new `commands/library.md` describing browse/search usage, preview marketplace tie-in.
   - Add `commands/plan-studio.md` summarizing the combined planning flows.

3. **Skill Files**
   - `skills/start/skill.md`: note `/run` as primary trigger; document built-in presets (Ralph loop, refinement, etc.) so we can delete duplicate instructions from `commands/ralph.md`.
   - `skills/sessions/skill.md` and `skills/monitor/skill.md`: update usage sections to reference `/runs manage` / `/runs watch` command strings.
   - Create new lightweight `skills/library/skill.md` (can wrap current discovery logic from start skill until marketplace exists).
   - Add an umbrella skill doc for `/plan studio` that links to create-prd, create-tasks, and plan-refinery workflows.

4. **Agent Visibility**
   - In `commands/pipeline.md` (future `/pipelines design`), explicitly mention when pipeline-architect, stage-creator, or pipeline-assembler agents will be invoked so users understand next steps.
   - Add “Subagent” callouts in relevant command docs to demystify long-running tasks.

5. **Migration Notes**
   - Update `CLAUDE.md` (full reference) and any plugin metadata to reflect the new command names/aliases.
   - Consider adding a short `docs/migrations/command-aliases.md` so existing users know `/start` still works but `/run` is preferred.

---

## Skill & Command Wiring Plan

1. **Aliases & Routing**
   - Update plugin manifest (commands list) so `/run` is canonical and `/start` remains as alias for backward compatibility.
   - Add nested verbs (`/runs manage`, `/runs watch`) – ensure the plugin router can parse the second token (`manage`, `watch`) before dispatching to the correct skill.

2. **Skill Refactors**
   - Extend `skills/start` to include the Q&A currently in `commands/ralph.md` (“where are your tasks?”, “iterations?”) as ready-made Q&A steps.
   - Ensure `skills/sessions` exposes the same actions listed in the revamped `/runs manage` doc.
   - Extract discovery listing from `skills/start` into a shared helper that both `/run` and `/library` can call.

3. **Subagent Triggers**
   - `/pipelines design` continues to route to `pipeline-designer` (which then invokes `pipeline-architect`) and onward to stage creation/assembly once approved.
   - `/plan studio` uses existing skills but surfaces them as options (“Write PRD”, “Generate Tasks”, “Refine Plan”, “Run Idea Wizard”, etc.).

---

## Rollout Checklist

- [ ] Update README command table + cheat sheet.
- [ ] Rename/refresh command docs (`commands/run.md`, `/runs manage`, `/runs watch`, `/plan studio`, `/library`).
- [ ] Update skills usage language + create new `library` skill.
- [ ] Ensure plugin command registry (if any) reflects renamed verbs and aliases.
- [ ] Announce changes in `docs/CHANGELOG.md` or equivalent once shipped.

---

## Open Questions

- Should `/library` also handle install/import (marketplace) in its first iteration, or stay read-only until marketplace ships?
- Do we keep `/start` visible in the command palette as an alias, or hide it entirely after users adapt?
- Should `/runs manage` include direct “start” functionality, or always defer to `/run` to avoid overlapping UX?

---

**Next Action:** green-light this plan, then execute documentation updates + manifest changes in a single docs-focused pull request.
