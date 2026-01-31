# SenroUsecaser

A UseCase pattern implementation library for Ruby. Framework-agnostic with a focus on simplicity and type safety.

## Design Philosophy

### Single Responsibility Principle

Each UseCase handles exactly one business operation. This makes the code easier to understand, test, and maintain.

```ruby
# Good: Single responsibility
class CreateUserUseCase < SenroUsecaser::Base
  def call(input)
    # Only user creation
  end
end

# Bad: Multiple responsibilities
class CreateUserAndSendEmailUseCase < SenroUsecaser::Base
  def call(input)
    # User creation + email sending (should be separated)
  end
end
```

### Result Pattern

All UseCases explicitly return success or failure. Instead of relying on exceptions, callers can handle results appropriately.

```ruby
result = CreateUserUseCase.call(CreateUserUseCase::Input.new(name: "Taro", email: "taro@example.com"))

if result.success?
  user = result.value
  # Handle success
else
  errors = result.errors
  # Handle failure
end
```

### Dependency Injection via DI Container

UseCase dependencies are injected through a DI Container. This enables easy mock substitution during testing and achieves loose coupling.

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :user_repository, UserRepository
  depends_on :event_publisher, EventPublisher

  class Input
    #: (name: String, email: String, **untyped) -> void
    def initialize(name:, email:, **_rest)
      @name = name
      @email = email
    end

    def name = @name
    def email = @email
  end

  input Input
  output User

  def call(input)
    user = user_repository.create(name: input.name, email: input.email)
    event_publisher.publish(UserCreated.new(user))
    success(user)
  end
end

# In tests
container = SenroUsecaser::Container.new
container.register(:user_repository, MockUserRepository.new)
container.register(:event_publisher, MockEventPublisher.new)
```

#### Namespaces

The DI Container and UseCases support hierarchical namespaces for organizing dependencies and controlling visibility.

##### Namespace Basics

```ruby
container = SenroUsecaser::Container.new

# Register in root namespace (global)
container.register(:logger, Logger.new)
container.register(:config, AppConfig.new)

# Register in nested namespaces
container.namespace(:admin) do
  register(:user_repository, AdminUserRepository.new)
  register(:audit_logger, AuditLogger.new)

  namespace(:reports) do
    register(:report_generator, ReportGenerator.new)
    register(:export_service, ExportService.new)
  end
end

container.namespace(:public) do
  register(:user_repository, PublicUserRepository.new)
end
```

##### Namespace Resolution Rules

Dependencies are resolved by looking up the current namespace and its ancestors (parents). Child namespaces are not accessible.

```
root
├── :logger           ← accessible from anywhere
├── :config           ← accessible from anywhere
├── admin
│   ├── :user_repository    ← accessible from admin and admin::*
│   ├── :audit_logger       ← accessible from admin and admin::*
│   └── reports
│       ├── :report_generator  ← accessible only from admin::reports
│       └── :export_service    ← accessible only from admin::reports
└── public
    └── :user_repository    ← accessible only from public and public::*
```

##### UseCase Namespace Declaration

```ruby
# UseCase in root namespace (default)
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :logger  # resolves from root

  def call(input); end
end

# UseCase in admin namespace
class Admin::CreateUserUseCase < SenroUsecaser::Base
  namespace :admin

  depends_on :user_repository  # resolves from admin
  depends_on :audit_logger     # resolves from admin
  depends_on :logger           # resolves from root (inherited)

  def call(input); end
end

# UseCase in admin::reports namespace
class Admin::Reports::GenerateReportUseCase < SenroUsecaser::Base
  namespace "admin::reports"

  depends_on :report_generator  # resolves from admin::reports
  depends_on :user_repository   # resolves from admin (parent)
  depends_on :logger            # resolves from root (ancestor)

  def call(input); end
end
```

##### Automatic Namespace Inference

Instead of explicitly declaring `namespace`, you can enable automatic inference from the Ruby module structure:

```ruby
SenroUsecaser.configure do |config|
  config.infer_namespace_from_module = true
end
```

With this enabled, namespaces are automatically derived from module names:

```ruby
# No explicit namespace declaration needed!

# Module "Admin" → namespace "admin"
module Admin
  class CreateUserUseCase < SenroUsecaser::Base
    depends_on :user_repository  # resolves from admin namespace
    def call(input); end
  end
end

# Module "Admin::Reports" → namespace "admin::reports"
module Admin
  module Reports
    class GenerateReportUseCase < SenroUsecaser::Base
      depends_on :report_generator  # resolves from admin::reports
      depends_on :user_repository   # resolves from admin (parent)
      def call(input); end
    end
  end
