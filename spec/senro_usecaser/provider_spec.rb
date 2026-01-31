# frozen_string_literal: true

RSpec.describe SenroUsecaser::Provider do
  # Reset global container before each test
  before { SenroUsecaser.reset_container! }

  describe "#register" do
    it "raises NotImplementedError when not overridden" do
      expect do
        described_class.new.register(SenroUsecaser.container)
      end.to raise_error(NotImplementedError)
    end
  end

  describe ".call" do
    let(:simple_provider) do
      Class.new(described_class) do
        def register(container)
          container.register(:logger, "test_logger")
        end
      end
    end

    it "registers dependencies to the container" do
      simple_provider.call(SenroUsecaser.container)

      expect(SenroUsecaser.container.resolve(:logger)).to eq("test_logger")
    end
  end

  describe ".namespace" do
    let(:namespaced_provider) do
      Class.new(described_class) do
        namespace :admin

        def register(container)
          container.register(:user_repository, "admin_repo")
        end
      end
    end

    it "registers dependencies within the namespace" do
      namespaced_provider.call(SenroUsecaser.container)

      expect(SenroUsecaser.container.resolve_in(:admin, :user_repository)).to eq("admin_repo")
    end

    it "does not register in root namespace" do
      namespaced_provider.call(SenroUsecaser.container)

      expect do
        SenroUsecaser.container.resolve(:user_repository)
      end.to raise_error(SenroUsecaser::Container::ResolutionError)
    end
  end

  describe "provider with dependencies" do
    let(:config_provider) do
      Class.new(described_class) do
        def register(container)
          container.register(:config, { db: "postgres", host: "localhost" })
        end
      end
    end

    let(:service_provider) do
      Class.new(described_class) do
        def register(container)
          container.register_singleton(:database) do |c|
            config = c.resolve(:config)
            "Connected to #{config[:db]} at #{config[:host]}"
          end
        end
      end
    end

    it "can depend on registrations from other providers" do
      config_provider.call(SenroUsecaser.container)
      service_provider.call(SenroUsecaser.container)

      expect(SenroUsecaser.container.resolve(:database)).to eq("Connected to postgres at localhost")
    end
  end

  describe "nested namespace provider" do
    let(:nested_provider) do
      Class.new(described_class) do
        namespace "admin::reports"

        def register(container)
          container.register(:generator, "report_generator")
        end
      end
    end

    it "registers in nested namespace" do
      nested_provider.call(SenroUsecaser.container)

      expect(SenroUsecaser.container.resolve_in("admin::reports", :generator)).to eq("report_generator")
    end
  end

  describe "SenroUsecaser.register_provider" do
    let(:single_provider) do
      Class.new(described_class) do
        def register(container)
          container.register(:service, "my_service")
        end
      end
    end

    it "registers provider to the global container" do
      SenroUsecaser.register_provider(single_provider)

      expect(SenroUsecaser.container.resolve(:service)).to eq("my_service")
    end
  end

  describe "SenroUsecaser.register_providers" do
    let(:first_provider) do
      Class.new(described_class) do
        def register(container)
          container.register(:service1, "service_1")
        end
      end
    end

    let(:second_provider) do
      Class.new(described_class) do
        def register(container)
          container.register(:service2, "service_2")
        end
      end
    end

    it "registers multiple providers to the global container" do
      SenroUsecaser.register_providers(first_provider, second_provider)

      expect(SenroUsecaser.container.resolve(:service1)).to eq("service_1")
      expect(SenroUsecaser.container.resolve(:service2)).to eq("service_2")
    end
  end

  describe ".depends_on" do
    it "declares dependencies on other providers" do
      core_provider = Class.new(described_class) do
        def register(container)
          container.register(:core, "core_service")
        end
      end

      dependent_provider = Class.new(described_class) do
        depends_on core_provider

        define_method(:register) do |container|
          container.register(:dependent, "dependent_service")
        end
      end

      expect(dependent_provider.provider_dependencies).to eq([core_provider])
    end

    it "accumulates multiple dependencies" do
      first = Class.new(described_class) { nil }
      second = Class.new(described_class) { nil }

      provider = Class.new(described_class) do
        depends_on first
        depends_on second
      end

      expect(provider.provider_dependencies).to eq([first, second])
    end

    it "does not add duplicate dependencies" do
      dep = Class.new(described_class) { nil }

      provider = Class.new(described_class) do
        depends_on dep
        depends_on dep
      end

      expect(provider.provider_dependencies).to eq([dep])
    end
  end

  describe ".enabled_if" do
    it "returns true by default" do
      provider = Class.new(described_class) { nil }

      expect(provider.enabled?).to be true
    end

    it "evaluates the condition block" do
      enabled_provider = Class.new(described_class) do
        enabled_if { true }
      end

      disabled_provider = Class.new(described_class) do
        enabled_if { false }
      end

      expect(enabled_provider.enabled?).to be true
      expect(disabled_provider.enabled?).to be false
    end

    it "evaluates condition dynamically" do
      flag = false
      provider = Class.new(described_class) do
        enabled_if { flag }
      end

      expect(provider.enabled?).to be false
      flag = true
      expect(provider.enabled?).to be true
    end
  end

  describe "lifecycle hooks" do
    it "calls before_register before register" do
      call_order = []

      provider_class = Class.new(described_class) do
        define_method(:before_register) do |_container|
          call_order << :before_register
        end

        define_method(:register) do |_container|
          call_order << :register
        end
      end

      provider_class.call(SenroUsecaser.container)

      expect(call_order).to eq(%i[before_register register])
    end
  end
