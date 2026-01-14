# Final Features: Hooks, Marketplace, Pipeline Cycles

> Three features that complete agent-pipelines as a production-ready, community-driven orchestrator.

---

## Overview

| Feature | What | Why |
|---------|------|-----|
| **Hooks** | Lifecycle events (shell, webhook, spawn) | Notifications, approvals, nested pipelines |
| **Marketplace** | Built-in + user + community workflows | Easy discovery, sharing, growing library |
| **Pipeline Cycles** | Run entire pipelines N times | Multi-agent workflows that repeat |

---

## Part 1: Hook System Implementation

**Status:** Design complete (`unified-hooks-spec.md`), needs implementation
**Effort:** Medium - spec is detailed, implementation is straightforward

### What We Have

The unified hook spec defines:
- **3 action types:** shell, webhook, spawn
- **2 modes:** await (blocking) vs fire-and-forget
- **6 hook points:** on_session_start, on_iteration_start, on_iteration_complete, on_stage_complete, on_session_complete, on_error
- **Conditions:** `when:` clauses with variable interpolation
- **Configuration:** per-stage, per-pipeline, and global hooks

### Implementation Plan

#### Phase 1: Core Infrastructure

**New files:**
```
scripts/lib/hooks.sh          # Main hook execution logic
scripts/lib/callback.sh       # Webhook callback server
```

**Key functions:**
```bash
# hooks.sh
execute_hooks()           # Main entry point, called by engine
execute_shell_action()    # Run shell commands
execute_webhook_action()  # Send HTTP requests
execute_spawn_action()    # Launch child pipelines
eval_condition()          # Evaluate `when:` clauses
resolve_variables()       # Replace ${VAR} in commands/bodies
```

**Engine integration points:**
```bash
# In engine.sh run_stage()
execute_hooks "on_session_start" "$hooks_config"   # Before first iteration
# ... iteration loop ...
execute_hooks "on_iteration_start" "$hooks_config"  # Before claude call
# ... run claude ...
execute_hooks "on_iteration_complete" "$hooks_config"  # After success
# ... or on error ...
execute_hooks "on_error" "$hooks_config"  # On failure

execute_hooks "on_stage_complete" "$hooks_config"  # After stage ends
execute_hooks "on_session_complete" "$hooks_config"  # After pipeline ends
```

#### Phase 2: Shell Actions

The simplest action type. Already have patterns in existing scripts.

```yaml
hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/backup-progress.sh ${PROGRESS}"
```

**Implementation:**
- Parse command from action config
- Resolve variables (${PROGRESS}, ${SESSION}, etc.)
- Execute with `bash -c`
- If `await: true`, use `timeout` wrapper
- Capture exit code for `${LAST_HOOK_STATUS}`

#### Phase 3: Webhook Actions

For notifications (Slack, Discord, Pagerduty) and external integrations.

```yaml
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      method: POST
      body:
        text: "Pipeline ${SESSION} completed"
```

**Implementation:**
- Use `curl` for HTTP requests
- Resolve variables in url, headers, body
- JSON encode body
- For `await: true`, start callback server

**Callback server (for approvals):**
- Simple HTTP server on localhost:${callback_port}
- Generates unique token per callback
- Blocks until POST received or timeout
- Returns response body as `${HOOK_RESPONSE}`

#### Phase 4: Spawn Actions

Launch child pipelines from hooks. This is powerful—enables recursive orchestration.

```yaml
hooks:
  on_iteration_complete:
    - type: spawn
      pipeline: code-review
      await: true
      inputs:
        files_changed: "${CHANGED_FILES}"
      when: "${ITERATION} % 10 == 0"
```

**Implementation:**
- Create child directory: `{session_dir}/children/{hook_point}-{iteration}/`
- Write inputs to child's `inputs.json`
- Call `engine.sh` recursively with child session
- If `await: true`, wait for completion and capture output
- Store output as `${SPAWN_OUTPUT}`

#### Phase 5: Conditions

The `when:` clause makes hooks conditional.

```yaml
when: "${ITERATION} % 10 == 0"
when: "${STAGE} == 'plan' && ${ITERATION} > 5"
when: "${LAST_DECISION} == 'stop'"
```

**Implementation:**
- Resolve variables in condition string
- Use `expr` or bash arithmetic for evaluation
- Support: `==`, `!=`, `>`, `<`, `>=`, `<=`, `%`, `&&`, `||`