end

# Top-level class → no namespace (root)
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :logger  # resolves from root
  def call(input); end
end
```

This also works for Providers:

```ruby
module Admin
  class ServiceProvider < SenroUsecaser::Provider
    # Automatically registers in "admin" namespace
    def register(container)
      container.register(:admin_service, AdminService.new)
    end
  end
end
```

**Note:** Explicit `namespace` declarations take precedence over inferred namespaces.

##### Scoped Containers

Create child containers for request-scoped dependencies (e.g., current_user):

```ruby
# Global container with lazy registration
SenroUsecaser.container.register_lazy(:task_repository) do |c|
  TaskRepository.new(current_user: c.resolve(:current_user))
end

# Per-request: create scoped container with current_user
request_container = SenroUsecaser.container.scope do
  register(:current_user, current_user)
end

# UseCase resolves task_repository with correct current_user
ListTasksUseCase.call(input, container: request_container)
```

#### Providers (Multi-file Registration)

For large applications, dependencies can be organized into Provider classes across multiple files. Providers declare their dependencies on other providers, ensuring correct load order.

##### Defining Providers

```ruby
# app/providers/core_provider.rb
class CoreProvider < SenroUsecaser::Provider
  def register(container)
    container.register(:logger, Logger.new(STDOUT))
    container.register(:config, AppConfig.load)
  end
end

# app/providers/persistence_provider.rb
class PersistenceProvider < SenroUsecaser::Provider
  depends_on CoreProvider  # Ensures CoreProvider loads first

  def register(container)
    container.register_singleton(:database) do |c|
      Database.connect(c.resolve(:config))
    end
  end
end

# app/providers/admin_provider.rb
class AdminProvider < SenroUsecaser::Provider
  depends_on CoreProvider
  depends_on PersistenceProvider

  namespace :admin  # Register in admin namespace

  def register(container)
    container.register(:user_repository, AdminUserRepository.new)
  end
end
```

##### Booting the Container

```ruby
# config/initializers/senro_usecaser.rb
SenroUsecaser.configure do |config|
  config.providers = [
    CoreProvider,
    PersistenceProvider,
    AdminProvider
  ]
end

# Boot resolves dependencies and loads in correct order:
# 1. CoreProvider (no dependencies)
# 2. PersistenceProvider (depends on Core)
# 3. AdminProvider (depends on Core, Persistence)
SenroUsecaser.boot!
```

##### Provider Lifecycle Hooks

```ruby
class PersistenceProvider < SenroUsecaser::Provider
  depends_on CoreProvider

  # Called before register
  def before_register(container)
    # Setup work
  end

  def register(container)
    container.register_singleton(:database) do |c|
      Database.connect(c.resolve(:config))
    end
  end

  # Called after all providers are registered
  def after_boot(container)
    container.resolve(:database).verify_connection!
  end

  # Called on application shutdown
  def shutdown(container)
    container.resolve(:database).disconnect
  end
end
```

##### Registration Types

```ruby
class PersistenceProvider < SenroUsecaser::Provider
  def register(container)
    # Eager: value stored directly
    container.register(:config, AppConfig.load)

    # Lazy: block called on every resolve
    container.register_lazy(:connection) do |c|
      Database.connect(c.resolve(:config))
    end

    # Singleton: block called once, result cached
    container.register_singleton(:connection_pool) do |c|
      ConnectionPool.new(size: 10) { c.resolve(:connection) }
    end
  end
end
```

##### Conditional Providers

```ruby
class DevelopmentProvider < SenroUsecaser::Provider
  enabled_if { SenroUsecaser.env.development? }

  def register(container)
    container.register(:mailer, DevelopmentMailer.new)
  end
end

class ProductionProvider < SenroUsecaser::Provider
  enabled_if { SenroUsecaser.env.production? }

  def register(container)
    container.register(:mailer, SmtpMailer.new)
  end
end
```

##### Provider Dependency Graph

The container ensures providers are loaded in topological order based on dependencies. Circular dependencies are detected and raise an error at boot time.

### Testability

Dependency injection allows unit testing UseCases without relying on external services or databases.

```ruby
RSpec.describe CreateUserUseCase do
  let(:user_repository) { instance_double(UserRepository) }
  let(:use_case) { described_class.new(dependencies: { user_repository: user_repository }) }

  it "creates a user" do
    allow(user_repository).to receive(:create).and_return(user)

    input = CreateUserUseCase::Input.new(name: "Taro", email: "taro@example.com")
    result = use_case.call(input)

    expect(result).to be_success
  end
