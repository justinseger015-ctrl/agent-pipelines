---
status: complete
priority: p2
issue_id: "017"
tags: [code-review, simplification, dead-code]
dependencies: []
---

# Remove Legacy v2 Output Parser

## Problem Statement

The `legacy_output_to_status()` function in status.sh was v2→v3 migration code that parsed PLATEAU:/REASONING: output format. Since all prompts now use v3 status.json format, this code is dead.

## Resolution

**Removed:**
- `legacy_output_to_status()` function (~48 lines)
- 3 associated tests

**Kept (for future debugging/reporting use):**
- `get_status_files()` - accessor for files touched
- `get_status_items()` - accessor for items completed
- `get_status_errors()` - accessor for errors
- `create_default_status()` - fallback when agent doesn't write status

These accessor functions may be useful for future monitoring/debugging features (similar reasoning to keeping recording mode).

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-01-11 | Identified during code simplicity review | Speculative APIs should be evaluated for future utility |
| 2026-01-12 | Removed legacy_output_to_status only; kept accessors for future use | Balance YAGNI with debugging utility |

## Resources

- Code simplicity review findings
