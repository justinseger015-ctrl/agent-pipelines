---
status: complete
priority: p3
issue_id: "010"
tags: [code-review, cleanup, deprecation]
dependencies: []
---

# Delete Deprecated parse.sh Instead of Keeping It

## Problem Statement

The file `scripts/lib/parse.sh` is marked "DEPRECATED" but still exists. The comment says "Kept for reference only" but this creates documentation debt. Git history preserves old code - there's no need to keep deprecated files in the active codebase.

## Findings

**Location:** `/Users/harrisonwells/loop-agents/scripts/lib/parse.sh`

**Current state:**
```bash
#!/bin/bash
# DEPRECATED: This file is no longer used in v3
# In v3, agents write status.json directly instead of using output parsing
# Kept for reference only - see scripts/lib/status.sh for the v3 approach
```

**Problem:** Deprecated files in the codebase:
1. Confuse new developers
2. May accidentally get sourced
3. Clutter the directory listing
4. Need to be updated if shared utilities change

## Proposed Solutions

### Solution 1: Delete parse.sh (Recommended)

**Pros:** Clean codebase, git preserves history
**Cons:** None (can always recover from git)
**Effort:** Trivial
**Risk:** None

### Solution 2: Move to archive directory

**Pros:** Available without git archaeology
**Cons:** Still clutters repo
**Effort:** Trivial
**Risk:** None

## Recommended Action

Delete the file. Reference commit hash in migration docs if anyone needs it.

## Technical Details

**Affected files:**
- `scripts/lib/parse.sh` (delete)

## Acceptance Criteria

- [ ] parse.sh deleted from codebase
- [ ] No other files source parse.sh
- [ ] Tests still pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code review | Deprecated = delete, git has history |
