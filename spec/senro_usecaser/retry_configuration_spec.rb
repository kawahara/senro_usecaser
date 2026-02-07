# frozen_string_literal: true

RSpec.describe SenroUsecaser::RetryConfiguration do
  describe "#initialize" do
    it "accepts matchers" do
      config = described_class.new(matchers: [:network_error])
      expect(config.matchers).to eq([:network_error])
    end

    it "has default attempts of 3" do
      config = described_class.new(matchers: [:error])
      expect(config.attempts).to eq(3)
    end

    it "has default wait of 0" do
      config = described_class.new(matchers: [:error])
      expect(config.wait).to eq(0)
    end

    it "has default backoff of :fixed" do
      config = described_class.new(matchers: [:error])
      expect(config.backoff).to eq(:fixed)
    end

    it "has default max_wait of 3600" do
      config = described_class.new(matchers: [:error])
      expect(config.max_wait).to eq(3600)
    end

    it "has default jitter of 0" do
      config = described_class.new(matchers: [:error])
      expect(config.jitter).to eq(0)
    end

    it "accepts custom values" do
      config = described_class.new(
        matchers: [:error],
        attempts: 5,
        wait: 2.0,
        backoff: :exponential,
        max_wait: 60,
        jitter: 0.1
      )

      expect(config.attempts).to eq(5)
      expect(config.wait).to eq(2.0)
      expect(config.backoff).to eq(:exponential)
      expect(config.max_wait).to eq(60)
      expect(config.jitter).to eq(0.1)
    end
  end

  describe "#matches?" do
    it "returns false for success results" do
      config = described_class.new(matchers: [:error])
      result = SenroUsecaser::Result.success("value")
      expect(config.matches?(result)).to be false
    end

    it "matches by error code" do
      config = described_class.new(matchers: [:network_error])
      error = SenroUsecaser::Error.new(code: :network_error, message: "failed")
      result = SenroUsecaser::Result.failure(error)

      expect(config.matches?(result)).to be true
    end

    it "does not match non-matching error code" do
      config = described_class.new(matchers: [:network_error])
      error = SenroUsecaser::Error.new(code: :validation_error, message: "failed")
      result = SenroUsecaser::Result.failure(error)

      expect(config.matches?(result)).to be false
    end

    it "matches by exception class" do
      config = described_class.new(matchers: [StandardError])
      exception = StandardError.new("test error")
      result = SenroUsecaser::Result.from_exception(exception)

      expect(config.matches?(result)).to be true
    end

    it "matches any of multiple matchers" do
      config = described_class.new(matchers: %i[network_error timeout])

      error1 = SenroUsecaser::Error.new(code: :network_error, message: "failed")
      result1 = SenroUsecaser::Result.failure(error1)
      expect(config.matches?(result1)).to be true

      error2 = SenroUsecaser::Error.new(code: :timeout, message: "failed")
      result2 = SenroUsecaser::Result.failure(error2)
      expect(config.matches?(result2)).to be true
    end
  end

  describe "#calculate_wait" do
    context "with :fixed backoff" do
      it "returns constant wait time" do
        config = described_class.new(matchers: [:error], wait: 2.0, backoff: :fixed)

        expect(config.calculate_wait(1)).to eq(2.0)
        expect(config.calculate_wait(2)).to eq(2.0)
        expect(config.calculate_wait(3)).to eq(2.0)
      end
    end

    context "with :linear backoff" do
      it "returns linearly increasing wait time" do
        config = described_class.new(matchers: [:error], wait: 2.0, backoff: :linear)

        expect(config.calculate_wait(1)).to eq(2.0)
        expect(config.calculate_wait(2)).to eq(4.0)
        expect(config.calculate_wait(3)).to eq(6.0)
      end
    end

    context "with :exponential backoff" do
      it "returns exponentially increasing wait time" do
        config = described_class.new(matchers: [:error], wait: 1.0, backoff: :exponential)

        expect(config.calculate_wait(1)).to eq(1.0)
        expect(config.calculate_wait(2)).to eq(2.0)
        expect(config.calculate_wait(3)).to eq(4.0)
        expect(config.calculate_wait(4)).to eq(8.0)
      end
    end

    context "with max_wait" do
      it "caps wait time at max_wait" do
        config = described_class.new(matchers: [:error], wait: 10.0, backoff: :exponential, max_wait: 20.0)

        expect(config.calculate_wait(1)).to eq(10.0)
        expect(config.calculate_wait(2)).to eq(20.0)
        expect(config.calculate_wait(3)).to eq(20.0)
      end
    end

    context "with jitter" do
      it "applies randomization to wait time" do
        config = described_class.new(matchers: [:error], wait: 10.0, jitter: 0.1)

        # With 10% jitter on 10s wait, expect range of 9-11s
        results = Array.new(100) { config.calculate_wait(1) }

        expect(results.min).to be >= 9.0
        expect(results.max).to be <= 11.0
        expect(results.uniq.length).to be > 1 # Values should vary
      end

      it "never returns negative wait time" do
        config = described_class.new(matchers: [:error], wait: 0.1, jitter: 1.0)

        results = Array.new(100) { config.calculate_wait(1) }
        expect(results.min).to be >= 0
      end
    end
  end
end