end
```

### Framework Agnostic

Implemented in pure Ruby, it can be used with any framework such as Rails, Sinatra, or Hanami.

### Type Safety (RBS Inline)

All implementations are designed to be type-safe using **RBS Inline** comments. Types are written directly in Ruby source files as comments.

#### Input/Output Classes

Each UseCase defines its Input and Output as inner classes with RBS Inline annotations:

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  class Input
    #: (name: String, email: String, ?age: Integer, **untyped) -> void
    def initialize(name:, email:, age: nil, **_rest)
      @name = name #: String
      @email = email #: String
      @age = age #: Integer?
    end

    #: () -> String
    def name = @name

    #: () -> String
    def email = @email

    #: () -> Integer?
    def age = @age
  end

  class Output
    #: (user: User, token: String) -> void
    def initialize(user:, token:)
      @user = user #: User
      @token = token #: String
    end

    #: () -> User
    def user = @user

    #: () -> String
    def token = @token
  end

  input Input
  output Output

  def call(input)
    user = User.create(name: input.name, email: input.email, age: input.age)
    token = generate_token(user)
    success(Output.new(user: user, token: token))
  end
end
```

The `**_rest` parameter in Input's initialize allows extra fields to be passed through pipeline steps without errors.

### Simplicity

Define UseCases with minimal boilerplate. Avoids over-abstraction and provides an intuitive API.

### UseCase Composition

Complex business operations can be composed from simpler UseCases using `organize` and `extend_with`.

#### organize - Sequential Execution

Execute multiple UseCases in sequence. Each step's output becomes the next step's input (converted to hash for compatibility).

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  class Input
    #: (user_id: Integer, product_ids: Array[Integer], **untyped) -> void
    def initialize(user_id:, product_ids:, **_rest)
      @user_id = user_id
      @product_ids = product_ids
    end

    def user_id = @user_id
    def product_ids = @product_ids
  end

  input Input
  output CreateOrderOutput

  organize do
    step ValidateOrderUseCase
    step CreateOrderUseCase
    step ChargePaymentUseCase
    step SendConfirmationEmailUseCase
  end
end
```

##### Error Handling Strategy

Configure how errors are handled using the `on_failure:` option.

**`:stop` (default)** - Stop execution on first failure.

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize on_failure: :stop do
    step ValidateOrderUseCase
    step CreateOrderUseCase
    step ChargePaymentUseCase      # Not executed if CreateOrderUseCase fails
  end
end
```

**`:continue`** - Continue execution even if a step fails.

```ruby
class BatchProcessUseCase < SenroUsecaser::Base
  organize on_failure: :continue do
    step ProcessItemAUseCase
    step ProcessItemBUseCase    # Executed even if A fails
    step ProcessItemCUseCase
  end
end
```

**`:collect`** - Continue execution and collect all errors.

```ruby
class ValidateFormUseCase < SenroUsecaser::Base
  organize on_failure: :collect do
    step ValidateNameUseCase
    step ValidateEmailUseCase
    step ValidatePasswordUseCase
  end
end

result = ValidateFormUseCase.call(input)
result.errors  # => [name_error, email_error, password_error]
```

##### Per-Step Error Handling

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step CreateOrderUseCase
    step SendConfirmationEmailUseCase, on_failure: :continue  # Don't fail if email fails
    step NotifyAnalyticsUseCase, on_failure: :continue        # Optional step
  end
end
```

#### Conditional Execution with `if:` / `unless:`

Use `if:` or `unless:` options to conditionally execute steps.

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step ApplyCouponUseCase,       if: :has_coupon?
    step CreateOrderUseCase
    step ChargePaymentUseCase,     unless: :free_order?
    step SendGiftNotificationUseCase, if: :gift_order?
  end

  private

  # Condition methods receive the current context (hash)
  def has_coupon?(context)
    context[:coupon_code].present?
  end

  def free_order?(context)
    context[:total].zero?
  end

  def gift_order?(context)
    context[:gift_recipient].present?
  end
end
```

##### Condition as Lambda

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step ApplyCouponUseCase, if: ->(ctx) { ctx[:coupon_code].present? }
    step NotifyAdminUseCase, if: ->(ctx) { ctx[:total] > 10_000 }
  end
