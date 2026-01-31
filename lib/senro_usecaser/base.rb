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
    class << self
      # Declares a dependency to be injected from the container
      #
      #: (Symbol, ?Class) -> void
      def depends_on(name, type = nil)
        dependencies << name unless dependencies.include?(name)
        dependency_types[name] = type if type

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
      #
      #: () { (untyped) { () -> Result[untyped] } -> Result[untyped] } -> void
      def around(&block)
        around_hooks << block if block
      end

      # Returns the list of around hooks
      #
      #: () -> Array[Proc]
      def around_hooks
        @around_hooks ||= []
      end

      # Declares the expected input type for this UseCase
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

      execute_with_hooks(input) do
        call(input)
      end
    end

    # Executes the UseCase logic
    #
    #: (?untyped input) -> Result[untyped]
    def call(input = nil)
      return execute_pipeline(input) if self.class.organized_steps

      raise NotImplementedError, "#{self.class.name}#call must be implemented"
    end

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

    # Executes the core logic with before/after/around hooks
    #
    #: (untyped) { () -> Result[untyped] } -> Result[untyped]
    def execute_with_hooks(input, &core_block)
      execution = build_around_chain(input, core_block)
      run_before_hooks(input)
      result = execution.call
      run_after_hooks(input, result)
      result
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
      all_around_hooks = collect_around_hooks

      all_around_hooks.reverse.reduce(wrapped_core) do |inner, hook|
        -> { wrap_result(hook.call(input) { inner.call }) }
      end
    end

    # Collects all around hooks from extensions and block-based hooks
    #
    #: () -> Array[Proc]
    def collect_around_hooks
      hooks = [] #: Array[Proc]
      self.class.extensions.each do |ext|
        hooks << ext.method(:around).to_proc if ext.respond_to?(:around)
      end
      hooks.concat(self.class.around_hooks)
      hooks
    end

    # Runs all before hooks
    #
    #: (untyped) -> void
    def run_before_hooks(input)
      self.class.extensions.each do |ext|
        ext.send(:before, input) if ext.respond_to?(:before)
      end
      self.class.before_hooks.each { |hook| hook.call(input) }
    end

    # Runs all after hooks
    #
    #: (untyped, Result[untyped]) -> void
    def run_after_hooks(input, result)
      self.class.extensions.each do |ext|
        ext.send(:after, input, result) if ext.respond_to?(:after)
      end
      self.class.after_hooks.each { |hook| hook.call(input, result) }
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
    #
    #: () -> (Symbol | String)?
    def effective_namespace
      return self.class.use_case_namespace if self.class.use_case_namespace
      return nil unless SenroUsecaser.configuration.infer_namespace_from_module

      infer_namespace_from_class
    end

    # Infers namespace from the class's module structure
    #
    #: () -> String?
    def infer_namespace_from_class
      class_name = self.class.name
      return nil unless class_name

      parts = class_name.split("::")
      return nil if parts.length <= 1

      module_parts = parts[0...-1] || [] #: Array[String]
      return nil if module_parts.empty?

      module_parts.map { |part| part.gsub(/([a-z])([A-Z])/, '\1_\2').downcase }.join("::")
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

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        return step_result if step_result.failure? && step_should_stop?(step)

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

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(current_input, self)

        step_result = execute_step(step, current_input)
        return step_result if step_result.failure? && step.on_failure == :stop

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
      state = { input: input, errors: errors, last_success: nil }

      self.class.organized_steps&.each do |step|
        next unless step.should_execute?(state[:input], self)

        result = execute_step(step, state[:input])
        break if should_stop_collect_pipeline?(result, step, state)
      end

      build_collect_result(state)
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
    # Requires input_class to be defined for pipeline steps
    #
    #: (singleton(Base), untyped) -> Result[untyped]
    def call_use_case(use_case_class, input)
      unless use_case_class.input_class
        raise ArgumentError, "#{use_case_class.name} must define `input` class to be used in a pipeline"
      end

      call_method = @_capture_exceptions || false ? :call! : :call #: Symbol
      use_case_class.public_send(call_method, input, container: @_container)
    end
  end
end
