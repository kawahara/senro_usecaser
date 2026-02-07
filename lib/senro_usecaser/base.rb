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
    #:  ?input_mapping: (Symbol | Proc)?) -> void
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
    def should_execute?(input, use_case_instance)
      return false if if_condition && !evaluate_condition(if_condition, input, use_case_instance)
      return false if unless_condition && evaluate_condition(unless_condition, input, use_case_instance)
      return false if all_conditions && !all_conditions_met?(input, use_case_instance)
      return false if any_conditions && !any_condition_met?(input, use_case_instance)

      true
    end

    # Maps the input for this step based on input_mapping configuration
    #
    #: (untyped, untyped) -> untyped
    def map_input(input, use_case_instance)
      return input unless input_mapping

      case input_mapping
      when Symbol
        use_case_instance.send(input_mapping, input)
      when Proc
        input_mapping.call(input)
      else
        input
      end
    end

    private

    #: ((Symbol | Proc), untyped, untyped) -> bool
    def evaluate_condition(condition, input, use_case_instance)
      case condition
      when Symbol
        use_case_instance.send(condition, input)
      when Proc
        condition.call(input)
      else
        raise ArgumentError, "Invalid condition type: #{condition.class}"
      end
    end

    #: (untyped, untyped) -> bool
    def all_conditions_met?(input, use_case_instance)
      all_conditions.all? { |cond| evaluate_condition(cond, input, use_case_instance) }
    end

    #: (untyped, untyped) -> bool
    def any_condition_met?(input, use_case_instance)
      any_conditions.any? { |cond| evaluate_condition(cond, input, use_case_instance) }
    end
  end

  # Base class for all UseCases
  #
  # @example Basic UseCase with keyword arguments
  #   class CreateUserUseCase < SenroUsecaser::Base
  #     def call(name:, email:)
  #       user = User.create(name: name, email: email)
  #       success(user)
  #     end
  #   end
  #
  #   result = CreateUserUseCase.call(name: "Taro", email: "taro@example.com")
  #
  # @example With input/output classes (recommended for pipelines)
  #   class CreateUserUseCase < SenroUsecaser::Base
  #     input CreateUserInput
  #     output CreateUserOutput
  #
  #     def call(input)
  #       user = User.create(name: input.name, email: input.email)
  #       success(CreateUserOutput.new(user: user))
  #     end
  #   end
  #
  # @example Pipeline with input/output chaining
  #   class StepA < SenroUsecaser::Base
  #     input AInput
  #     output AOutput
  #     def call(input)
  #       success(AOutput.new(value: input.value * 2))
  #     end
  #   end
  #
  #   class StepB < SenroUsecaser::Base
  #     input AOutput  # Receives StepA's output directly
  #     output BOutput
  #     def call(input)
  #       success(BOutput.new(result: input.value + 1))
  #     end
  #   end
  #
  #   class Pipeline < SenroUsecaser::Base
  #     organize StepA, StepB
  #   end
  class Base
    extend DependsOn

    class << self
      # Alias for backward compatibility
      #
      #: () -> (Symbol | String)?
      alias use_case_namespace declared_namespace

      # Declares a sequence of UseCases to execute as a pipeline
      #
      # @example Basic organize
      #   organize StepA, StepB, StepC
      #
      # @example With block and step
      #   organize do
      #     step StepA
      #     step StepB, if: :should_run?
      #     step StepC, on_failure: :continue
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
      # rubocop:disable Metrics/ParameterLists
      #: (Class, ?if: (Symbol | Proc)?, ?unless: (Symbol | Proc)?, ?on_failure: Symbol?,
      #:  ?all: Array[(Symbol | Proc)]?, ?any: Array[(Symbol | Proc)]?,
      #:  ?input: (Symbol | Proc)?) -> void
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

      # Adds extension modules with hooks
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
      #: () { (untyped) -> void } -> void
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
      #: () { (untyped, Result[untyped]) -> void } -> void
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
      # Block receives (input, use_case, &block) where use_case allows access to dependencies
      #
      #: () { (untyped, Base) { () -> Result[untyped] } -> Result[untyped] } -> void
      def around(&block)
        around_hooks << block if block
      end

      # Returns the list of around hooks
      #
      #: () -> Array[Proc]
      def around_hooks
        @around_hooks ||= []
      end

      # Adds an on_failure hook
      #
      #: () { (untyped, Result[untyped], ?RetryContext?) -> void } -> void
      def on_failure(&block)
        on_failure_hooks << block
      end

      # Returns the list of on_failure hooks
      #
      #: () -> Array[Proc]
      def on_failure_hooks
        @on_failure_hooks ||= []
      end

      # Configures automatic retry for specific error types
      #
      # @example Retry on network errors
      #   retry_on :network_error, attempts: 3, wait: 1
      #
      # @example Retry on exception class
      #   retry_on Net::OpenTimeout, attempts: 5, wait: 2, backoff: :exponential
      #
      # @example Multiple error types with jitter
      #   retry_on :rate_limited, :timeout, attempts: 3, wait: 1, jitter: 0.1
      #
      # rubocop:disable Metrics/ParameterLists
      #: (*(Symbol | Class), ?attempts: Integer, ?wait: (Float | Integer),
      #:  ?backoff: Symbol, ?max_wait: (Float | Integer)?, ?jitter: (Float | Integer)) -> void
      def retry_on(*error_matchers, attempts: 3, wait: 0, backoff: :fixed, max_wait: nil, jitter: 0)
        retry_configurations << RetryConfiguration.new(
          matchers: error_matchers.flatten,
          attempts: attempts,
          wait: wait,
          backoff: backoff,
          max_wait: max_wait,
          jitter: jitter
        )
      end
      # rubocop:enable Metrics/ParameterLists

      # Returns the list of retry configurations
      #
      #: () -> Array[RetryConfiguration]
      def retry_configurations
        @retry_configurations ||= []
      end

      # Configures errors that should immediately discard (no retry)
      #
      # @example Discard on validation errors
      #   discard_on :validation_error, :not_found
      #
      # @example Discard on exception class
      #   discard_on ArgumentError
      #
      #: (*(Symbol | Class)) -> void
      def discard_on(*error_matchers)
        discard_matchers.concat(error_matchers.flatten)
      end

      # Returns the list of discard matchers
      #
      #: () -> Array[(Symbol | Class)]
      def discard_matchers
        @discard_matchers ||= []
      end

      # Adds a before_retry hook
      #
      #: () { (untyped, Result[untyped], RetryContext) -> void } -> void
      def before_retry(&block)
        before_retry_hooks << block
      end

      # Returns the list of before_retry hooks
      #
      #: () -> Array[Proc]
      def before_retry_hooks
        @before_retry_hooks ||= []
      end

      # Adds an after_retries_exhausted hook
      #
      #: () { (untyped, Result[untyped], RetryContext) -> void } -> void
      def after_retries_exhausted(&block)
        after_retries_exhausted_hooks << block
      end

      # Returns the list of after_retries_exhausted hooks
      #
      #: () -> Array[Proc]
      def after_retries_exhausted_hooks
        @after_retries_exhausted_hooks ||= []
      end

      # Declares the expected input type(s) for this UseCase
      # Accepts a Class or one or more Modules that input must include
      #
      # @example Single class
      #   input UserInput
      #
      # @example Single module (interface)
      #   input HasUserId
      #
      # @example Multiple modules (interfaces)
      #   input HasUserId, HasEmail
      #
      #: (*Module) -> void
      def input(*types)
        @input_types = types
      end

      # Returns the input types as an array
      #
      #: () -> Array[Module]
      def input_types
        @input_types || []
      end

      # Returns the input class (for backwards compatibility)
      # If a Class is specified, returns it. Otherwise returns the first type.
      #
      #: () -> Module?
      def input_class
        types = input_types
        return nil if types.empty?

        # Class があればそれを返す（単一 Class 指定の後方互換）
        types.find { |t| t.is_a?(Class) } || types.first
      end

      # Declares the expected output type for this UseCase
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
      #: [T] (?untyped, ?container: Container, **untyped) -> Result[T]
      def call(input = nil, container: nil, **args)
        new(container: container).perform(input, capture_exceptions: false, **args)
      end

      # Calls the UseCase and captures any exceptions as failures
      #
      #: [T] (?untyped, ?container: Container, **untyped) -> Result[T]
      def call!(input = nil, container: nil, **args)
        new(container: container).perform(input, capture_exceptions: true, **args)
      rescue StandardError => e
        Result.from_exception(e)
      end

      # Calls the UseCase with custom exception handling options
      #
      #: [T] (input: untyped, ?container: Container, ?exception_classes: Array[Class], ?code: Symbol) -> Result[T]
      def call_with_capture(input:, container: nil, exception_classes: [StandardError], code: :exception)
        new(container: container).perform(input)
      rescue *exception_classes => e
        Result.from_exception(e, code: code)
      end

      # @api private
      def inherited(subclass)
        super
        copy_configuration_to(subclass)
        copy_hooks_to(subclass)
      end

      private

      def copy_configuration_to(subclass)
        copy_depends_on_to(subclass)
        subclass.instance_variable_set(:@organized_steps, @organized_steps&.dup)
        subclass.instance_variable_set(:@on_failure_strategy, @on_failure_strategy)
        subclass.instance_variable_set(:@input_types, @input_types&.dup)
        subclass.instance_variable_set(:@output_schema, @output_schema)
        subclass.instance_variable_set(:@retry_configurations, retry_configurations.dup)
        subclass.instance_variable_set(:@discard_matchers, discard_matchers.dup)
      end

      def copy_hooks_to(subclass)
        subclass.instance_variable_set(:@extensions, extensions.dup)
        subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
        subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
        subclass.instance_variable_set(:@around_hooks, around_hooks.dup)
        subclass.instance_variable_set(:@on_failure_hooks, on_failure_hooks.dup)
        subclass.instance_variable_set(:@before_retry_hooks, before_retry_hooks.dup)
        subclass.instance_variable_set(:@after_retries_exhausted_hooks, after_retries_exhausted_hooks.dup)
      end
    end

    # Initializes the UseCase with dependencies resolved from the container
    #
    #: (?container: Container?, ?dependencies: Hash[Symbol, untyped]) -> void
    def initialize(container: nil, dependencies: {})
      @_container = container || SenroUsecaser.container
      @_dependencies = {} #: Hash[Symbol, untyped]

      resolve_dependencies(@_container, dependencies)
    end

    # Performs the UseCase with hooks
    #
    #: (untyped, ?capture_exceptions: bool) -> Result[untyped]
    def perform(input, capture_exceptions: false)
      @_capture_exceptions = capture_exceptions

      unless self.class.input_class || self.class.organized_steps
        raise ArgumentError, "#{self.class.name} must define `input` class"
      end

      validate_input!(input)
      execute_with_retry(input)
    end

    # Executes the UseCase logic
    #
    #: (?untyped input) -> Result[untyped]
    def call(input = nil)
      return execute_pipeline(input) if self.class.organized_steps

      raise NotImplementedError, "#{self.class.name}#call must be implemented"
    end

    # Represents a record of a step execution in a pipeline
    StepExecutionRecord = Struct.new(:step, :input, :result, keyword_init: true)

    private

    # Creates a success Result with the given value
    #
    #: [T] (T) -> Result[T]
    def success(value)
      Result.success(value)
    end

    # Creates a failure Result with the given errors
    #
    #: (*Error) -> Result[untyped]
    def failure(*errors)
      Result.failure(*errors)
    end

    # Creates a failure Result from an exception
    #
    #: (Exception, ?code: Symbol) -> Result[untyped]
    def failure_from_exception(exception, code: :exception)
      Result.from_exception(exception, code: code)
    end

    # Executes a block and captures any exceptions as failures
    #
    #: [T] (*Class, ?code: Symbol) { () -> T } -> Result[T]
    def capture(*exception_classes, code: :exception, &)
      Result.capture(*exception_classes, code: code, &)
    end

    # Validates that input satisfies all declared input types
    # For Modules: checks if input's class includes the module
    # For Classes: checks if input is an instance of the class
    #
    #: (untyped) -> void
    def validate_input!(input)
      types = self.class.input_types
      return if types.empty?

      types.each do |expected_type|
        if expected_type.is_a?(Module) && !expected_type.is_a?(Class)
          # Module の場合: include しているかを検査
          unless input.class.include?(expected_type)
            raise ArgumentError,
                  "Input #{input.class} must include #{expected_type}"
          end
        elsif !input.is_a?(expected_type)
          # Class の場合: インスタンスかを検査
          raise ArgumentError,
                "Input must be an instance of #{expected_type}, got #{input.class}"
        end
      end
    end

    # Validates that the result's value satisfies the declared output type
    # Only validates if result is success and output_schema is a Class
    #
    #: (Result[untyped]) -> void
    def validate_output!(result)
      return unless result.success?

      expected_type = self.class.output_schema
      return if expected_type.nil?
      return unless expected_type.is_a?(Class)

      value = result.value
      return if value.is_a?(expected_type)

      raise TypeError,
            "Output must be an instance of #{expected_type}, got #{value.class}"
    end

    # Executes the core logic with before/after/around hooks
    #
    #: (untyped) { () -> Result[untyped] } -> Result[untyped]
    def execute_with_hooks(input, &core_block)
      execution = build_around_chain(input, core_block)
      run_before_hooks(input)
      result = execution.call
      validate_output!(result)
      run_after_hooks(input, result)
      result
    end

    # Executes the UseCase with retry support
    #
    #: (untyped) -> Result[untyped]
    def execute_with_retry(input)
      context = build_retry_context
      current_input = input

      loop do
        result = execute_with_hooks(current_input) { call(current_input) }

        return result if result.success?
        return result if should_discard?(result)

        retry_config = find_matching_retry_config(result)
        run_on_failure_hooks(current_input, result, context)

        should_retry = context.should_retry? || (retry_config && !context.exhausted?)

        unless should_retry
          run_after_retries_exhausted_hooks(current_input, result, context) if context.retried?
          return result
        end

        wait_time = context.retry_wait || retry_config&.calculate_wait(context.attempt) || 0
        run_before_retry_hooks(current_input, result, context)

        sleep(wait_time) if wait_time.positive?

        current_input = context.retry_input || current_input
        context.increment!(last_error: result.errors.first)
      end
    end

    # Builds a retry context with max attempts from configurations
    #
    #: () -> RetryContext
    def build_retry_context
      max_attempts = self.class.retry_configurations.map(&:attempts).max
      RetryContext.new(max_attempts: max_attempts)
    end

    # Finds a retry configuration that matches the result
    #
    #: (Result[untyped]) -> RetryConfiguration?
    def find_matching_retry_config(result)
      self.class.retry_configurations.find { |c| c.matches?(result) }
    end

    # Checks if the result should be discarded (no retry)
    #
    #: (Result[untyped]) -> bool
    def should_discard?(result)
      return false unless result.failure?

      result.errors.any? do |error|
        self.class.discard_matchers.any? do |matcher|
          case matcher
          when Symbol
            error.code == matcher
          when Class
            error.cause&.is_a?(matcher)
          end
        end
      end
    end

    # Runs before_retry hooks
    #
    #: (untyped, Result[untyped], RetryContext) -> void
    def run_before_retry_hooks(input, result, context)
      self.class.before_retry_hooks.each do |hook|
        instance_exec(input, result, context, &hook) # steep:ignore BlockTypeMismatch
      end
    end

    # Runs after_retries_exhausted hooks
    #
    #: (untyped, Result[untyped], RetryContext) -> void
    def run_after_retries_exhausted_hooks(input, result, context)
      self.class.after_retries_exhausted_hooks.each do |hook|
        instance_exec(input, result, context, &hook) # steep:ignore BlockTypeMismatch
      end
    end

    # Wraps a non-Result value in Result.success
    #
    #: (untyped) -> Result[untyped]
    def wrap_result(value)
      return value if value.is_a?(Result)

      Result.success(value)
    end

    # Builds the around hook chain
    #
    #: (untyped, Proc) -> Proc
    def build_around_chain(input, core_block)
      wrapped_core = -> { wrap_result(core_block.call) }
      chain = wrap_extension_around_hooks(input, wrapped_core)
      wrap_block_around_hooks(input, chain)
    end

    # Wraps extension/module around hooks
    #
    #: (untyped, Proc) -> Proc
    def wrap_extension_around_hooks(input, chain)
      collect_extension_around_hooks.reverse.reduce(chain) do |inner, hook|
        -> { wrap_result(hook.call(input) { inner.call }) }
      end
    end

    # Wraps block-based around hooks (pass self as second argument)
    #
    #: (untyped, Proc) -> Proc
    def wrap_block_around_hooks(input, chain)
      use_case_instance = self
      self.class.around_hooks.reverse.reduce(chain) do |inner, hook|
        -> { wrap_result(hook.call(input, use_case_instance) { inner.call }) }
      end
    end

    # Collects around hooks from Hook classes and extension modules (not block-based)
    #
    #: () -> Array[Proc]
    def collect_extension_around_hooks
      hooks = hook_instances.map { |hook_instance| hook_instance.method(:around).to_proc }
      self.class.extensions.each do |ext|
        next if hook_class?(ext)

        hooks << ext.method(:around).to_proc if ext.respond_to?(:around)
      end
      hooks
    end

    # Runs all before hooks
    #
    #: (untyped) -> void
    def run_before_hooks(input)
      hook_instances.each do |hook_instance|
        hook_instance.before(input)
      end
      self.class.extensions.each do |ext|
        next if hook_class?(ext)

        ext.send(:before, input) if ext.respond_to?(:before)
      end
      self.class.before_hooks.each { |hook| instance_exec(input, &hook) } # steep:ignore BlockTypeMismatch
    end

    # Runs all after hooks
    #
    #: (untyped, Result[untyped]) -> void
    def run_after_hooks(input, result)
      hook_instances.each do |hook_instance|
        hook_instance.after(input, result)
      end
      self.class.extensions.each do |ext|
        next if hook_class?(ext)

        ext.send(:after, input, result) if ext.respond_to?(:after)
      end
      self.class.after_hooks.each { |hook| instance_exec(input, result, &hook) } # steep:ignore BlockTypeMismatch
    end

    # Runs all on_failure hooks when result is a failure
    #
    #: (untyped, Result[untyped], ?RetryContext?) -> void
    def run_on_failure_hooks(input, result, context = nil)
      return unless result.failure?

      hook_instances.each do |hook_instance|
        call_on_failure_hook(hook_instance, :on_failure, input, result, context)
      end

      self.class.extensions.each do |ext|
        next if hook_class?(ext)
        next unless ext.respond_to?(:on_failure)

        call_on_failure_hook(ext, :on_failure, input, result, context)
      end

      self.class.on_failure_hooks.each do |hook|
        if context && (hook.arity == 3 || hook.arity.negative?)
          instance_exec(input, result, context, &hook) # steep:ignore BlockTypeMismatch
        else
          instance_exec(input, result, &hook) # steep:ignore BlockTypeMismatch
        end
      end
    end

    # Calls an on_failure hook with appropriate arguments
    #
    #: (untyped, Symbol, untyped, Result[untyped], RetryContext?) -> void
    def call_on_failure_hook(target, method_name, input, result, context)
      method = target.method(method_name)
      if context && (method.arity == 3 || method.arity.negative?)
        target.send(method_name, input, result, context)
      else
        target.send(method_name, input, result)
      end
    end

    # Returns instantiated hook objects
    #
    #: () -> Array[Hook]
    def hook_instances
      @hook_instances ||= self.class.extensions.filter_map do |ext|
        next unless hook_class?(ext)

        hook_class = ext #: singleton(Hook)
        hook_class.new(container: @_container, use_case_namespace: effective_namespace)
      end
    end

    # Checks if the extension is a Hook class
    #
    #: (untyped) -> bool
    def hook_class?(ext)
      ext.is_a?(Class) && ext < Hook
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
    # Overrides DependsOn::InstanceMethods to accept container as parameter
    #
    #: (Container, Symbol) -> untyped
    def resolve_from_container(container, name)
      ns = effective_namespace
      if ns
        container.resolve_in(ns, name)
      else
        container.resolve(name)
      end
    end

    # Executes the organized UseCase pipeline
    #
    #: (untyped) -> Result[untyped]
    def execute_pipeline(input)
      case self.class.on_failure_strategy
      when :stop
        execute_pipeline_stop(input)
      when :continue
        execute_pipeline_continue(input)
      when :collect
        execute_pipeline_collect(input)
      else
        raise ArgumentError, "Unknown on_failure strategy: #{self.class.on_failure_strategy}"
      end
    end

    # Executes pipeline with :stop strategy
    #
    #: (untyped) -> Result[untyped]
    def execute_pipeline_stop(input)
      current_input = input
      result = nil #: Result[untyped]?
      executed_steps = [] #: Array[StepExecutionRecord]

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        executed_steps << StepExecutionRecord.new(step: step, input: current_input, result: step_result)

        if step_result.failure? && step_should_stop?(step)
          execute_pipeline_rollback(executed_steps)
          return step_result
        end

        current_input = step_result.value if step_result.success?
        result = step_result
      end

      result || success(current_input)
    end

    # Executes pipeline with :continue strategy
    #
    #: (untyped) -> Result[untyped]
    def execute_pipeline_continue(input)
      current_input = input
      result = nil #: Result[untyped]?
      executed_steps = [] #: Array[StepExecutionRecord]

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        executed_steps << StepExecutionRecord.new(step: step, input: current_input, result: step_result)

        if step_result.failure? && step.on_failure == :stop
          execute_pipeline_rollback(executed_steps)
          return step_result
        end

        current_input = step_result.value if step_result.success?
        result = step_result
      end

      result || success(current_input)
    end

    # Executes pipeline with :collect strategy
    #
    #: (untyped) -> Result[untyped]
    def execute_pipeline_collect(input)
      errors = [] #: Array[Error]
      executed_steps = [] #: Array[StepExecutionRecord]
      state = { input: input, errors: errors, last_success: nil }

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(state[:input], self)

        result = execute_step(step, state[:input])
        executed_steps << StepExecutionRecord.new(step: step, input: state[:input], result: result)
        break if should_stop_collect_pipeline?(result, step, state)
      end

      final_result = build_collect_result(state)
      execute_pipeline_rollback(executed_steps) if final_result.failure?
      final_result
    end

    # Updates collect state and checks if pipeline should stop
    #
    #: (Result[untyped], Step, Hash[Symbol, untyped]) -> bool
    def should_stop_collect_pipeline?(result, step, state)
      if result.failure?
        state[:errors].concat(result.errors)
        step.on_failure == :stop
      else
        state[:input] = result.value
        state[:last_success] = result
        false
      end
    end

    # Builds the final result for collect mode
    #
    #: (Hash[Symbol, untyped]) -> Result[untyped]
    def build_collect_result(state)
      if state[:errors].any?
        Result.failure(*state[:errors])
      else
        state[:last_success] || success(state[:input])
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
    # Requires input type(s) to be defined for pipeline steps
    # Note: on_failure hooks are not called here - they're called in pipeline rollback
    #
    #: (singleton(Base), untyped) -> Result[untyped]
    def call_use_case(use_case_class, input)
      if use_case_class.input_types.empty?
        raise ArgumentError, "#{use_case_class.name} must define `input` type(s) to be used in a pipeline"
      end

      instance = use_case_class.new(container: @_container)
      instance.send(:perform_as_pipeline_step, input, capture_exceptions: @_capture_exceptions || false)
    end

    # Performs the UseCase as a pipeline step (without on_failure hooks)
    # on_failure hooks are handled by the pipeline's rollback mechanism instead
    #
    #: (untyped, ?capture_exceptions: bool) -> Result[untyped]
    def perform_as_pipeline_step(input, capture_exceptions: false)
      @_capture_exceptions = capture_exceptions

      unless self.class.input_class || self.class.organized_steps
        raise ArgumentError, "#{self.class.name} must define `input` class"
      end

      validate_input!(input)
      execute_with_hooks(input) { call(input) }
    rescue StandardError => e
      raise unless capture_exceptions

      Result.from_exception(e)
    end

    # Executes rollback by calling on_failure hooks on executed steps in reverse order
    # Unlike run_on_failure_hooks, this method calls hooks regardless of result status
    # because we want to rollback even successfully completed steps when pipeline fails
    #
    #: (Array[StepExecutionRecord]) -> void
    def execute_pipeline_rollback(executed_steps)
      executed_steps.reverse_each do |record|
        step_instance = record.step.use_case_class.new(container: @_container)
        step_instance.send(:run_rollback_hooks, record.input, record.result)
      end
    end

    # Runs on_failure hooks for rollback purposes (regardless of result status)
    #
    #: (untyped, Result[untyped]) -> void
    def run_rollback_hooks(input, result)
      hook_instances.each do |hook_instance|
        call_on_failure_hook(hook_instance, :on_failure, input, result, nil)
      end

      self.class.extensions.each do |ext|
        next if hook_class?(ext)
        next unless ext.respond_to?(:on_failure)

        call_on_failure_hook(ext, :on_failure, input, result, nil)
      end

      self.class.on_failure_hooks.each do |hook|
        instance_exec(input, result, &hook) # steep:ignore BlockTypeMismatch
      end
    end
  end
end