#### Phase 6: Global Hooks

Hooks that apply to all pipelines unless disabled.

```yaml
# ~/.config/agent-pipelines/hooks.yaml
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Pipeline finished" }
```

**Implementation:**
- Check for global config at startup
- Merge with pipeline/stage hooks (global runs after local by default)
- Honor `disable_global_hooks: true` in stage/pipeline config

### Testing Strategy

1. **Unit tests** for each action type (mock curl, mock engine calls)
2. **Integration tests** with actual shell commands
3. **End-to-end test** pipeline with all hook points
4. **Webhook test** using httpbin.org or local mock server

---

## Part 2: Marketplace

**Status:** Conceptual—needs design decisions
**Effort:** Medium to High depending on ambition

### Vision

> "See someone's workflow on Twitter, take the prompts, build a pipeline that does exactly that. Tag them about it."

This means:
1. **Shareable units** - stages and pipelines as standalone packages
2. **Easy import** - from URL, from prompt text, from marketplace
3. **Attribution** - credit original creators
4. **Discovery** - browse, search, filter community contributions

### Design Decisions

#### Decision 1: What's Shareable?

| Unit | Description | Shareable As |
|------|-------------|--------------|
| Stage | Single loop type (prompt + config) | Directory: `stage.yaml` + `prompt.md` |
| Pipeline | Multi-stage workflow | File: `pipeline.yaml` |
| Skill | Claude Code skill extension | Directory: `SKILL.md` + workflows/ |
| Bundle | Stage + dependencies + examples | Archive: `.agp` file (tar.gz) |

**Recommendation:** Start with Stages as the primary shareable unit. They're self-contained and the most useful building block.

#### Decision 2: Where Does the Registry Live?

**Option A: Central GitHub Repository** (Recommended for v1)
```
github.com/agent-pipelines/marketplace/
├── registry.json           # Index of all stages/pipelines
├── stages/
│   ├── code-review/
│   │   ├── stage.yaml
│   │   └── prompt.md
│   ├── bug-discovery/
│   └── ...
└── pipelines/
    ├── full-refine.yaml
    └── ...
```

Pros:
- Simple, familiar workflow (PRs to contribute)
- Version control built-in
- GitHub Actions can validate contributions
- Works offline once cloned

Cons:
- Single point of control
- Merge queue for contributions

**Option B: Distributed Registry (URLs)**
```json
{
  "registries": [
    "https://github.com/agent-pipelines/marketplace",
    "https://github.com/someuser/my-pipelines",
    "https://raw.githubusercontent.com/..."
  ]
}
```

Pros:
- Anyone can host their own registry
- No gatekeeping
- Federated discovery

Cons:
- More complex resolution
- Trust/verification challenges

**Option C: Hybrid**
- Official marketplace for curated stages
- Personal registries for experiments
- Import directly from any URL

**Recommendation:** Option C (Hybrid) with official marketplace as default.

#### Decision 3: Import Mechanism

```bash
# From official marketplace
./scripts/run.sh marketplace install code-review

# From URL
./scripts/run.sh marketplace install https://github.com/user/stage --as my-review

# From prompt text (the Twitter use case!)
./scripts/run.sh marketplace create --from-prompt "..."
```

The **from-prompt** feature is key for the Twitter workflow:
1. User pastes a prompt they saw
2. System generates a `stage.yaml` and `prompt.md`
3. User can run it immediately or refine

#### Decision 4: Package Format

**Simple (just files):**
```
my-stage/
├── stage.yaml      # Config with metadata
├── prompt.md       # The prompt template
├── README.md       # Usage instructions (optional)
└── examples/       # Example inputs/outputs (optional)
```

**Enhanced stage.yaml for marketplace:**
```yaml
name: code-review
version: 1.0.0
description: Automated code review with security focus
author:
  name: Harrison Wells
  twitter: "@hwells"
  github: "hwells4"

tags: [review, security, quality]
requires:
  min_version: "0.5.0"
  commands: [git, jq]

termination:
  type: judgment
  consensus: 2

# Attribution for derivatives
based_on:
  name: original-review
  author: "@someone"
  url: "https://..."
```

### Implementation Plan

#### Phase 1: Local Package Management

Before external marketplace, support local packages.

