# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Configuration for automatic retry behavior
  #
  # This class defines when and how retries should occur based on
  # error codes or exception classes, with configurable backoff strategies.
  #
  # @example Basic retry configuration
  #   RetryConfiguration.new(
  #     matchers: [:network_error, Net::OpenTimeout],
  #     attempts: 3,
  #     wait: 1.0
  #   )
  #
  # @example With exponential backoff
  #   RetryConfiguration.new(
  #     matchers: [:rate_limited],
  #     attempts: 5,
  #     wait: 2.0,
  #     backoff: :exponential,
  #     max_wait: 60
  #   )
  class RetryConfiguration
    # Returns the list of error matchers (Symbols for error codes, Classes for exceptions)
    #: () -> Array[(Symbol | Class)]
    attr_reader :matchers

    # Returns the maximum number of attempts
    #: () -> Integer
    attr_reader :attempts

    # Returns the base wait time in seconds
    #: () -> (Float | Integer)
    attr_reader :wait

    # Returns the backoff strategy (:fixed, :linear, :exponential)
    #: () -> Symbol
    attr_reader :backoff

    # Returns the maximum wait time in seconds
    #: () -> (Float | Integer)
    attr_reader :max_wait

    # Returns the jitter factor (0.0 to 1.0)
    #: () -> (Float | Integer)
    attr_reader :jitter

    # Initializes a new retry configuration
    #
    # @param matchers [Array<Symbol, Class>] Error codes or exception classes to match
    # @param attempts [Integer] Maximum number of attempts (default: 3)
    # @param wait [Numeric] Base wait time in seconds (default: 0)
    # @param backoff [Symbol] Backoff strategy: :fixed, :linear, or :exponential (default: :fixed)
    # @param max_wait [Numeric] Maximum wait time in seconds (default: 3600)
    # @param jitter [Numeric] Jitter factor 0.0-1.0 to randomize wait times (default: 0)
    #
    # rubocop:disable Metrics/ParameterLists
    #: (matchers: Array[(Symbol | Class)], ?attempts: Integer, ?wait: (Float | Integer),
    #:  ?backoff: Symbol, ?max_wait: (Float | Integer)?, ?jitter: (Float | Integer)) -> void
    def initialize(matchers:, attempts: 3, wait: 0, backoff: :fixed, max_wait: nil, jitter: 0)
      # rubocop:enable Metrics/ParameterLists
      @matchers = matchers
      @attempts = attempts
      @wait = wait
      @backoff = backoff
      @max_wait = max_wait || 3600
      @jitter = jitter
    end

    # Checks if this configuration matches the given result
    #
    #: (Result[untyped]) -> bool
    def matches?(result)
      return false unless result.failure?

      result.errors.any? { |error| matches_error?(error) }
    end

    # Calculates the wait time for the given attempt number
    #
    #: (Integer) -> Float
    def calculate_wait(attempt)
      base = calculate_base_wait(attempt)
      base = [base, @max_wait].min
      apply_jitter(base)
    end

    private

    # Checks if an error matches any of the configured matchers
    #
    #: (Error) -> bool
    def matches_error?(error)
      @matchers.any? do |matcher|
        case matcher
        when Symbol
          error.code == matcher
        when Class
          error.cause&.is_a?(matcher)
        end
      end
    end

    # Calculates the base wait time based on backoff strategy
    #
    #: (Integer) -> (Float | Integer)
    def calculate_base_wait(attempt)
      case @backoff
      when :linear
        @wait * attempt
      when :exponential
        @wait * (2**(attempt - 1))
      else # :fixed or any other value
        @wait
      end
    end

    # Applies jitter to the wait time
    #
    #: ((Float | Integer)) -> Float
    def apply_jitter(base)
      return base.to_f if @jitter <= 0

      jitter_amount = (rand * @jitter * base * 2) - (@jitter * base)
      [base + jitter_amount, 0.0].max.to_f
    end
  end
end
