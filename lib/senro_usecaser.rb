# frozen_string_literal: true

# rbs_inline: enabled

require_relative "senro_usecaser/version"
require_relative "senro_usecaser/error"
require_relative "senro_usecaser/result"
require_relative "senro_usecaser/container"
require_relative "senro_usecaser/configuration"
require_relative "senro_usecaser/provider"
require_relative "senro_usecaser/base"

# SenroUsecaser is a type-safe UseCase pattern implementation library for Ruby.
#
# It provides:
# - Type-safe input/output with RBS Inline
# - DI container with namespaces
# - Flexible composition with organize/include/extend patterns
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
#   if result.success?
#     puts result.value.name
#   end
module SenroUsecaser
  class << self
    # Returns the global container instance
    #
    # @example
    #   SenroUsecaser.container.register(:logger, Logger.new)
    #
    #: () -> Container
    def container
      @container ||= Container.new
    end

    # Sets the global container instance
    #
    # @example
    #   SenroUsecaser.container = MyCustomContainer.new
    #
    #: (Container) -> Container
    attr_writer :container

    # Resets the global container (useful for testing)
    #
    #: () -> void
    def reset_container!
      @container = nil
    end

    # Registers a provider to the global container
    #
    # @example
    #   SenroUsecaser.register_provider(UserProvider)
    #
    #: (singleton(Provider)) -> void
    def register_provider(provider_class)
      provider_class.call(container)
    end

    # Registers multiple providers to the global container
    #
    # @example
    #   SenroUsecaser.register_providers(UserProvider, OrderProvider, PaymentProvider)
    #
    #: (*singleton(Provider)) -> void
    def register_providers(*provider_classes)
      provider_classes.each { |klass| register_provider(klass) }
    end

    # Returns the configuration instance
    #
    #: () -> Configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # Configures SenroUsecaser
    #
    # @example
    #   SenroUsecaser.configure do |config|
    #     config.providers = [CoreProvider, UserProvider]
    #     config.infer_namespace_from_module = true
    #   end
    #
    #: () { (Configuration) -> void } -> void
    def configure
      yield configuration
    end

    # Boots all configured providers in dependency order
    #
    # @example
    #   SenroUsecaser.configure do |config|
    #     config.providers = [CoreProvider, UserProvider]
    #   end
    #   SenroUsecaser.boot!
    #
    #: () -> void
    def boot!
      @booter = ProviderBooter.new(configuration.providers, container)
      @booter.boot!
    end

    # Shuts down all booted providers
    #
    #: () -> void
    def shutdown!
      @booter&.shutdown!
    end

    # Returns the current environment
    #
    # @example
    #   SenroUsecaser.env.development?
    #   SenroUsecaser.env.production?
    #
    #: () -> Environment
    def env
      @env ||= Environment.new(detect_environment)
    end

    # Sets the environment
    #
    #: (String) -> void
    def env=(name)
      @env = Environment.new(name)
    end

    # Resets all state (useful for testing)
    #
    #: () -> void
    def reset!
      @container = nil
      @configuration = nil
      @booter = nil
      @env = nil
    end

    private

    #: () -> String
    def detect_environment
      ENV["SENRO_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
    end
  end
end
