# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Base class for dependency providers
  #
  # Providers allow organizing dependency registrations across multiple files.
  # Each provider is responsible for registering a group of related dependencies.
  #
  # @example Basic provider
  #   class UserProvider < SenroUsecaser::Provider
  #     def register(container)
  #       container.register(:user_repository, UserRepository.new)
  #       container.register_singleton(:user_service) do |c|
  #         UserService.new(repo: c.resolve(:user_repository))
  #       end
  #     end
  #   end
  #
  # @example Provider with namespace
  #   class AdminProvider < SenroUsecaser::Provider
  #     namespace :admin
  #
  #     def register(container)
  #       container.register(:user_repository, AdminUserRepository.new)
  #     end
  #   end
  #
  # @example Provider with dependencies
  #   class PersistenceProvider < SenroUsecaser::Provider
  #     depends_on CoreProvider
  #
  #     def register(container)
  #       container.register(:database, Database.connect)
  #     end
  #   end
  #
  # @example Conditional provider
  #   class DevelopmentProvider < SenroUsecaser::Provider
  #     enabled_if { SenroUsecaser.env.development? }
  #   end
  #
  class Provider
    class << self
      # Declares dependencies on other providers
      #
      # @example
      #   class PersistenceProvider < SenroUsecaser::Provider
      #     depends_on CoreProvider
      #     depends_on ConfigProvider
      #   end
      #
      #: (*singleton(Provider)) -> void
      def depends_on(*provider_classes)
        provider_classes.each do |klass|
          provider_dependencies << klass unless provider_dependencies.include?(klass)
        end
      end

      # Returns the list of provider dependencies
      #
      #: () -> Array[singleton(Provider)]
      def provider_dependencies
        @provider_dependencies ||= [] #: Array[singleton(Provider)]
      end

      # Sets a condition for enabling this provider
      #
      # @example
      #   class DevelopmentProvider < SenroUsecaser::Provider
      #     enabled_if { Rails.env.development? }
      #   end
      #
      #: () { () -> bool } -> void
      def enabled_if(&block)
        @enabled_condition = block
      end

      # Returns whether this provider is enabled
      #
      #: () -> bool
      def enabled?
        return true unless @enabled_condition

        @enabled_condition.call
      end

      # Sets the namespace for this provider's registrations
      #
      # @example
      #   class AdminProvider < SenroUsecaser::Provider
      #     namespace :admin
      #   end
      #
      #: ((Symbol | String)) -> void
      def namespace(name = nil)
        if name
          @provider_namespace = name
        else
          @provider_namespace
        end
      end

      # @rbs!
      #   def self.provider_namespace: () -> (Symbol | String)?
      attr_reader :provider_namespace

      # Registers this provider's dependencies to the given container
      #
      #: (Container) -> void
      def call(container)
        new.register_to(container)
      end
    end

    # Registers dependencies to the container, wrapped in namespace if declared
    #
    #: (Container) -> void
    def register_to(container)
      before_register(container)

      ns = effective_namespace
      if ns
        # Capture self to call provider's register method within namespace context
        provider = self
        container.namespace(ns) { provider.register(container) }
      else
        register(container)
      end
    end

    # Returns the effective namespace for this provider
    # Uses explicitly declared namespace, or infers from module structure if configured
    #
    #: () -> (Symbol | String)?
    def effective_namespace
      # Explicit namespace takes precedence
      return self.class.provider_namespace if self.class.provider_namespace

      # Infer from module structure if enabled
      return nil unless SenroUsecaser.configuration.infer_namespace_from_module

      infer_namespace_from_class
    end

    # Infers namespace from the class's module structure
    #
    # @example
    #   Admin::UserProvider => "admin"
    #   Admin::Reports::ReportProvider => "admin::reports"
    #   CoreProvider => nil
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

    # Called before register. Override in subclasses.
    #
    # @example
    #   def before_register(container)
    #     # Setup work
    #   end
    #
    #: (Container) -> void
    def before_register(container); end

    # Override this method to register dependencies
    #
    # @example
    #   def register(container)
    #     container.register(:logger, Logger.new)
    #   end
    #
    #: (Container) -> void
    def register(container)
      raise NotImplementedError, "#{self.class.name}#register must be implemented"
    end

    # Called after all providers are registered. Override in subclasses.
    #
    # @example
    #   def after_boot(container)
    #     container.resolve(:database).verify_connection!
    #   end
    #
    #: (Container) -> void
    def after_boot(container); end

    # Called on application shutdown. Override in subclasses.
    #
    # @example
    #   def shutdown(container)
    #     container.resolve(:database).disconnect
    #   end
    #
    #: (Container) -> void
    def shutdown(container); end
  end
end
