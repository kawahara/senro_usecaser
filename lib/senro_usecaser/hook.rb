# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Base class for hooks with dependency injection support
  #
  # Hook classes provide a way to define before/after/around hooks
  # with access to the DI container and automatic dependency resolution.
  #
  # @example Basic hook
  #   class LoggingHook < SenroUsecaser::Hook
  #     depends_on :logger, Logger
  #
  #     def before(input)
  #       logger.info("Starting with #{input.class.name}")
  #     end
  #
  #     def after(input, result)
  #       logger.info("Finished: #{result.success? ? 'success' : 'failure'}")
  #     end
  #   end
  #
  # @example Hook with namespace
  #   class Admin::AuditHook < SenroUsecaser::Hook
  #     namespace :admin
  #     depends_on :audit_logger, AuditLogger
  #
  #     def after(input, result)
  #       audit_logger.log(input: input, result: result)
  #     end
  #   end
  #
  # @example Hook with around
  #   class TransactionHook < SenroUsecaser::Hook
  #     def around(input)
  #       ActiveRecord::Base.transaction { yield }
  #     end
  #   end
  class Hook
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

      # Sets or returns the namespace for dependency resolution
      #
      #: (?(Symbol | String)) -> (Symbol | String)?
      def namespace(name = nil)
        if name
          @hook_namespace = name
        else
          @hook_namespace
        end
      end

      # Alias for namespace() without arguments
      #
      #: () -> (Symbol | String)?
      def hook_namespace # rubocop:disable Style/TrivialAccessors
        @hook_namespace
      end

      # @api private
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@dependencies, dependencies.dup)
        subclass.instance_variable_set(:@dependency_types, dependency_types.dup)
        subclass.instance_variable_set(:@hook_namespace, @hook_namespace)
      end
    end

    # Initializes the hook with dependencies resolved from the container
    #
    #: (container: Container, ?use_case_namespace: (Symbol | String)?) -> void
    def initialize(container:, use_case_namespace: nil)
      @_container = container
      @_use_case_namespace = use_case_namespace
      @_dependencies = {} #: Hash[Symbol, untyped]

      resolve_dependencies
    end

    # Called before the UseCase executes
    # Override in subclass to add before logic
    #
    #: (untyped) -> void
    def before(input)
      # Override in subclass
    end

    # Called after the UseCase executes
    # Override in subclass to add after logic
    #
    #: (untyped, Result[untyped]) -> void
    def after(input, result)
      # Override in subclass
    end

    # Wraps the UseCase execution
    # Override in subclass to add around logic
    #
    #: (untyped) { () -> Result[untyped] } -> Result[untyped]
    def around(_input)
      yield
    end

    private

    # Returns the effective namespace for dependency resolution
    #
    #: () -> (Symbol | String)?
    def effective_namespace
      return self.class.hook_namespace if self.class.hook_namespace
      return @_use_case_namespace if @_use_case_namespace
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

    # Resolves dependencies from the container
    #
    #: () -> void
    def resolve_dependencies
      self.class.dependencies.each do |name|
        @_dependencies[name] = resolve_from_container(name)
      end
    end

    # Resolves a single dependency from the container
    #
    #: (Symbol) -> untyped
    def resolve_from_container(name)
      namespace = effective_namespace
      if namespace
        @_container.resolve_in(namespace, name)
      else
        @_container.resolve(name)
      end
    end
  end
end
