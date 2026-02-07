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

### Runtime Type Validation

In addition to static type checking with RBS, SenroUsecaser provides runtime type validation for Input and Output. This ensures that the actual values passed at runtime match the expected types.

#### Input Type Validation

The `input` declaration supports three patterns:

##### 1. Class Validation (Traditional)

When a Class is specified, input must be an instance of that class:

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  input CreateUserInput  # Class

  def call(input)
    # input must be a CreateUserInput instance
    success(input.name)
  end
end

# OK
CreateUserUseCase.call(CreateUserInput.new(name: "Taro"))

# ArgumentError: Input must be an instance of CreateUserInput, got String
CreateUserUseCase.call("invalid")
```

##### 2. Interface Validation (Single Module)

When a Module is specified, input's class must include that module. This enables duck-typing with explicit interface contracts:

```ruby
# Define interface
module HasUserId
  def user_id
    raise NotImplementedError
  end
end

# UseCase expects input that includes HasUserId
class FindUserUseCase < SenroUsecaser::Base
  input HasUserId

  #: (HasUserId) -> SenroUsecaser::Result[User]
  def call(input)
    user = User.find(input.user_id)
    success(user)
  end
end

# Input class that implements the interface
class UserQuery
  include HasUserId

  attr_reader :user_id

  def initialize(user_id:)
    @user_id = user_id
  end
end

# OK - UserQuery includes HasUserId
FindUserUseCase.call(UserQuery.new(user_id: 123))

# ArgumentError: Input UserQuery must include HasUserId
class InvalidInput
  attr_reader :user_id
  def initialize(user_id:) = @user_id = user_id
end
FindUserUseCase.call(InvalidInput.new(user_id: 123))
```

##### 3. Multiple Interfaces Validation

Multiple Modules can be specified. The input must include ALL of them:

```ruby
module HasUserId
  def user_id = raise NotImplementedError
end

module HasEmail
  def email = raise NotImplementedError
end

# UseCase requires both interfaces
class NotifyUserUseCase < SenroUsecaser::Base
  input HasUserId, HasEmail

  #: ((HasUserId & HasEmail)) -> SenroUsecaser::Result[bool]
  def call(input)
    notify(input.user_id, input.email)
    success(true)
  end
end

# Input class must include both modules
class NotificationRequest
  include HasUserId
  include HasEmail

  attr_reader :user_id, :email

  def initialize(user_id:, email:)
    @user_id = user_id
    @email = email
  end
end

# OK
NotifyUserUseCase.call(NotificationRequest.new(user_id: 123, email: "test@example.com"))
```

##### Interface Pattern in Pipelines

Interface validation is especially useful for sub-UseCases in pipelines. A parent UseCase's Input can include multiple interfaces, and each step only requires the interfaces it needs:

```ruby
# Parent UseCase - Input includes both interfaces
class ProcessOrderUseCase < SenroUsecaser::Base
  class Input
    include HasUserId
    include HasEmail

    attr_reader :user_id, :email, :order_items

    def initialize(user_id:, email:, order_items:)
      @user_id = user_id
      @email = email
      @order_items = order_items
    end
  end

  input Input

  organize do
    step FindUserUseCase      # Only needs HasUserId
    step NotifyUserUseCase    # Needs HasUserId and HasEmail
    step CreateOrderUseCase
  end
end
```

#### Output Type Validation

When `output` is declared with a Class, the success result's value is validated:

```ruby
class UserOutput
  attr_reader :user
  def initialize(user:) = @user = user
end

class FindUserUseCase < SenroUsecaser::Base
  input FindUserInput
  output UserOutput  # Class declaration enables validation

  def call(input)
    user = User.find(input.user_id)
    success(UserOutput.new(user: user))  # OK

    # TypeError: Output must be an instance of UserOutput, got User
    # success(user)  # Wrong! Must wrap in UserOutput
  end
