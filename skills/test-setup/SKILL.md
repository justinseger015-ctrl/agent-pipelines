---
name: test-setup
description: Initialize a professional test suite for any project. Use when user says "set up tests", "add testing", "configure tests", "test foundation", or when starting a new project that needs testing infrastructure.
---

## What This Skill Produces

A complete, production-ready test suite foundation including:
1. Proper directory structure mirroring source code
2. Framework configuration (jest, pytest, rspec, etc.)
3. Shared fixtures and test utilities
4. Example tests demonstrating team conventions
5. A `.test-conventions.md` documenting standards

This is NOT about writing tests for existing code. It's about setting up the infrastructure so tests can be written properly.

## Core Principles (From Industry Research)

### The Testing Pyramid
- **Unit tests (80%)**: Fast, isolated, test individual functions/classes
- **Integration tests (15%)**: Test components working together
- **E2E tests (5%)**: Critical user journeys only

### Real-World Scale Reference
- Shopify: 300,000 tests
- SQLite: 248+ million test instances (380:1 test-to-code ratio)
- Google: Billions of tests weekly
- **Normal ratio**: 0.5:1 to 1.5:1 (test code to production code)
- **Target coverage**: 70-80% on critical paths

### Key Standards
- **One test file per source file** as default
- **AAA pattern**: Arrange-Act-Assert structure
- **Mirror directory structure**: Tests follow source layout
- **Sociable unit tests**: Use real collaborators when practical, mock external dependencies

## Process

### 1. Detect Project Type

Analyze the codebase to determine:
```bash
# Check for project indicators
ls package.json pyproject.toml setup.py Gemfile Cargo.toml go.mod pom.xml build.gradle 2>/dev/null

# Check existing test setup
ls -d test* tests spec __tests__ 2>/dev/null

# Check for existing test config
ls jest.config.* pytest.ini setup.cfg .rspec vitest.config.* 2>/dev/null
```

### 2. Ask Clarifying Questions

Use `AskUserQuestion` to understand preferences:

```json
{
  "questions": [{
    "question": "What type of project is this?",
    "header": "Project Type",
    "options": [
      {"label": "Node.js/TypeScript", "description": "Jest, Vitest, or similar"},
      {"label": "Python", "description": "pytest with fixtures"},
      {"label": "Ruby/Rails", "description": "RSpec with factories"},
      {"label": "Go", "description": "Built-in testing package"}
    ],
    "multiSelect": false
  }, {
    "question": "What's your testing philosophy preference?",
    "header": "Test Style",
    "options": [
      {"label": "Pyramid (unit-heavy)", "description": "Many fast unit tests, fewer integration (Recommended)"},
      {"label": "Trophy (integration-heavy)", "description": "Focus on integration tests (Kent C. Dodds style)"},
      {"label": "Minimal", "description": "Just the essentials, grow as needed"}
    ],
    "multiSelect": false
  }]
}
```

### 3. Create Directory Structure

**Pattern A: Separate test directory (default for most projects)**
```
project/
├── src/
│   └── services/
│       └── auth.ts
└── tests/
    ├── unit/
    │   └── services/
    │       └── auth.test.ts
    ├── integration/
    ├── e2e/
    ├── fixtures/
    │   └── users.json
    ├── helpers/
    │   └── test-utils.ts
    └── setup.ts
```

**Pattern B: Co-located tests (frontend/component projects)**
```
src/
├── components/
│   ├── Button.tsx
│   └── Button.test.tsx
├── services/
│   ├── api.ts
│   └── api.test.ts
└── __tests__/
    ├── integration/
    └── e2e/
```

### 4. Create Framework Configuration

Use the appropriate template from `references/`:

| Project Type | Config File | Reference |
|--------------|-------------|-----------|
| Node.js/TS | jest.config.js or vitest.config.ts | references/jest-config.md |
| Python | pytest.ini + conftest.py | references/pytest-config.md |
| Ruby | .rspec + spec_helper.rb | references/rspec-config.md |
| Go | (built-in, no config needed) | references/go-testing.md |

### 5. Create Shared Test Utilities

Every test suite needs:
- **Setup/teardown helpers**: Database cleanup, mock reset
- **Fixture loading**: Consistent test data
- **Custom assertions**: Domain-specific matchers
- **Factory functions**: Generate test objects

