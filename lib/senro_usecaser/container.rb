# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Wrapper for singleton registrations that caches the result
  class SingletonRegistration
    #: (^(Container) -> untyped) -> void
    def initialize(block)
      @block = block
      @resolved = false
      @value = nil
    end

    #: (Container) -> untyped
    def call(container)
      unless @resolved
        @value = @block.call(container)
        @resolved = true
      end
      @value
    end
  end

  # DI Container with namespace support
  #
  # @example Basic usage
  #   container = SenroUsecaser::Container.new
  #   container.register(:logger, Logger.new)
  #   container.resolve(:logger) # => Logger instance
  #
  # @example With namespaces
  #   container = SenroUsecaser::Container.new
  #   container.register(:logger, Logger.new)
  #
  #   container.namespace(:admin) do
  #     register(:user_repository, AdminUserRepository.new)
  #   end
  #
  #   # From admin namespace, can resolve both admin and root dependencies
  #   container.resolve_in(:admin, :user_repository) # => AdminUserRepository
  #   container.resolve_in(:admin, :logger)          # => Logger (from root)
  class Container
    # Error raised when a dependency cannot be resolved
    class ResolutionError < StandardError; end

    # Error raised when a dependency is already registered
    class DuplicateRegistrationError < StandardError; end

    #: (?parent: Container?) -> void
    def initialize(parent: nil)
      @parent = parent
      @registrations = {} #: Hash[String, untyped]
      @current_namespace = [] #: Array[Symbol]
    end

    # Creates a scoped child container that inherits from this container
    #
    # @example
    #   scoped = container.scope do
    #     register(:current_user, current_user)
    #   end
    #   scoped.resolve(:current_user) # => current_user
    #   scoped.resolve(:logger)       # => resolved from parent
    #
    #: () ?{ () -> void } -> Container
    def scope(&block)
      child = Container.new(parent: self)
      child.instance_eval(&block) if block # steep:ignore BlockTypeMismatch
      child
    end

    # Registers a dependency in the current namespace
    #
    # @example With value (returns same value every time)
    #   container.register(:logger, Logger.new)
    #
    # @example With block (lazy evaluation, called every time, receives container)
    #   container.register(:database) { |container| Database.connect }
    #
    #: (Symbol, ?untyped) ?{ (Container) -> untyped } -> void
    def register(key, value = nil, &block)
      raise ArgumentError, "Provide either a value or a block, not both" if value && block
      raise ArgumentError, "Provide either a value or a block" if value.nil? && block.nil?

      full_key = build_key(key)
      check_duplicate_registration!(full_key)

      @registrations[full_key] = block || ->(_) { value }
    end

    # Registers a lazy dependency (block is called every time on resolve)
    #
    # @example
    #   container.register_lazy(:connection) { |c| Database.connect }
    #
    # @example With dependency resolution
    #   container.register_lazy(:user_repository) do |container|
    #     UserRepository.new(current_user: container.resolve(:current_user))
    #   end
    #
    #: [T] (Symbol) { (Container) -> T } -> void
    def register_lazy(key, &block)
      raise ArgumentError, "Block is required for register_lazy" unless block

      full_key = build_key(key)
      check_duplicate_registration!(full_key)

      @registrations[full_key] = block
    end

    # Registers a singleton dependency (block is called once and cached)
    #
    # @example
    #   container.register_singleton(:database) { |c| Database.connect }
    #   container.resolve(:database) # => same instance every time
    #
    # @example With dependency resolution
    #   container.register_singleton(:service) do |container|
    #     Service.new(logger: container.resolve(:logger))
    #   end
    #
    #: [T] (Symbol) { (Container) -> T } -> void
    def register_singleton(key, &block)
      raise ArgumentError, "Block is required for register_singleton" unless block

      full_key = build_key(key)
      check_duplicate_registration!(full_key)

      @registrations[full_key] = SingletonRegistration.new(block)
    end

    # Resolves a dependency from the current namespace or its ancestors
    #
    # @example
    #   container.resolve(:logger)
    #
    #: [T] (Symbol) -> T
    def resolve(key)
      resolve_in(current_namespace_path, key)
    end

    # Resolves a dependency from a specific namespace or its ancestors
    #
    # @example
    #   container.resolve_in(:admin, :logger)
    #   container.resolve_in("admin::reports", :generator)
    #
    #: [T] ((Symbol | String | Array[Symbol]), Symbol) -> T
    def resolve_in(namespace, key)
      registration = find_registration(namespace, key)

      unless registration
        raise ResolutionError,
              "Dependency #{key.inspect} not found in namespace #{namespace.inspect} or its ancestors"
      end

      # Always invoke with self (the resolving container) for proper scoping
      invoke_registration(registration)
    end

    # Checks if a dependency is registered
    #
    #: (Symbol) -> bool
    def registered?(key)
      registered_in?(current_namespace_path, key)
    end

    # Checks if a dependency is registered in a specific namespace or its ancestors
    #
    #: ((Symbol | String | Array[Symbol]), Symbol) -> bool
    def registered_in?(namespace, key)
      namespace_parts = normalize_namespace(namespace)

      (namespace_parts.length + 1).times do |i|
        current_parts = namespace_parts[0, namespace_parts.length - i] || []
        full_key = build_key_with_namespace(current_parts, key)
        return true if @registrations.key?(full_key)
      end

      # Check parent container if available
      return @parent.registered_in?(namespace, key) if @parent

      false
    end

    # Creates a namespace scope for registering dependencies
    #
    # @example
    #   container.namespace(:admin) do
    #     register(:user_repository, AdminUserRepository.new)
    #
    #     namespace(:reports) do
    #       register(:generator, ReportGenerator.new)
    #     end
    #   end
    #
    #: ((Symbol | String)) { () -> void } -> void
    def namespace(name, &)
      @current_namespace.push(name.to_sym)
      instance_eval(&) # steep:ignore BlockTypeMismatch
    ensure
      @current_namespace.pop
    end

    # Returns all registered keys (including parent keys)
    #
    #: () -> Array[String]
    def keys
      own_keys = @registrations.keys
      return own_keys unless @parent

      (own_keys + @parent.keys).uniq
    end

    # Returns only keys registered in this container (excluding parent)
    #
    #: () -> Array[String]
    def own_keys
      @registrations.keys
    end

    # Returns the parent container if any
    #
    #: () -> Container?
    attr_reader :parent

    # Clears all registrations
    #
    #: () -> void
    def clear!
      @registrations.clear
    end

    private

    #: () -> String
    def current_namespace_path
      @current_namespace.join("::")
    end

    #: (Symbol) -> String
    def build_key(key)
      build_key_with_namespace(@current_namespace, key)
    end

    #: (Array[Symbol], Symbol) -> String
    def build_key_with_namespace(namespace_parts, key)
      if namespace_parts.empty?
        key.to_s
      else
        "#{namespace_parts.join("::")}::#{key}"
      end
    end

    #: ((Symbol | String | Array[Symbol])) -> Array[Symbol]
    def normalize_namespace(namespace)
      case namespace
      when Array then normalize_array_namespace(namespace)
      when Symbol then normalize_symbol_namespace(namespace)
      when String then normalize_string_namespace(namespace)
      else raise ArgumentError, "Invalid namespace: #{namespace.inspect}"
      end
    end

    #: (Array[Symbol]) -> Array[Symbol]
    def normalize_array_namespace(namespace)
      namespace.map(&:to_sym)
    end

    #: (Symbol) -> Array[Symbol]
    def normalize_symbol_namespace(namespace)
      namespace == :root ? [] : [namespace]
    end

    #: (String) -> Array[Symbol]
    def normalize_string_namespace(namespace)
      namespace.empty? ? [] : namespace.split("::").map(&:to_sym)
    end

    #: (String) -> void
    def check_duplicate_registration!(full_key)
      return unless @registrations.key?(full_key)

      raise DuplicateRegistrationError, "Dependency #{full_key.inspect} is already registered"
    end

    # Invokes a registration, passing the container for dependency resolution
    #
    #: (untyped) -> untyped
    def invoke_registration(registration)
      registration.call(self)
    end

    protected

    # Finds a registration in this container or its parent chain
    #
    #: ((Symbol | String | Array[Symbol]), Symbol) -> untyped
    def find_registration(namespace, key)
      namespace_parts = normalize_namespace(namespace)

      # Try to find in the specified namespace and its ancestors
      (namespace_parts.length + 1).times do |i|
        current_parts = namespace_parts[0, namespace_parts.length - i] || []
        full_key = build_key_with_namespace(current_parts, key)

        return @registrations[full_key] if @registrations.key?(full_key)
      end

      # Fall back to parent container if available
      @parent&.find_registration(namespace, key)
    end
  end
end