end
```

**Note:** When `output` is a Hash schema (e.g., `output({ user: User })`), validation is skipped for backwards compatibility.

**Note:** Type validation errors raise exceptions (`ArgumentError` for input, `TypeError` for output). See [`.call` vs `.call!`](#call-vs-call-1) for how exceptions are handled.

### Simplicity

Define UseCases with minimal boilerplate. Avoids over-abstraction and provides an intuitive API.

### UseCase Composition

Complex business operations can be composed from simpler UseCases using `organize` and `extend_with`.

#### organize - Sequential Execution

Execute multiple UseCases in sequence. Each step's output object becomes the next step's input directly (type chaining).

**Important:** All pipeline steps must define an `input` class. The output of step A should be compatible with the input of step B.

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

  # Each step's output becomes the next step's input:
  # PlaceOrderUseCase::Input -> ValidateOrderUseCase
  # ValidateOrderUseCase::Output -> CreateOrderUseCase::Input
  # CreateOrderUseCase::Output -> ChargePaymentUseCase::Input
  # ChargePaymentUseCase::Output -> SendConfirmationEmailUseCase::Input
  # SendConfirmationEmailUseCase::Output -> CreateOrderOutput
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

  # Condition methods receive the current input object (output from previous step)
  def has_coupon?(input)
    input.coupon_code.present?
  end

  def free_order?(input)
    input.total.zero?
  end

  def gift_order?(input)
    input.gift_recipient.present?
  end
end
```

##### Condition as Lambda

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step ApplyCouponUseCase, if: ->(input) { input.coupon_code.present? }
    step NotifyAdminUseCase, if: ->(input) { input.total > 10_000 }
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

By default, the previous step's output object is passed directly as input to the next step. Use `input:` to transform it:

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step ValidateOrderUseCase
    step CreateOrderUseCase

    # Method reference - transform current input for next step
    step SendEmailUseCase, input: :prepare_email_input

    # Lambda - transform current input
    step NotifyUseCase, input: ->(input) { NotifyInput.new(message: "Order #{input.order_id}") }
  end

  def prepare_email_input(input)
    SendEmailInput.new(to: input.customer_email, subject: "Order Confirmation")
  end
end
```

#### extend_with - Hooks (before/after/around)

Add cross-cutting concerns like logging, authorization, or transaction handling.

```ruby
# Define extension modules
module Logging
  def self.before(input)
    puts "Starting: #{input.class.name}"
  end

  def self.after(input, result)
    puts "Finished: #{result.success? ? 'success' : 'failure'}"
  end
end

module Transaction
  def self.around(input, &block)
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

Block hooks are executed in the UseCase instance context, allowing access to `depends_on` dependencies.

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :logger
  depends_on :metrics
  input Input

  # before/after blocks can access dependencies directly
  before do |input|
    logger.info("Starting with #{input.class.name}")
  end

  after do |input, result|
    logger.info("Finished: #{result.success? ? 'success' : 'failure'}")
    metrics.increment(:use_case_completed)
  end

  # around block receives use_case as second argument for dependency access
  around do |input, use_case, &block|
    use_case.logger.info("Transaction start")
    result = ActiveRecord::Base.transaction { block.call }
    use_case.logger.info("Transaction end")
    result
  end

  def call(input)
    # main logic
  end
end
```

##### Hook Classes

For more complex hooks with their own dependencies, use `SenroUsecaser::Hook` class:

```ruby
class LoggingHook < SenroUsecaser::Hook
  depends_on :logger
  depends_on :metrics

  def before(input)
    logger.info("Starting with #{input.class.name}")
  end

  def after(input, result)
    logger.info("Finished: #{result.success? ? 'success' : 'failure'}")
    metrics.increment(:use_case_completed)
  end

  def around(input)
    logger.info("Around start")
    result = yield
    logger.info("Around end")
    result
  end
end

class CreateUserUseCase < SenroUsecaser::Base
  extend_with LoggingHook

  def call(input)
    # main logic
  end
end
```

Hook classes support:
- `depends_on` for dependency injection
- `namespace` for scoped dependency resolution
- Automatic namespace inference from module structure (when `infer_namespace_from_module` is enabled)
- Inheriting namespace from the UseCase if not explicitly declared

```ruby
# Hook with explicit namespace
class Admin::AuditHook < SenroUsecaser::Hook
  namespace :admin
  depends_on :audit_logger

  def after(input, result)
    audit_logger.log(action: "create", success: result.success?)
  end
end

# Hook inheriting namespace from UseCase
class MetricsHook < SenroUsecaser::Hook
  depends_on :metrics  # resolved from UseCase's namespace

  def after(input, result)
    metrics.increment(:completed)
  end
