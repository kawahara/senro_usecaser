# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Configuration for SenroUsecaser
  #
  # @example
  #   SenroUsecaser.configure do |config|
  #     config.providers = [CoreProvider, UserProvider]
  #     config.infer_namespace_from_module = true
  #   end
  #
  class Configuration
    # List of provider classes to boot
    #: () -> Array[singleton(Provider)]
    attr_accessor :providers

    # Whether to infer namespace from module structure
    #: () -> bool
    attr_accessor :infer_namespace_from_module

    #: () -> void
    def initialize
      @providers = []
      @infer_namespace_from_module = false
    end
  end

  # Environment detection
  #
  # @example
  #   SenroUsecaser.env.development?
  #   SenroUsecaser.env.production?
  #
  class Environment
    #: (String) -> void
    def initialize(name)
      @name = name
    end

    #: () -> String
    attr_reader :name

    #: () -> bool
    def development?
      @name == "development"
    end

    #: () -> bool
    def test?
      @name == "test"
    end

    #: () -> bool
    def production?
      @name == "production"
    end

    #: () -> String
    def to_s
      @name
    end
  end

  # Provider boot manager
  #
  # Resolves provider dependencies and boots them in correct order.
  #
  class ProviderBooter
    # Error raised when circular dependencies are detected
    class CircularDependencyError < StandardError; end

    #: (Array[singleton(Provider)], Container) -> void
    def initialize(provider_classes, container)
      @provider_classes = provider_classes
      @container = container
      @booted_providers = [] #: Array[singleton(Provider)]
      @provider_instances = {} #: Hash[singleton(Provider), Provider]
    end

    # Boots all providers in dependency order
    #
    #: () -> void
    def boot!
      sorted = topological_sort(@provider_classes)

      sorted.each do |provider_class|
        next unless provider_class.enabled?

        instance = provider_class.new
        @provider_instances[provider_class] = instance
        instance.register_to(@container)
        @booted_providers << provider_class
      end

      # Call after_boot on all providers
      @booted_providers.each do |provider_class|
        @provider_instances[provider_class].after_boot(@container)
      end
    end

    # Shuts down all providers in reverse order
    #
    #: () -> void
    def shutdown!
      @booted_providers.reverse_each do |provider_class|
        @provider_instances[provider_class].shutdown(@container)
      end
    end

    private

    # Topologically sorts providers based on dependencies
    #
    #: (Array[singleton(Provider)]) -> Array[singleton(Provider)]
    def topological_sort(providers)
      sorted = [] #: Array[singleton(Provider)]
      visited = {} #: Hash[singleton(Provider), bool]
      visiting = {} #: Hash[singleton(Provider), bool]

      providers.each do |provider|
        visit(provider, sorted, visited, visiting) unless visited[provider]
      end

      sorted
    end

    #: (singleton(Provider), Array[singleton(Provider)], untyped, untyped) -> void
    def visit(provider, sorted, visited, visiting)
      return if visited[provider]

      if visiting[provider]
        raise CircularDependencyError,
              "Circular dependency detected involving #{provider.name}"
      end

      visiting[provider] = true

      provider.provider_dependencies.each do |dep|
        visit(dep, sorted, visited, visiting) unless visited[dep]
      end

      visiting.delete(provider)
      visited[provider] = true
      sorted << provider
    end
  end
end
