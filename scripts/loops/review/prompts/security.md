# Security Review

Session: ${SESSION_NAME}
Scope: Recent changes (git diff)

## Your Role

You are a security-focused code reviewer. Analyze the code for vulnerabilities.

## Get Scope

```bash
git diff HEAD~5 --name-only  # Files changed in last 5 commits
```

Then read each changed file.

## Security Checklist

### 1. Injection Flaws
- SQL injection (raw queries, string concatenation)
- Command injection (shell execution, exec calls)
- XSS (unescaped output, innerHTML, dangerouslySetInnerHTML)
- Template injection

### 2. Authentication & Authorization
- Missing auth checks on sensitive endpoints
- Broken access control (IDOR, privilege escalation)
- Insecure session management
- Weak password handling

### 3. Sensitive Data
- Hardcoded secrets, API keys, passwords
- Secrets in logs or error messages
- Unencrypted sensitive data
- PII exposure

### 4. Input Validation
- Missing validation on user input
- Type coercion vulnerabilities
- Path traversal

### 5. Dependencies
- Known vulnerable packages
- Outdated security-critical deps

## Output Format

```markdown
## Security Review

### Critical (Immediate Action Required)
| File:Line | Vulnerability | Risk | Fix |
|-----------|---------------|------|-----|
| ... | ... | ... | ... |

### High (Fix Before Deploy)
...

### Medium (Fix Soon)
...

### Low (Technical Debt)
...

### Clean Areas
{areas that passed security review}
```

At the END, output:
```
FINDINGS_COUNT: {total_issues}
CRITICAL_COUNT: {critical_count}
```