end
```

##### Multiple Conditions

Combine multiple conditions with `all:` (AND) or `any:` (OR):

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    # Runs only if ALL conditions are true
    step PremiumDiscountUseCase, all: [:premium_user?, :eligible_for_discount?]
    # Runs if ANY condition is true
    step SendNotificationUseCase, any: [:email_opted_in?, :sms_opted_in?]
  end
end
```

#### Custom Input Mapping

By default, the previous step's output is passed as input to the next step. Use `input:` to customize:

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step CreateOrderUseCase

    # Hash mapping: { new_key: :source_key }
    step ChargePaymentUseCase, input: { amount: :total, user: :customer }

    # Method reference
    step SendEmailUseCase, input: :prepare_email_input

    # Lambda
    step NotifyUseCase, input: ->(ctx) { { message: "Order #{ctx[:order_id]}" } }
  end

  def prepare_email_input(context)
    { to: context[:customer_email], subject: "Order Confirmation" }
  end
end
```

#### Accumulated Context

Access data from earlier steps (not just the previous one) using `accumulated_context`:

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase     # Output: { user:, items: }
    step CreateOrderUseCase       # Output: { order: }
    step ChargePaymentUseCase     # Output: { payment: }
    step SendEmailUseCase, if: :should_send_email?
  end

  def should_send_email?(context)
    # accumulated_context has all data from previous steps
    accumulated_context[:user][:email_notifications_enabled]
  end
end
```

#### extend_with - Hooks (before/after/around)

Add cross-cutting concerns like logging, authorization, or transaction handling.

```ruby
# Define extension modules
module Logging
  def self.before(context)
    puts "Starting: #{context.keys}"
  end

  def self.after(context, result)
    puts "Finished: #{result.success? ? 'success' : 'failure'}"
  end
end

module Transaction
  def self.around(context, &block)
    ActiveRecord::Base.transaction { block.call }
  end
end

# Apply to UseCase
class CreateUserUseCase < SenroUsecaser::Base
  extend_with Logging, Transaction

  def call(input)
    # main logic
  end
end
```

##### Block Syntax

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  before do |context|
    # runs before call
  end

  after do |context, result|
    # runs after call
  end

  around do |context, &block|
    ActiveRecord::Base.transaction do
      block.call
    end
  end

  def call(input)
    # main logic
  end
end
```

#### Combining Composition Patterns

```ruby
class RegisterUserUseCase < SenroUsecaser::Base
  class Input
    #: (name: String, email: String, password: String, **untyped) -> void
    def initialize(name:, email:, password:, **_rest)
      @name = name
      @email = email
      @password = password
    end

    def name = @name
    def email = @email
    def password = @password
  end

  # Hooks
  extend_with Logging
  extend_with TransactionWrapper

  input Input
  output UserOutput

  # Pipeline
  organize do
    step ValidateUserInputUseCase
    step CheckDuplicateEmailUseCase
    step CreateUserUseCase
    step SendWelcomeEmailUseCase, on_failure: :continue
  end
end
```

## Installation

```bash
bundle add senro_usecaser
```

Or add to your Gemfile:

```ruby
gem "senro_usecaser"
```

## Usage

### Basic UseCase

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  class Input
    #: (name: String, email: String, **untyped) -> void
    def initialize(name:, email:, **_rest)
      @name = name #: String
      @email = email #: String
    end

    #: () -> String
    def name = @name

    #: () -> String
    def email = @email
  end

  class Output
    #: (user: User) -> void
    def initialize(user:)
      @user = user #: User
    end

    #: () -> User
    def user = @user
  end

  input Input
  output Output

  def call(input)
    user = User.create(name: input.name, email: input.email)
    success(Output.new(user: user))
  rescue ActiveRecord::RecordInvalid => e
    failure(SenroUsecaser::Error.new(
      code: :validation_error,
      message: e.message
    ))
  end
end

input = CreateUserUseCase::Input.new(name: "Taro", email: "taro@example.com")
result = CreateUserUseCase.call(input)

if result.success?
  puts "Created user: #{result.value.user.name}"
else
  puts "Error: #{result.errors.first.message}"
end
```

### With Dependencies

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :user_repository, UserRepository
  depends_on :event_publisher, EventPublisher

  class Input
    #: (name: String, email: String, **untyped) -> void
    def initialize(name:, email:, **_rest)
      @name = name
      @email = email
    end

    def name = @name
    def email = @email
  end

  class Output
    #: (user: User) -> void
    def initialize(user:)
      @user = user
    end

    def user = @user
  end

  input Input
  output Output

  def call(input)
    user = user_repository.create(name: input.name, email: input.email)
    event_publisher.publish(UserCreated.new(user))
    success(Output.new(user: user))
  end
