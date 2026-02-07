# frozen_string_literal: true

RSpec.describe SenroUsecaser::RetryContext do
  describe "#initialize" do
    it "starts with attempt 1" do
      context = described_class.new
      expect(context.attempt).to eq(1)
    end

    it "accepts max_attempts" do
      context = described_class.new(max_attempts: 5)
      expect(context.max_attempts).to eq(5)
    end

    it "records started_at" do
      before = Time.now
      context = described_class.new
      after = Time.now

      expect(context.started_at).to be_between(before, after)
    end

    it "starts with no retry request" do
      context = described_class.new
      expect(context.should_retry?).to be false
      expect(context.retry_input).to be_nil
      expect(context.retry_wait).to be_nil
    end
  end

  describe "#retried?" do
    it "returns false on first attempt" do
      context = described_class.new
      expect(context.retried?).to be false
    end

    it "returns true after increment" do
      context = described_class.new
      context.increment!
      expect(context.retried?).to be true
    end
  end

  describe "#elapsed_time" do
    it "returns time since start" do
      context = described_class.new
      sleep 0.01
      expect(context.elapsed_time).to be > 0
    end
  end

  describe "#exhausted?" do
    it "returns false when no max_attempts" do
      context = described_class.new
      expect(context.exhausted?).to be false
    end

    it "returns false when attempts remaining" do
      context = described_class.new(max_attempts: 3)
      expect(context.exhausted?).to be false
    end

    it "returns true when max_attempts reached" do
      context = described_class.new(max_attempts: 2)
      context.increment!
      expect(context.exhausted?).to be true
    end
  end

  describe "#retry!" do
    it "marks for retry" do
      context = described_class.new
      context.retry!
      expect(context.should_retry?).to be true
    end

    it "accepts input" do
      context = described_class.new
      context.retry!(input: "new_input")
      expect(context.retry_input).to eq("new_input")
    end

    it "accepts wait time" do
      context = described_class.new
      context.retry!(wait: 2.5)
      expect(context.retry_wait).to eq(2.5)
    end

    it "accepts both input and wait" do
      context = described_class.new
      context.retry!(input: "new", wait: 1.0)
      expect(context.retry_input).to eq("new")
      expect(context.retry_wait).to eq(1.0)
    end
  end

  describe "#increment!" do
    it "increments attempt count" do
      context = described_class.new
      context.increment!
      expect(context.attempt).to eq(2)
    end

    it "stores last_error" do
      context = described_class.new
      error = SenroUsecaser::Error.new(code: :test, message: "test error")
      context.increment!(last_error: error)
      expect(context.last_error).to eq(error)
    end

    it "resets retry state" do
      context = described_class.new
      context.retry!(input: "input", wait: 1.0)
      context.increment!

      expect(context.should_retry?).to be false
      expect(context.retry_input).to be_nil
      expect(context.retry_wait).to be_nil
    end
  end

  describe "#reset_retry_state!" do
    it "clears retry state" do
      context = described_class.new
      context.retry!(input: "input", wait: 1.0)
      context.reset_retry_state!

      expect(context.should_retry?).to be false
      expect(context.retry_input).to be_nil
      expect(context.retry_wait).to be_nil
    end
  end
end
