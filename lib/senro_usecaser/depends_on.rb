# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Module that provides dependency injection support
  #
  # This module can be extended into any class to enable the full DI functionality
  # similar to UseCase and Hook classes, including:
  # - `depends_on` for declaring dependencies
  # - `namespace` for scoped dependency resolution
  # - Automatic `infer_namespace_from_module` support
  # - Default `initialize` that sets up dependency injection (uses SenroUsecaser.container if not provided)
  #
  # @example Basic usage (no initialize needed)
  #   class MyService
  #     extend SenroUsecaser::DependsOn
  #
  #     depends_on :logger, Logger
  #     depends_on :repository
  #
  #     # No initialize needed! Default is provided automatically.
  #
  #     def perform
  #       logger.info("Performing...")
  #       repository.find(1)
  #     end
  #   end
  #
  #   service = MyService.new  # Uses SenroUsecaser.container
  #   service.logger  # => Logger instance
  #
  # @example Custom initialize with super
  #   class MyService
  #     extend SenroUsecaser::DependsOn
  #
  #     depends_on :logger
  #     attr_reader :extra
  #
  #     def initialize(extra:, container: nil)
  #       super(container: container)  # Handles dependency resolution
  #       @extra = extra
  #     end
  #   end
  #
  # @example With explicit namespace
  #   class Admin::UserService
  #     extend SenroUsecaser::DependsOn
  #
  #     namespace :admin
  #     depends_on :user_repository, UserRepository
  #   end
  #
  # @example With infer_namespace_from_module (when configured)
  #   # When SenroUsecaser.configuration.infer_namespace_from_module = true
  #   class Admin::Orders::ProcessService
  #     extend SenroUsecaser::DependsOn
  #
  #     depends_on :order_repository  # resolved from "admin::orders" namespace
  #   end
  module DependsOn
    # Hook called when module is extended into a class
    # Automatically includes InstanceMethods
    #
    def self.extended(base)
      base.include(InstanceMethods)
    end

    # Declares a dependency to be injected from the container
    #
    # @param name [Symbol] The name of the dependency
    # @param type [Class, nil] Optional expected type for the dependency
    #
    # @example Basic dependency
    #   depends_on :logger
    #
    # @example Typed dependency
    #   depends_on :repository, UserRepository
    #
    #: (Symbol, ?Class) -> void
    def depends_on(name, type = nil)
      dependencies << name unless dependencies.include?(name)
      dependency_types[name] = type if type

      define_method(name) do # steep:ignore NoMethod
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
    # @param name [Symbol, String, nil] The namespace to set
    # @return [Symbol, String, nil] The current namespace when no argument given
    #
    # @example Setting namespace
    #   namespace :admin
    #
    # @example Getting namespace
    #   current_ns = namespace
    #
    #: (?(Symbol | String)) -> (Symbol | String)?
    def namespace(name = nil)
      if name
        @declared_namespace = name
      else
        @declared_namespace
      end
    end

    # Returns the declared namespace
    #
    #: () -> (Symbol | String)?
    def declared_namespace
      @declared_namespace
    end

    # Copies dependency configuration to a subclass
    #
    # @param subclass [Class] The subclass to copy dependencies to
    #
    # @example In inherited hook
    #   def self.inherited(subclass)
    #     super
    #     copy_depends_on_to(subclass)
    #   end
    #
    #: (Class) -> void
    def copy_depends_on_to(subclass)
      subclass.instance_variable_set(:@dependencies, dependencies.dup)
      subclass.instance_variable_set(:@dependency_types, dependency_types.dup)
      subclass.instance_variable_set(:@declared_namespace, @declared_namespace)
    end

    # Instance methods for dependency resolution
    #
    # These methods are automatically included when DependsOn is extended.
    # They require @_container and @_dependencies instance variables to be set.
    module InstanceMethods
      # Default initialize for classes using DependsOn
      #
      # This provides a default initialize that sets up dependency injection.
      # Classes can override this and call super to extend the behavior.
      #
      # @param container [Container, nil] The DI container to resolve dependencies from.
      #   If nil, uses SenroUsecaser.container.
      #
      # @example Default usage (no arguments needed)
      #   class MyService
      #     extend SenroUsecaser::DependsOn
      #     depends_on :logger
      #   end
      #   service = MyService.new  # Uses SenroUsecaser.container
      #
      # @example With explicit container
      #   service = MyService.new(container: custom_container)
      #
      # @example Custom initialize with super
      #   class MyService
      #     extend SenroUsecaser::DependsOn
      #     depends_on :logger
      #     attr_reader :extra
      #
      #     def initialize(extra:, container: nil)
      #       super(container: container)
      #       @extra = extra
      #     end
      #   end
      #
      #: (?container: Container?) -> void
      def initialize(container: nil)
        @_container = container || SenroUsecaser.container
        @_dependencies = {} #: Hash[Symbol, untyped]
        resolve_dependencies
      end

      # Resolves all declared dependencies from the container
      #
      # Call this in your initialize method after setting @_container and @_dependencies.
      #
      # @example
      #   def initialize(container:)
      #     @_container = container
      #     @_dependencies = {}
      #     resolve_dependencies
      #   end
      #
      #: () -> void
      def resolve_dependencies
        self.class.dependencies.each do |name| # steep:ignore NoMethod
          @_dependencies[name] = resolve_from_container(name)
        end
      end

      private

      # Returns the effective namespace for dependency resolution
      #
      # Priority:
      # 1. Explicitly declared namespace via `namespace :name`
      # 2. Inferred namespace from module structure (if configured)
      #
      #: () -> (Symbol | String)?
      def effective_namespace
        declared = self.class.declared_namespace # steep:ignore NoMethod
        return declared if declared
        return nil unless SenroUsecaser.configuration.infer_namespace_from_module

        infer_namespace_from_class
      end

      # Infers namespace from the class's module structure
      #
      # Converts CamelCase module names to snake_case and joins with "::"
      # e.g., Admin::Orders::ProcessService -> "admin::orders"
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

      # Resolves a single dependency from the container
      #
      #: (Symbol) -> untyped
      def resolve_from_container(name)
        ns = effective_namespace
        if ns
          @_container.resolve_in(ns, name)
        else
          @_container.resolve(name)
        end
      end
    end
  end
end
