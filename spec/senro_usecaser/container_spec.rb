# frozen_string_literal: true

RSpec.describe SenroUsecaser::Container do
  subject(:container) { described_class.new }

  describe "#register" do
    it "registers a dependency with a value" do
      container.register(:logger, "my_logger")

      expect(container.resolve(:logger)).to eq("my_logger")
    end

    it "registers a dependency with a block" do
      call_count = 0
      container.register(:counter) { call_count += 1 }

      expect(container.resolve(:counter)).to eq(1)
      expect(container.resolve(:counter)).to eq(2)
    end

    it "raises error when both value and block are provided" do
      expect do
        container.register(:test, "value") { "block" }
      end.to raise_error(ArgumentError, /Provide either a value or a block, not both/)
    end

    it "raises error when neither value nor block is provided" do
      expect do
        container.register(:test)
      end.to raise_error(ArgumentError, /Provide either a value or a block/)
    end

    it "raises error when key is already registered" do
      container.register(:logger, "logger1")

      expect do
        container.register(:logger, "logger2")
      end.to raise_error(SenroUsecaser::Container::DuplicateRegistrationError)
    end
  end

  describe "#register_lazy" do
    it "calls the block on every resolve" do
      call_count = 0
      container.register_lazy(:counter) { call_count += 1 }

      expect(container.resolve(:counter)).to eq(1)
      expect(container.resolve(:counter)).to eq(2)
      expect(container.resolve(:counter)).to eq(3)
    end

    it "passes container to the block for dependency resolution" do
      container.register(:config, { db: "postgres" })
      container.register_lazy(:database) do |c|
        "Connected to #{c.resolve(:config)[:db]}"
      end

      expect(container.resolve(:database)).to eq("Connected to postgres")
    end

    it "raises error when block is not provided" do
      expect do
        container.register_lazy(:test)
      end.to raise_error(ArgumentError, /Block is required/)
    end

    it "raises error when key is already registered" do
      container.register_lazy(:counter) { 1 }

      expect do
        container.register_lazy(:counter) { 2 }
      end.to raise_error(SenroUsecaser::Container::DuplicateRegistrationError)
    end
  end

  describe "#register_singleton" do
    it "calls the block only once and caches the result" do
      call_count = 0
      container.register_singleton(:instance) do
        call_count += 1
        "instance_#{call_count}"
      end

      expect(container.resolve(:instance)).to eq("instance_1")
      expect(container.resolve(:instance)).to eq("instance_1")
      expect(container.resolve(:instance)).to eq("instance_1")
      expect(call_count).to eq(1)
    end

    it "passes container to the block for dependency resolution" do
      container.register(:logger, "my_logger")
      container.register_singleton(:service) do |c|
        "Service with #{c.resolve(:logger)}"
      end

      expect(container.resolve(:service)).to eq("Service with my_logger")
    end

    it "raises error when block is not provided" do
      expect do
        container.register_singleton(:test)
      end.to raise_error(ArgumentError, /Block is required/)
    end

    it "raises error when key is already registered" do
      container.register_singleton(:instance) { "first" }

      expect do
        container.register_singleton(:instance) { "second" }
      end.to raise_error(SenroUsecaser::Container::DuplicateRegistrationError)
    end
  end

  describe "#resolve" do
    it "resolves a registered dependency" do
      container.register(:config, { env: "test" })

      expect(container.resolve(:config)).to eq({ env: "test" })
    end

    it "raises error when dependency is not found" do
      expect do
        container.resolve(:unknown)
      end.to raise_error(SenroUsecaser::Container::ResolutionError)
    end
  end

  describe "#namespace" do
    it "registers dependencies in a namespace" do
      container.namespace(:admin) do
        register(:user_repository, "admin_repo")
      end

      expect(container.resolve_in(:admin, :user_repository)).to eq("admin_repo")
    end

    it "supports nested namespaces" do
      container.namespace(:admin) do
        namespace(:reports) do
          register(:generator, "report_generator")
        end
      end

      expect(container.resolve_in("admin::reports", :generator)).to eq("report_generator")
    end

    it "isolates namespace scopes" do
      container.namespace(:admin) do
        register(:repo, "admin_repo")
      end

      container.namespace(:public) do
        register(:repo, "public_repo")
      end

      expect(container.resolve_in(:admin, :repo)).to eq("admin_repo")
      expect(container.resolve_in(:public, :repo)).to eq("public_repo")
    end
  end

  describe "#resolve_in" do
    before do
      container.register(:logger, "root_logger")
      container.register(:config, "root_config")

      container.namespace(:admin) do
        register(:user_repository, "admin_repo")
        register(:logger, "admin_logger")

        namespace(:reports) do
          register(:generator, "report_generator")
        end
      end
    end

    it "resolves from the specified namespace" do
      expect(container.resolve_in(:admin, :user_repository)).to eq("admin_repo")
    end

    it "resolves from parent namespace when not found in current" do
      expect(container.resolve_in("admin::reports", :user_repository)).to eq("admin_repo")
    end

    it "resolves from root namespace when not found in ancestors" do
      expect(container.resolve_in("admin::reports", :config)).to eq("root_config")
    end

    it "prefers closer namespace over ancestors" do
      expect(container.resolve_in(:admin, :logger)).to eq("admin_logger")
      expect(container.resolve_in("admin::reports", :logger)).to eq("admin_logger")
    end

    it "accepts namespace as array of symbols" do
      expect(container.resolve_in(%i[admin reports], :generator)).to eq("report_generator")
    end

    it "raises error when not found in any ancestor" do
      expect do
        container.resolve_in(:admin, :unknown)
      end.to raise_error(SenroUsecaser::Container::ResolutionError)
    end

    context "with :root namespace" do
      it "resolves from root namespace only" do
        expect(container.resolve_in(:root, :logger)).to eq("root_logger")
      end

      it "does not resolve from child namespaces" do
        expect do
          container.resolve_in(:root, :user_repository)
        end.to raise_error(SenroUsecaser::Container::ResolutionError)
      end
    end
  end

  describe "#registered?" do
    it "returns true when dependency is registered" do
      container.register(:logger, "logger")

      expect(container.registered?(:logger)).to be true
    end

    it "returns false when dependency is not registered" do
      expect(container.registered?(:unknown)).to be false
    end
  end

  describe "#registered_in?" do
    before do
      container.register(:root_dep, "root")

      container.namespace(:admin) do
        register(:admin_dep, "admin")
      end
    end

    it "returns true when found in specified namespace" do
      expect(container.registered_in?(:admin, :admin_dep)).to be true
    end

    it "returns true when found in ancestor namespace" do
      expect(container.registered_in?(:admin, :root_dep)).to be true
    end

    it "returns false when not found" do
      expect(container.registered_in?(:admin, :unknown)).to be false
    end

    it "returns false when only in child namespace" do
      expect(container.registered_in?(:root, :admin_dep)).to be false
    end
  end

  describe "#keys" do
    it "returns all registered keys" do
      container.register(:logger, "logger")
      container.namespace(:admin) do
        register(:repo, "repo")
      end

      expect(container.keys).to contain_exactly("logger", "admin::repo")
    end
  end

  describe "#clear!" do
    it "removes all registrations" do
      container.register(:logger, "logger")
      container.clear!

      expect(container.keys).to be_empty
    end
  end

  describe "#scope" do
    before do
      container.register(:logger, "root_logger")
      container.register(:config, "root_config")

      container.namespace(:admin) do
        register(:repository, "admin_repo")
      end
    end

    it "creates a child container with parent reference" do
      scoped = container.scope { nil }

      expect(scoped.parent).to eq(container)
    end

    it "allows registering new dependencies in scoped container" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.resolve(:current_user)).to eq("user_123")
    end

    it "resolves dependencies from parent when not in scope" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.resolve(:logger)).to eq("root_logger")
    end

    it "overrides parent dependencies in scope" do
      scoped = container.scope do
        register(:logger, "scoped_logger")
      end

      expect(scoped.resolve(:logger)).to eq("scoped_logger")
      expect(container.resolve(:logger)).to eq("root_logger")
    end

    it "does not affect parent container" do
      container.scope do
        register(:scoped_only, "scoped_value")
      end

      expect { container.resolve(:scoped_only) }.to raise_error(
        SenroUsecaser::Container::ResolutionError
      )
    end

    it "resolves namespaced dependencies from parent" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.resolve_in(:admin, :repository)).to eq("admin_repo")
    end

    it "supports nested scopes" do
      scoped1 = container.scope do
        register(:level, 1)
      end

      scoped2 = scoped1.scope do
        register(:level, 2)
      end

      expect(scoped2.resolve(:level)).to eq(2)
      expect(scoped2.resolve(:logger)).to eq("root_logger")
    end

    it "includes parent keys in keys method" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.keys).to include("logger", "config", "current_user")
    end

    it "returns only own keys with own_keys method" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.own_keys).to eq(["current_user"])
    end

    it "checks registration in parent with registered?" do
      scoped = container.scope do
        register(:current_user, "user_123")
      end

      expect(scoped.registered?(:logger)).to be true
      expect(scoped.registered?(:current_user)).to be true
      expect(scoped.registered?(:unknown)).to be false
    end

    context "with request-scoped dependencies" do
      it "resolves parent lazy registration with scoped dependencies" do
        # Boot time: register repository that depends on current_user
        container.register_lazy(:user_repository) do |c|
          user = c.resolve(:current_user)
          "Repository for #{user}"
        end

        # Request time: create scoped container with current_user
        scoped = container.scope do
          register(:current_user, "user_456")
        end

        expect(scoped.resolve(:user_repository)).to eq("Repository for user_456")
      end

      it "resolves with different users in different scopes" do
        container.register_lazy(:user_repository) do |c|
          "Repository for #{c.resolve(:current_user)}"
        end

        scope1 = container.scope { register(:current_user, "alice") }
        scope2 = container.scope { register(:current_user, "bob") }

        expect(scope1.resolve(:user_repository)).to eq("Repository for alice")
        expect(scope2.resolve(:user_repository)).to eq("Repository for bob")
      end
    end
  end
end
