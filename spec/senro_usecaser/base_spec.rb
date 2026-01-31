# frozen_string_literal: true

RSpec.describe SenroUsecaser::Base do
  # Reset global container before each test
  before { SenroUsecaser.reset_container! }

  # Common input class for simple tests
  let(:simple_input) { Struct.new(:value, :message, :should_raise, keyword_init: true) }

  # Test UseCase that returns success
  let(:success_use_case) do
    input_class = simple_input
    Class.new(described_class) do
      input input_class

      def call(input)
        success(input.value)
      end
    end
  end

  # Test UseCase that returns failure
  let(:failure_use_case) do
    input_class = simple_input
    Class.new(described_class) do
      input input_class

      def call(input)
        failure(SenroUsecaser::Error.new(code: :test_error, message: input.message))
      end
    end
  end

  # Test UseCase that raises an exception
  let(:raising_use_case) do
    input_class = simple_input
    Class.new(described_class) do
      input input_class

      def call(input)
        raise StandardError, input.message
      end
    end
  end

  # Test UseCase that uses capture
  let(:capture_use_case) do
    input_class = simple_input
    Class.new(described_class) do
      input input_class

      def call(input)
        capture(code: :captured) do
          raise StandardError, "Error" if input.should_raise

          "success"
        end
      end
    end
  end

  describe ".call" do
    it "creates an instance and calls #call" do
      result = success_use_case.call(simple_input.new(value: "hello"))

      expect(result).to be_success
      expect(result.value).to eq("hello")
    end

    it "returns failure result" do
      result = failure_use_case.call(simple_input.new(message: "Something went wrong"))

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Something went wrong")
    end
  end

  describe ".call!" do
    it "returns success result when no exception is raised" do
      result = success_use_case.call!(simple_input.new(value: "hello"))

      expect(result).to be_success
      expect(result.value).to eq("hello")
    end

    it "captures exceptions and returns failure result" do
      result = raising_use_case.call!(simple_input.new(message: "Error occurred"))

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Error occurred")
      expect(result.errors.first.code).to eq(:exception)
    end

    context "with organize pipeline" do
      # Input/Output classes for pipeline tests
      let(:pipeline_input) do
        Struct.new(:value, keyword_init: true)
      end

      let(:step_output) do
        Struct.new(:value, keyword_init: true)
      end

      it "captures exceptions in steps and collects them with on_failure: :collect" do
        input_class = pipeline_input
        output_class = step_output

        raising_step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            raise StandardError, "Error in step 1"
          end
        end

        raising_step2 = Class.new(described_class) do
          input output_class
          output output_class

          def call(_input)
            raise StandardError, "Error in step 2"
          end
        end

        organized = Class.new(described_class) do
          organize raising_step1, raising_step2, on_failure: :collect
        end

        result = organized.call!(input_class.new(value: 1))

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:message)).to eq(["Error in step 1", "Error in step 2"])
      end

      it "stops on first exception with on_failure: :stop (default)" do
        input_class = pipeline_input
        output_class = step_output
        call_count = 0

        raising_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            raise StandardError, "Error in step"
          end
        end

        tracking_step = Class.new(described_class) do
          input output_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(output_class.new(value: input.value))
          end
        end

        organized = Class.new(described_class) do
          organize raising_step, tracking_step
        end

        result = organized.call!(input_class.new(value: 1))

        expect(result).to be_failure
        expect(call_count).to eq(0)
      end
    end
  end

  describe ".call_with_capture" do
    it "captures exceptions with custom code" do
      result = raising_use_case.call_with_capture(input: simple_input.new(message: "Error"), code: :custom_error)

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:custom_error)
    end

    it "captures only specified exception classes" do
      custom_error_class = Class.new(StandardError)
      capture_input = Struct.new(:raise_type, keyword_init: true)

      input_class = capture_input
      use_case = Class.new(described_class) do
        input input_class

        def call(input)
          raise StandardError, "Standard error" if input.raise_type == :standard

          success("ok")
        end
      end

      # Should not capture StandardError when only CustomError is specified
      expect do
        use_case.call_with_capture(
          input: capture_input.new(raise_type: :standard),
          exception_classes: [custom_error_class]
        )
      end.to raise_error(StandardError)
    end
  end

  describe "#call" do
    it "raises NotImplementedError when not overridden" do
      input_class = simple_input
      empty_use_case = Class.new(described_class) do
        input input_class
      end

      expect { empty_use_case.call(simple_input.new) }.to raise_error(NotImplementedError)
    end
  end

  describe "#success" do
    it "is available in subclasses" do
      expect(success_use_case.call(simple_input.new(value: "test"))).to be_success
    end
  end

  describe "#failure" do
    it "is available in subclasses" do
      expect(failure_use_case.call(simple_input.new(message: "error"))).to be_failure
    end
  end

  describe "#capture" do
    it "returns success when block succeeds" do
      result = capture_use_case.call(simple_input.new(should_raise: false))

      expect(result).to be_success
      expect(result.value).to eq("success")
    end

    it "returns failure when block raises" do
      result = capture_use_case.call(simple_input.new(should_raise: true))

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:captured)
    end
  end

  describe "#failure_from_exception" do
    it "creates failure from exception" do
      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class

        def call(_input)
          raise StandardError, "Not found"
        rescue StandardError => e
          failure_from_exception(e, code: :not_found)
        end
      end

      result = use_case.call(simple_input.new)

      expect(result).to be_failure
      expect(result.errors.first.code).to eq(:not_found)
    end
  end

  describe ".depends_on" do
    it "registers dependencies" do
      use_case = Class.new(described_class) do
        depends_on :logger
        depends_on :repository
      end

      expect(use_case.dependencies).to eq(%i[logger repository])
    end

    it "resolves dependencies from global container" do
      SenroUsecaser.container.register(:logger, "test_logger")

      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class
        depends_on :logger

        def call(_input)
          success(logger)
        end
      end

      result = use_case.call(simple_input.new)

      expect(result.value).to eq("test_logger")
    end

    it "resolves dependencies from custom container" do
      container = SenroUsecaser::Container.new
      container.register(:logger, "custom_logger")

      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class
        depends_on :logger

        def call(_input)
          success(logger)
        end
      end

      result = use_case.call(simple_input.new, container: container)

      expect(result.value).to eq("custom_logger")
    end

    it "allows manual dependency injection for testing" do
      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class
        depends_on :logger

        def call(_input)
          success(logger)
        end
      end

      instance = use_case.new(dependencies: { logger: "mock_logger" })
      result = instance.perform(simple_input.new)

      expect(result.value).to eq("mock_logger")
    end
  end

  describe ".namespace" do
    it "sets the namespace" do
      use_case = Class.new(described_class) do
        namespace :admin
      end

      expect(use_case.use_case_namespace).to eq(:admin)
    end

    it "resolves dependencies from namespace" do
      SenroUsecaser.container.namespace(:admin) do |ns|
        ns.register(:logger, "admin_logger")
      end

      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class
        namespace :admin
        depends_on :logger

        def call(_input)
          success(logger)
        end
      end

      result = use_case.call(simple_input.new)

      expect(result.value).to eq("admin_logger")
    end

    it "resolves dependencies from parent namespace" do
      SenroUsecaser.container.register(:logger, "root_logger")
      SenroUsecaser.container.namespace(:admin) do |ns|
        ns.register(:other, "admin_other")
      end

      input_class = simple_input
      use_case = Class.new(described_class) do
        input input_class
        namespace :admin
        depends_on :logger

        def call(_input)
          success(logger)
        end
      end

      result = use_case.call(simple_input.new)

      expect(result.value).to eq("root_logger")
    end
  end

  describe "inheritance" do
    it "inherits dependencies from parent" do
      parent = Class.new(described_class) do
        depends_on :logger
      end

      child = Class.new(parent) do
        depends_on :repository
      end

      expect(child.dependencies).to eq(%i[logger repository])
    end

    it "inherits namespace from parent" do
      parent = Class.new(described_class) do
        namespace :admin
      end

      child = Class.new(parent)

      expect(child.use_case_namespace).to eq(:admin)
    end

    it "does not modify parent dependencies" do
      parent = Class.new(described_class) do
        depends_on :logger
      end

      Class.new(parent) do
        depends_on :repository
      end

      expect(parent.dependencies).to eq(%i[logger])
    end
  end

  describe ".organize" do
    # Input/Output classes for pipeline tests
    let(:order_input) { Struct.new(:name, :price, keyword_init: true) }
    let(:validated_output) { Struct.new(:name, :price, :validated, keyword_init: true) }
    let(:calculated_output) { Struct.new(:name, :price, :validated, :tax, keyword_init: true) }

    let(:validate_step) do
      input_class = order_input
      output_class = validated_output

      Class.new(described_class) do
        input input_class
        output output_class

        def call(input)
          if input.name.empty?
            return failure(SenroUsecaser::Error.new(code: :invalid_name,
                                                    message: "Name is required"))
          end

          if input.price <= 0
            return failure(SenroUsecaser::Error.new(code: :invalid_price, message: "Price must be positive"))
          end

          success(self.class.output_schema.new(name: input.name, price: input.price, validated: true))
        end
      end
    end

    let(:calculate_tax_step) do
      input_class = validated_output
      output_class = calculated_output

      Class.new(described_class) do
        input input_class
        output output_class

        def call(input)
          tax = (input.price * 0.1).to_i
          success(self.class.output_schema.new(
                    name: input.name,
                    price: input.price,
                    validated: input.validated,
                    tax: tax
                  ))
        end
      end
    end

    describe "basic pipeline" do
      it "executes UseCases in sequence" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("Test")
        expect(result.value.tax).to eq(10)
      end

      it "passes previous result as input to next step" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(order_input.new(name: "Product", price: 1000))

        expect(result).to be_success
        expect(result.value.tax).to eq(100)
      end
    end

    describe "on_failure: :stop (default)" do
      it "stops on first failure" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(order_input.new(name: "", price: 100))

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:invalid_name)
      end

      it "does not execute subsequent steps after failure" do
        call_count = 0
        input_class = order_input
        output_class = validated_output

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        tracking_step = Class.new(described_class) do
          input output_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(input)
          end
        end

        organized = Class.new(described_class) do
          organize failing_step, tracking_step
        end

        organized.call(input_class.new(name: "Test", price: 100))

        expect(call_count).to eq(0)
      end
    end

    describe "on_failure: :continue" do
      it "continues execution after failure" do
        call_count = 0
        input_class = order_input
        output_class = validated_output

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        tracking_step = Class.new(described_class) do
          input input_class # Gets original input since previous step failed
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(output_class.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize failing_step, tracking_step, on_failure: :continue
        end

        organized.call(input_class.new(name: "Test", price: 100))

        expect(call_count).to eq(1)
      end

      it "returns the last result" do
        input_class = order_input
        output_class = validated_output

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        success_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize failing_step, success_step, on_failure: :continue
        end

        result = organized.call(input_class.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.validated).to be true
      end
    end

    describe "on_failure: :collect" do
      it "collects all errors" do
        input_class = order_input
        output_class = validated_output

        failing_step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :error1, message: "Error 1"))
          end
        end

        failing_step2 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :error2, message: "Error 2"))
          end
        end

        organized = Class.new(described_class) do
          organize failing_step1, failing_step2, on_failure: :collect
        end

        result = organized.call(input_class.new(name: "Test", price: 100))

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:code)).to eq(%i[error1 error2])
      end

      it "returns success if no errors" do
        step1 = validate_step
        step2 = calculate_tax_step

        organized = Class.new(described_class) do
          organize step1, step2, on_failure: :collect
        end

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
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

        result = child.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.tax).to eq(10)
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

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.tax).to eq(10)
      end
    end

    describe "conditional execution with if:" do
      it "executes step when condition is true (symbol)" do
        step1 = validate_step
        input_class = validated_output
        output_class = validated_output

        optional_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(
                      name: "#{input.name}_optional",
                      price: input.price,
                      validated: input.validated
                    ))
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

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("Test_optional")
      end

      it "skips step when condition is false (symbol)" do
        step1 = validate_step
        input_class = validated_output
        output_class = validated_output

        optional_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(
                      name: "#{input.name}_optional",
                      price: input.price,
                      validated: input.validated
                    ))
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

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("Test")
      end

      it "executes step when lambda condition is true" do
        step1 = validate_step
        input_class = validated_output
        output_class = validated_output

        optional_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(
                      name: "#{input.name}_discounted",
                      price: input.price,
                      validated: input.validated
                    ))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: ->(ctx) { ctx.price > 50 }
          end
        end

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("Test_discounted")
      end

      it "skips step when lambda condition is false" do
        step1 = validate_step
        input_class = validated_output
        output_class = validated_output

        optional_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(
                      name: "#{input.name}_discounted",
                      price: input.price,
                      validated: input.validated
                    ))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1
            step optional_step, if: ->(ctx) { ctx.price > 200 }
          end
        end

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("Test")
      end
    end

    describe "custom input mapping with input:" do
      it "maps input using a symbol (method)" do
        input_class = order_input
        output_class = validated_output

        step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1, input: :transform_input
          end

          define_method(:transform_input) do |ctx|
            input_class.new(name: "transformed_#{ctx.name}", price: ctx.price)
          end
        end

        result = organized.call(input_class.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("transformed_Test")
      end

      it "maps input using a lambda" do
        input_class = order_input
        output_class = validated_output

        step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            success(self.class.output_schema.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step step1, input: ->(ctx) { input_class.new(name: "lambda_#{ctx.name}", price: ctx.price) }
          end
        end

        result = organized.call(input_class.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.name).to eq("lambda_Test")
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

        result = organized.call(order_input.new(name: "Test", price: 100))

        expect(result).to be_success
        expect(result.value.tax).to eq(10)
      end
    end

    describe "per-step on_failure" do
      it "continues on failure for specific step with on_failure: :continue" do
        input_class = order_input
        output_class = validated_output
        call_count = 0

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        tracking_step = Class.new(described_class) do
          input input_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(output_class.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize do
            step failing_step, on_failure: :continue
            step tracking_step
          end
        end

        organized.call(input_class.new(name: "Test", price: 100))

        expect(call_count).to eq(1)
      end

      it "stops on failure for step without on_failure override" do
        input_class = order_input
        output_class = validated_output
        call_count = 0

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        tracking_step = Class.new(described_class) do
          input output_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(input)
          end
        end

        organized = Class.new(described_class) do
          organize failing_step, tracking_step
        end

        organized.call(input_class.new(name: "Test", price: 100))

        expect(call_count).to eq(0)
      end

      it "per-step :stop overrides global :continue" do
        input_class = order_input
        output_class = validated_output
        call_count = 0

        failing_step = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        tracking_step = Class.new(described_class) do
          input input_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(output_class.new(name: input.name, price: input.price, validated: true))
          end
        end

        organized = Class.new(described_class) do
          organize on_failure: :continue do
            step failing_step, on_failure: :stop
            step tracking_step
          end
        end

        organized.call(input_class.new(name: "Test", price: 100))

        expect(call_count).to eq(0)
      end

      it "per-step :stop overrides global :collect and collects errors up to that point" do
        input_class = order_input
        output_class = validated_output

        failing_step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :error1, message: "Error 1"))
          end
        end

        failing_step2 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :error2, message: "Error 2"))
          end
        end

        failing_step3 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :error3, message: "Error 3"))
          end
        end

        organized = Class.new(described_class) do
          organize on_failure: :collect do
            step failing_step1
            step failing_step2, on_failure: :stop
            step failing_step3
          end
        end

        result = organized.call(input_class.new(name: "Test", price: 100))

        expect(result).to be_failure
        expect(result.errors.size).to eq(2)
        expect(result.errors.map(&:code)).to eq(%i[error1 error2])
      end
    end

    describe "requires input class for pipeline steps" do
      it "raises error when step does not define input class" do
        step_without_input = Class.new(described_class) do
          def call(input)
            success(input)
          end
        end

        organized = Class.new(described_class) do
          organize step_without_input
        end

        input_class = Struct.new(:value, keyword_init: true)
        expect { organized.call(input_class.new(value: 1)) }.to raise_error(ArgumentError, /must define `input` class/)
      end
    end
  end

  describe "hooks" do
    let(:hook_input) { Struct.new(:value, keyword_init: true) }

    describe "before hook" do
      it "runs before the main call" do
        call_order = []
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          before { call_order << :before }

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[before call])
      end

      it "receives context as argument" do
        received_context = nil
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          before { |ctx| received_context = ctx }

          def call(input)
            success(input.value)
          end
        end

        input = hook_input.new(value: "test")
        use_case.call(input)

        expect(received_context).to eq(input)
      end
    end

    describe "after hook" do
      it "runs after the main call" do
        call_order = []
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          after { call_order << :after }

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[call after])
      end

      it "receives context and result as arguments" do
        received_context = nil
        received_result = nil
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          after do |ctx, result|
            received_context = ctx
            received_result = result
          end

          def call(input)
            success(input.value)
          end
        end

        input = hook_input.new(value: "test")
        use_case.call(input)

        expect(received_context).to eq(input)
        expect(received_result).to be_success
        expect(received_result.value).to eq("test")
      end
    end

    describe "around hook" do
      it "wraps the main call" do
        call_order = []
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          around do |_ctx, _use_case, &block|
            call_order << :around_before
            result = block.call
            call_order << :around_after
            result
          end

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[around_before call around_after])
      end

      it "can modify the result" do
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          around do |_ctx, _use_case, &block|
            result = block.call
            SenroUsecaser::Result.success("#{result.value}_modified")
          end

          def call(input)
            success(input.value)
          end
        end

        result = use_case.call(hook_input.new(value: "test"))

        expect(result.value).to eq("test_modified")
      end

      it "can short-circuit execution" do
        call_count = 0
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          around do |_ctx, _use_case, &_block|
            SenroUsecaser::Result.failure(SenroUsecaser::Error.new(code: :blocked, message: "Blocked"))
          end

          define_method(:call) do |input|
            call_count += 1
            success(input.value)
          end
        end

        result = use_case.call(hook_input.new(value: "test"))

        expect(result).to be_failure
        expect(call_count).to eq(0)
      end
    end

    describe "multiple hooks" do
      it "runs hooks in order: before -> around -> call -> around -> after" do
        call_order = []
        input_class = hook_input

        use_case = Class.new(described_class) do
          input input_class
          before { call_order << :before }

          around do |_ctx, _use_case, &block|
            call_order << :around_before
            result = block.call
            call_order << :around_after
            result
          end

          after { call_order << :after }

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[before around_before call around_after after])
      end
    end

    describe "block hooks accessing dependencies" do
      let(:container) { SenroUsecaser::Container.new }
      let(:logger) { Object.new }

      before do
        container.register(:logger, logger)
        SenroUsecaser.instance_variable_set(:@container, container)
      end

      after do
        SenroUsecaser.reset!
      end

      it "before hook can access depends_on via instance_exec" do
        accessed_logger = nil
        input_class = hook_input
        lgr = logger

        use_case = Class.new(described_class) do
          depends_on :logger
          input input_class

          before do |_input|
            accessed_logger = logger
          end

          def call(input)
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(accessed_logger).to eq(lgr)
      end

      it "after hook can access depends_on via instance_exec" do
        accessed_logger = nil
        input_class = hook_input
        lgr = logger

        use_case = Class.new(described_class) do
          depends_on :logger
          input input_class

          after do |_input, _result|
            accessed_logger = logger
          end

          def call(input)
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(accessed_logger).to eq(lgr)
      end

      it "around hook can access depends_on via use_case argument" do
        accessed_logger = nil
        input_class = hook_input
        lgr = logger

        use_case = Class.new(described_class) do
          depends_on :logger
          input input_class

          around do |_input, uc, &block|
            accessed_logger = uc.send(:logger)
            block.call
          end

          def call(input)
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(accessed_logger).to eq(lgr)
      end
    end

    describe "extend_with" do
      it "runs extension hooks" do
        call_order = []
        input_class = hook_input

        extension = Module.new do
          define_singleton_method(:before) { |_ctx| call_order << :ext_before }
          define_singleton_method(:after) { |_ctx, _result| call_order << :ext_after }
        end

        use_case = Class.new(described_class) do
          input input_class
          extend_with extension

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[ext_before call ext_after])
      end

      it "runs multiple extension hooks in order" do
        call_order = []
        input_class = hook_input

        ext1 = Module.new do
          define_singleton_method(:before) { |_ctx| call_order << :ext1_before }
        end

        ext2 = Module.new do
          define_singleton_method(:before) { |_ctx| call_order << :ext2_before }
        end

        use_case = Class.new(described_class) do
          input input_class
          extend_with ext1, ext2

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        use_case.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[ext1_before ext2_before call])
      end

      it "supports around hooks in extensions" do
        input_class = hook_input

        extension = Module.new do
          def self.around(_ctx, &block)
            result = block.call
            SenroUsecaser::Result.success(result.value + 10)
          end
        end

        use_case = Class.new(described_class) do
          input input_class
          extend_with extension

          def call(input)
            success(input.value)
          end
        end

        result = use_case.call(hook_input.new(value: 5))

        expect(result.value).to eq(15)
      end
    end

    describe "inheritance" do
      it "inherits hooks from parent" do
        call_order = []
        input_class = hook_input

        parent = Class.new(described_class) do
          input input_class
          before { call_order << :parent_before }
        end

        child = Class.new(parent) do
          before { call_order << :child_before }

          define_method(:call) do |input|
            call_order << :call
            success(input.value)
          end
        end

        child.call(hook_input.new(value: "test"))

        expect(call_order).to eq(%i[parent_before child_before call])
      end
    end
  end

  describe "implicit success wrapping" do
    let(:wrap_input) { Struct.new(:value, keyword_init: true) }

    describe "single UseCase" do
      it "wraps plain value in Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(input)
            input.value * 2
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to eq(20)
      end

      it "wraps nil in Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(_input)
            nil
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to be_nil
      end

      it "wraps Hash in Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(input)
            { result: input.value * 2 }
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to eq({ result: 20 })
      end

      it "wraps String in Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(input)
            "Result: #{input.value}"
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to eq("Result: 10")
      end

      it "wraps Array in Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(input)
            [input.value, input.value * 2, input.value * 3]
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to eq([10, 20, 30])
      end

      it "wraps custom object in Result.success" do
        custom_class = Struct.new(:data)
        input_class = wrap_input

        use_case = Class.new(described_class) do
          input input_class

          define_method(:call) do |input|
            custom_class.new(input.value * 2)
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to be_a(custom_class)
        expect(result.value.data).to eq(20)
      end

      it "does not double-wrap explicit Result.success" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(input)
            success(input.value * 2)
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_success
        expect(result.value).to eq(20)
      end

      it "does not wrap explicit Result.failure" do
        input_class = wrap_input
        use_case = Class.new(described_class) do
          input input_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :test, message: "test"))
          end
        end

        result = use_case.call(wrap_input.new(value: 10))

        expect(result).to be_failure
      end
    end

    describe "pipeline with implicit success" do
      let(:pipeline_input) { Struct.new(:value, keyword_init: true) }
      let(:pipeline_output) { Struct.new(:value, :step1, :step2, keyword_init: true) }

      it "wraps step results in Result.success" do
        input_class = pipeline_input
        output_class = Struct.new(:value, :step1, keyword_init: true)
        final_output_class = pipeline_output

        step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(input)
            self.class.output_schema.new(value: input.value, step1: true)
          end
        end

        step2 = Class.new(described_class) do
          input output_class
          output final_output_class

          def call(input)
            self.class.output_schema.new(value: input.value, step1: input.step1, step2: true)
          end
        end

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(input_class.new(value: 10))

        expect(result).to be_success
        expect(result.value.value).to eq(10)
        expect(result.value.step1).to be true
        expect(result.value.step2).to be true
      end

      it "stops pipeline on explicit failure" do
        input_class = pipeline_input
        output_class = Struct.new(:value, keyword_init: true)
        call_count = 0

        step1 = Class.new(described_class) do
          input input_class
          output output_class

          def call(_input)
            failure(SenroUsecaser::Error.new(code: :failed, message: "Failed"))
          end
        end

        step2 = Class.new(described_class) do
          input output_class
          output output_class

          define_method(:call) do |input|
            call_count += 1
            success(input)
          end
        end

        organized = Class.new(described_class) do
          organize step1, step2
        end

        result = organized.call(input_class.new(value: 10))

        expect(result).to be_failure
        expect(call_count).to eq(0)
      end
    end

    describe "with hooks" do
      it "after hook receives wrapped Result" do
        received_result = nil
        input_class = wrap_input

        use_case = Class.new(described_class) do
          input input_class
          after { |_ctx, result| received_result = result }

          def call(input)
            input.value * 2
          end
        end

        use_case.call(wrap_input.new(value: 10))

        expect(received_result).to be_a(SenroUsecaser::Result)
        expect(received_result).to be_success
        expect(received_result.value).to eq(20)
      end

      it "around hook can modify wrapped Result" do
        input_class = wrap_input

        use_case = Class.new(described_class) do
          input input_class
          around do |_ctx, _use_case, &block|
            result = block.call
            if result.success?
              SenroUsecaser::Result.success(result.value + 100)
            else
              result
            end
          end

          def call(input)
            input.value * 2
          end
        end

        result = use_case.call(wrap_input.new(value: 5))

        expect(result).to be_success
        expect(result.value).to eq(110) # (5 * 2) + 100
      end
    end
  end

  describe "input/output validation with extend_with" do
    # Input class with validation
    let(:validatable_input_class) do
      Class.new do
        attr_reader :name, :email

        def initialize(name:, email:)
          @name = name
          @email = email
        end

        def validate!
          raise ArgumentError, "name is required" if name.nil? || name.empty?
          raise ArgumentError, "email must contain @" unless email.include?("@")
        end
      end
    end

    # Input validation module - context is now the input object directly
    let(:input_validation_module) do
      Module.new do
        def self.around(context, &block)
          return block.call unless context.respond_to?(:validate!)

          context.validate!
          block.call
        rescue StandardError => e
          SenroUsecaser::Result.failure(SenroUsecaser::Error.new(code: :validation_error, message: e.message))
        end
      end
    end

    context "with input class declaration (input CreateUserInput format)" do
      it "validates input via around hook before call" do
        input_class = validatable_input_class
        validation_module = input_validation_module

        use_case = Class.new(described_class) do
          input input_class
          extend_with validation_module

          def call(input)
            success({ name: input.name, email: input.email })
          end
        end

        # Valid input
        valid_input = input_class.new(name: "Taro", email: "taro@example.com")
        result = use_case.call(valid_input)

        expect(result).to be_success
        expect(result.value[:name]).to eq("Taro")
      end

      it "returns failure when validation fails" do
        input_class = validatable_input_class
        validation_module = input_validation_module

        use_case = Class.new(described_class) do
          input input_class
          extend_with validation_module

          def call(input)
            success({ name: input.name, email: input.email })
          end
        end

        # Invalid input (missing @)
        invalid_input = input_class.new(name: "Taro", email: "invalid-email")
        result = use_case.call(invalid_input)

        expect(result).to be_failure
        expect(result.errors.first.code).to eq(:validation_error)
        expect(result.errors.first.message).to eq("email must contain @")
      end
    end
  end
end
