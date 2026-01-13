# pytest Configuration

## Basic Setup

### pytest.ini (or pyproject.toml)

```ini
[pytest]
# Test discovery
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Output
addopts = -v --tb=short --strict-markers

# Markers for categorizing tests
markers =
    unit: Unit tests (fast, isolated)
    integration: Integration tests (may use external services)
    slow: Tests that take > 1s
    e2e: End-to-end tests

# Coverage
# addopts = --cov=src --cov-report=term-missing --cov-fail-under=80
```

### pyproject.toml Alternative

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = "-v --tb=short --strict-markers"
markers = [
    "unit: Unit tests",
    "integration: Integration tests",
    "slow: Slow tests",
    "e2e: End-to-end tests"
]

[tool.coverage.run]
source = ["src"]
omit = ["tests/*", "**/__init__.py"]

[tool.coverage.report]
fail_under = 80
show_missing = true
```

## Directory Structure

```
project/
├── src/
│   └── mypackage/
│       ├── __init__.py
│       └── services/
│           └── auth.py
└── tests/
    ├── __init__.py
    ├── conftest.py           # Shared fixtures
    ├── unit/
    │   ├── __init__.py
    │   └── services/
    │       └── test_auth.py
    ├── integration/
    │   └── test_api.py
    └── fixtures/
        └── users.json
```

## conftest.py (Shared Fixtures)

```python
"""Shared test fixtures and configuration."""
import pytest
import json
from pathlib import Path

# -----------------------------------------------------------------------------
# Fixture Scope Reference:
# - function (default): New instance for each test
# - class: Shared within test class
# - module: Shared within test file
# - session: Shared across all tests
# -----------------------------------------------------------------------------

@pytest.fixture
def sample_user():
    """Create a basic test user."""
    return {
        "id": "user-123",
        "email": "test@example.com",
        "name": "Test User"
    }


@pytest.fixture
def sample_users(sample_user):
    """Create multiple test users."""
    return [
        sample_user,
        {"id": "user-456", "email": "other@example.com", "name": "Other User"}
    ]


@pytest.fixture
def fixtures_path():
    """Path to fixtures directory."""
    return Path(__file__).parent / "fixtures"


@pytest.fixture
def load_fixture(fixtures_path):
    """Load JSON fixture by name."""
    def _load(name: str):
        path = fixtures_path / f"{name}.json"
        with open(path) as f:
            return json.load(f)
    return _load


# -----------------------------------------------------------------------------
# Database fixtures (if using database)
# -----------------------------------------------------------------------------

@pytest.fixture(scope="session")
def db_engine():
    """Create database engine (once per session)."""
    # from sqlalchemy import create_engine
    # engine = create_engine("sqlite:///:memory:")
    # yield engine
    # engine.dispose()
    pass


@pytest.fixture
def db_session(db_engine):
    """Create database session (per test, auto-rollback)."""
    # from sqlalchemy.orm import sessionmaker
    # Session = sessionmaker(bind=db_engine)
    # session = Session()
    # yield session
    # session.rollback()
    # session.close()
    pass


# -----------------------------------------------------------------------------
# Mock fixtures
# -----------------------------------------------------------------------------

@pytest.fixture
def mock_api_client(mocker):
    """Mock external API client."""
    client = mocker.MagicMock()
    client.get.return_value = {"status": "ok"}
    return client


# -----------------------------------------------------------------------------
# Markers and hooks
# -----------------------------------------------------------------------------

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")


def pytest_collection_modifyitems(config, items):
    """Auto-mark tests based on path."""
    for item in items:
        if "unit" in str(item.fspath):
            item.add_marker(pytest.mark.unit)
        elif "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)
```

## Example Test File

```python
"""Tests for authentication service."""
import pytest
from mypackage.services.auth import AuthService, AuthError


class TestAuthService:
    """Tests for AuthService."""

    @pytest.fixture
    def auth_service(self, mock_api_client):
        """Create AuthService with mocked dependencies."""
        return AuthService(api_client=mock_api_client)

    # -------------------------------------------------------------------------
    # authenticate() tests
    # -------------------------------------------------------------------------

    def test_authenticate_with_valid_credentials(self, auth_service, sample_user):
        """Returns user when credentials are valid."""
        # Arrange
        email = sample_user["email"]
        password = "valid-password"

        # Act
        result = auth_service.authenticate(email, password)

        # Assert
        assert result["email"] == email
        assert "token" in result

    def test_authenticate_with_invalid_password(self, auth_service):
        """Raises AuthError when password is invalid."""
        with pytest.raises(AuthError, match="Invalid credentials"):
            auth_service.authenticate("test@example.com", "wrong")

    def test_authenticate_with_unknown_user(self, auth_service):
        """Raises AuthError when user doesn't exist."""
        with pytest.raises(AuthError, match="User not found"):
            auth_service.authenticate("unknown@example.com", "password")

    # -------------------------------------------------------------------------
    # Parameterized tests
    # -------------------------------------------------------------------------

    @pytest.mark.parametrize("email,expected_valid", [
        ("valid@example.com", True),
        ("also.valid@test.org", True),
        ("invalid", False),
        ("missing@domain", False),
        ("", False),
    ])
    def test_validate_email(self, auth_service, email, expected_valid):
        """Validates email format correctly."""
        assert auth_service.validate_email(email) == expected_valid
```

## Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=src --cov-report=html

# Run specific markers
pytest -m unit
pytest -m "not slow"

# Run specific file/test
pytest tests/unit/test_auth.py
pytest tests/unit/test_auth.py::TestAuthService::test_authenticate_with_valid_credentials

# Verbose output
pytest -v

# Stop on first failure
pytest -x

# Show local variables in tracebacks
pytest -l

# Parallel execution (requires pytest-xdist)
pytest -n auto
```

## Useful Plugins

```bash
# Install common plugins
pip install pytest-cov      # Coverage
pip install pytest-xdist    # Parallel execution
pip install pytest-mock     # Mocking helpers
pip install pytest-asyncio  # Async test support
pip install pytest-timeout  # Test timeouts
pip install pytest-randomly # Randomize test order
```
