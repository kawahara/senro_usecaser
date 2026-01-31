# frozen_string_literal: true

RSpec.describe SenroUsecaser::Base do
  # Reset global container before each test
  before { SenroUsecaser.reset_container! }

  # Test UseCase that returns success
  let(:success_use_case) do
    Class.new(described_class) do
      def call(value:)
        success(value)
      end
    end
  end

  # Test UseCase that returns failure
  let(:failure_use_case) do
    Class.new(described_class) do
      def call(message:)
        failure(SenroUsecaser::Error.new(code: :test_error, message: message))
      end
    end
  end

  # Test UseCase that raises an exception
  let(:raising_use_case) do
    Class.new(described_class) do
      def call(message:)
        raise StandardError, message
      end
    end
  end

  # Test UseCase that uses capture
  let(:capture_use_case) do
    Class.new(described_class) do
      def call(should_raise:)
        capture(code: :captured) do
          raise StandardError, "Error" if should_raise

          "success"
        end
      end
    end
  end

  describe ".call" do
    it "creates an instance and calls #call" do
      result = success_use_case.call(value: "hello")

      expect(result).to be_success
      expect(result.value).to eq("hello")
    end

    it "returns failure result" do
      result = failure_use_case.call(message: "Something went wrong")

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Something went wrong")
    end
  end

  describe ".call!" do
    it "returns success result when no exception is raised" do
      result = success_use_case.call!(value: "hello")

      expect(result).to be_success
      expect(result.value).to eq("hello")
    end

    it "captures exceptions and returns failure result" do
      result = raising_use_case.call!(message: "Error occurred")

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Error occurred")
      expect(result.errors.first.code).to eq(:exception)
    end

    context "with organize pipeline" do
      it "captures exceptions in steps and collects them with on_failure: :collect" do
        raising_step1 = Class.new(described_class) do
          def call(**_args)
            raise StandardError, "Error in step 1"
          end
        end

        raising_step2 = Class.new(described_class) do
          def call(**_args)
            raise StandardError, "Error in step 2"
          end
        end

        organized = Class.new(described_class) do
          organize raising_step1, raising_step2, on_failure: :collect
        end

        result = organized.call!(value: 1)

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:message)).to eq(["Error in step 1", "Error in step 2"])
        expect(result.errors.map(&:code)).to eq(%i[exception exception])
      end

      it "collects both exceptions and explicit failures" do
        raising_step = Class.new(described_class) do
          def call(**_args)
            raise StandardError, "Exception error"
          end
        end

        failure_step = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :validation_error, message: "Validation failed"))
          end
        end

        organized = Class.new(described_class) do
          organize raising_step, failure_step, on_failure: :collect
        end

        result = organized.call!(value: 1)

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:code)).to eq(%i[exception validation_error])
      end

      it "stops on first exception with on_failure: :stop (default)" do
        call_count = 0
        raising_step = Class.new(described_class) do
          define_method(:call) do |**_args|
            raise StandardError, "Error in step"
          end
        end

        tracking_step = Class.new(described_class) do
          define_method(:call) do |**_args|
            call_count += 1
            success({ tracked: true })
          end
        end

        organized = Class.new(described_class) do
          organize raising_step, tracking_step
        end

        result = organized.call!(value: 1)

        expect(result).to be_failure
        expect(result.errors.size).to eq(1)
        expect(call_count).to eq(0)
      end

      it "chains call! to nested organize pipelines" do
        inner_raising_step = Class.new(described_class) do
          def call(**_args)
            raise StandardError, "Inner error"
          end
        end

        inner_organized = Class.new(described_class) do
          organize inner_raising_step, on_failure: :collect
        end

        outer_raising_step = Class.new(described_class) do
          def call(**_args)
            raise StandardError, "Outer error"
          end
        end

        outer_organized = Class.new(described_class) do
          organize inner_organized, outer_raising_step, on_failure: :collect
        end

        result = outer_organized.call!(value: 1)

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:message)).to eq(["Inner error", "Outer error"])
      end
    end
  end

  describe ".call_with_capture" do
    it "captures exceptions with custom code" do
      result = raising_use_case.call_with_capture(
        input: { message: "Error" },
        code: :custom_error
      )

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:custom_error)
    end

    it "captures only specified exception classes" do
      result = raising_use_case.call_with_capture(
        input: { message: "Error" },
        exception_classes: [StandardError],
        code: :specific_error
      )

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:specific_error)
    end
  end

  describe "#call" do
    it "raises NotImplementedError when not overridden" do
      expect { described_class.new.call }.to raise_error(NotImplementedError)
    end
  end

  describe "#success" do
    it "is available in subclasses" do
      result = success_use_case.call(value: { id: 1, name: "Test" })

      expect(result).to be_success
      expect(result.value).to eq({ id: 1, name: "Test" })
    end
  end

  describe "#failure" do
    it "is available in subclasses" do
      result = failure_use_case.call(message: "Invalid input")

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:test_error)
    end
  end

  describe "#capture" do
    it "returns success when block succeeds" do
      result = capture_use_case.call(should_raise: false)

      expect(result).to be_success
      expect(result.value).to eq("success")
    end

    it "returns failure when block raises" do
      result = capture_use_case.call(should_raise: true)

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:captured)
      expect(result.errors.first.message).to eq("Error")
    end
  end

  describe "#failure_from_exception" do
    let(:exception_handling_use_case) do
      Class.new(described_class) do
        def call(should_raise:)
          raise StandardError, "Error" if should_raise

          success("ok")
        rescue StandardError => e
          failure_from_exception(e, code: :handled_error)
        end
      end
    end

    it "creates failure from exception" do
      result = exception_handling_use_case.call(should_raise: true)

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:handled_error)
      expect(result.errors.first.cause).to be_a(StandardError)
    end
  end

  describe ".depends_on" do
    let(:use_case_with_dependencies) do
      Class.new(described_class) do
        depends_on :user_repository
        depends_on :logger

        def call(name:)
          logger.log("Creating user: #{name}")
          user = user_repository.create(name: name)
          success(user)
        end
      end
    end

    let(:mock_repository) do
      repo = Object.new
      def repo.create(name:)
        { id: 1, name: name }
      end
      repo
    end

    let(:mock_logger) do
      logger = Object.new
      def logger.log(message)
        @messages ||= []
        @messages << message
      end

      def logger.messages
        @messages || []
      end
      logger
    end

    it "registers dependencies" do
      expect(use_case_with_dependencies.dependencies).to eq(%i[user_repository logger])
    end

    it "resolves dependencies from global container" do
      SenroUsecaser.container.register(:user_repository, mock_repository)
      SenroUsecaser.container.register(:logger, mock_logger)

      result = use_case_with_dependencies.call(name: "Taro")

      expect(result).to be_success
      expect(result.value).to eq({ id: 1, name: "Taro" })
      expect(mock_logger.messages).to include("Creating user: Taro")
    end

    it "resolves dependencies from custom container" do
      container = SenroUsecaser::Container.new
      container.register(:user_repository, mock_repository)
      container.register(:logger, mock_logger)

      result = use_case_with_dependencies.call(name: "Jiro", container: container)

      expect(result).to be_success
      expect(result.value).to eq({ id: 1, name: "Jiro" })
    end

    it "allows manual dependency injection for testing" do
      use_case = use_case_with_dependencies.new(dependencies: {
                                                  user_repository: mock_repository,
                                                  logger: mock_logger
                                                })

      result = use_case.call(name: "Saburo")

      expect(result).to be_success
      expect(result.value).to eq({ id: 1, name: "Saburo" })
    end
  end

  describe ".namespace" do
    let(:namespaced_use_case) do
      Class.new(described_class) do
        namespace :admin
        depends_on :user_repository

        def call(name:)
          user = user_repository.create(name: name)
          success(user)
        end
      end
    end

    let(:mock_admin_repository) do
      repo = Object.new
      def repo.create(name:)
        { id: 1, name: name, admin: true }
      end
      repo
    end

    it "sets the namespace" do
      expect(namespaced_use_case.use_case_namespace).to eq(:admin)
    end

    it "resolves dependencies from namespace" do
      repo = mock_admin_repository
      SenroUsecaser.container.namespace(:admin) do
        register(:user_repository, repo)
      end

      result = namespaced_use_case.call(name: "Admin User")

      expect(result).to be_success
      expect(result.value).to eq({ id: 1, name: "Admin User", admin: true })
    end

    it "resolves dependencies from parent namespace" do
      mock_logger = Object.new
      SenroUsecaser.container.register(:logger, mock_logger)

      use_case = Class.new(described_class) do
        namespace :admin
        depends_on :logger

        def call
          success(logger)
        end
      end

      result = use_case.call

      expect(result).to be_success
      expect(result.value).to eq(mock_logger)
    end
  end

  describe "inheritance" do
    let(:parent_use_case) do
      Class.new(described_class) do
        depends_on :logger
        namespace :parent
      end
    end

    let(:child_use_case) do
      Class.new(parent_use_case) do
        depends_on :repository
      end
    end

    it "inherits dependencies from parent" do
      expect(child_use_case.dependencies).to include(:logger)
      expect(child_use_case.dependencies).to include(:repository)
    end

    it "inherits namespace from parent" do
      expect(child_use_case.use_case_namespace).to eq(:parent)
    end

    it "does not modify parent dependencies" do
      expect(parent_use_case.dependencies).to eq([:logger])
    end
  end

  describe ".organize" do
    # Step 1: Validates input and returns validated data
    let(:validate_step) do
      Class.new(described_class) do
        def call(name:, price:)
          return failure(SenroUsecaser::Error.new(code: :invalid_name, message: "Name is required")) if name.empty?

          if price <= 0
            return failure(SenroUsecaser::Error.new(code: :invalid_price,
                                                    message: "Price must be positive"))
          end

          success({ name: name, price: price, validated: true })
        end
      end
    end

    # Step 2: Calculates tax
    let(:calculate_tax_step) do
      Class.new(described_class) do
        def call(name:, price:, validated:)
          tax = (price * 0.1).round
          success({ name: name, price: price, tax: tax, validated: validated })
        end
      end
    end

    # Step 3: Creates order
    let(:create_order_step) do
      Class.new(described_class) do
        def call(name:, price:, tax:, **_extra)
          success({ order_id: 123, name: name, total: price + tax })
        end
      end
    end

    # Step that always fails
    let(:failing_step) do
      Class.new(described_class) do
        def call(**_args)
          failure(SenroUsecaser::Error.new(code: :step_failed, message: "This step always fails"))
        end
      end
    end

    describe "basic pipeline" do
      it "executes UseCases in sequence" do
        step1 = validate_step
        step2 = calculate_tax_step
        step3 = create_order_step

        organized = Class.new(described_class) do
          organize step1, step2, step3
        end

        result = organized.call(name: "Product", price: 1000)

        expect(result).to be_success
        expect(result.value[:order_id]).to eq(123)
        expect(result.value[:total]).to eq(1100)
      end

      it "passes previous result as input to next step" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(name: "Test", price: 500)

        expect(result).to be_success
        expect(result.value[:tax]).to eq(50)
        expect(result.value[:validated]).to be true
      end
    end

    describe "on_failure: :stop (default)" do
      it "stops on first failure" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(name: "", price: 1000)

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:invalid_name)
      end

      it "does not execute subsequent steps after failure" do
        step1 = failing_step
        validate_step

        call_count = 0
        tracking_step = Class.new(described_class) do
          define_method(:call) do |**_args|
            call_count += 1
            success({ tracked: true })
          end
        end

        organized = Class.new(described_class) do
          organize step1, tracking_step
        end

        organized.call(name: "Test", price: 100)

        expect(call_count).to eq(0)
      end
    end

    describe "on_failure: :continue" do
      it "continues execution after failure" do
        step1 = failing_step

        call_count = 0
        tracking_step = Class.new(described_class) do
          define_method(:call) do |**_args|
            call_count += 1
            success({ tracked: true })
          end
        end

        organized = Class.new(described_class) do
          organize step1, tracking_step, on_failure: :continue
        end

        organized.call(name: "Test", price: 100)

        expect(call_count).to eq(1)
      end

      it "returns the last result" do
        fail_step = failing_step
        final_step = Class.new(described_class) do
          def call(**_args)
            success({ final: true })
          end
        end

        organized = Class.new(described_class) do
          organize fail_step, final_step, on_failure: :continue
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:final]).to be true
      end
    end

    describe "on_failure: :collect" do
      it "collects all errors" do
        failing1 = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error1, message: "Error 1"))
          end
        end

        failing2 = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error2, message: "Error 2"))
          end
        end

        organized = Class.new(described_class) do
          organize failing1, failing2, on_failure: :collect
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_failure
        expect(result.errors.map(&:code)).to eq(%i[error1 error2])
      end

      it "returns success if no errors" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2, on_failure: :collect
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
      end

      it "continues with last successful input after failure" do
        failing1 = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error1, message: "Error 1"))
          end
        end

        success_step = Class.new(described_class) do
          def call(name:, **_extra)
            success({ name: name, processed: true })
          end
        end

        organized = Class.new(described_class) do
          organize success_step, failing1, on_failure: :collect
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:error1)
      end
    end

    describe "with non-hash result values" do
      it "wraps non-hash values in a hash with :value key" do
        string_step = Class.new(described_class) do
          def call(**_args)
            success("string result")
          end
        end

        receiver_step = Class.new(described_class) do
          def call(value:)
            success({ received: value })
          end
        end

        organized = Class.new(described_class) do
          organize string_step, receiver_step
        end

        result = organized.call(input: "test")

        expect(result).to be_success
        expect(result.value[:received]).to eq("string result")
      end
    end

    describe "inheritance" do
      it "inherits organize configuration" do
        step1 = validate_step
        step2 = calculate_tax_step

        parent = Class.new(described_class) do
          organize step1, step2
        end

        child = Class.new(parent)

        result = child.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:tax]).to eq(10)
      end
    end

    describe "block syntax with step" do
      it "executes steps in sequence" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize do
            step step1
            step step2
          end
        end

        result = organized.call(name: "Product", price: 1000)

        expect(result).to be_success
        expect(result.value[:tax]).to eq(100)
      end
    end

    describe "conditional execution with if:" do
      it "executes step when condition is true (symbol)" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(name:, price:, validated:)
            success({ name: name, price: price, validated: validated, optional: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: :should_run_optional?
          end

          define_method(:should_run_optional?) do |_context|
            true
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:optional]).to be true
      end

      it "skips step when condition is false (symbol)" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(**_args)
            success({ optional: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: :should_run_optional?
          end

          define_method(:should_run_optional?) do |_context|
            false
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:optional]).to be_nil
      end

      it "executes step when lambda condition is true" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(name:, price:, validated:)
            success({ name: name, price: price, validated: validated, discounted: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: ->(ctx) { ctx[:price] > 50 }
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:discounted]).to be true
      end

      it "skips step when lambda condition is false" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(**_args)
            success({ discounted: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: ->(ctx) { ctx[:price] > 200 }
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:discounted]).to be_nil
      end
    end

    describe "conditional execution with unless:" do
      it "executes step when condition is false" do
        step1 = validate_step
        charge_step = Class.new(described_class) do
          def call(name:, price:, validated:)
            success({ name: name, price: price, validated: validated, charged: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step charge_step, unless: :free_order?
          end

          define_method(:free_order?) do |context|
            context[:price].zero?
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:charged]).to be true
      end

      it "skips step when condition is true" do
        # Simple step that just passes through
        pass_step = Class.new(described_class) do
          def call(name:, amount:)
            success({ name: name, amount: amount })
          end
        end
        charge_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(charged: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step pass_step
            step charge_step, unless: :free_order?
          end

          define_method(:free_order?) do |context|
            context[:amount].zero?
          end
        end

        result = organized.call(name: "Free", amount: 0)

        expect(result).to be_success
        expect(result.value[:charged]).to be_nil
        expect(result.value[:name]).to eq("Free")
      end
    end

    describe "multiple conditions with all:" do
      it "executes step when all conditions are true" do
        step1 = validate_step
        guarded_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(guarded: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step guarded_step, all: %i[has_name? has_valid_price?]
          end

          define_method(:has_name?) do |ctx|
            !ctx[:name].to_s.empty?
          end

          define_method(:has_valid_price?) do |ctx|
            ctx[:price].to_i > 0
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:guarded]).to be true
      end

      it "skips step when any condition is false" do
        step1 = validate_step
        guarded_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(guarded: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step guarded_step, all: %i[always_true? always_false?]
          end

          define_method(:always_true?) do |_ctx|
            true
          end

          define_method(:always_false?) do |_ctx|
            false
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:guarded]).to be_nil
      end

      it "supports lambda conditions in all:" do
        step1 = validate_step
        guarded_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(guarded: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step guarded_step, all: [
              ->(ctx) { ctx[:name].length > 2 },
              ->(ctx) { ctx[:price] > 50 }
            ]
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:guarded]).to be true
      end
    end

    describe "multiple conditions with any:" do
      it "executes step when any condition is true" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(optional: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, any: %i[is_premium? is_admin?]
          end

          define_method(:is_premium?) do |_ctx|
            false
          end

          define_method(:is_admin?) do |_ctx|
            true
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:optional]).to be true
      end

      it "skips step when all conditions are false" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(optional: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, any: %i[is_premium? is_admin?]
          end

          define_method(:is_premium?) do |_ctx|
            false
          end

          define_method(:is_admin?) do |_ctx|
            false
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:optional]).to be_nil
      end

      it "supports lambda conditions in any:" do
        step1 = validate_step
        optional_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(optional: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, any: [
              ->(ctx) { ctx[:price] > 1000 },  # false
              ->(ctx) { ctx[:name] == "Test" } # true
            ]
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:optional]).to be true
      end
    end

    describe "custom input mapping with input:" do
      it "maps input using a hash" do
        passthrough_step = Class.new(described_class) do
          def call(**args)
            success(args)
          end
        end
        user_step = Class.new(described_class) do
          def call(user_name:, user_email:)
            success({ user: { name: user_name, email: user_email } })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step passthrough_step
            step user_step, input: { user_name: :name, user_email: :email }
          end
        end

        result = organized.call(name: "Taro", email: "taro@example.com", price: 100)

        expect(result).to be_success
        expect(result.value[:user]).to eq({ name: "Taro", email: "taro@example.com" })
      end

      it "maps input using a symbol (method)" do
        passthrough_step = Class.new(described_class) do
          def call(**args)
            success(args)
          end
        end
        order_step = Class.new(described_class) do
          def call(order_name:, total:)
            success({ order: { name: order_name, total: total } })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step passthrough_step
            step order_step, input: :prepare_order_input
          end

          define_method(:prepare_order_input) do |ctx|
            { order_name: ctx[:name], total: ctx[:price] + ctx[:tax].to_i }
          end
        end

        result = organized.call(name: "Product", price: 100, tax: 10)

        expect(result).to be_success
        expect(result.value[:order]).to eq({ name: "Product", total: 110 })
      end

      it "maps input using a lambda" do
        passthrough_step = Class.new(described_class) do
          def call(**args)
            success(args)
          end
        end
        summary_step = Class.new(described_class) do
          def call(summary:)
            success({ summary: summary })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step passthrough_step
            step summary_step, input: ->(ctx) { { summary: "#{ctx[:name]}: $#{ctx[:price]}" } }
          end
        end

        result = organized.call(name: "Widget", price: 50)

        expect(result).to be_success
        expect(result.value[:summary]).to eq("Widget: $50")
      end

      it "passes through context when input is not specified" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize do
            step step1
            step step2
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:tax]).to eq(10)
      end
    end

    describe "per-step on_failure" do
      it "continues on failure for specific step with on_failure: :continue" do
        step1 = validate_step
        fail_step = failing_step
        final_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(final: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step fail_step, on_failure: :continue
            step final_step
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(result.value[:final]).to be true
      end

      it "stops on failure for step without on_failure override" do
        fail_step = failing_step
        final_step = Class.new(described_class) do
          def call(**_args)
            success({ final: true })
          end
        end

        organized = Class.new(described_class) do
          organize do
            step fail_step
            step final_step
          end
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_failure
      end

      it "per-step :stop overrides global :continue" do
        call_count = 0
        success_step = Class.new(described_class) do
          define_method(:call) do |**args|
            success(args)
          end
        end

        normal_fail = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :normal, message: "Normal failure"))
          end
        end

        critical_fail = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :critical, message: "Critical failure"))
          end
        end

        tracking_step = Class.new(described_class) do
          define_method(:call) do |**args|
            call_count += 1
            success(args.merge(tracked: true))
          end
        end

        organized = Class.new(described_class) do
          organize on_failure: :continue do
            step success_step
            step normal_fail                        # continues due to global :continue
            step critical_fail, on_failure: :stop   # stops here
            step tracking_step                      # should not run
          end
        end

        result = organized.call(value: 1)

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:critical)
        expect(call_count).to eq(0)
      end

      it "per-step :stop overrides global :collect and collects errors up to that point" do
        call_count = 0
        fail1 = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error1, message: "Error 1"))
          end
        end

        fail2_critical = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error2_critical, message: "Error 2 critical"))
          end
        end

        tracking_step = Class.new(described_class) do
          define_method(:call) do |**args|
            call_count += 1
            success(args)
          end
        end

        organized = Class.new(described_class) do
          organize on_failure: :collect do
            step fail1                               # collected
            step fail2_critical, on_failure: :stop   # collected then stops
            step tracking_step                       # should not run
          end
        end

        result = organized.call(value: 1)

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:code)).to eq(%i[error1 error2_critical])
        expect(call_count).to eq(0)
      end
    end

    describe "accumulated_context" do
      it "accumulates data from all steps" do
        step1 = Class.new(described_class) do
          def call(name:, price:)
            success({ name: name, price: price, step1_done: true })
          end
        end

        step2 = Class.new(described_class) do
          def call(name:, price:, step1_done:)
            tax = (price * 0.1).round
            success({ name: name, price: price, tax: tax, step1_done: step1_done, step2_done: true })
          end
        end

        check_context = nil
        step3 = Class.new(described_class) do
          define_method(:call) do |**args|
            check_context = args
            success(args.merge(step3_done: true))
          end
        end

        organized = Class.new(described_class) do
          organize step1, step2, step3
        end

        result = organized.call(name: "Test", price: 100)

        expect(result).to be_success
        expect(check_context).to include(step1_done: true, step2_done: true)
      end

      it "allows condition checks using accumulated_context" do
        user_step = Class.new(described_class) do
          def call(user_id:)
            success({ user_id: user_id, user: { id: user_id, name: "User #{user_id}" } })
          end
        end

        profile_step = Class.new(described_class) do
          def call(**args)
            success(args.merge(profile_loaded: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step user_step
            step profile_step, if: :has_user?
          end

          define_method(:has_user?) do |_ctx|
            accumulated_context[:user].is_a?(Hash)
          end
        end

        result = organized.call(user_id: 1)

        expect(result).to be_success
        expect(result.value[:profile_loaded]).to be true
      end

      it "includes initial args in accumulated_context" do
        received_accumulated = nil

        step1 = Class.new(described_class) do
          def call(**args)
            success(args.merge(processed: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1, if: :check_initial_args?
          end

          define_method(:check_initial_args?) do |_ctx|
            received_accumulated = accumulated_context.dup
            true
          end
        end

        organized.call(initial: "value", count: 42)

        expect(received_accumulated).to include(initial: "value", count: 42)
      end

      it "updates accumulated_context after each successful step" do
        contexts_at_each_step = []

        step1 = Class.new(described_class) do
          def call(**args)
            success(args.merge(from_step1: "data1"))
          end
        end

        step2 = Class.new(described_class) do
          def call(**args)
            success(args.merge(from_step2: "data2"))
          end
        end

        step3 = Class.new(described_class) do
          def call(**args)
            success(args.merge(from_step3: "data3"))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1, if: :record_context
            step step2, if: :record_context
            step step3, if: :record_context
          end

          define_method(:record_context) do |_ctx|
            contexts_at_each_step << accumulated_context.dup
            true
          end
        end

        organized.call(initial: true)

        expect(contexts_at_each_step[0]).to eq({ initial: true })
        expect(contexts_at_each_step[1]).to include(initial: true, from_step1: "data1")
        expect(contexts_at_each_step[2]).to include(initial: true, from_step1: "data1", from_step2: "data2")
      end
    end
  end

  describe "hooks" do
    describe "before hook" do
      it "runs before the main call" do
        call_order = []

        use_case = Class.new(described_class) do
          before { call_order << :before }

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[before call])
      end

      it "receives context as argument" do
        received_context = nil

        use_case = Class.new(described_class) do
          before { |ctx| received_context = ctx }

          def call(name:)
            success(name)
          end
        end

        use_case.call(name: "Test")

        expect(received_context).to eq({ name: "Test" })
      end
    end

    describe "after hook" do
      it "runs after the main call" do
        call_order = []

        use_case = Class.new(described_class) do
          after { call_order << :after }

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[call after])
      end

      it "receives context and result as arguments" do
        received_context = nil
        received_result = nil

        use_case = Class.new(described_class) do
          after do |ctx, result|
            received_context = ctx
            received_result = result
          end

          def call(value:)
            success(value * 2)
          end
        end

        use_case.call(value: 21)

        expect(received_context).to eq({ value: 21 })
        expect(received_result.value).to eq(42)
      end
    end

    describe "around hook" do
      it "wraps the main call" do
        call_order = []

        use_case = Class.new(described_class) do
          around do |_ctx, &block|
            call_order << :around_before
            result = block.call
            call_order << :around_after
            result
          end

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[around_before call around_after])
      end

      it "can modify the result" do
        use_case = Class.new(described_class) do
          around do |_ctx, &block|
            result = block.call
            if result.success?
              SenroUsecaser::Result.success(result.value.merge(wrapped: true))
            else
              result
            end
          end

          def call(value:)
            success({ value: value })
          end
        end

        result = use_case.call(value: 42)

        expect(result.value).to eq({ value: 42, wrapped: true })
      end

      it "can short-circuit execution" do
        call_count = 0

        use_case = Class.new(described_class) do
          around do |ctx, &block|
            if ctx[:skip]
              SenroUsecaser::Result.success(:skipped)
            else
              block.call
            end
          end

          define_method(:call) do |**_args|
            call_count += 1
            success(:executed)
          end
        end

        result = use_case.call(skip: true)

        expect(result.value).to eq(:skipped)
        expect(call_count).to eq(0)
      end
    end

    describe "multiple hooks" do
      it "runs hooks in order: before -> around -> call -> around -> after" do
        call_order = []

        use_case = Class.new(described_class) do
          before { call_order << :before1 }
          before { call_order << :before2 }

          around do |_ctx, &block|
            call_order << :around1_before
            result = block.call
            call_order << :around1_after
            result
          end

          around do |_ctx, &block|
            call_order << :around2_before
            result = block.call
            call_order << :around2_after
            result
          end

          after { call_order << :after1 }
          after { call_order << :after2 }

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[
                                   before1 before2
                                   around1_before around2_before
                                   call
                                   around2_after around1_after
                                   after1 after2
                                 ])
      end
    end

    describe "extend_with" do
      it "runs extension hooks" do
        call_order = []

        logging_extension = Module.new do
          define_singleton_method(:before) do |_ctx|
            call_order << :log_before
          end

          define_singleton_method(:after) do |_ctx, _result|
            call_order << :log_after
          end
        end

        use_case = Class.new(described_class) do
          extend_with logging_extension

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[log_before call log_after])
      end

      it "runs multiple extension hooks in order" do
        call_order = []

        ext1 = Module.new do
          define_singleton_method(:before) { |_| call_order << :ext1_before }
          define_singleton_method(:after) { |_, _| call_order << :ext1_after }
        end

        ext2 = Module.new do
          define_singleton_method(:before) { |_| call_order << :ext2_before }
          define_singleton_method(:after) { |_, _| call_order << :ext2_after }
        end

        use_case = Class.new(described_class) do
          extend_with ext1, ext2

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[ext1_before ext2_before call ext1_after ext2_after])
      end

      it "supports around hooks in extensions" do
        call_order = []

        transaction_extension = Module.new do
          define_singleton_method(:around) do |_ctx, &block|
            call_order << :transaction_begin
            result = block.call
            call_order << :transaction_commit
            result
          end
        end

        use_case = Class.new(described_class) do
          extend_with transaction_extension

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        use_case.call

        expect(call_order).to eq(%i[transaction_begin call transaction_commit])
      end
    end

    describe "inheritance" do
      it "inherits hooks from parent" do
        call_order = []

        parent = Class.new(described_class) do
          before { call_order << :parent_before }
        end

        child = Class.new(parent) do
          before { call_order << :child_before }

          define_method(:call) do |**_args|
            call_order << :call
            success(:done)
          end
        end

        child.call

        expect(call_order).to eq(%i[parent_before child_before call])
      end
    end
  end

  describe "implicit success wrapping" do
    describe "single UseCase" do
      it "wraps plain value in Result.success" do
        use_case = Class.new(described_class) do
          def call(value:)
            value * 2
          end
        end

        result = use_case.call(value: 21)

        expect(result).to be_success
        expect(result.value).to eq(42)
      end

      it "wraps nil in Result.success" do
        use_case = Class.new(described_class) do
          def call(**_args)
            nil
          end
        end

        result = use_case.call

        expect(result).to be_success
        expect(result.value).to be_nil
      end

      it "wraps Hash in Result.success" do
        use_case = Class.new(described_class) do
          def call(name:)
            { user: name, created: true }
          end
        end

        result = use_case.call(name: "Taro")

        expect(result).to be_success
        expect(result.value).to eq({ user: "Taro", created: true })
      end

      it "wraps String in Result.success" do
        use_case = Class.new(described_class) do
          def call(name:)
            "Hello, #{name}!"
          end
        end

        result = use_case.call(name: "World")

        expect(result).to be_success
        expect(result.value).to eq("Hello, World!")
      end

      it "wraps Array in Result.success" do
        use_case = Class.new(described_class) do
          def call(count:)
            (1..count).to_a
          end
        end

        result = use_case.call(count: 3)

        expect(result).to be_success
        expect(result.value).to eq([1, 2, 3])
      end

      it "wraps custom object in Result.success" do
        user_class = Struct.new(:name, :email)

        use_case = Class.new(described_class) do
          define_method(:call) do |name:, email:|
            user_class.new(name, email)
          end
        end

        result = use_case.call(name: "Taro", email: "taro@example.com")

        expect(result).to be_success
        expect(result.value.name).to eq("Taro")
        expect(result.value.email).to eq("taro@example.com")
      end

      it "does not double-wrap explicit Result.success" do
        use_case = Class.new(described_class) do
          def call(value:)
            success(value)
          end
        end

        result = use_case.call(value: "explicit")

        expect(result).to be_success
        expect(result.value).to eq("explicit")
      end

      it "does not wrap explicit Result.failure" do
        use_case = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :error, message: "Failed"))
          end
        end

        result = use_case.call

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:error)
      end
    end

    describe "pipeline with implicit success" do
      it "wraps step results in Result.success" do
        step1 = Class.new(described_class) do
          def call(value:)
            { value: value, step1: true }
          end
        end

        step2 = Class.new(described_class) do
          def call(value:, step1:)
            { value: value * 2, step1: step1, step2: true }
          end
        end

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(value: 10)

        expect(result).to be_success
        expect(result.value).to eq({ value: 20, step1: true, step2: true })
      end

      it "works with mixed explicit and implicit success" do
        implicit_step = Class.new(described_class) do
          def call(value:)
            { value: value, implicit: true }
          end
        end

        explicit_step = Class.new(described_class) do
          def call(value:, implicit:)
            success({ value: value * 2, implicit: implicit, explicit: true })
          end
        end

        organized = Class.new(described_class) do
          organize implicit_step, explicit_step
        end

        result = organized.call(value: 5)

        expect(result).to be_success
        expect(result.value).to eq({ value: 10, implicit: true, explicit: true })
      end

      it "stops pipeline on explicit failure" do
        implicit_step = Class.new(described_class) do
          def call(**_args)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Stop here"))
          end
        end

        never_called = Class.new(described_class) do
          def call(**_args)
            { should_not: :reach }
          end
        end

        organized = Class.new(described_class) do
          organize implicit_step, never_called
        end

        result = organized.call(value: 1)

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:failed)
      end
    end

    describe "with hooks" do
      it "after hook receives wrapped Result" do
        received_result = nil

        use_case = Class.new(described_class) do
          after { |_ctx, result| received_result = result }

          def call(value:)
            value * 3
          end
        end

        use_case.call(value: 7)

        expect(received_result).to be_a(SenroUsecaser::Result)
        expect(received_result).to be_success
        expect(received_result.value).to eq(21)
      end

      it "around hook can modify wrapped Result" do
        use_case = Class.new(described_class) do
          around do |_ctx, &block|
            result = block.call
            if result.success?
              SenroUsecaser::Result.success(result.value + 100)
            else
              result
            end
          end

          def call(value:)
            value * 2
          end
        end

        result = use_case.call(value: 5)

        expect(result).to be_success
        expect(result.value).to eq(110) # (5 * 2) + 100
      end
    end
  end
end