end

class Admin::CreateUserUseCase < SenroUsecaser::Base
  namespace :admin
  extend_with MetricsHook  # metrics resolved from :admin namespace

  def call(input)
    # ...
  end
end
```

##### Using DependsOn in Custom Classes

The `SenroUsecaser::DependsOn` module can be used in any class to enable the same dependency injection features available in UseCase and Hook classes. This is useful for services, repositories, or other application components that need DI support.

**Basic Usage (No initialize needed)**

When you extend `DependsOn`, a default `initialize` is provided automatically. If no container is passed, it uses `SenroUsecaser.container`:

```ruby
class OrderService
  extend SenroUsecaser::DependsOn

  depends_on :order_repository, OrderRepository
  depends_on :payment_gateway, PaymentGateway
  depends_on :logger, Logger

  # No initialize needed! Default is provided automatically.

  def process_order(order_id)
    order = order_repository.find(order_id)
    logger.info("Processing order #{order_id}")
    payment_gateway.charge(order.total)
  end
end

# Usage - uses SenroUsecaser.container by default
service = OrderService.new
service.process_order(123)

# Or with explicit container
service = OrderService.new(container: custom_container)
```

**Custom initialize with super**

If you need additional parameters, define your own `initialize` and call `super`:

```ruby
class OrderService
  extend SenroUsecaser::DependsOn

  depends_on :order_repository, OrderRepository
  attr_reader :default_currency

  def initialize(default_currency: "JPY", container: nil)
    super(container: container)  # Handles dependency resolution
    @default_currency = default_currency
  end

  def process_order(order_id)
    order = order_repository.find(order_id)
    order.charge(currency: default_currency)
  end
end

# Uses SenroUsecaser.container by default
service = OrderService.new(default_currency: "USD")
service.default_currency  # => "USD"
service.order_repository  # => OrderRepository instance
```

**With Namespace**

```ruby
class Admin::ReportService
  extend SenroUsecaser::DependsOn

  namespace :admin
  depends_on :report_generator, ReportGenerator
  depends_on :logger, Logger  # Falls back to root namespace

  # No initialize needed!

  def generate_monthly_report
    logger.info("Generating monthly report")
    report_generator.generate(:monthly)
  end
end
```

**With Automatic Namespace Inference**

When `infer_namespace_from_module` is enabled, the namespace is automatically derived from the module structure:

```ruby
SenroUsecaser.configure do |config|
  config.infer_namespace_from_module = true
end

module Admin
  module Reports
    class ExportService
      extend SenroUsecaser::DependsOn

      # No explicit namespace needed!
      # Automatically uses "admin::reports" namespace
      depends_on :exporter, Exporter        # from admin::reports
      depends_on :storage, Storage          # from admin (fallback)
      depends_on :logger, Logger            # from root (fallback)

      # No initialize needed!

      def export(data)
        result = exporter.export(data)
        storage.save(result)
        logger.info("Export completed")
      end
    end
  end
end
```

**Features provided by DependsOn:**

- `depends_on :name, Type` - Declare dependencies with optional type hints
- `namespace :name` - Set explicit namespace for dependency resolution
- `declared_namespace` - Get the declared namespace
- `dependencies` - List of declared dependency names
- `dependency_types` - Hash of dependency name to type
- `copy_depends_on_to(subclass)` - Copy configuration to subclasses (for inheritance)

**Instance methods (via InstanceMethods module):**

- `initialize(container: nil)` - Default initialize that sets up dependency injection. Uses `SenroUsecaser.container` if no container is provided.
- `resolve_dependencies` - Resolve all declared dependencies from the container
- `effective_namespace` - Get the namespace used for resolution (declared or inferred)

**Custom initialize (full override):**

If you need complete control, you can manually set up the required instance variables:

```ruby
def initialize(extra:, container: nil)
  @_container = container || SenroUsecaser.container
  @_dependencies = {}
  @extra = extra
  resolve_dependencies
