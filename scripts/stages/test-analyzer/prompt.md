# Test Analyzer

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

## Your Task

You are analyzing the test gaps discovered by the scanner stage. Your job is to:
1. Identify patterns across the gaps
2. Prioritize based on risk and impact
3. Create actionable recommendations

### Step 1: Load Scanner Findings

Read the progress file with all scanner findings:
```bash
cat ${PROGRESS}
```

### Step 2: Analyze Patterns

Look for systemic issues:

**Coverage Patterns:**
- Are certain types of code consistently untested? (e.g., all error handlers)
- Are there entire modules with no tests?
- Is there a testing pyramid imbalance? (too few unit tests, too many E2E?)

**Risk Assessment:**
- Which untested code is most critical to business logic?
- Which code changes most frequently? (check git history)
- Which code handles sensitive operations? (auth, payments, data)

```bash
# Check which files change most frequently (high-risk if untested)
git log --pretty=format: --name-only --since="3 months ago" | sort | uniq -c | sort -rn | head -20
```

### Step 3: Prioritize Gaps

Create a prioritized list based on:

| Factor | Weight | Description |
|--------|--------|-------------|
| Business Criticality | High | Core features, revenue-impacting code |
| Change Frequency | High | Frequently modified = higher risk |
| Complexity | Medium | More branches = more test cases needed |
| Blast Radius | Medium | Shared code affects many features |
| Security Sensitivity | High | Auth, data handling, external APIs |

### Step 4: Generate Recommendations

For each priority tier, recommend:

1. **Immediate** (do first):
   - Critical business logic without tests
   - Security-sensitive code
   - Frequently breaking code

2. **Short-term** (this sprint):
   - High-change-frequency modules
   - Integration points
   - Error handling paths

3. **Backlog** (future work):
   - Utility functions
   - Edge cases in stable code
   - Nice-to-have coverage improvements

### Step 5: Update Progress

Append your analysis to the progress file:

```markdown
## Iteration ${ITERATION} - Test Analysis

### Pattern Analysis

**Systemic Gaps:**
- [Pattern 1: e.g., "Error handlers are consistently untested"]
- [Pattern 2: e.g., "No integration tests for external API calls"]

**Risk Assessment:**
| Area | Risk Level | Reason |
|------|------------|--------|
| auth/ | Critical | Business critical, no tests |
| utils/ | Low | Stable, rarely changes |

### Prioritized Recommendations

#### Immediate Priority
1. [Specific recommendation with file/function]
2. [...]

#### Short-term Priority
1. [...]

#### Backlog
1. [...]

### Testing Strategy Recommendations
- [Any architectural recommendations, e.g., "Add integration test suite for API layer"]
- [Framework suggestions if applicable]
```

### Step 6: Write Status

After analyzing, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Brief explanation",
  "summary": "One paragraph describing your analysis and key findings",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": []
}
```

**Decision guide:**
- `"continue"` - Analysis is incomplete, more patterns to investigate
- `"stop"` - All gaps are analyzed, prioritized, and recommendations are clear
- `"error"` - Insufficient data from scanner stage to analyze

Focus on actionable insights. The next stage will convert these recommendations into specific tasks.
