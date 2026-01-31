# frozen_string_literal: true

RSpec.describe SenroUsecaser::Hook do
  let(:container) { SenroUsecaser::Container.new }

  describe ".depends_on" do
    it "registers dependencies" do
      hook_class = Class.new(described_class) do
        depends_on :logger
        depends_on :metrics, Object
      end

      expect(hook_class.dependencies).to eq(%i[logger metrics])
      expect(hook_class.dependency_types[:metrics]).to eq(Object)
    end
  end

  describe ".namespace" do
    it "sets the namespace" do
      hook_class = Class.new(described_class) do
        namespace :admin
      end

      expect(hook_class.hook_namespace).to eq(:admin)
    end
  end

  describe "#initialize" do
    it "resolves dependencies from container" do
      logger = Object.new
      container.register(:logger, logger)

      hook_class = Class.new(described_class) do
        depends_on :logger

        def resolved_logger
          logger
        end
      end

      hook = hook_class.new(container: container)
      expect(hook.resolved_logger).to eq(logger)
    end

    it "resolves dependencies from namespace" do
      admin_logger = Object.new
      container.namespace(:admin) do
        register(:logger, admin_logger)
      end

      hook_class = Class.new(described_class) do
        namespace :admin
        depends_on :logger

        def resolved_logger
          logger
        end
      end

      hook = hook_class.new(container: container)
      expect(hook.resolved_logger).to eq(admin_logger)
    end

    it "inherits namespace from use_case_namespace" do
      admin_logger = Object.new
      container.namespace(:admin) do
        register(:logger, admin_logger)
      end

      hook_class = Class.new(described_class) do
        depends_on :logger

        def resolved_logger
          logger
        end
      end

      hook = hook_class.new(container: container, use_case_namespace: :admin)
      expect(hook.resolved_logger).to eq(admin_logger)
    end

    it "prioritizes hook namespace over use_case_namespace" do
      root_logger = Object.new
      admin_logger = Object.new
      container.register(:logger, root_logger)
      container.namespace(:admin) do
        register(:logger, admin_logger)
      end

      hook_class = Class.new(described_class) do
        namespace :root
        depends_on :logger

        def resolved_logger
          logger
        end
      end

      # Hook declares :root namespace, should not use admin from use_case_namespace
      hook = hook_class.new(container: container, use_case_namespace: :admin)
      expect(hook.resolved_logger).to eq(root_logger)
    end
  end

  describe "infer_namespace_from_module" do
    before do
      SenroUsecaser.configuration.infer_namespace_from_module = true
    end

    after do
      SenroUsecaser.configuration.infer_namespace_from_module = false
    end

    it "infers namespace from module structure" do
      admin_logger = Object.new
      container.namespace(:admin) do
        register(:logger, admin_logger)
      end

      # Create hook in Admin module
      admin_module = Module.new
      hook_class = Class.new(described_class) do
        depends_on :logger

        def resolved_logger
          logger
        end
      end
      admin_module.const_set(:AuditHook, hook_class)
      stub_const("Admin", admin_module)

      hook = Admin::AuditHook.new(container: container)
      expect(hook.resolved_logger).to eq(admin_logger)
    end
  end

  describe "lifecycle methods" do
    it "calls before hook" do
      called_with = nil

      hook_class = Class.new(described_class) do
        define_method(:before) do |input|
          called_with = input
        end
      end

      hook = hook_class.new(container: container)
      hook.before("test_input")

      expect(called_with).to eq("test_input")
    end

    it "calls after hook" do
      called_with = nil

      hook_class = Class.new(described_class) do
        define_method(:after) do |input, result|
          called_with = [input, result]
        end
      end

      result = SenroUsecaser::Result.success("value")
      hook = hook_class.new(container: container)
      hook.after("test_input", result)

      expect(called_with).to eq(["test_input", result])
    end

    it "calls around hook" do
      call_order = []

      hook_class = Class.new(described_class) do
        define_method(:around) do |_input, &block|
          call_order << :before
          result = block.call
          call_order << :after
          result
        end
      end

      hook = hook_class.new(container: container)
      result = hook.around("input") do
        call_order << :inner
        SenroUsecaser::Result.success("value")
      end

      expect(call_order).to eq(%i[before inner after])
      expect(result).to be_success
    end
  end

  describe "inheritance" do
    it "inherits dependencies from parent" do
      parent = Class.new(described_class) do
        depends_on :logger
      end

      child = Class.new(parent) do
        depends_on :metrics
      end

      expect(child.dependencies).to eq(%i[logger metrics])
      expect(parent.dependencies).to eq(%i[logger])
    end

    it "inherits namespace from parent" do
      parent = Class.new(described_class) do
        namespace :admin
      end

      child = Class.new(parent)

      expect(child.hook_namespace).to eq(:admin)
    end
  end
end

RSpec.describe "UseCase with Hook class" do
  let(:container) { SenroUsecaser::Container.new }
  let(:simple_input) { Struct.new(:value, keyword_init: true) }

  before do
    SenroUsecaser.instance_variable_set(:@container, container)
  end

  after do
    SenroUsecaser.reset!
  end

  it "runs Hook class before/after/around hooks" do
    call_order = []
    logger = Object.new

    container.register(:logger, logger)

    hook_class = Class.new(SenroUsecaser::Hook) do
      depends_on :logger

      define_method(:before) do |_input|
        call_order << :hook_before
      end

      define_method(:after) do |_input, _result|
        call_order << :hook_after
      end

      define_method(:around) do |_input, &block|
        call_order << :hook_around_start
        result = block.call
        call_order << :hook_around_end
        result
      end
    end

    input_class = simple_input
    use_case = Class.new(SenroUsecaser::Base) do
      input input_class
      extend_with hook_class

      define_method(:call) do |input|
        call_order << :call
        success(input.value * 2)
      end
    end

    result = use_case.call(simple_input.new(value: 5))

    expect(result).to be_success
    expect(result.value).to eq(10)
    expect(call_order).to eq(%i[hook_before hook_around_start call hook_around_end hook_after])
  end

  it "resolves Hook dependencies with UseCase namespace" do
    resolved_logger = nil
    admin_logger = Object.new

    container.namespace(:admin) do
      register(:logger, admin_logger)
    end

    hook_class = Class.new(SenroUsecaser::Hook) do
      depends_on :logger

      define_method(:before) do |_input|
        resolved_logger = logger
      end
    end

    input_class = simple_input
    use_case = Class.new(SenroUsecaser::Base) do
      namespace :admin
      input input_class
      extend_with hook_class

      define_method(:call) do |input|
        success(input.value)
      end
    end

    use_case.call(simple_input.new(value: 1))

    expect(resolved_logger).to eq(admin_logger)
  end

  it "mixes Hook classes and modules" do
    call_order = []
    logger = Object.new
    container.register(:logger, logger)

    hook_class = Class.new(SenroUsecaser::Hook) do
      depends_on :logger

      define_method(:before) do |_input|
        call_order << :class_before
      end
    end

    hook_module = Module.new do
      define_singleton_method(:before) do |_input|
        call_order << :module_before
      end
    end

    input_class = simple_input
    use_case = Class.new(SenroUsecaser::Base) do
      input input_class
      extend_with hook_class
      extend_with hook_module

      define_method(:call) do |input|
        call_order << :call
        success(input.value)
      end
    end

    use_case.call(simple_input.new(value: 1))

    expect(call_order).to eq(%i[class_before module_before call])
  end
end