end
```

##### on_failure Hook

The `on_failure` hook is called only when the UseCase execution results in a failure. Unlike `after` which is always called, `on_failure` provides a dedicated hook for error handling, logging, or recovery logic.

**Block Syntax**

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  depends_on :logger
  depends_on :error_notifier
  input Input

  # on_failure block is executed in UseCase instance context
  # allowing access to dependencies
  on_failure do |input, result|
    logger.error("Failed to create user: #{result.errors.map(&:message).join(', ')}")
    error_notifier.notify(
      action: "create_user",
      input: input,
      errors: result.errors
    )
  end

  def call(input)
    user = User.create!(name: input.name, email: input.email)
    success(user)
  rescue ActiveRecord::RecordInvalid => e
    failure(Error.new(code: :validation_error, message: e.message))
  end
end
```

**Module Syntax (with extend_with)**

```ruby
module ErrorLogging
  def self.on_failure(input, result)
    Rails.logger.error("UseCase failed: #{result.errors.first&.message}")
  end
end

class CreateUserUseCase < SenroUsecaser::Base
  extend_with ErrorLogging

  def call(input)
    # ...
  end
end
```

**Hook Class Syntax**

```ruby
class ErrorNotificationHook < SenroUsecaser::Hook
  depends_on :error_notifier
  depends_on :logger

  def on_failure(input, result)
    logger.error("UseCase failed with #{result.errors.size} error(s)")
    error_notifier.notify(
      errors: result.errors,
      input_class: input.class.name,
      timestamp: Time.current
    )
  end
end

class CreateUserUseCase < SenroUsecaser::Base
  extend_with ErrorNotificationHook

  def call(input)
    # ...
  end
end
```

**Execution Order**

When a UseCase fails, hooks are executed in the following order:

1. `around` hooks (unwinding)
2. `after` hooks (always called, regardless of success/failure)
3. `on_failure` hooks (only called when `result.failure?` is true)

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  after do |input, result|
    puts "after: #{result.success? ? 'success' : 'failure'}"
  end

  on_failure do |input, result|
    puts "on_failure: handling error..."
  end

  def call(input)
    failure(Error.new(code: :error, message: "Something went wrong"))
  end
end

# Output:
# after: failure
# on_failure: handling error...
```

**Use Cases for on_failure**

- **Error logging**: Log detailed error information for debugging
- **Error notification**: Send alerts to monitoring systems (Sentry, Bugsnag, etc.)
- **Cleanup operations**: Rollback partial state changes on failure
- **Retry preparation**: Queue failed operations for retry
- **Metrics**: Increment failure counters for observability

##### on_failure in Pipelines (Rollback Behavior)

When using `organize` pipelines, the `on_failure` hook provides **rollback behavior**. If a step fails, the `on_failure` hooks of all previously successful steps are executed in **reverse order**.

This enables compensation logic (Saga pattern) where each step can define how to undo its changes when a later step fails.

```ruby
class CreateOrderUseCase < SenroUsecaser::Base
  input Input

  on_failure do |input, result|
    # Called if a later step fails
    Order.find_by(id: input.order_id)&.destroy
    puts "Rolled back: order creation"
  end

  def call(input)
    order = Order.create!(user_id: input.user_id)
    success(Output.new(order_id: order.id, user_id: input.user_id))
  end
end

class ReserveInventoryUseCase < SenroUsecaser::Base
  input Input

  on_failure do |input, result|
    # Called if a later step fails
    Inventory.release(order_id: input.order_id)
    puts "Rolled back: inventory reservation"
  end

  def call(input)
    Inventory.reserve(order_id: input.order_id)
    success(input)
  end
end

class ChargePaymentUseCase < SenroUsecaser::Base
  input Input

  on_failure do |input, result|
    # Called when this step itself fails (no rollback needed for self)
    puts "Payment failed: #{result.errors.first&.message}"
  end

  def call(input)
    # Payment fails
    failure(Error.new(code: :payment_failed, message: "Insufficient funds"))
  end
end

class PlaceOrderUseCase < SenroUsecaser::Base
  input Input

  organize do
    step CreateOrderUseCase       # Step 1: Success
    step ReserveInventoryUseCase  # Step 2: Success
    step ChargePaymentUseCase     # Step 3: Failure!
  end
end