```bash
# List installed stages (built-in + local)
./scripts/run.sh stages list

# Show stage info
./scripts/run.sh stages info code-review

# Copy a stage for customization
./scripts/run.sh stages fork code-review my-review
```

**Implementation:**
- `scripts/lib/packages.sh` - package discovery and metadata
- Scan `scripts/stages/` for built-in, `~/.config/agent-pipelines/stages/` for user

#### Phase 2: URL Import

Import stages directly from URLs.

```bash
# Install from GitHub
./scripts/run.sh marketplace install \
  https://github.com/user/repo/tree/main/stages/cool-review

# Install from raw URL
./scripts/run.sh marketplace install \
  https://gist.githubusercontent.com/user/abc/raw/stage.yaml

# Install with alias
./scripts/run.sh marketplace install https://... --as security-review
```

**Implementation:**
- `scripts/lib/import.sh` - fetch, validate, install stages
- Support GitHub URLs, raw URLs, gist URLs
- Validate `stage.yaml` schema
- Install to `~/.config/agent-pipelines/stages/{name}/`

#### Phase 3: Official Marketplace

Central repository with curated stages.

**Registry structure:**
```json
{
  "version": "1.0.0",
  "updated": "2026-01-13T...",
  "stages": [
    {
      "name": "code-review",
      "version": "1.2.0",
      "description": "Thorough code review with security focus",
      "author": {"name": "Harrison Wells", "twitter": "@hwells"},
      "tags": ["review", "security"],
      "downloads": 1234,
      "rating": 4.8,
      "url": "https://github.com/agent-pipelines/marketplace/tree/main/stages/code-review"
    }
  ],
  "pipelines": [...]
}
```

**Commands:**
```bash
# Search marketplace
./scripts/run.sh marketplace search "code review"
./scripts/run.sh marketplace search --tag=security

# Browse categories
./scripts/run.sh marketplace browse
./scripts/run.sh marketplace browse --category=review

# Install from marketplace
./scripts/run.sh marketplace install code-review

# Update installed
./scripts/run.sh marketplace update

# Publish (opens PR flow)
./scripts/run.sh marketplace publish ./my-stage
```

**Implementation:**
- `scripts/lib/marketplace.sh` - registry interaction
- Cache registry locally (`~/.config/agent-pipelines/marketplace-cache.json`)
- Refresh on `marketplace search` or `marketplace update`

#### Phase 4: Create from Prompt

The killer feature: generate stages from prompt text.

```bash
# Interactive
./scripts/run.sh marketplace create

# From text
./scripts/run.sh marketplace create --from-prompt "You are a code reviewer..."

# From file
./scripts/run.sh marketplace create --from-file ~/prompts/review.md
```

**Implementation:**
1. Take prompt text as input
2. Use Claude to analyze and generate:
   - `stage.yaml` with appropriate termination strategy
   - `prompt.md` with template variables
   - README.md with usage instructions
3. Allow user to refine before saving
4. Optionally publish to marketplace

**Prompt for generation:**
```markdown
You are helping create an agent-pipelines stage from a user's prompt.

Given this prompt:
"""
{user_prompt}
"""

Generate:
1. A stage.yaml with:
   - Appropriate name (kebab-case)
   - Good description
   - Termination strategy (fixed for simple, judgment for iterative)
   - Any special configuration

2. A prompt.md that:
   - Uses template variables (${CTX}, ${PROGRESS}, ${STATUS})
   - Includes clear instructions for status.json output
   - Preserves the user's core intent

3. A README.md with usage examples
```

#### Phase 5: Attribution & Social

Enable the Twitter workflow with proper attribution.

**When creating from someone's prompt:**
```yaml
# Generated stage.yaml
name: twitter-review
based_on:
  source: twitter
  author: "@clever_dev"
  tweet: "https://twitter.com/clever_dev/status/..."
  date: "2026-01-13"
```

**When sharing:**
```bash
# Generate shareable tweet text
./scripts/run.sh marketplace share twitter-review

# Output:
# "Built a Claude Code pipeline from @clever_dev's brilliant review prompt!
# Try it: ./scripts/run.sh marketplace install https://...
# #ClaudeCode #AgentPipelines"
```

**Attribution chain:**
- Track `based_on` through forks
- Credit original authors in README
- Optional: notify via Twitter API (requires auth)

### Directory Structure

