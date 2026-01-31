# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Represents a step in an organized pipeline
  class Step
    attr_reader :use_case_class, :if_condition, :unless_condition, :on_failure, :all_conditions, :any_conditions,
                :input_mapping

    # rubocop:disable Metrics/ParameterLists
    #: (singleton(Base), ?if_condition: (Symbol | Proc)?, ?unless_condition: (Symbol | Proc)?, ?on_failure: Symbol?,
    #:  ?all_conditions: Array[(Symbol | Proc)]?, ?any_conditions: Array[(Symbol | Proc)]?,
    #:  ?input_mapping: (Symbol | Proc | Hash[Symbol, Symbol])?) -> void
    def initialize(use_case_class, if_condition: nil, unless_condition: nil, on_failure: nil,
                   all_conditions: nil, any_conditions: nil, input_mapping: nil)
      @use_case_class = use_case_class
      @if_condition = if_condition
      @unless_condition = unless_condition
      @on_failure = on_failure
      @all_conditions = all_conditions
      @any_conditions = any_conditions
      @input_mapping = input_mapping
    end
    # rubocop:enable Metrics/ParameterLists

    # Checks if this step should be executed based on conditions
    #
    #: (untyped, untyped) -> bool
    def should_execute?(context, use_case_instance)
      return false if if_condition && !evaluate_condition(if_condition, context, use_case_instance)
      return false if unless_condition && evaluate_condition(unless_condition, context, use_case_instance)
      return false if all_conditions && !all_conditions_met?(context, use_case_instance)
      return false if any_conditions && !any_condition_met?(context, use_case_instance)

      true
    end

    # Maps the input for this step based on input_mapping configuration
    #
    #: (untyped, untyped) -> untyped
    def map_input(context, use_case_instance)
      return context unless input_mapping

      case input_mapping
      when Symbol
        use_case_instance.send(input_mapping, context)
      when Proc
        input_mapping.call(context)
      when Hash
        map_hash_input(context)
      else
        context
      end
    end

    private

    #: ((Symbol | Proc), untyped, untyped) -> bool
    def evaluate_condition(condition, context, use_case_instance)
      case condition
      when Symbol
        use_case_instance.send(condition, context)
      when Proc
        condition.call(context)
      else
        raise ArgumentError, "Invalid condition type: #{condition.class}"
      end
    end

    #: (untyped, untyped) -> bool
    def all_conditions_met?(context, use_case_instance)
      all_conditions.all? { |cond| evaluate_condition(cond, context, use_case_instance) }
    end

    #: (untyped, untyped) -> bool
    def any_condition_met?(context, use_case_instance)
      any_conditions.any? { |cond| evaluate_condition(cond, context, use_case_instance) }
    end

    #: (Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
    def map_hash_input(context)
      return context unless context.is_a?(Hash)

      input_mapping.transform_values do |source_key|
        context[source_key]
      end
    end
  end

  # Base class for all UseCases
  #
  # @example Basic UseCase
  #   class CreateUserUseCase < SenroUsecaser::Base
  #     def call(name:, email:)
  #       user = User.create(name: name, email: email)
  #       success(user)
  #     end
  #   end
  #
  #   result = CreateUserUseCase.call(name: "Taro", email: "taro@example.com")
  #
  # @example With dependency injection
  #   class CreateUserUseCase < SenroUsecaser::Base
  #     depends_on :user_repository
  #     depends_on :event_publisher
  #
  #     def call(name:, email:)
  #       user = user_repository.create(name: name, email: email)
  #       event_publisher.publish(UserCreated.new(user))
  #       success(user)
  #     end
  #   end
  #
  # @example With namespace
  #   class Admin::CreateUserUseCase < SenroUsecaser::Base
  #     namespace :admin
  #     depends_on :user_repository  # Resolves from admin namespace
  #
  #     def call(name:, email:)
  #       # ...
  #     end
  #   end
  class Base
    class << self
      # Declares a dependency to be injected from the container
      #
      # @example Without type (untyped)
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     depends_on :user_repository
      #     depends_on :logger
      #   end
      #
      # @example With type
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     depends_on :user_repository, UserRepository
      #     depends_on :logger, Logger
      #   end
      #
      #: (Symbol, ?Class) -> void
      def depends_on(name, type = nil)
        dependencies << name unless dependencies.include?(name)
        dependency_types[name] = type if type

        # Define accessor method
        define_method(name) do
          @_dependencies[name]
        end
      end

      # Returns the list of declared dependencies
      #
      #: () -> Array[Symbol]
      def dependencies
        @dependencies ||= []
      end

      # Returns the dependency type mapping
      #
      #: () -> Hash[Symbol, Class]
      def dependency_types
        @dependency_types ||= {}
      end

      # Sets the namespace for dependency resolution
      #
      # @example
      #   class Admin::CreateUserUseCase < SenroUsecaser::Base
      #     namespace :admin
      #   end
      #
      # @example With nested namespace
      #   class Admin::Reports::GenerateUseCase < SenroUsecaser::Base
      #     namespace "admin::reports"
      #   end
      #
      #: ((Symbol | String)) -> void
      def namespace(name)
        @use_case_namespace = name
      end

      # Returns the declared namespace
      #
      #: () -> (Symbol | String)?
      attr_reader :use_case_namespace

      # Declares a sequence of UseCases to execute as a pipeline
      #
      # @example Basic organize (list format)
      #   class CreateOrderUseCase < SenroUsecaser::Base
      #     organize ValidateOrder, ChargePayment, SendConfirmation
      #   end
      #
      # @example With block and step (DSL format)
      #   class CreateOrderUseCase < SenroUsecaser::Base
      #     organize do
      #       step ValidateOrder
      #       step ApplyCoupon, if: :has_coupon?
      #       step ChargePayment, unless: :free_order?
      #       step SendEmail, on_failure: :continue
      #     end
      #   end
      #
      # @example With error strategy
      #   class CreateOrderUseCase < SenroUsecaser::Base
      #     organize ValidateOrder, ChargePayment, on_failure: :collect
      #   end
      #
      #: (*Class, ?on_failure: Symbol) ?{ () -> void } -> void
      def organize(*use_case_classes, on_failure: :stop, &block)
        @on_failure_strategy = on_failure

        if block
          @organized_steps = [] #: Array[Step]
          @_defining_steps = true
          instance_eval(&block) # steep:ignore BlockTypeMismatch
          @_defining_steps = false
        else
          @organized_steps = use_case_classes.map { |klass| Step.new(klass) }
        end
      end

      # Defines a step in the organize block
      #
      # @example Basic step
      #   step ValidateOrder
      #
      # @example With conditions
      #   step ApplyCoupon, if: :has_coupon?
      #   step ChargePayment, unless: :free_order?
      #
      # @example With lambda condition
      #   step ApplyCoupon, if: ->(ctx) { ctx[:coupon_code].present? }
      #
      # @example With per-step error handling
      #   step SendEmail, on_failure: :continue
      #
      # @example With multiple conditions (all must be true)
      #   step SendNotification, all: [:has_email?, :notification_enabled?]
      #
      # @example With multiple conditions (any must be true)
      #   step SendEmail, any: [:is_admin?, :is_vip?]
      #
      # @example With custom input mapping (hash)
      #   step CreateUser, input: { name: :user_name, email: :user_email }
      #
      # @example With custom input mapping (method)
      #   step CreateUser, input: :prepare_user_input
      #
      # @example With custom input mapping (lambda)
      #   step CreateUser, input: ->(ctx) { { name: ctx[:full_name] } }
      #
      # rubocop:disable Metrics/ParameterLists
      #: (Class, ?if: (Symbol | Proc)?, ?unless: (Symbol | Proc)?, ?on_failure: Symbol?,
      #:  ?all: Array[(Symbol | Proc)]?, ?any: Array[(Symbol | Proc)]?,
      #:  ?input: (Symbol | Proc | Hash[Symbol, Symbol])?) -> void
      def step(use_case_class, if: nil, unless: nil, on_failure: nil, all: nil, any: nil, input: nil)
        raise "step can only be called inside organize block" unless @_defining_steps

        @organized_steps << Step.new(
          use_case_class,
          if_condition: binding.local_variable_get(:if),
          unless_condition: binding.local_variable_get(:unless),
          on_failure: on_failure,
          all_conditions: all,
          any_conditions: any,
          input_mapping: input
        )
      end
      # rubocop:enable Metrics/ParameterLists

      # Returns the list of organized steps
      #
      #: () -> Array[Step]?
      attr_reader :organized_steps

      # Returns the failure handling strategy
      #
      #: () -> Symbol
      def on_failure_strategy
        @on_failure_strategy || :stop
      end

      # Adds extension modules with hooks (before/after/around)
      #
      # @example
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     extend_with Logging, Transaction
      #   end
      #
      #: (*Module) -> void
      def extend_with(*extensions)
        extensions.each { |ext| self.extensions << ext }
      end

      # Returns the list of extensions
      #
      #: () -> Array[Module]
      def extensions
        @extensions ||= []
      end

      # Adds a before hook
      #
      # @example
      #   before { |context| puts "Before: #{context}" }
      #
      #: () { (Hash[Symbol, untyped]) -> void } -> void
      def before(&block)
        before_hooks << block
      end

      # Returns the list of before hooks
      #
      #: () -> Array[Proc]
      def before_hooks
        @before_hooks ||= []
      end

      # Adds an after hook
      #
      # @example
      #   after { |context, result| puts "After: #{result}" }
      #
      #: () { (Hash[Symbol, untyped], Result[untyped]) -> void } -> void
      def after(&block)
        after_hooks << block
      end

      # Returns the list of after hooks
      #
      #: () -> Array[Proc]
      def after_hooks
        @after_hooks ||= []
      end

      # Adds an around hook
      #
      # @example
      #   around do |context, &block|
      #     ActiveRecord::Base.transaction { block.call }
      #   end
      #
      #: () { (Hash[Symbol, untyped]) { () -> Result[untyped] } -> Result[untyped] } -> void
      def around(&block)
        around_hooks << block if block
      end

      # Returns the list of around hooks
      #
      #: () -> Array[Proc]
      def around_hooks
        @around_hooks ||= []
      end

      # Declares the expected input parameters for this UseCase
      #
      # This is primarily for documentation and can be used for validation.
      #
      # @example
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     input CreateUserInput
      #   end
      #
      #: (Class) -> void
      def input(type)
        @input_class = type
      end

      # Returns the input class
      #
      #: () -> Class?
      attr_reader :input_class

      # Declares the expected output type for this UseCase
      #
      # This is primarily for documentation and can be used for validation.
      #
      # @example
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     output User
      #   end
      #
      # @example With structure
      #   class CreateUserUseCase < SenroUsecaser::Base
      #     output user: User, token: String
      #   end
      #
      #: ((Class | Hash[Symbol, Class])) -> void
      def output(type_or_schema)
        @output_schema = type_or_schema
      end

      # Returns the output schema
      #
      #: () -> (Class | Hash[Symbol, Class])?
      attr_reader :output_schema

      # Calls the UseCase with the given input
      #
      # @example With input class
      #   input = CreateUserInput.new(name: "Taro", email: "taro@example.com")
      #   CreateUserUseCase.call(input)
      #
      # @example With custom container
      #   CreateUserUseCase.call(input, container: my_container)
      #
      # @example Pipeline step (keyword arguments)
      #   StepUseCase.call(user_id: 1, product_ids: [101])
      #
      #: [T] (?untyped, ?container: Container, **untyped) -> Result[T]
      def call(input = nil, container: nil, **args)
        new(container: container).perform(input, **args)
      end

      # Calls the UseCase and captures any exceptions as failures
      #
      # @example
      #   CreateUserUseCase.call!(input)
      #
      #: [T] (?untyped, ?container: Container, **untyped) -> Result[T]
      def call!(input = nil, container: nil, **args)
        new(container: container).perform(input, **args)
      rescue StandardError => e
        Result.from_exception(e)
      end

      # Calls the UseCase with custom exception handling options
      #
      # rubocop:disable Layout/LineLength
      #: [T] (input: untyped, ?container: Container, ?exception_classes: Array[Class], ?code: Symbol) -> Result[T]
      # rubocop:enable Layout/LineLength
      def call_with_capture(input:, container: nil, exception_classes: [StandardError], code: :exception)
        new(container: container).perform(input)
      rescue *exception_classes => e
        Result.from_exception(e, code: code)
      end

      # @api private
      # Hook called when the class is inherited
      def inherited(subclass)
        super
        copy_configuration_to(subclass)
        copy_hooks_to(subclass)
      end

      private

      def copy_configuration_to(subclass)
        subclass.instance_variable_set(:@dependencies, dependencies.dup)
        subclass.instance_variable_set(:@dependency_types, dependency_types.dup)
        subclass.instance_variable_set(:@use_case_namespace, @use_case_namespace)
        subclass.instance_variable_set(:@organized_steps, @organized_steps&.dup)
        subclass.instance_variable_set(:@on_failure_strategy, @on_failure_strategy)
        subclass.instance_variable_set(:@input_class, @input_class)
        subclass.instance_variable_set(:@output_schema, @output_schema)
      end

      def copy_hooks_to(subclass)
        subclass.instance_variable_set(:@extensions, extensions.dup)
        subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
        subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
        subclass.instance_variable_set(:@around_hooks, around_hooks.dup)
      end
    end

    # Initializes the UseCase with dependencies resolved from the container
    #
    # @example With global container
    #   use_case = CreateUserUseCase.new
    #
    # @example With custom container
    #   use_case = CreateUserUseCase.new(container: my_container)
    #
    # @example With manual dependencies (for testing)
    #   use_case = CreateUserUseCase.new(dependencies: { user_repository: mock_repo })
    #
    #: (?container: Container?, ?dependencies: Hash[Symbol, untyped]) -> void
    def initialize(container: nil, dependencies: {})
      @_container = container || SenroUsecaser.container
      @_dependencies = {} #: Hash[Symbol, untyped]

      resolve_dependencies(@_container, dependencies)
    end

    # Performs the UseCase with hooks
    #
    # This is the entry point called by class methods.
    # It wraps the call method with before/after/around hooks.
    #
    #: (?untyped, **untyped) -> Result[untyped]
    def perform(input = nil, **args)
      # Convert input object to hash if provided
      effective_args = if input && self.class.input_class
                         input_to_hash(input)
                       elsif input.is_a?(Hash)
                         input
                       else
                         args
                       end

      # Determine how to call based on whether input class is defined
      execute_with_hooks(effective_args) do
        if self.class.input_class
          # Convert hash back to input object for call
          input_obj = input || hash_to_input(effective_args)
          call(input_obj)
        else
          call(**effective_args)
        end
      end
    end

    # Executes the UseCase logic
    #
    # If organize is defined, executes the pipeline.
    # Otherwise, subclasses must implement this method.
    #
    #: (?untyped input) -> Result[untyped]
    def call(input = nil)
      return execute_pipeline_with_input(input) if self.class.organized_steps

      raise NotImplementedError, "#{self.class.name}#call must be implemented"
    end

    private

    # Creates a success Result with the given value
    #
    # @example
    #   def call(name:)
    #     user = User.create(name: name)
    #     success(user)
    #   end
    #
    #: [T] (T) -> Result[T]
    def success(value)
      Result.success(value)
    end

    # Creates a failure Result with the given errors
    #
    # @example
    #   def call(name:)
    #     return failure(Error.new(code: :invalid, message: "Invalid")) if name.empty?
    #     # ...
    #   end
    #
    #: (*Error) -> Result[untyped]
    def failure(*errors)
      Result.failure(*errors)
    end

    # Converts an input object to a hash for internal processing
    #
    #: (untyped) -> Hash[Symbol, untyped]
    def input_to_hash(input)
      return input if input.is_a?(Hash)

      # Get all public reader methods (excluding Object methods)
      methods = input.class.instance_methods(false).select do |m|
        input.class.instance_method(m).arity.zero?
      end

      # @type var hash: Hash[Symbol, untyped]
      hash = {}
      methods.each do |method|
        hash[method] = input.send(method)
      end
      hash
    end

    # Converts a hash to an input object
    #
    #: (Hash[Symbol, untyped]) -> untyped
    def hash_to_input(hash)
      input_class = self.class.input_class
      return hash unless input_class

      # Create input object from hash using keyword arguments
      input_class.new(**hash)
    rescue ArgumentError
      # If the input class doesn't accept these kwargs, return hash
      hash
    end

    # Creates a failure Result from an exception
    #
    # @example
    #   def call(id:)
    #     user = User.find(id)
    #     success(user)
    #   rescue ActiveRecord::RecordNotFound => e
    #     failure_from_exception(e, code: :not_found)
    #   end
    #
    #: (Exception, ?code: Symbol) -> Result[untyped]
    def failure_from_exception(exception, code: :exception)
      Result.from_exception(exception, code: code)
    end

    # Executes a block and captures any exceptions as failures
    #
    # @example
    #   def call(id:)
    #     capture { User.find(id) }
    #   end
    #
    # @example With specific exception classes
    #   def call(id:)
    #     capture(ActiveRecord::RecordNotFound, code: :not_found) { User.find(id) }
    #   end
    #
    #: [T] (*Class, ?code: Symbol) { () -> T } -> Result[T]
    def capture(*exception_classes, code: :exception, &)
      Result.capture(*exception_classes, code: code, &)
    end

    # Executes the core logic with before/after/around hooks
    #
    #: (Hash[Symbol, untyped]) { () -> Result[untyped] } -> Result[untyped]
    def execute_with_hooks(context, &core_block)
      # Build the execution chain with around hooks
      execution = build_around_chain(context, core_block)

      # Run before hooks
      run_before_hooks(context)

      # Execute the chain (around hooks wrapping core logic)
      result = execution.call

      # Run after hooks
      run_after_hooks(context, result)

      result
    end

    # Builds the around hook chain
    #
    #: (Hash[Symbol, untyped], Proc) -> Proc
    def build_around_chain(context, core_block)
      # Collect all around hooks (from extensions and block-based)
      all_around_hooks = collect_around_hooks

      # Build chain from inside out
      all_around_hooks.reverse.reduce(core_block) do |inner, hook|
        -> { hook.call(context) { inner.call } }
      end
    end

    # Collects all around hooks from extensions and block-based hooks
    #
    #: () -> Array[Proc]
    def collect_around_hooks
      hooks = [] #: Array[Proc]

      # From extensions
      self.class.extensions.each do |ext|
        hooks << ext.method(:around).to_proc if ext.respond_to?(:around)
      end

      # Block-based hooks
      hooks.concat(self.class.around_hooks)

      hooks
    end

    # Runs all before hooks
    #
    #: (Hash[Symbol, untyped]) -> void
    def run_before_hooks(context)
      # From extensions
      self.class.extensions.each do |ext|
        ext.send(:before, context) if ext.respond_to?(:before)
      end

      # Block-based hooks
      self.class.before_hooks.each do |hook|
        hook.call(context)
      end
    end

    # Runs all after hooks
    #
    #: (Hash[Symbol, untyped], Result[untyped]) -> void
    def run_after_hooks(context, result)
      # From extensions
      self.class.extensions.each do |ext|
        ext.send(:after, context, result) if ext.respond_to?(:after)
      end

      # Block-based hooks
      self.class.after_hooks.each do |hook|
        hook.call(context, result)
      end
    end

    # Resolves dependencies from the container
    #
    #: (Container, Hash[Symbol, untyped]) -> void
    def resolve_dependencies(container, manual_dependencies)
      self.class.dependencies.each do |name|
        @_dependencies[name] = if manual_dependencies.key?(name)
                                 manual_dependencies[name]
                               else
                                 resolve_from_container(container, name)
                               end
      end
    end

    # Resolves a single dependency from the container
    #
    #: (Container, Symbol) -> untyped
    def resolve_from_container(container, name)
      namespace = effective_namespace
      if namespace
        container.resolve_in(namespace, name)
      else
        container.resolve(name)
      end
    end

    # Returns the effective namespace for dependency resolution
    # Uses explicitly declared namespace, or infers from module structure if configured
    #
    #: () -> (Symbol | String)?
    def effective_namespace
      # Explicit namespace takes precedence
      return self.class.use_case_namespace if self.class.use_case_namespace

      # Infer from module structure if enabled
      return nil unless SenroUsecaser.configuration.infer_namespace_from_module

      infer_namespace_from_class
    end

    # Infers namespace from the class's module structure
    #
    # @example
    #   Admin::CreateUserUseCase => "admin"
    #   Admin::Reports::GenerateReportUseCase => "admin::reports"
    #   CreateUserUseCase => nil
    #
    #: () -> String?
    def infer_namespace_from_class
      class_name = self.class.name
      return nil unless class_name

      parts = class_name.split("::")
      return nil if parts.length <= 1

      # Remove the class name itself, keep only module parts
      module_parts = parts[0...-1] || [] #: Array[String]
      return nil if module_parts.empty?

      # Convert to lowercase namespace format (Admin::Reports => "admin::reports")
      module_parts.map { |part| part.gsub(/([a-z])([A-Z])/, '\1_\2').downcase }.join("::")
    end

    # Executes the organized UseCase pipeline
    # Executes the pipeline with an input object
    #
    #: (untyped) -> Result[untyped]
    def execute_pipeline_with_input(input)
      args = input_to_hash(input)
      execute_pipeline(**args)
    end

    #
    #: (**untyped) -> Result[untyped]
    def execute_pipeline(**args)
      # Initialize accumulated context with input args
      @_accumulated_context = args.dup

      case self.class.on_failure_strategy
      when :stop
        execute_pipeline_stop(**args)
      when :continue
        execute_pipeline_continue(**args)
      when :collect
        execute_pipeline_collect(**args)
      else
        raise ArgumentError, "Unknown on_failure strategy: #{self.class.on_failure_strategy}"
      end
    end

    # Returns the accumulated context across pipeline steps
    # This is available during pipeline execution.
    #
    # @example Accessing accumulated context
    #   def has_user?(ctx)
    #     accumulated_context[:user].present?
    #   end
    #
    #: () -> Hash[Symbol, untyped]
    def accumulated_context
      @_accumulated_context || {}
    end

    # Executes pipeline with :stop strategy - stops on first failure
    #
    #: (**untyped) -> Result[untyped]
    def execute_pipeline_stop(**args)
      current_input = args
      result = nil #: Result[untyped]?

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        return step_result if step_result.failure? && step_should_stop?(step)

        if step_result.success?
          current_input = result_to_input(step_result)
          merge_to_accumulated_context(current_input)
        end
        result = step_result
      end

      result || success(current_input)
    end

    # Executes pipeline with :continue strategy - continues even on failure
    #
    #: (**untyped) -> Result[untyped]
    def execute_pipeline_continue(**args)
      current_input = args
      result = nil #: Result[untyped]?

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        current_input = result_to_input(step_result)
        merge_to_accumulated_context(current_input) if step_result.success?
        result = step_result
      end

      result || success(current_input)
    end

    # Executes pipeline with :collect strategy - collects all errors
    #
    #: (**untyped) -> Result[untyped]
    def execute_pipeline_collect(**args)
      current_input = args
      collected_errors = [] #: Array[Error]
      last_success_result = nil #: Result[untyped]?

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        result = execute_step(step, current_input)
        collected_errors, last_success_result, current_input =
          process_collect_result(result, collected_errors, last_success_result, current_input)
      end

      collected_errors.any? ? Result.failure(*collected_errors) : (last_success_result || success(current_input))
    end

    # Processes a single result in collect mode
    #
    #: (Result[untyped], Array[Error], Result[untyped]?, untyped) -> [Array[Error], Result[untyped]?, untyped]
    def process_collect_result(result, errors, last_success, current_input)
      if result.failure?
        [errors + result.errors, last_success, current_input]
      else
        new_input = result_to_input(result)
        merge_to_accumulated_context(new_input)
        [errors, result, new_input]
      end
    end

    # Executes a single step in the pipeline
    #
    #: (Step, untyped) -> Result[untyped]
    def execute_step(step, input)
      mapped_input = step.map_input(input, self)
      call_use_case(step.use_case_class, mapped_input)
    end

    # Determines if a step failure should stop the pipeline
    #
    #: (Step) -> bool
    def step_should_stop?(step)
      step_strategy = step.on_failure || self.class.on_failure_strategy
      step_strategy == :stop
    end

    # Calls a single UseCase in the pipeline
    #
    #: (singleton(Base), Hash[Symbol, untyped]) -> Result[untyped]
    def call_use_case(use_case_class, input)
      input_class = use_case_class.input_class
      if input_class
        # Convert hash to input object for UseCases with input class
        input_obj = input_class.new(**input)
        use_case_class.call(input_obj, container: @_container)
      else
        use_case_class.call(nil, container: @_container, **input)
      end
    rescue ArgumentError
      # Fallback to keyword arguments if input class doesn't accept the hash
      use_case_class.call(nil, container: @_container, **input)
    end

    # Converts a result to input for the next UseCase
    #
    #: (Result[untyped]) -> Hash[Symbol, untyped]
    def result_to_input(result)
      value = result.value
      if value.is_a?(Hash)
        value
      else
        # Convert output object to hash for next step
        output_to_hash(value)
      end
    end

    # Converts an output object to a hash
    #
    #: (untyped) -> Hash[Symbol, untyped]
    def output_to_hash(output)
      return output if output.is_a?(Hash)

      # Wrap basic types in :value key
      return { value: output } if basic_type?(output)

      # Get all public reader methods (excluding Object methods)
      methods = output.class.instance_methods(false).select do |m|
        output.class.instance_method(m).arity.zero?
      end

      # If no custom methods, wrap in :value
      return { value: output } if methods.empty?

      # @type var hash: Hash[Symbol, untyped]
      hash = {}
      methods.each do |method|
        hash[method] = output.send(method)
      end
      hash
    end

    # Checks if the value is a basic Ruby type
    #
    #: (untyped) -> bool
    def basic_type?(value)
      case value
      when String, Symbol, Integer, Float, TrueClass, FalseClass, NilClass, Array
        true
      else
        false
      end
    end

    # Merges new data into the accumulated context
    #
    #: (Hash[Symbol, untyped]) -> void
    def merge_to_accumulated_context(data)
      return unless data.is_a?(Hash)

      @_accumulated_context ||= {} #: Hash[Symbol, untyped]
      @_accumulated_context.merge!(data)
    end
  end
end