result = PlaceOrderUseCase.call(input)
# Output (in order):
# Payment failed: Insufficient funds       <- ChargePaymentUseCase.on_failure
# Rolled back: inventory reservation       <- ReserveInventoryUseCase.on_failure
# Rolled back: order creation              <- CreateOrderUseCase.on_failure
```

**Execution Flow on Pipeline Failure:**

```
Step A (success) → Step B (success) → Step C (failure)
                                           ↓
                                    C.on_failure (failed step)
                                           ↓
                                    B.on_failure (rollback)
                                           ↓
                                    A.on_failure (rollback)
```

**Important Notes:**

1. **Reverse order**: `on_failure` hooks are called in reverse order of successful execution, ensuring proper cleanup sequence.

2. **Input context**: Each step's `on_failure` receives the input that was passed to that specific step (the output of the previous step), not the original pipeline input.

3. **Failed step included**: The step that failed also has its `on_failure` called (first, before rollback of previous steps).

4. **on_failure: :continue steps**: Steps marked with `on_failure: :continue` that fail will have their `on_failure` hook called, but won't trigger rollback of previous steps since the pipeline continues.

5. **Independent of on_failure_strategy**: The rollback behavior works consistently with `:stop`, `:continue`, and `:collect` strategies. For `:collect`, rollback occurs after all steps have been attempted.

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step CreateOrderUseCase
    step SendNotificationUseCase, on_failure: :continue  # Optional step
    step ChargePaymentUseCase
  end
end

# If SendNotificationUseCase fails:
# - SendNotificationUseCase.on_failure is called
# - Pipeline continues (no rollback of CreateOrderUseCase)
# - ChargePaymentUseCase executes

# If ChargePaymentUseCase fails:
# - ChargePaymentUseCase.on_failure is called
# - CreateOrderUseCase.on_failure is called (rollback)
# - SendNotificationUseCase.on_failure is NOT called (it was optional and didn't cause the failure)
```

##### Retry on Failure

SenroUsecaser provides retry functionality similar to ActiveJob, allowing automatic retry of failed UseCases with configurable strategies.

###### Basic Retry Configuration

Use `retry_on` to configure automatic retry for specific error codes or exception types:

```ruby
class FetchExternalDataUseCase < SenroUsecaser::Base
  input Input

  # Retry up to 3 times for specific error codes
  retry_on :network_error, :timeout_error, attempts: 3

  # Retry on specific exception types
  retry_on NetworkError, Timeout::Error, attempts: 5, wait: 1.second

  def call(input)
    response = ExternalAPI.fetch(input.url)
    success(response)
  rescue Timeout::Error => e
    failure(Error.new(code: :timeout_error, message: e.message, cause: e))
  end
end
```

###### Retry Options

| Option | Description | Default |
|--------|-------------|---------|
| `attempts` | Maximum number of retry attempts | 3 |
| `wait` | Time to wait between retries (seconds or Duration) | 0 |
| `backoff` | Backoff strategy (`:fixed`, `:linear`, `:exponential`) | `:fixed` |
| `max_wait` | Maximum wait time when using backoff | 1 hour |
| `jitter` | Add randomness to wait time (0.0 to 1.0) | 0 |

```ruby
class ProcessPaymentUseCase < SenroUsecaser::Base
  input Input

  # Exponential backoff: 1s, 2s, 4s, 8s... (capped at 30s)
  retry_on :gateway_error,
           attempts: 5,
           wait: 1.second,
           backoff: :exponential,
           max_wait: 30.seconds

  # Linear backoff with jitter: 2s, 4s, 6s... (±20% randomness)
  retry_on :rate_limited,
           attempts: 10,
           wait: 2.seconds,
           backoff: :linear,
           jitter: 0.2

  def call(input)
    PaymentGateway.charge(input.amount)
  end
end
```

###### Backoff Strategies Explained

The `backoff` option controls how wait time increases between retry attempts:

**`:fixed` (default)** - Same wait time for every retry.

```
wait: 2s
  Attempt 1 fails → wait 2s → Attempt 2
  Attempt 2 fails → wait 2s → Attempt 3
  Attempt 3 fails → wait 2s → Attempt 4
```

Best for: Temporary errors expected to recover quickly.

**`:linear`** - Wait time increases by a fixed amount each retry.