### 6. Create Example Tests

Write 2-3 example tests demonstrating:
- Proper AAA structure
- Naming conventions
- Fixture usage
- Mock patterns (when appropriate)

Example (TypeScript/Jest):
```typescript
// tests/unit/services/calculator.test.ts
import { Calculator } from '../../../src/services/calculator';

describe('Calculator', () => {
  describe('add', () => {
    it('returns sum of two positive numbers', () => {
      // Arrange
      const calculator = new Calculator();

      // Act
      const result = calculator.add(2, 3);

      // Assert
      expect(result).toBe(5);
    });

    it('handles negative numbers', () => {
      const calculator = new Calculator();
      expect(calculator.add(-1, 5)).toBe(4);
    });
  });
});
```

### 7. Create Metrics Configuration

Save to project root as `.test-metrics.json`:

```json
{
  "version": 1,
  "targets": {
    "pass_rate": { "healthy": 99, "warning": 95, "critical": 90 },
    "flakiness_percent": { "healthy": 1, "warning": 5, "critical": 10 },
    "unit_test_time_seconds": { "healthy": 300, "warning": 600, "critical": 900 },
    "full_suite_time_seconds": { "healthy": 1800, "warning": 3600, "critical": 7200 },
    "coverage_percent": { "healthy": 80, "warning": 60, "critical": 40 },
    "skipped_tests_percent": { "healthy": 1, "warning": 5, "critical": 10 }
  },
  "commands": {
    "test": "npm test",
    "test_unit": "npm run test:unit",
    "test_integration": "npm run test:integration",
    "coverage": "npm test -- --coverage"
  }
}
```

Adjust targets based on project type:
- **New project**: Start with relaxed targets, tighten over time
- **Legacy project**: Set realistic targets based on current state
- **Critical system**: Stricter targets (99%+ pass rate, <1% flakiness)

This config is read by `/test-audit` to compare actual metrics against targets.

### 8. Create Conventions Document

Save to project root as `.test-conventions.md`:

```markdown
# Test Conventions

## Structure
- One test file per source file
- Tests mirror source directory structure
- Unit tests in `tests/unit/`, integration in `tests/integration/`

## Naming
- Test files: `{source-name}.test.{ext}`
- Describe blocks: Feature or class name
- It blocks: Start with verb (returns, throws, handles)

## Patterns
- Use AAA: Arrange-Act-Assert
- One assertion per test (logical behavior)
- Mock external dependencies, use real implementations for internal code

## Coverage Targets
- Unit: 80%+ on business logic
- Integration: Key pathways covered
- E2E: Critical user journeys only

## Running Tests
- `npm test` / `pytest` / `rspec` - Run all
- `npm test -- --watch` - Watch mode
- `npm test -- --coverage` - Coverage report
```

### 8. Update Package/Project Configuration

Add test scripts to package.json/pyproject.toml/etc:

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage",
    "test:unit": "jest tests/unit",
    "test:integration": "jest tests/integration"
  }
}
```

### 10. Confirm Output

Tell the user:
```
✅ Test suite foundation created:

📁 Structure:
- tests/unit/          (unit tests)
- tests/integration/   (integration tests)
- tests/fixtures/      (shared test data)
- tests/helpers/       (utilities)

📄 Configuration:
- jest.config.js       (framework config)
- .test-conventions.md (team standards)
- .test-metrics.json   (health targets for /test-audit)

📝 Examples:
- tests/unit/example.test.ts

Next steps:
- Run tests: npm test
- Add coverage: npm test -- --coverage
- Write more tests following the examples
- Run /test-audit to check quality and compare against targets
```

## Success Criteria

- [ ] Detected project type correctly
- [ ] Created directory structure matching source layout
- [ ] Framework configured and working (`npm test` runs)
- [ ] Shared fixtures/helpers location established
- [ ] Example tests demonstrate conventions
- [ ] `.test-conventions.md` created with team standards
- [ ] `.test-metrics.json` created with health targets
- [ ] Test commands added to project config
- [ ] User can run tests successfully after setup

## References

See `references/` for framework-specific configuration templates:
- `jest-config.md` - Jest/Vitest setup
- `pytest-config.md` - pytest setup
- `rspec-config.md` - RSpec setup
- `go-testing.md` - Go testing patterns
- `test-patterns.md` - Common patterns across all frameworks
