# frozen_string_literal: true

RSpec.describe SenroUsecaser::Result do
  let(:error) { SenroUsecaser::Error.new(code: :invalid, message: "Invalid") }

  describe ".success" do
    it "creates a success result with a value" do
      result = described_class.success("hello")

      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.value).to eq("hello")
      expect(result.errors).to be_empty
    end

    it "creates a success result with nil value" do
      result = described_class.success(nil)

      expect(result).to be_success
      expect(result.value).to be_nil
    end
  end

  describe ".failure" do
    it "creates a failure result with an error" do
      result = described_class.failure(error)

      expect(result).to be_failure
      expect(result).not_to be_success
      expect(result.value).to be_nil
      expect(result.errors).to eq([error])
    end

    it "creates a failure result with multiple errors" do
      error2 = SenroUsecaser::Error.new(code: :not_found, message: "Not found")
      result = described_class.failure(error, error2)

      expect(result.errors).to eq([error, error2])
    end

    it "creates a failure result with an array of errors" do
      error2 = SenroUsecaser::Error.new(code: :not_found, message: "Not found")
      result = described_class.failure([error, error2])

      expect(result.errors).to eq([error, error2])
    end

    it "raises an error when no errors are provided" do
      expect { described_class.failure }.to raise_error(ArgumentError)
    end
  end

  describe ".from_exception" do
    it "creates a failure result from an exception" do
      exception = RuntimeError.new("Something went wrong")
      result = described_class.from_exception(exception)

      expect(result).to be_failure
      expect(result.errors.size).to eq(1)
      expect(result.errors.first.code).to eq(:exception)
      expect(result.errors.first.message).to eq("Something went wrong")
      expect(result.errors.first.cause).to eq(exception)
    end

    it "creates a failure result with custom code" do
      exception = RuntimeError.new("Not found")
      result = described_class.from_exception(exception, code: :not_found)

      expect(result.errors.first.code).to eq(:not_found)
    end
  end

  describe ".capture" do
    it "returns success result when block succeeds" do
      result = described_class.capture { 1 + 1 }

      expect(result).to be_success
      expect(result.value).to eq(2)
    end

    it "returns failure result when block raises StandardError" do
      result = described_class.capture { raise StandardError, "Error" }

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Error")
      expect(result.errors.first.cause).to be_a(StandardError)
    end

    it "returns failure result with custom code" do
      result = described_class.capture(code: :custom_error) { raise StandardError, "Error" }

      expect(result.errors.first.code).to eq(:custom_error)
    end

    it "captures only specified exception classes" do
      result = described_class.capture(ArgumentError) { raise ArgumentError, "Bad argument" }

      expect(result).to be_failure
      expect(result.errors.first.message).to eq("Bad argument")
    end

    it "re-raises exceptions not in the specified classes" do
      expect do
        described_class.capture(ArgumentError) { raise "Runtime error" }
      end.to raise_error(RuntimeError)
    end

    it "captures multiple exception classes" do
      result1 = described_class.capture(ArgumentError, TypeError) { raise ArgumentError, "Error 1" }
      result2 = described_class.capture(ArgumentError, TypeError) { raise TypeError, "Error 2" }

      expect(result1).to be_failure
      expect(result2).to be_failure
    end
  end

  describe "#value!" do
    it "returns the value for success result" do
      result = described_class.success("hello")

      expect(result.value!).to eq("hello")
    end

    it "raises an error for failure result" do
      result = described_class.failure(error)

      expect { result.value! }.to raise_error(RuntimeError)
    end
  end

  describe "#value_or" do
    it "returns the value for success result" do
      result = described_class.success("hello")

      expect(result.value_or("default")).to eq("hello")
    end

    it "returns the default for failure result" do
      result = described_class.failure(error)

      expect(result.value_or("default")).to eq("default")
    end
  end

  describe "#map" do
    it "applies the block to the value for success result" do
      result = described_class.success(5)
      mapped = result.map { |v| v * 2 }

      expect(mapped).to be_success
      expect(mapped.value).to eq(10)
    end

    it "returns self for failure result" do
      result = described_class.failure(error)
      mapped = result.map { |v| v * 2 }

      expect(mapped).to be_failure
      expect(mapped).to eq(result)
    end
  end

  describe "#and_then" do
    it "applies the block to the value for success result" do
      result = described_class.success(5)
      chained = result.and_then { |v| described_class.success(v * 2) }

      expect(chained).to be_success
      expect(chained.value).to eq(10)
    end

    it "propagates failure from the block" do
      result = described_class.success(5)
      chained = result.and_then { |_v| described_class.failure(error) }

      expect(chained).to be_failure
    end

    it "returns self for failure result" do
      result = described_class.failure(error)
      chained = result.and_then { |v| described_class.success(v * 2) }

      expect(chained).to be_failure
      expect(chained).to eq(result)
    end
  end

  describe "#or_else" do
    it "returns self for success result" do
      result = described_class.success(5)
      recovered = result.or_else { |_errors| described_class.success(0) }

      expect(recovered).to be_success
      expect(recovered.value).to eq(5)
    end

    it "applies the block for failure result" do
      result = described_class.failure(error)
      recovered = result.or_else { |_errors| described_class.success(0) }

      expect(recovered).to be_success
      expect(recovered.value).to eq(0)
    end
  end

  describe "#==" do
    it "returns true for results with the same state" do
      result1 = described_class.success("hello")
      result2 = described_class.success("hello")

      expect(result1).to eq(result2)
    end

    it "returns false for results with different state" do
      result1 = described_class.success("hello")
      result2 = described_class.success("world")

      expect(result1).not_to eq(result2)
    end

    it "returns false when compared with non-Result objects" do
      result = described_class.success("hello")

      expect(result).not_to eq("hello")
    end
  end

  describe "#inspect" do
    it "returns success inspection string" do
      result = described_class.success("hello")

      expect(result.inspect).to eq('#<SenroUsecaser::Result success value="hello">')
    end

    it "returns failure inspection string" do
      result = described_class.failure(error)

      expect(result.inspect).to include("failure errors=")
    end
  end

  describe "immutability" do
    it "freezes the result and errors array" do
      result = described_class.success("hello")

      expect(result).to be_frozen
      expect(result.errors).to be_frozen
    end
  end
end