```
wait: 2s (formula: wait × attempt)
  Attempt 1 fails → wait 2s  → Attempt 2
  Attempt 2 fails → wait 4s  → Attempt 3
  Attempt 3 fails → wait 6s  → Attempt 4
  Attempt 4 fails → wait 8s  → Attempt 5
```

Best for: Load-related errors where gradual recovery is expected.

**`:exponential`** - Wait time doubles each retry (most aggressive backoff).

```
wait: 2s (formula: wait × 2^(attempt-1))
  Attempt 1 fails → wait 2s  → Attempt 2
  Attempt 2 fails → wait 4s  → Attempt 3
  Attempt 3 fails → wait 8s  → Attempt 4
  Attempt 4 fails → wait 16s → Attempt 5
```

Best for: Rate limiting, server overload, external API throttling.

**Summary:**

| Strategy | Formula | Use Case |
|----------|---------|----------|
| `:fixed` | `wait` | Quick recovery expected |
| `:linear` | `wait × attempt` | Gradual recovery expected |
| `:exponential` | `wait × 2^(attempt-1)` | Rate limits, heavy load |

**`max_wait`** caps the wait time to prevent excessive delays with `:exponential`:

```ruby
retry_on :api_error,
         wait: 1.second,
         backoff: :exponential,
         max_wait: 30.seconds  # Never wait more than 30s

# Without max_wait, attempt 10 would wait 512 seconds (8.5 minutes)!
# With max_wait: 30s, it caps at 30 seconds
```

**`jitter`** adds randomness to prevent thundering herd problem when many processes retry simultaneously:

```ruby
retry_on :api_error,
         wait: 2.seconds,
         backoff: :exponential,
         jitter: 0.25  # ±25% randomness

# Attempt 2 wait: 4s ± 1s (3s to 5s)
# Attempt 3 wait: 8s ± 2s (6s to 10s)
```

###### Manual Retry in on_failure

For more control, use `retry!` within an `on_failure` block:

```ruby
class SendEmailUseCase < SenroUsecaser::Base
  input Input

  on_failure do |input, result, context|
    if result.errors.any? { |e| e.code == :temporary_failure }
      # Retry with same input
      retry! if context.attempt < 3

      # Or retry with modified input
      retry!(input: ModifiedInput.new(input, fallback: true))

      # Or retry after delay
      retry!(wait: 5.seconds) if context.attempt < 5
    end
  end

  def call(input)
    Mailer.send(input.to, input.subject, input.body)
  end
end
```

###### Retry Context

The `on_failure` block receives a `context` object with retry information:

```ruby
on_failure do |input, result, context|
  context.attempt        # Current attempt number (1, 2, 3...)
  context.max_attempts   # Maximum attempts configured (nil if unlimited)
  context.retried?       # Whether this is a retry (attempt > 1)
  context.elapsed_time   # Total time elapsed since first attempt
  context.last_error     # The error from the previous attempt (if retried)
end
```

###### Discard (Don't Retry)

Use `discard_on` to skip retry for specific errors:

```ruby
class CreateUserUseCase < SenroUsecaser::Base
  input Input

  # Always retry on these
  retry_on :database_error, attempts: 3

  # Never retry on these (fail immediately)
  discard_on :validation_error, :duplicate_record

  def call(input)
    User.create!(input.to_h)
  end
end
```

###### Callbacks for Retry Events

```ruby
class ProcessOrderUseCase < SenroUsecaser::Base
  input Input

  retry_on :payment_error, attempts: 3

  # Called before each retry attempt
  before_retry do |input, result, context|
    logger.warn("Retrying attempt #{context.attempt + 1}...")
  end

  # Called when all retry attempts are exhausted
  after_retries_exhausted do |input, result, context|
    logger.error("All #{context.max_attempts} attempts failed")
    ErrorNotifier.notify(result.errors, attempts: context.attempt)
  end

  def call(input)
    # ...
  end
end
```

###### Retry in Pipelines

When a step in a pipeline fails and retries, the behavior depends on the retry outcome:

```ruby
class PlaceOrderUseCase < SenroUsecaser::Base
  organize do
    step CreateOrderUseCase
    step ChargePaymentUseCase    # Has retry_on :gateway_error, attempts: 3
    step SendConfirmationUseCase
  end
end
```

