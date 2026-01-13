# Jest/Vitest Configuration

## Jest Setup (JavaScript/TypeScript)

### Basic jest.config.js

```javascript
/** @type {import('jest').Config} */
module.exports = {
  // Test environment
  testEnvironment: 'node', // or 'jsdom' for browser

  // File patterns
  testMatch: [
    '**/tests/**/*.test.[jt]s?(x)',
    '**/__tests__/**/*.[jt]s?(x)'
  ],

  // TypeScript support (if using ts-jest)
  transform: {
    '^.+\\.tsx?$': 'ts-jest'
  },

  // Module resolution
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1'
  },

  // Setup files
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],

  // Coverage
  collectCoverageFrom: [
    'src/**/*.{js,ts,jsx,tsx}',
    '!src/**/*.d.ts',
    '!src/**/index.{js,ts}'
  ],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },

  // Performance
  maxWorkers: '50%',

  // Clear mocks between tests
  clearMocks: true,
  restoreMocks: true
};
```

### Test Setup File (tests/setup.ts)

```typescript
// Global test setup
import { jest } from '@jest/globals';

// Extend expect with custom matchers
// import '@testing-library/jest-dom';

// Mock console to reduce noise
// global.console = {
//   ...console,
//   log: jest.fn(),
//   debug: jest.fn(),
// };

// Global teardown
afterAll(() => {
  // Cleanup resources
});

// Reset mocks between tests
beforeEach(() => {
  jest.clearAllMocks();
});
```

### Test Utilities (tests/helpers/test-utils.ts)

```typescript
// Factory for creating test users
export function createTestUser(overrides = {}) {
  return {
    id: 'test-user-1',
    email: 'test@example.com',
    name: 'Test User',
    ...overrides
  };
}

// Async helper with timeout
export async function waitFor(
  condition: () => boolean,
  timeout = 5000
): Promise<void> {
  const start = Date.now();
  while (!condition()) {
    if (Date.now() - start > timeout) {
      throw new Error('waitFor timeout');
    }
    await new Promise(r => setTimeout(r, 50));
  }
}

// Mock response factory
export function mockResponse(data: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(data),
    text: () => Promise.resolve(JSON.stringify(data))
  };
}
```

## Vitest Setup (Modern Alternative)

### vitest.config.ts

```typescript
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: ['node_modules/', 'tests/']
    },
    // Parallel execution
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false
      }
    }
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src')
    }
  }
});
```

## Package.json Scripts

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage",
    "test:unit": "jest tests/unit",
    "test:integration": "jest tests/integration --runInBand",
    "test:e2e": "jest tests/e2e --runInBand"
  }
}
```

## Common Patterns

### Mocking Modules

```typescript
// Mock entire module
jest.mock('../src/services/api');

// Mock with implementation
jest.mock('../src/services/api', () => ({
  fetchUser: jest.fn().mockResolvedValue({ id: '1', name: 'Test' })
}));

// Spy on method
const spy = jest.spyOn(service, 'method');
```

### Testing Async Code

```typescript
it('fetches user data', async () => {
  const user = await fetchUser('123');
  expect(user.name).toBe('Test User');
});

it('rejects on error', async () => {
  await expect(fetchUser('invalid')).rejects.toThrow('Not found');
});
```

### Parameterized Tests

```typescript
describe.each([
  [1, 1, 2],
  [1, 2, 3],
  [2, 2, 4],
])('add(%i, %i)', (a, b, expected) => {
  it(`returns ${expected}`, () => {
    expect(add(a, b)).toBe(expected);
  });
});
```
