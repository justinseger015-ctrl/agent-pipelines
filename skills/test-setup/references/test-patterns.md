# Common Test Patterns (All Frameworks)

## The AAA Pattern

**Arrange-Act-Assert** is the standard structure for all unit tests:

```
Arrange: Set up preconditions and inputs
Act:     Execute the code under test
Assert:  Verify expected outcomes
```

### Example (Pseudocode)

```
// Arrange
user = create_user(email: "test@example.com")
calculator = Calculator.new()

// Act
result = calculator.calculate_tax(user.income)

// Assert
expect(result).to_equal(5000)
```

### Why This Matters

- **Readability**: Anyone can understand what the test does
- **Debugging**: Clear separation makes failures easy to diagnose
- **Maintenance**: Each section can be modified independently

## Naming Conventions

### Test File Names

| Language | Convention | Example |
|----------|-----------|---------|
| JavaScript/TS | `*.test.ts` or `*.spec.ts` | `auth.test.ts` |
| Python | `test_*.py` | `test_auth.py` |
| Ruby | `*_spec.rb` | `auth_spec.rb` |
| Go | `*_test.go` | `auth_test.go` |
| Java | `*Test.java` | `AuthTest.java` |

### Test Method/Function Names

Good test names describe the scenario and expected outcome:

```
# Good
test_authenticate_returns_user_when_credentials_valid
test_authenticate_raises_error_when_password_invalid
it "returns user when credentials are valid"
it "raises AuthError when password is invalid"

# Bad
test_authenticate
test1
it "works"
```

### Pattern: should/when/given

```
describe Calculator
  describe "#add"
    context "when both numbers are positive"
      it "returns the sum"

    context "when one number is negative"
      it "returns the correct result"
```

## The Testing Pyramid

```
        /\
       /  \      E2E (5%)
      /----\
     /      \    Integration (15%)
    /--------\
   /          \  Unit (80%)
  /____________\
```

### Unit Tests

- Test individual functions/classes in isolation
- Mock external dependencies
- Fast (milliseconds)
- High quantity

```python
def test_calculate_tax_applies_rate():
    calculator = TaxCalculator(rate=0.25)
    assert calculator.calculate(100) == 25
```

### Integration Tests

- Test components working together
- May use real databases, APIs
- Slower (seconds)
- Medium quantity

```python
def test_user_service_creates_user_in_database(db_session):
    service = UserService(db_session)
    user = service.create(email="test@example.com")

    saved = db_session.query(User).get(user.id)
    assert saved.email == "test@example.com"
```

### E2E Tests

- Test complete user flows
- Use real browser/UI
- Slowest (minutes)
- Few, only critical paths

```javascript
test('user can complete checkout', async ({ page }) => {
  await page.goto('/products');
  await page.click('[data-testid="add-to-cart"]');
  await page.click('[data-testid="checkout"]');
  await page.fill('#email', 'test@example.com');
  await page.click('[data-testid="submit"]');
  await expect(page.locator('.success')).toBeVisible();
});
```

## Mocking Strategies

### When to Mock

| Mock | Don't Mock |
|------|------------|
| External APIs | Core business logic |
| Databases (in unit tests) | Value objects |
| File system | Pure functions |
| Time/randomness | Internal collaborators (usually) |
| Email services | |

### Mock Types

- **Stub**: Returns canned data, no verification
- **Mock**: Verifies interactions (was method called?)
- **Fake**: Working implementation (in-memory DB)
- **Spy**: Records calls for later verification

### Example: Stubbing an API Client

```python
def test_user_service_fetches_from_api(mocker):
    # Stub the API response
    mock_client = mocker.Mock()
    mock_client.get_user.return_value = {"id": "123", "name": "Test"}

    service = UserService(api_client=mock_client)
    user = service.get_user("123")

    assert user.name == "Test"
```

### Example: Verifying Interaction

```python
def test_order_service_sends_confirmation_email(mocker):
    mock_mailer = mocker.Mock()
    service = OrderService(mailer=mock_mailer)

    service.complete_order(order_id="123")

    # Verify the mailer was called correctly
    mock_mailer.send.assert_called_once_with(
        to="customer@example.com",
        subject="Order Confirmed",
        body=mocker.ANY
    )
```

## Test Data Patterns

### Factories

Create test objects with sensible defaults:

```ruby
# Factory definition
factory :user do
  email { Faker::Internet.email }
  name { "Test User" }
  role { "member" }

  trait :admin do
    role { "admin" }
  end
end

# Usage
user = create(:user)
admin = create(:user, :admin)
custom = create(:user, email: "specific@example.com")
```

### Fixtures

Static data loaded from files:

```json
// fixtures/users.json
{
  "valid_user": {
    "email": "test@example.com",
    "name": "Test User"
  },
  "admin_user": {
    "email": "admin@example.com",
    "name": "Admin",
    "role": "admin"
  }
}
```

### Builders

Fluent interface for complex objects:

```typescript
const user = new UserBuilder()
  .withEmail("test@example.com")
  .withRole("admin")
  .withPosts(3)
  .build();
```

## Common Anti-Patterns to Avoid

### 1. The Giant

❌ Too many assertions in one test

```python
# Bad
def test_user():
    user = create_user()
    assert user.email is not None
    assert user.name is not None
    assert user.created_at is not None
    assert user.role == "member"
    assert user.can_login() == True
    assert user.validate() == True
```

✅ One logical behavior per test

```python
# Good
def test_user_has_default_role():
    user = create_user()
    assert user.role == "member"

def test_new_user_can_login():
    user = create_user()
    assert user.can_login() == True
```

### 2. The Mockery

❌ Over-mocking internal implementation

```python
# Bad - testing implementation details
def test_calculate_total(mocker):
    mocker.patch.object(Order, '_apply_discount')
    mocker.patch.object(Order, '_calculate_tax')
    mocker.patch.object(Order, '_sum_items')
    # ...
```

✅ Test behavior, mock boundaries

```python
# Good - mock external dependency only
def test_calculate_total_with_discount(mock_discount_api):
    mock_discount_api.get_discount.return_value = 0.1
    order = Order(items=[item1, item2])

    total = order.calculate_total()

    assert total == 90  # 100 - 10% discount
```

### 3. The Liar

❌ Tests that pass but don't verify anything

```python
# Bad
def test_process_order():
    order = Order()
    order.process()  # No assertion!
```

✅ Always assert expected outcomes

```python
# Good
def test_process_order_updates_status():
    order = Order(status="pending")
    order.process()
    assert order.status == "completed"
```

### 4. Excessive Setup

❌ 50 lines of setup for 2 lines of test

✅ Use fixtures, factories, and shared setup

### 5. Test Interdependence

❌ Tests that depend on other tests running first

✅ Each test should be independent and idempotent

## Coverage Guidelines

### What to Aim For

| Area | Target |
|------|--------|
| Business logic | 80-90% |
| Utilities/helpers | 70-80% |
| Controllers/routes | 60-70% |
| Configuration | Don't chase |

### What Coverage DOESN'T Tell You

- Whether tests are meaningful
- Whether edge cases are covered
- Whether the right things are tested
- Code quality

### Martin Fowler's Advice

> "Test coverage is a useful tool for finding untested parts of a codebase. Test coverage is of little use as a numeric statement of how good your tests are."

If you have:
- **High coverage + confident refactoring** → Good tests
- **High coverage + fear of changes** → Bad tests (probably testing implementation)
