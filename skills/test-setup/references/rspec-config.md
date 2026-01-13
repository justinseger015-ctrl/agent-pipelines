# RSpec Configuration

## Basic Setup

### .rspec

```
--require spec_helper
--format documentation
--color
--order random
```

### spec/spec_helper.rb

```ruby
# frozen_string_literal: true

RSpec.configure do |config|
  # Raise errors for deprecated syntax
  config.raise_errors_for_deprecations!

  # Allow focus on specific tests with :focus tag
  config.filter_run_when_matching :focus

  # Disable monkey-patching (use RSpec.describe instead of describe)
  config.disable_monkey_patching!

  # Detailed output for single test runs
  config.default_formatter = "doc" if config.files_to_run.one?

  # Run specs in random order for better isolation
  config.order = :random
  Kernel.srand config.seed

  # Expectations configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect # Disable should syntax
  end

  # Mocking configuration
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  # Shared context configuration
  config.shared_context_metadata_behavior = :apply_to_host_groups
end
```

### spec/rails_helper.rb (Rails Projects)

```ruby
# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Load support files
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Use transactional fixtures
  config.use_transactional_fixtures = true

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter Rails-specific backtrace lines
  config.filter_rails_from_backtrace!

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Database cleaner (if using)
  # config.before(:suite) do
  #   DatabaseCleaner.strategy = :transaction
  #   DatabaseCleaner.clean_with(:truncation)
  # end
end
```

## Directory Structure

```
project/
├── app/
│   ├── models/
│   │   └── user.rb
│   ├── services/
│   │   └── auth_service.rb
│   └── controllers/
│       └── users_controller.rb
└── spec/
    ├── spec_helper.rb
    ├── rails_helper.rb
    ├── support/
    │   ├── factory_bot.rb
    │   └── shared_examples.rb
    ├── factories/
    │   └── users.rb
    ├── models/
    │   └── user_spec.rb
    ├── services/
    │   └── auth_service_spec.rb
    ├── controllers/
    │   └── users_controller_spec.rb
    ├── requests/
    │   └── users_spec.rb
    └── system/
        └── user_flows_spec.rb
```

## Factories (spec/factories/users.rb)

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }
    password { "password123" }

    trait :admin do
      role { "admin" }
    end

    trait :with_posts do
      transient do
        posts_count { 3 }
      end

      after(:create) do |user, evaluator|
        create_list(:post, evaluator.posts_count, author: user)
      end
    end

    factory :admin_user, traits: [:admin]
  end
end
```

## Example Specs

### Model Spec (spec/models/user_spec.rb)

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_length_of(:password).is_at_least(8) }
  end

  describe "associations" do
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to belong_to(:organization).optional }
  end

  describe "#full_name" do
    subject(:user) { build(:user, first_name: "John", last_name: "Doe") }

    it "returns first and last name combined" do
      expect(user.full_name).to eq("John Doe")
    end
  end
end
```

### Service Spec (spec/services/auth_service_spec.rb)

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuthService do
  subject(:service) { described_class.new }

  describe "#authenticate" do
    let(:user) { create(:user, password: "correct-password") }

    context "with valid credentials" do
      it "returns the user" do
        result = service.authenticate(user.email, "correct-password")
        expect(result).to eq(user)
      end

      it "generates an auth token" do
        result = service.authenticate(user.email, "correct-password")
        expect(result.auth_token).to be_present
      end
    end

    context "with invalid password" do
      it "raises AuthenticationError" do
        expect {
          service.authenticate(user.email, "wrong-password")
        }.to raise_error(AuthService::AuthenticationError, /invalid credentials/i)
      end
    end

    context "with unknown email" do
      it "raises AuthenticationError" do
        expect {
          service.authenticate("unknown@example.com", "any-password")
        }.to raise_error(AuthService::AuthenticationError, /user not found/i)
      end
    end
  end
end
```

### Request Spec (spec/requests/users_spec.rb)

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users API" do
  describe "POST /users" do
    let(:valid_params) do
      {
        user: {
          email: "new@example.com",
          password: "password123",
          name: "New User"
        }
      }
    end

    context "with valid parameters" do
      it "creates a new user" do
        expect {
          post "/users", params: valid_params
        }.to change(User, :count).by(1)
      end

      it "returns created status" do
        post "/users", params: valid_params
        expect(response).to have_http_status(:created)
      end

      it "returns the user data" do
        post "/users", params: valid_params
        expect(json_response["email"]).to eq("new@example.com")
      end
    end

    context "with invalid parameters" do
      it "returns unprocessable entity" do
        post "/users", params: { user: { email: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
```

## Support Files

### spec/support/shared_examples.rb

```ruby
# frozen_string_literal: true

RSpec.shared_examples "requires authentication" do
  context "without authentication" do
    before { request.headers["Authorization"] = nil }

    it "returns unauthorized" do
      subject
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

RSpec.shared_examples "paginated response" do
  it "includes pagination metadata" do
    subject
    expect(json_response).to include("meta")
    expect(json_response["meta"]).to include("total", "page", "per_page")
  end
end
```

### spec/support/request_helpers.rb

```ruby
# frozen_string_literal: true

module RequestHelpers
  def json_response
    JSON.parse(response.body)
  end

  def auth_headers(user)
    token = JsonWebToken.encode(user_id: user.id)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
```

## Running Tests

```bash
# Run all specs
bundle exec rspec

# Run specific file
bundle exec rspec spec/models/user_spec.rb

# Run specific test
bundle exec rspec spec/models/user_spec.rb:15

# Run by tag
bundle exec rspec --tag focus
bundle exec rspec --tag type:request

# With coverage
COVERAGE=true bundle exec rspec

# Parallel (with parallel_tests gem)
bundle exec parallel_rspec spec/
```

## Useful Gems

```ruby
# Gemfile (test group)
group :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "simplecov", require: false
  gem "webmock"
  gem "vcr"
end
```