```
scripts/
├── lib/
│   ├── packages.sh      # Local package discovery
│   ├── import.sh        # URL import logic
│   ├── marketplace.sh   # Registry interaction
│   └── create.sh        # Generate from prompt

~/.config/agent-pipelines/
├── stages/              # User-installed stages
│   ├── cool-review/
│   └── ...
├── pipelines/           # User pipelines
├── marketplace-cache.json
└── config.yaml          # User preferences
```

### Example Workflows

**1. Twitter → Pipeline in 60 seconds:**
```bash
# See cool prompt on Twitter, copy it
./scripts/run.sh marketplace create --from-prompt "You are an expert code reviewer..."
# Claude generates stage files
# "Created: twitter-review in ~/.config/agent-pipelines/stages/"

# Run it immediately
./scripts/run.sh twitter-review my-feature 5

# Share back
./scripts/run.sh marketplace share twitter-review
# "Tweet text copied to clipboard!"
```

**2. Browse and install:**
```bash
./scripts/run.sh marketplace search "bug"
# Results:
# 1. bug-discovery - Fresh-eyes bug exploration (★4.9, 2.3k downloads)
# 2. bug-triage - Bug categorization and priority (★4.7, 1.8k downloads)
# 3. bug-fix - Systematic bug fixing workflow (★4.5, 1.2k downloads)

./scripts/run.sh marketplace install bug-discovery
# Installed to ~/.config/agent-pipelines/stages/bug-discovery
```

**3. Fork and customize:**
```bash
./scripts/run.sh stages fork bug-discovery my-bug-hunter
# Copied to ~/.config/agent-pipelines/stages/my-bug-hunter

# Edit prompt.md with your customizations
vim ~/.config/agent-pipelines/stages/my-bug-hunter/prompt.md

# Run your version
./scripts/run.sh my-bug-hunter feature-x 10
```

**4. Publish your creation:**
```bash
./scripts/run.sh marketplace publish ~/.config/agent-pipelines/stages/my-bug-hunter
# Validates stage structure
# Opens GitHub PR to official marketplace
# Adds attribution for `based_on` sources
```

---

## Implementation Priority

### Must Have (v1.0)

**Hooks:**
1. ✓ Shell actions (fire-and-forget)
2. ✓ Shell actions with await
3. ✓ Conditions (when clauses)
4. ✓ Hook points in engine

**Marketplace:**
1. ✓ Local package discovery (`stages list`)
2. ✓ URL import (`marketplace install <url>`)
3. ✓ Create from prompt (`marketplace create`)

### Nice to Have (v1.1)

**Hooks:**
- Webhook actions (notifications)
- Callback server (approvals)
- Global hooks

**Marketplace:**
- Official registry with search
- Browse by category/tag
- Ratings and download counts

### Future (v2.0)

**Hooks:**
- Spawn actions (nested pipelines)
- Complex condition logic
- Hook debugging/tracing

**Marketplace:**
- Attribution chains
- Twitter integration
- Automatic updates
- Dependency resolution

---

## Open Questions

### Hooks

1. **Parallel hook execution?** Should fire-and-forget hooks run in parallel or sequence?
   - Suggestion: Parallel by default, `sequential: true` option

2. **Hook timeout defaults?** What's reasonable?
   - Suggestion: 5 minutes for shell, 1 hour for webhook await, 1 hour for spawn

3. **Callback server security?** How to handle if user's network exposes localhost?
   - Suggestion: Token validation, option for external callback relay service

### Marketplace

1. **Namespace collisions?** What if two stages have the same name?
   - Suggestion: Namespace by author (`hwells/code-review`) or require unique names

2. **Version pinning?** How to handle updates that break compatibility?
   - Suggestion: Semantic versioning, lock file for installed versions

3. **Private stages?** Should marketplace support private/enterprise registries?
   - Suggestion: Yes, via `registries:` config pointing to private URLs

4. **Quality control?** How to prevent low-quality submissions to official marketplace?
   - Suggestion: Review process for official, anything goes for personal registries

---

## Success Metrics

**Hooks:**
- [ ] Can notify Slack on session complete
- [ ] Can require human approval between stages
- [ ] Can spawn review pipeline every 10 iterations
- [ ] Global hooks work across all pipelines

**Marketplace:**
- [ ] Can install stage from GitHub URL in < 30 seconds
- [ ] Can create stage from Twitter prompt in < 2 minutes
- [ ] Can search and install from official marketplace
- [ ] Attribution preserved through fork chain
