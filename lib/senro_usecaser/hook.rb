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
    extend DependsOn

    class << self
      # Alias for backward compatibility
      #
      #: () -> (Symbol | String)?
      alias hook_namespace declared_namespace

      # @api private
      def inherited(subclass)
        super
        copy_depends_on_to(subclass)
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

    # Called when the UseCase fails
    # Override in subclass to add failure handling or rollback logic
    #
    # @example Basic logging
    #   def on_failure(input, result)
    #     logger.error("Failed: #{result.errors.first&.message}")
    #   end
    #
    # @example Request retry
    #   def on_failure(input, result, context)
    #     if result.errors.first&.code == :network_error && context.attempt < 3
    #       context.retry!(wait: 2.0)
    #     end
    #   end
    #
    #: (untyped, Result[untyped], ?RetryContext?) -> void
    def on_failure(input, result, context = nil)
      # Override in subclass
    end

    private

    # Returns the effective namespace for dependency resolution
    # Overrides DependsOn::InstanceMethods to add use_case_namespace fallback
    #
    #: () -> (Symbol | String)?
    def effective_namespace
      declared = self.class.declared_namespace
      return declared if declared
      return @_use_case_namespace if @_use_case_namespace
      return nil unless SenroUsecaser.configuration.infer_namespace_from_module

      infer_namespace_from_class
    end
  end
end
