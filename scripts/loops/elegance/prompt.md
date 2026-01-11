# Elegance Review

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

You are here to make this codebase stunningly elegant. The kind of code that if you placed it in front of Jeff Dean or Fabrice Bellard, they would be genuinely impressed by how beautiful, simple, and essential it is. Not impressed by cleverness or features, but by clarity.

This is not a checklist task. You have full latitude to explore, investigate, and use your intelligence as you see fit. Trust your instincts. Follow threads that interest you. Go deep where depth is warranted.

## Context

Read the progress file to see what previous iterations discovered:
```bash
cat ${PROGRESS_FILE}
```

## Exploration

Begin by understanding what you're exploring—whether that's a branch, a PR, a subsystem, or the entire codebase. Get the lay of the land. Understand the core architecture and how the pieces connect before judging any of them.

Spin up subagents freely. When you encounter something that warrants deeper investigation—a suspicious abstraction, a complex subsystem, a pattern you don't fully understand—launch a targeted subagent to explore it thoroughly and report back. Manage your context wisely. Use subagents for depth; reserve your own context for synthesis and judgment.

Look for what doesn't need to exist. Functions that could merge into something cleaner. Abstractions serving no real purpose. Features whose complexity outweighs their value. Machinery solving problems you don't actually have. Code fighting against itself. But also: hidden opportunities. Places where a different algorithm, data structure, or paradigm would make everything click. Ways the system could be recast to expose an obviously simpler solution.

## Output

Append your findings to the progress file, then output:

```
FINDINGS:
- [Sharp observations from this iteration—what you discovered, what's suspect, what could be elegant]

PLATEAU: true/false
REASONING: [Why there's more to uncover, or why you've found what there is to find]
```

Use ultrathink.