**Retry succeeds**: Pipeline continues to the next step normally.

```
CreateOrder ✓ → ChargePayment ✗ → (retry) → ChargePayment ✓ → SendConfirmation ✓
```

**Retry exhausted**: Pipeline fails and rollback is triggered.

```
CreateOrder ✓ → ChargePayment ✗ → (retry x3) → ChargePayment ✗ (exhausted)
                     ↓
              ChargePayment.on_failure
                     ↓
              CreateOrder.on_failure (rollback)
```

###### Combining retry_on with on_failure

`retry_on` is evaluated first. If retries are exhausted or the error is discarded, `on_failure` is called:

```ruby
class ProcessPaymentUseCase < SenroUsecaser::Base
  input Input

  retry_on :gateway_error, attempts: 3
  discard_on :invalid_card

  on_failure do |input, result, context|
    if context.retried?
      # All retries exhausted
      logger.error("Payment failed after #{context.attempt} attempts")
    else
      # First failure (discarded or non-retryable error)
      logger.error("Payment failed immediately: #{result.errors.first&.code}")
    end
  end

  def call(input)
    # ...
  end
end
```

###### Execution Flow with Retry

```
call(input)
    ↓
  failure ←──────────────────────────────┐
    ↓                                    │
  retry_on matches? ──yes──→ attempt < max?
    ↓ no                         ↓ yes   │ no
    ↓                    wait → retry ───┘
    ↓                            ↓
    └────────────────────────────┴──→ on_failure
                                            ↓
                                      (rollback if pipeline)
```

##### Input/Output Validation

Use `extend_with` to integrate validation libraries like ActiveModel::Validations:

```ruby
# Define validation extension
module InputValidation
  def self.around(input, &block)
    # input is the input object passed to call
    return block.call unless input.respond_to?(:validate!)

    input.validate!
    block.call
  rescue ActiveModel::ValidationError => e
    errors = e.model.errors.map do |error|
      SenroUsecaser::Error.new(
        code: :validation_error,
        field: error.attribute,
        message: error.full_message
      )
    end
    SenroUsecaser::Result.failure(*errors)
  end
end

module OutputValidation
  def self.after(input, result)
    return unless result.success?

    output = result.value
    output.validate! if output.respond_to?(:validate!)
  rescue ActiveModel::ValidationError => e
    Rails.logger.error("Output validation failed: #{e.message}")
  end
end

# Input class with ActiveModel validations
class CreateUserInput
  include ActiveModel::Validations

  attr_accessor :name, :email

  validates :name, presence: true, length: { minimum: 2 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def initialize(name:, email:)
    @name = name
    @email = email
  end
end

# Apply validation to UseCase using input class declaration
class CreateUserUseCase < SenroUsecaser::Base
  input CreateUserInput
  extend_with InputValidation, OutputValidation

  def call(user_input)
    # user_input is already validated by InputValidation hook
    User.create!(name: user_input.name, email: user_input.email)
  end
end

# Usage - pass input object directly
input = CreateUserInput.new(name: "", email: "invalid")
result = CreateUserUseCase.call(input)
result.failure?  # => true
result.errors.first.field  # => :name
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

**Type validation errors** (from `input` and `output` declarations) also follow this pattern:

```ruby
# With .call - type validation errors raise exceptions
begin
  UseCase.call(invalid_input)
rescue ArgumentError => e
  puts e.message  # "Input SomeClass must include HasUserId"
end

# With .call! - type validation errors become Result.failure
result = UseCase.call!(invalid_input)
result.failure?              # => true
result.errors.first.code     # => :exception
result.errors.first.message  # => "Input SomeClass must include HasUserId"
```

| Validation | Exception type | With `.call` | With `.call!` |
|------------|---------------|--------------|---------------|
| Input type | `ArgumentError` | Raises | `Result.failure` |
| Output type | `TypeError` | Raises | `Result.failure` |

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

## Roadmap

The following features are planned for future releases:

- **Parallel execution in organize** - Execute multiple steps concurrently within a pipeline for improved performance
- **Ruby LSP extension for Container** - IDE autocompletion support for dependency injection with Container
- **Automatic RBS generation** - Auto-generate RBS type definitions for `input`, `output`, `call`, and `depends_on` declarations