end

RSpec.describe SenroUsecaser::Configuration do
  describe "#initialize" do
    it "has empty providers by default" do
      config = described_class.new

      expect(config.providers).to eq([])
    end

    it "has infer_namespace_from_module as false by default" do
      config = described_class.new

      expect(config.infer_namespace_from_module).to be false
    end
  end

  describe "#providers=" do
    it "sets providers" do
      config = described_class.new
      provider = Class.new(SenroUsecaser::Provider) { nil }

      config.providers = [provider]

      expect(config.providers).to eq([provider])
    end
  end
end

RSpec.describe SenroUsecaser::Environment do
  describe "#development?" do
    it "returns true for development environment" do
      env = described_class.new("development")

      expect(env.development?).to be true
      expect(env.test?).to be false
      expect(env.production?).to be false
    end
  end

  describe "#test?" do
    it "returns true for test environment" do
      env = described_class.new("test")

      expect(env.development?).to be false
      expect(env.test?).to be true
      expect(env.production?).to be false
    end
  end

  describe "#production?" do
    it "returns true for production environment" do
      env = described_class.new("production")

      expect(env.development?).to be false
      expect(env.test?).to be false
      expect(env.production?).to be true
    end
  end

  describe "#name" do
    it "returns the environment name" do
      env = described_class.new("staging")

      expect(env.name).to eq("staging")
    end
  end

  describe "#to_s" do
    it "returns the environment name as string" do
      env = described_class.new("production")

      expect(env.to_s).to eq("production")
    end
  end
end

RSpec.describe SenroUsecaser::ProviderBooter do
  before { SenroUsecaser.reset! }

  describe "#boot!" do
    it "boots providers in dependency order" do
      boot_order = []

      core_provider = Class.new(SenroUsecaser::Provider) do
        define_method(:register) do |_container|
          boot_order << :core
        end
      end

      dependent_provider = Class.new(SenroUsecaser::Provider) do
        depends_on core_provider

        define_method(:register) do |_container|
          boot_order << :dependent
        end
      end

      # Register in wrong order to test sorting
      booter = described_class.new([dependent_provider, core_provider], SenroUsecaser.container)
      booter.boot!

      expect(boot_order).to eq(%i[core dependent])
    end

    it "skips disabled providers" do
      boot_order = []

      enabled = Class.new(SenroUsecaser::Provider) do
        enabled_if { true }

        define_method(:register) do |_container|
          boot_order << :enabled
        end
      end

      disabled = Class.new(SenroUsecaser::Provider) do
        enabled_if { false }

        define_method(:register) do |_container|
          boot_order << :disabled
        end
      end

      booter = described_class.new([enabled, disabled], SenroUsecaser.container)
      booter.boot!

      expect(boot_order).to eq([:enabled])
    end

    it "calls after_boot on all booted providers" do
      after_boot_called = []

      provider = Class.new(SenroUsecaser::Provider) do
        define_method(:register) do |container|
          container.register(:value, 42)
        end

        define_method(:after_boot) do |container|
          after_boot_called << container.resolve(:value)
        end
      end

      booter = described_class.new([provider], SenroUsecaser.container)
      booter.boot!

      expect(after_boot_called).to eq([42])
    end

    it "raises CircularDependencyError for circular dependencies" do
      provider_a = Class.new(SenroUsecaser::Provider) do
        define_method(:register) { |_c| nil }
      end

      provider_b = Class.new(SenroUsecaser::Provider) do
        depends_on provider_a

        define_method(:register) { |_c| nil }
      end

      provider_a.depends_on(provider_b)

      booter = described_class.new([provider_a, provider_b], SenroUsecaser.container)

      expect { booter.boot! }.to raise_error(described_class::CircularDependencyError)
    end
  end

  describe "#shutdown!" do
    it "calls shutdown on providers in reverse order" do
      shutdown_order = []

      first_provider = Class.new(SenroUsecaser::Provider) do
        define_method(:register) { |_c| nil }

        define_method(:shutdown) do |_container|
          shutdown_order << :first
        end
      end

      second_provider = Class.new(SenroUsecaser::Provider) do
        depends_on first_provider

        define_method(:register) { |_c| nil }

        define_method(:shutdown) do |_container|
          shutdown_order << :second
        end
      end

      booter = described_class.new([second_provider, first_provider], SenroUsecaser.container)
      booter.boot!
      booter.shutdown!

      expect(shutdown_order).to eq(%i[second first])
    end
  end
