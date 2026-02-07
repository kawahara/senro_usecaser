# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Represents the context of a retry operation
  #
  # This class tracks the state of retry attempts including:
  # - Current attempt number
  # - Maximum attempts allowed
  # - Elapsed time since first attempt
  # - Whether a retry should occur
  #
  # @example Basic usage in on_failure hook
  #   on_failure do |input, result, context|
  #     if context.attempt < 3
  #       context.retry!(wait: 1.0)
  #     end
  #   end
  #
  # @example With modified input
  #   on_failure do |input, result, context|
  #     if result.errors.first&.code == :rate_limited
  #       context.retry!(input: input.with_reduced_batch_size, wait: 5.0)
  #     end
  #   end
  class RetryContext
    # Returns the current attempt number (1-indexed)
    #: () -> Integer
    attr_reader :attempt

    # Returns the maximum number of attempts allowed
    #: () -> Integer?
    attr_reader :max_attempts

    # Returns the time when the first attempt started
    #: () -> Time
    attr_reader :started_at

    # Returns the error from the last failed attempt
    #: () -> Error?
    attr_reader :last_error

    # Returns the input to use for the retry (nil means use original)
    #: () -> untyped
    attr_reader :retry_input

    # Returns the wait time before retrying
    #: () -> (Float | Integer)?
    attr_reader :retry_wait

    # Initializes a new retry context
    #
    #: (?max_attempts: Integer?) -> void
    def initialize(max_attempts: nil)
      @attempt = 1
      @max_attempts = max_attempts
      @started_at = Time.now
      @last_error = nil
      @should_retry = false
      @retry_input = nil
      @retry_wait = nil
    end

    # Returns true if this is a retry (attempt > 1)
    #
    #: () -> bool
    def retried?
      @attempt > 1
    end

    # Returns the elapsed time since the first attempt
    #
    #: () -> Float
    def elapsed_time
      Time.now - @started_at
    end

    # Returns true if max_attempts has been reached
    #
    #: () -> bool
    def exhausted?
      return false unless @max_attempts

      @attempt >= @max_attempts
    end

    # Returns true if a retry has been requested
    #
    #: () -> bool
    def should_retry?
      @should_retry
    end

    # Requests a retry with optional modified input and wait time
    #
    # @example Retry with default settings
    #   context.retry!
    #
    # @example Retry with wait time
    #   context.retry!(wait: 2.0)
    #
    # @example Retry with modified input
    #   context.retry!(input: modified_input, wait: 1.0)
    #
    #: (?input: untyped, ?wait: (Float | Integer)?) -> void
    def retry!(input: nil, wait: nil)
      @should_retry = true
      @retry_input = input
      @retry_wait = wait
    end

    # Increments the attempt counter and resets retry state
    # Called internally between retry attempts
    #
    #: (?last_error: Error?) -> void
    def increment!(last_error: nil)
      @attempt += 1
      @last_error = last_error
      reset_retry_state!
    end

    # Resets the retry request state
    # Called internally after processing retry decision
    #
    #: () -> void
    def reset_retry_state!
      @should_retry = false
      @retry_input = nil
      @retry_wait = nil
    end
  end
end
