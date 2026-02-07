# frozen_string_literal: true

RSpec.describe SenroUsecaser::DependsOn do
  before do
    stub_const("TestLogger", Class.new)
    stub_const("TestRepository", Class.new)
  end

  after do
    SenroUsecaser.container.clear!
  end

  let(:container) do
    SenroUsecaser::Container.new.tap do |c|
      c.register(:logger, TestLogger.new)
      c.register(:repository, TestRepository.new)
    end
  end

  describe "when extended into a class" do
    let(:service_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        depends_on :logger, TestLogger
        depends_on :repository

        def initialize(container:)
          @_container = container
          @_dependencies = {}
          resolve_dependencies
        end

        def perform
          [logger, repository]
        end
      end
    end

    it "provides depends_on class method" do
      expect(service_class).to respond_to(:depends_on)
    end

    it "provides dependencies class method" do
      expect(service_class.dependencies).to eq(%i[logger repository])
    end

    it "provides dependency_types class method" do
      expect(service_class.dependency_types).to eq({ logger: TestLogger })
    end

    it "includes InstanceMethods automatically" do
      expect(service_class.included_modules).to include(SenroUsecaser::DependsOn::InstanceMethods)
    end

    it "defines accessor methods for dependencies" do
      service = service_class.new(container: container)
      logger, repository = service.perform

      expect(logger).to be_a(TestLogger)
      expect(repository).to be_a(TestRepository)
    end
  end

  describe ".namespace" do
    let(:container_with_namespace) do
      SenroUsecaser::Container.new.tap do |c|
        c.namespace(:admin) do
          register(:logger, TestLogger.new)
        end
      end
    end

    let(:service_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        namespace :admin
        depends_on :logger

        def initialize(container:)
          @_container = container
          @_dependencies = {}
          resolve_dependencies
        end
      end
    end

    it "sets the namespace" do
      expect(service_class.declared_namespace).to eq(:admin)
    end

    it "returns the namespace when called without arguments" do
      expect(service_class.namespace).to eq(:admin)
    end

    it "sets the namespace when called with argument" do
      service_class.namespace :user
      expect(service_class.declared_namespace).to eq(:user)
    end

    it "resolves dependencies from namespace" do
      service = service_class.new(container: container_with_namespace)

      expect(service.logger).to be_a(TestLogger)
    end
  end

  describe "infer_namespace_from_module" do
    let(:container_with_namespace) do
      SenroUsecaser::Container.new.tap do |c|
        c.namespace(:admin) do
          namespace(:orders) do
            register(:repository, TestRepository.new)
          end
        end
      end
    end

    before do
      SenroUsecaser.configuration.infer_namespace_from_module = true

      stub_const("Admin::Orders::ProcessService", Class.new do
        extend SenroUsecaser::DependsOn

        depends_on :repository

        def initialize(container:)
          @_container = container
          @_dependencies = {}
          resolve_dependencies
        end
      end)
    end

    after do
      SenroUsecaser.configuration.infer_namespace_from_module = false
    end

    it "infers namespace from module structure" do
      service = Admin::Orders::ProcessService.new(container: container_with_namespace)

      expect(service.repository).to be_a(TestRepository)
    end
  end

  describe ".copy_depends_on_to" do
    let(:parent_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        namespace :parent_ns
        depends_on :logger, TestLogger
      end
    end

    it "copies dependencies to subclass" do
      child_class = Class.new(parent_class)
      parent_class.copy_depends_on_to(child_class)

      expect(child_class.dependencies).to eq([:logger])
      expect(child_class.dependency_types).to eq({ logger: TestLogger })
    end

    it "copies namespace to subclass" do
      child_class = Class.new(parent_class)
      parent_class.copy_depends_on_to(child_class)

      expect(child_class.declared_namespace).to eq(:parent_ns)
    end

    it "creates independent copies" do
      child_class = Class.new(parent_class)
      parent_class.copy_depends_on_to(child_class)

      child_class.depends_on :repository
      child_class.namespace :child_ns

      expect(parent_class.dependencies).to eq([:logger])
      expect(child_class.dependencies).to eq(%i[logger repository])
      expect(parent_class.declared_namespace).to eq(:parent_ns)
      expect(child_class.declared_namespace).to eq(:child_ns)
    end
  end

  describe "default initialize" do
    let(:service_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        depends_on :logger
      end
    end

    it "provides default initialize when not defined" do
      service = service_class.new(container: container)
      expect(service.logger).to be_a(TestLogger)
    end

    it "uses global container when container not provided" do
      SenroUsecaser.container.register(:logger, TestLogger.new)
      service = service_class.new
      expect(service.logger).to be_a(TestLogger)
    end
  end

  describe "custom initialize with super" do
    let(:service_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        depends_on :logger
        attr_reader :extra

        def initialize(extra:, container: nil)
          super(container: container)
          @extra = extra
        end
      end
    end

    it "uses super to call default initialize" do
      service = service_class.new(container: container, extra: "value")
      expect(service.extra).to eq("value")
      expect(service.logger).to be_a(TestLogger)
    end

    it "uses global container when container not provided" do
      SenroUsecaser.container.register(:logger, TestLogger.new)
      service = service_class.new(extra: "value")
      expect(service.extra).to eq("value")
      expect(service.logger).to be_a(TestLogger)
    end
  end

  describe "custom initialize without super (full override)" do
    let(:service_class) do
      Class.new do
        extend SenroUsecaser::DependsOn

        depends_on :logger
        attr_reader :extra

        def initialize(container:, extra:)
          @_container = container
          @_dependencies = {}
          @extra = extra
          resolve_dependencies
        end
      end
    end

    it "uses fully custom initialize" do
      service = service_class.new(container: container, extra: "value")
      expect(service.extra).to eq("value")
      expect(service.logger).to be_a(TestLogger)
    end
  end

  describe "integration with SenroUsecaser::Base" do
    before do
      stub_const("TestInput", Struct.new(:data))
    end

    let(:use_case_class) do
      Class.new(SenroUsecaser::Base) do
        input TestInput
        depends_on :logger, TestLogger

        def call(_input)
          success(logger)
        end
      end
    end

    it "works with SenroUsecaser::Base" do
      result = use_case_class.call(TestInput.new("test"), container: container)

      expect(result.success?).to be true
      expect(result.value).to be_a(TestLogger)
    end
  end

  describe "integration with SenroUsecaser::Hook" do
    let(:hook_class) do
      Class.new(SenroUsecaser::Hook) do
        depends_on :logger, TestLogger
      end
    end

    it "works with SenroUsecaser::Hook" do
      hook = hook_class.new(container: container)

      expect(hook.logger).to be_a(TestLogger)
    end
  end
end
