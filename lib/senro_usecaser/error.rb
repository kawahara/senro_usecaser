# frozen_string_literal: true

# rbs_inline: enabled

module SenroUsecaser
  # Represents an error in a Result
  #
  # @example Basic error
  #   error = SenroUsecaser::Error.new(
  #     code: :invalid_email,
  #     message: "Email format is invalid",
  #     field: :email
  #   )
  #
  # @example Error from exception
  #   begin
  #     # some code that raises
  #   rescue => e
  #     error = SenroUsecaser::Error.new(
  #       code: :unexpected_error,
  #       message: e.message,
  #       cause: e
  #     )
  #   end
  class Error
    #: Symbol
    attr_reader :code

    #: String
    attr_reader :message

    #: Symbol?
    attr_reader :field

    #: Exception?
    attr_reader :cause

    #: (code: Symbol, message: String, ?field: Symbol?, ?cause: Exception?) -> void
    def initialize(code:, message:, field: nil, cause: nil)
      @code = code
      @message = message
      @field = field
      @cause = cause
    end

    # Creates an Error from an exception
    #
    #: (Exception, ?code: Symbol) -> Error
    def self.from_exception(exception, code: :exception)
      new(
        code: code,
        message: exception.message,
        cause: exception
      )
    end

    # Returns true if this error was caused by an exception
    #
    #: () -> bool
    def caused_by_exception?
      !cause.nil?
    end

    #: (Error) -> bool
    def ==(other)
      return false unless other.is_a?(Error)

      code == other.code && message == other.message && field == other.field && cause == other.cause
    end

    #: () -> String
    def to_s
      base = field ? "[#{field}] #{message} (#{code})" : "#{message} (#{code})"
      cause ? "#{base} caused by #{cause.class}" : base
    end

    #: () -> String
    def inspect
      parts = [
        "code=#{code.inspect}",
        "message=#{message.inspect}",
        "field=#{field.inspect}"
      ]
      parts << "cause=#{cause.class}" if cause
      "#<#{self.class.name} #{parts.join(" ")}>"
    end
  end
end
