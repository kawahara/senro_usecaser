# frozen_string_literal: true

RSpec.describe SenroUsecaser::Error do
  describe "#initialize" do
    it "creates an error with code and message" do
      error = described_class.new(code: :invalid, message: "Invalid value")

      expect(error.code).to eq(:invalid)
      expect(error.message).to eq("Invalid value")
      expect(error.field).to be_nil
      expect(error.cause).to be_nil
    end

    it "creates an error with code, message, and field" do
      error = described_class.new(code: :invalid_email, message: "Email is invalid", field: :email)

      expect(error.code).to eq(:invalid_email)
      expect(error.message).to eq("Email is invalid")
      expect(error.field).to eq(:email)
    end

    it "creates an error with cause" do
      exception = StandardError.new("Something went wrong")
      error = described_class.new(code: :unexpected, message: "Unexpected error", cause: exception)

      expect(error.cause).to eq(exception)
    end
  end

  describe ".from_exception" do
    it "creates an error from an exception with default code" do
      exception = RuntimeError.new("Something went wrong")
      error = described_class.from_exception(exception)

      expect(error.code).to eq(:exception)
      expect(error.message).to eq("Something went wrong")
      expect(error.cause).to eq(exception)
    end

    it "creates an error from an exception with custom code" do
      exception = RuntimeError.new("Not found")
      error = described_class.from_exception(exception, code: :not_found)

      expect(error.code).to eq(:not_found)
      expect(error.message).to eq("Not found")
      expect(error.cause).to eq(exception)
    end
  end

  describe "#caused_by_exception?" do
    it "returns true when error has a cause" do
      exception = StandardError.new("Error")
      error = described_class.new(code: :error, message: "Error", cause: exception)

      expect(error.caused_by_exception?).to be true
    end

    it "returns false when error has no cause" do
      error = described_class.new(code: :error, message: "Error")

      expect(error.caused_by_exception?).to be false
    end
  end

  describe "#==" do
    it "returns true for errors with the same attributes" do
      error1 = described_class.new(code: :invalid, message: "Invalid", field: :name)
      error2 = described_class.new(code: :invalid, message: "Invalid", field: :name)

      expect(error1).to eq(error2)
    end

    it "returns false for errors with different attributes" do
      error1 = described_class.new(code: :invalid, message: "Invalid")
      error2 = described_class.new(code: :not_found, message: "Not found")

      expect(error1).not_to eq(error2)
    end

    it "returns false when compared with non-Error objects" do
      error = described_class.new(code: :invalid, message: "Invalid")

      expect(error).not_to eq("invalid")
    end

    it "returns false for errors with different causes" do
      exception1 = StandardError.new("Error 1")
      exception2 = StandardError.new("Error 2")
      error1 = described_class.new(code: :error, message: "Error", cause: exception1)
      error2 = described_class.new(code: :error, message: "Error", cause: exception2)

      expect(error1).not_to eq(error2)
    end
  end

  describe "#to_s" do
    it "returns formatted string without field" do
      error = described_class.new(code: :invalid, message: "Invalid value")

      expect(error.to_s).to eq("Invalid value (invalid)")
    end

    it "returns formatted string with field" do
      error = described_class.new(code: :invalid, message: "Invalid value", field: :email)

      expect(error.to_s).to eq("[email] Invalid value (invalid)")
    end

    it "includes cause class in string" do
      exception = RuntimeError.new("Something went wrong")
      error = described_class.new(code: :error, message: "Error", cause: exception)

      expect(error.to_s).to eq("Error (error) caused by RuntimeError")
    end
  end

  describe "#inspect" do
    it "returns detailed inspection string" do
      error = described_class.new(code: :invalid, message: "Invalid value", field: :email)

      expect(error.inspect).to eq(
        '#<SenroUsecaser::Error code=:invalid message="Invalid value" field=:email>'
      )
    end

    it "includes cause class in inspection string" do
      exception = RuntimeError.new("Error")
      error = described_class.new(code: :error, message: "Error", cause: exception)

      expect(error.inspect).to include("cause=RuntimeError")
    end
  end
end