end

# Register dependencies
SenroUsecaser.container.register(:user_repository, UserRepository.new)
SenroUsecaser.container.register(:event_publisher, EventPublisher.new)

# Call
input = CreateUserUseCase::Input.new(name: "Taro", email: "taro@example.com")
result = CreateUserUseCase.call(input)
```

### Calling UseCases

#### `.call` vs `.call!`

SenroUsecaser provides two methods for invoking a UseCase:

**`.call`** - Standard invocation. Exceptions are not automatically caught.

```ruby
result = CreateUserUseCase.call(input)
# If an unhandled exception is raised, it propagates up
```

**`.call!`** - Safe invocation. Any `StandardError` is caught and converted to `Result.failure`.

```ruby
result = CreateUserUseCase.call!(input)
# If User.create raises an exception, result is:
# Result.failure(Error.new(code: :exception, message: "...", cause: exception))

if result.failure?
  error = result.errors.first
  error.code     # => :exception
  error.message  # => Exception message
  error.cause    # => Original exception object
end
```

Use `.call!` when you want to ensure all exceptions are captured as `Result.failure` without explicit rescue blocks in your UseCase.

#### Exception Handling in Pipelines

When using `.call!` with `organize` pipelines, the exception capture behavior is **chained** to all steps. This is especially useful with `on_failure: :collect`:

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize on_failure: :collect do
    step ValidateOrderUseCase   # Raises exception -> captured as Result.failure
    step ChargePaymentUseCase   # Raises exception -> captured as Result.failure
    step SendEmailUseCase       # Returns explicit failure
  end
end

result = PlaceOrderUseCase.call!(input)
# All errors (from exceptions and explicit failures) are collected
result.errors  # => [exception_error_1, exception_error_2, explicit_error]
```

**Behavior comparison:**

| Call method | Pipeline step behavior | Exception handling |
|-------------|----------------------|-------------------|
| `.call`     | Steps use `.call`    | Exception propagates up |
| `.call!`    | Steps use `.call!`   | Exception → `Result.failure`, collected if `:collect` |

This chaining also applies to nested pipelines:

```ruby
class InnerUseCase < SenroUsecaser::Base
  organize on_failure: :collect do
    step StepA  # Raises exception
  end
end

class OuterUseCase < SenroUsecaser::Base
  organize on_failure: :collect do
    step InnerUseCase  # Inner exception is captured
    step StepB         # Raises exception
  end
end

result = OuterUseCase.call!(input)
result.errors  # => [inner_exception_error, step_b_exception_error]
```

#### Implicit Success Wrapping

By default, if a `call` method returns a non-Result value, it is automatically wrapped in `Result.success`. This allows for more concise UseCase implementations.

```ruby
# Explicit success (traditional style)
class CreateUserUseCase < SenroUsecaser::Base
  def call(input)
    user = User.create(name: input.name)
    success(user)  # Explicitly wrap in Result.success
  end
end

# Implicit success (concise style)
class CreateUserUseCase < SenroUsecaser::Base
  def call(input)
    User.create(name: input.name)  # Automatically wrapped as Result.success(user)
  end
end
```

This works with any return type:

```ruby
class GetUserUseCase < SenroUsecaser::Base
  def call(id:)
    User.find(id)  # Returns Result.success(user)
  end
end

class ListUsersUseCase < SenroUsecaser::Base
  def call(**_args)
    User.all.to_a  # Returns Result.success([user1, user2, ...])
  end
end

class CheckHealthUseCase < SenroUsecaser::Base
  def call(**_args)
    nil  # Returns Result.success(nil)
  end
end
```

**Note:** Explicit `failure(...)` calls are never wrapped - they remain as `Result.failure`.

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  def call(input)
    return failure(Error.new(code: :invalid, message: "Name required")) if input.name.empty?

    User.create(name: input.name)  # Implicit success
  end
end
```

### Result Operations

```ruby
input = CreateUserUseCase::Input.new(name: "Taro", email: "taro@example.com")
result = CreateUserUseCase.call(input)

# Check status
result.success?  # => true/false
result.failure?  # => true/false

# Get value
result.value     # => Output or nil
result.value!    # => Output or raises error
result.value_or(default)  # => Output or default

# Transform
result.map { |output| output.user.name }  # => Result[String]
result.and_then { |output| UpdateProfileUseCase.call(user: output.user) }  # => Result[...]

# Handle errors
result.errors  # => Array[Error]
result.or_else { |errors| handle_errors(errors) }
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/senro_usecaser.
