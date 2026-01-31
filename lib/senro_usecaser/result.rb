# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Represents the result of a UseCase execution
  #
  # Result is a generic type that holds either a success value or an array of errors.
  # Use {.success} and {.failure} class methods to create instances.
  #
  # @example Success case
  #   result = SenroUsecaser::Result.success(user)
  #   result.success? # => true
  #   result.value    # => user
  #
  # @example Failure case
  #   result = SenroUsecaser::Result.failure(
  #     SenroUsecaser::Error.new(code: :not_found, message: "User not found")
  #   )
  #   result.failure? # => true
  #   result.errors   # => [#<SenroUsecaser::Error ...>]
  #
  # @rbs generic T
  class Result
    # @rbs!
    #   attr_reader value: T?
    #   attr_reader errors: Array[Error]

    # @rbs skip
    attr_reader :value
    # @rbs skip
    attr_reader :errors

    # Creates a success Result with the given value
    #
    #: [T] (T) -> Result[T]
    def self.success(value)
      new(value: value, errors: [])
    end

    # Creates a failure Result with the given errors
    #
    #: (*Error) -> Result[untyped]
    def self.failure(*errors)
      errors = errors.flatten
      raise ArgumentError, "At least one error is required for failure" if errors.empty?

      new(value: nil, errors: errors)
    end

    # Creates a failure Result from an exception
    #
    # @example
    #   begin
    #     # some code that raises
    #   rescue => e
    #     Result.from_exception(e)
    #   end
    #
    #: (Exception, ?code: Symbol) -> Result[untyped]
    def self.from_exception(exception, code: :exception)
      error = Error.from_exception(exception, code: code)
      failure(error)
    end

    # Executes a block and captures any exception as a failure Result
    #
    # @example
    #   result = Result.capture { User.find(id) }
    #   # If User.find raises, result is a failure with the exception
    #   # If User.find succeeds, result is a success with the return value
    #
    # @example With specific exception classes
    #   result = Result.capture(ActiveRecord::RecordNotFound, code: :not_found) do
    #     User.find(id)
    #   end
    #
    #: [T] (*Class, ?code: Symbol) { () -> T } -> Result[T]
    def self.capture(*exception_classes, code: :exception, &block)
      raise ArgumentError, "Block is required" unless block

      exception_classes = [StandardError] if exception_classes.empty?
      value = block.call
      success(value)
    rescue *exception_classes => e
      from_exception(e, code: code)
    end

    #: (?value: T?, ?errors: Array[Error]) -> void
    def initialize(value: nil, errors: [])
      @value = value
      @errors = errors.freeze
      freeze
    end

    # Returns true if the result is a success
    #
    #: () -> bool
    def success?
      errors.empty?
    end

    # Returns true if the result is a failure
    #
    #: () -> bool
    def failure?
      !success?
    end

    # Returns the value if success, otherwise raises an error
    #
    #: () -> T
    def value! # steep:ignore MethodBodyTypeMismatch
      raise "Cannot unwrap value from a failure result" if failure?

      @value
    end

    # Returns the value if success, otherwise returns the given default
    #
    #: [U] (U) -> (T | U)
    def value_or(default) # steep:ignore MethodBodyTypeMismatch
      if success?
        @value
      else
        default
      end
    end

    # Applies a block to the value if success, returns failure with same errors if failure
    #
    #: [U] () { (T) -> U } -> Result[U]
    def map(&block)
      return Result.new(value: nil, errors: errors) if failure?

      # @type var v: untyped
      v = @value
      Result.success(block.call(v))
    end

    # Applies a block to the value if success, returns failure with same errors if failure
    # The block should return a Result
    #
    #: [U] () { (T) -> Result[U] } -> Result[U]
    def and_then(&block)
      return Result.new(value: nil, errors: errors) if failure?

      # @type var v: untyped
      v = @value
      block.call(v)
    end

    # Applies a block to the errors if failure, returns self if success
    #
    #: () { (Array[Error]) -> Result[T] } -> Result[T]
    def or_else(&block)
      return self if success?

      block.call(errors)
    end

    #: (Result[untyped]) -> bool
    def ==(other)
      return false unless other.is_a?(Result)

      # @type var v: untyped
      v = @value
      v == other.value && errors == other.errors
    end

    #: () -> String
    def inspect
      if success?
        # @type var v: untyped
        v = @value
        "#<#{self.class.name} success value=#{v.inspect}>"
      else
        "#<#{self.class.name} failure errors=#{errors.inspect}>"
      end
    end
  end
end