end

RSpec.describe "SenroUsecaser configuration and boot" do
  before { SenroUsecaser.reset! }

  describe ".configure" do
    it "yields configuration" do
      SenroUsecaser.configure do |config|
        config.providers = []
        config.infer_namespace_from_module = true
      end

      expect(SenroUsecaser.configuration.infer_namespace_from_module).to be true
    end
  end

  describe ".boot!" do
    it "boots all configured providers" do
      provider = Class.new(SenroUsecaser::Provider) do
        define_method(:register) do |container|
          container.register(:booted, true)
        end
      end

      SenroUsecaser.configure do |config|
        config.providers = [provider]
      end

      SenroUsecaser.boot!

      expect(SenroUsecaser.container.resolve(:booted)).to be true
    end
  end

  describe ".shutdown!" do
    it "shuts down all booted providers" do
      shutdown_called = false

      provider = Class.new(SenroUsecaser::Provider) do
        define_method(:register) { |_c| nil }

        define_method(:shutdown) do |_container|
          shutdown_called = true
        end
      end

      SenroUsecaser.configure do |config|
        config.providers = [provider]
      end

      SenroUsecaser.boot!
      SenroUsecaser.shutdown!

      expect(shutdown_called).to be true
    end
  end

  describe ".env" do
    it "detects environment from SENRO_ENV" do
      allow(ENV).to receive(:[]).with("SENRO_ENV").and_return("staging")
      allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(nil)
      allow(ENV).to receive(:[]).with("RACK_ENV").and_return(nil)

      SenroUsecaser.reset!

      expect(SenroUsecaser.env.name).to eq("staging")
    end

    it "falls back to RAILS_ENV" do
      allow(ENV).to receive(:[]).with("SENRO_ENV").and_return(nil)
      allow(ENV).to receive(:[]).with("RAILS_ENV").and_return("production")
      allow(ENV).to receive(:[]).with("RACK_ENV").and_return(nil)

      SenroUsecaser.reset!

      expect(SenroUsecaser.env.name).to eq("production")
    end

    it "defaults to development" do
      allow(ENV).to receive(:[]).with("SENRO_ENV").and_return(nil)
      allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(nil)
      allow(ENV).to receive(:[]).with("RACK_ENV").and_return(nil)

      SenroUsecaser.reset!

      expect(SenroUsecaser.env.name).to eq("development")
    end
  end

  describe ".env=" do
    it "sets the environment" do
      SenroUsecaser.env = "custom"

      expect(SenroUsecaser.env.name).to eq("custom")
    end
  end

  describe ".reset!" do
    it "resets all state" do
      SenroUsecaser.container.register(:test, "value")
      SenroUsecaser.configuration.providers = [Class.new]
      SenroUsecaser.env = "custom"

      SenroUsecaser.reset!

      expect(SenroUsecaser.container.keys).to be_empty
      expect(SenroUsecaser.configuration.providers).to eq([])
      expect(SenroUsecaser.env.name).to eq("development")
    end
  end
end
