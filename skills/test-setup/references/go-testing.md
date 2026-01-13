# Go Testing Patterns

Go has built-in testing support via the `testing` package. No external configuration needed.

## Directory Structure

Go tests live alongside source files by convention:

```
project/
├── go.mod
├── main.go
├── internal/
│   └── auth/
│       ├── auth.go
│       └── auth_test.go
├── pkg/
│   └── utils/
│       ├── helpers.go
│       └── helpers_test.go
└── testdata/
    └── fixtures.json
```

## Basic Test File

```go
// auth_test.go
package auth

import (
    "testing"
)

func TestAuthenticate(t *testing.T) {
    // Arrange
    service := NewAuthService()
    email := "test@example.com"
    password := "valid-password"

    // Act
    user, err := service.Authenticate(email, password)

    // Assert
    if err != nil {
        t.Fatalf("expected no error, got %v", err)
    }
    if user.Email != email {
        t.Errorf("expected email %s, got %s", email, user.Email)
    }
}

func TestAuthenticate_InvalidPassword(t *testing.T) {
    service := NewAuthService()

    _, err := service.Authenticate("test@example.com", "wrong")

    if err == nil {
        t.Fatal("expected error for invalid password")
    }
    if err != ErrInvalidCredentials {
        t.Errorf("expected ErrInvalidCredentials, got %v", err)
    }
}
```

## Table-Driven Tests (Recommended Pattern)

```go
func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name     string
        email    string
        expected bool
    }{
        {
            name:     "valid email",
            email:    "user@example.com",
            expected: true,
        },
        {
            name:     "missing @",
            email:    "userexample.com",
            expected: false,
        },
        {
            name:     "empty string",
            email:    "",
            expected: false,
        },
        {
            name:     "missing domain",
            email:    "user@",
            expected: false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := ValidateEmail(tt.email)
            if result != tt.expected {
                t.Errorf("ValidateEmail(%q) = %v, want %v",
                    tt.email, result, tt.expected)
            }
        })
    }
}
```

## Subtests for Organization

```go
func TestAuthService(t *testing.T) {
    service := NewAuthService()

    t.Run("Authenticate", func(t *testing.T) {
        t.Run("with valid credentials", func(t *testing.T) {
            user, err := service.Authenticate("test@example.com", "password")
            if err != nil {
                t.Fatalf("unexpected error: %v", err)
            }
            if user == nil {
                t.Fatal("expected user, got nil")
            }
        })

        t.Run("with invalid password", func(t *testing.T) {
            _, err := service.Authenticate("test@example.com", "wrong")
            if err == nil {
                t.Fatal("expected error")
            }
        })
    })

    t.Run("Register", func(t *testing.T) {
        // ...
    })
}
```

## Test Fixtures

```go
// Use testdata/ directory (ignored by Go build)
func TestLoadConfig(t *testing.T) {
    // testdata/ is a special directory name
    config, err := LoadConfig("testdata/config.json")
    if err != nil {
        t.Fatalf("failed to load config: %v", err)
    }
    // ...
}
```

## Test Helpers

```go
// Helper function - note t.Helper() call
func assertEqual(t *testing.T, got, want interface{}) {
    t.Helper() // Marks this as a helper function for better error reporting
    if got != want {
        t.Errorf("got %v, want %v", got, want)
    }
}

func assertNoError(t *testing.T, err error) {
    t.Helper()
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
}

func assertError(t *testing.T, err error) {
    t.Helper()
    if err == nil {
        t.Fatal("expected error, got nil")
    }
}
```

## Setup and Teardown

```go
func TestMain(m *testing.M) {
    // Setup before all tests
    setup()

    // Run tests
    code := m.Run()

    // Teardown after all tests
    teardown()

    os.Exit(code)
}

// Per-test setup
func TestWithSetup(t *testing.T) {
    // Setup
    db := setupTestDB(t)
    defer db.Close()

    // Test...
}

// Using t.Cleanup (Go 1.14+)
func TestWithCleanup(t *testing.T) {
    db := setupTestDB(t)
    t.Cleanup(func() {
        db.Close()
    })

    // Test...
}
```

## Mocking with Interfaces

```go
// Define interface for dependencies
type UserRepository interface {
    FindByEmail(email string) (*User, error)
    Save(user *User) error
}

// Mock implementation for tests
type MockUserRepository struct {
    FindByEmailFunc func(email string) (*User, error)
    SaveFunc        func(user *User) error
}

func (m *MockUserRepository) FindByEmail(email string) (*User, error) {
    return m.FindByEmailFunc(email)
}

func (m *MockUserRepository) Save(user *User) error {
    return m.SaveFunc(user)
}

// Using the mock
func TestAuthService_Authenticate(t *testing.T) {
    mockRepo := &MockUserRepository{
        FindByEmailFunc: func(email string) (*User, error) {
            return &User{Email: email, PasswordHash: "hashed"}, nil
        },
    }

    service := NewAuthService(mockRepo)
    user, err := service.Authenticate("test@example.com", "password")

    // Assert...
}
```

## Benchmarks

```go
func BenchmarkHashPassword(b *testing.B) {
    for i := 0; i < b.N; i++ {
        HashPassword("test-password-123")
    }
}

func BenchmarkAuthenticate(b *testing.B) {
    service := NewAuthService()

    b.ResetTimer() // Don't count setup time

    for i := 0; i < b.N; i++ {
        service.Authenticate("test@example.com", "password")
    }
}
```

## Running Tests

```bash
# Run all tests
go test ./...

# Run with verbose output
go test -v ./...

# Run specific package
go test ./internal/auth

# Run specific test
go test -run TestAuthenticate ./internal/auth

# Run subtests
go test -run TestAuthService/Authenticate/with_valid_credentials ./internal/auth

# Run with coverage
go test -cover ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Run benchmarks
go test -bench=. ./...

# Race detection
go test -race ./...

# Short mode (skip slow tests)
go test -short ./...

# Parallel execution (default is GOMAXPROCS)
go test -parallel 4 ./...
```

## Test Flags in Code

```go
func TestSlowOperation(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping slow test in short mode")
    }

    // Slow test...
}
```

## Using testify (Popular Third-Party)

```go
import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestWithTestify(t *testing.T) {
    user, err := GetUser("123")

    // assert continues on failure
    assert.NoError(t, err)
    assert.Equal(t, "test@example.com", user.Email)
    assert.NotNil(t, user.CreatedAt)

    // require stops test on failure
    require.NoError(t, err)
    require.NotNil(t, user)
}

// Suite-based testing
type AuthServiceTestSuite struct {
    suite.Suite
    service *AuthService
}

func (s *AuthServiceTestSuite) SetupTest() {
    s.service = NewAuthService()
}

func (s *AuthServiceTestSuite) TestAuthenticate() {
    user, err := s.service.Authenticate("test@example.com", "password")
    s.NoError(err)
    s.NotNil(user)
}

func TestAuthServiceTestSuite(t *testing.T) {
    suite.Run(t, new(AuthServiceTestSuite))
}
```
