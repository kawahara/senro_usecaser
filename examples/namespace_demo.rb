#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable all

# rbs_inline: enabled

require_relative "../lib/senro_usecaser"

# =============================================================================
# サンプル: Namespace を活用したマルチドメインシステム
# =============================================================================
#
# このサンプルでは以下の Namespace 機能を検証します:
#   1. 基本的な namespace でのサービス登録
#   2. ネストした namespace (admin::reports)
#   3. namespace のフォールバック（子から親へ）
#   4. UseCase での namespace 指定（自動解決）
#   5. resolve_in による明示的な namespace 解決
#   6. Scoped Container と namespace の組み合わせ
#   7. infer_namespace_from_module によるモジュール名からの namespace 自動推論
#
# =============================================================================

# サンプル全体を NamespaceDemo モジュールで囲み、
# 他のサンプル（order_system.rb）とのクラス名衝突を回避
module NamespaceDemo
  # ===========================================================================
  # モデル
  # ===========================================================================

  class User
    #: Integer
    attr_reader :id

    #: String
    attr_reader :name

    #: String
    attr_reader :role

    #: (id: Integer, name: String, role: String) -> void
    def initialize(id:, name:, role:)
      @id = id
      @name = name
      @role = role
    end
  end

  class AuditLog
    #: String
    attr_reader :action

    #: User
    attr_reader :performed_by

    #: Time
    attr_reader :timestamp

    #: (action: String, performed_by: User, timestamp: Time) -> void
    def initialize(action:, performed_by:, timestamp:)
      @action = action
      @performed_by = performed_by
      @timestamp = timestamp
    end
  end

  # ===========================================================================
  # 共有インターフェース
  # ===========================================================================

  # 全 namespace で共有されるロガー
  class Logger
    #: String
    attr_reader :prefix

    #: (?String) -> void
    def initialize(prefix = "[LOG]")
      @prefix = prefix
    end

    #: (String) -> void
    def info(message)
      puts "    #{@prefix} #{message}"
    end
  end

  # ===========================================================================
  # Public 用のサービス実装
  # ===========================================================================

  module Public
    class UserRepository
      #: () -> void
      def initialize
        @users = {
          1 => User.new(id: 1, name: "一般ユーザーA", role: "user"),
          2 => User.new(id: 2, name: "一般ユーザーB", role: "user")
        } #: Hash[Integer, User]
      end

      #: (Integer) -> User?
      def find(id)
        @users[id]
      end

      #: () -> Array[User]
      def all
        @users.values
      end
    end

    class NotificationService
      #: (User, String) -> bool
      def notify(user, message)
        puts "    [Public Notification] #{user.name}: #{message}"
        true
      end
    end
  end

  # ===========================================================================
  # Admin 用のサービス実装
  # ===========================================================================

  module Admin
    class UserRepository
      #: () -> void
      def initialize
        @users = {
          100 => User.new(id: 100, name: "管理者A", role: "admin"),
          101 => User.new(id: 101, name: "管理者B", role: "super_admin")
        } #: Hash[Integer, User]
      end

      #: (Integer) -> User?
      def find(id)
        @users[id]
      end

      #: () -> Array[User]
      def all
        @users.values
      end

      # Admin 専用: ユーザーの全情報を取得
      #: (Integer) -> Hash[Symbol, untyped]?
      def find_with_permissions(id)
        user = @users[id]
        return nil unless user

        {
          user: user,
          permissions: user.role == "super_admin" ? [:all] : %i[read write],
          last_login: Time.now - 3600
        }
      end
    end

    class NotificationService
      #: (User, String) -> bool
      def notify(user, message)
        puts "    [Admin Notification] [PRIORITY] #{user.name}: #{message}"
        true
      end
    end

    class AuditLogger
      #: () -> void
      def initialize
        @logs = [] #: Array[AuditLog]
      end

      #: (action: String, performed_by: User) -> AuditLog
      def log(action:, performed_by:)
        entry = AuditLog.new(action: action, performed_by: performed_by, timestamp: Time.now)
        @logs << entry
        puts "    [Audit] #{performed_by.name}: #{action}"
        entry
      end

      #: () -> Array[AuditLog]
      def recent_logs
        @logs.last(10)
      end
    end
  end

  # ===========================================================================
  # Admin::Reports 用のサービス実装（ネストした namespace）
  # ===========================================================================

  module Admin
    module Reports
      class ReportGenerator
        #: (String, Hash[Symbol, untyped]) -> String
        def generate(type, data)
          puts "    [ReportGenerator] レポート生成: #{type}"
          "Report: #{type} - #{data.keys.join(", ")}"
        end
      end

      class ReportExporter
        #: (String, Symbol) -> String
        def export(report, format)
          puts "    [ReportExporter] エクスポート: #{format}"
          "#{report} (#{format}形式)"
        end
      end
    end
  end

  # ===========================================================================
  # Provider 定義
  # ===========================================================================

  # 共有サービス（ルート namespace）
  class CoreProvider < SenroUsecaser::Provider
    #: (SenroUsecaser::Container) -> void
    def register(container)
      container.register(:logger, Logger.new)
    end
  end

  # ===========================================================================
  # パターン1: Provider の namespace DSL を使用
  # ===========================================================================
  # メリット: シンプル、Provider レベルで namespace を宣言
  # デメリット: Steep の型チェックでエラーが出る場合がある

  # Public namespace のサービス（namespace DSL 使用）
  class PublicProvider < SenroUsecaser::Provider
    namespace :public
    depends_on CoreProvider

    #: (SenroUsecaser::Container) -> void
    def register(container)
      container.register_singleton(:user_repository) { |_c| Public::UserRepository.new }
      container.register_singleton(:notification_service) { |_c| Public::NotificationService.new }
    end
  end

  # ===========================================================================
  # パターン2: Container の namespace メソッドを直接使用
  # ===========================================================================
  # メリット: 型チェックが通りやすい、柔軟なネスト構造が可能
  # デメリット: やや冗長

  # Admin namespace のサービス（Container.namespace 直接使用）
  class AdminProvider < SenroUsecaser::Provider
    depends_on CoreProvider

    #: (SenroUsecaser::Container) -> void
    def register(container)
      container.namespace(:admin) do
        # @type self: SenroUsecaser::Container
        register_singleton(:user_repository) { |_c| Admin::UserRepository.new }
        register_singleton(:notification_service) { |_c| Admin::NotificationService.new }
        register_singleton(:audit_logger) { |_c| Admin::AuditLogger.new }
      end
    end

    #: (SenroUsecaser::Container) -> void
    def after_boot(container)
      logger = container.resolve(:logger) #: Logger
      logger.info("AdminProvider: 管理者サービス初期化完了")
    end
  end

  # Admin::Reports namespace のサービス（Container.namespace ネスト使用）
  class AdminReportsProvider < SenroUsecaser::Provider
    depends_on AdminProvider

    #: (SenroUsecaser::Container) -> void
    def register(container)
      container.namespace(:admin) do
        # @type self: SenroUsecaser::Container
        namespace(:reports) do
          # @type self: SenroUsecaser::Container
          register_singleton(:report_generator) { |_c| Admin::Reports::ReportGenerator.new }
          register_singleton(:report_exporter) { |_c| Admin::Reports::ReportExporter.new }
        end
      end
    end
  end

  # ===========================================================================
  # UseCase 定義
  # ===========================================================================

  # Public namespace の UseCase
  class ListPublicUsersUseCase < SenroUsecaser::Base
    namespace :public

    class Input
      #: (**untyped) -> void
      def initialize(**_rest)
      end
    end

    class Output
      #: (users: Array[User]) -> void
      def initialize(users:)
        @users = users #: Array[User]
      end

      #: () -> Array[User]
      attr_reader :users
    end

    depends_on :user_repository, Public::UserRepository
    depends_on :logger, Logger # ルートからフォールバック解決される

    # @rbs!
    #   def user_repository: () -> Public::UserRepository
    #   def logger: () -> Logger

    input Input
    output Output

    #: (Input) -> SenroUsecaser::Result[Output]
    def call(_input)
      logger.info("Public ユーザー一覧を取得")
      users = user_repository.all
      success(Output.new(users: users))
    end
  end

  # Admin namespace の UseCase
  class ListAdminUsersUseCase < SenroUsecaser::Base
    namespace :admin

    class Input
      #: (**untyped) -> void
      def initialize(**_rest)
      end
    end

    class Output
      #: (users: Array[User]) -> void
      def initialize(users:)
        @users = users #: Array[User]
      end

      #: () -> Array[User]
      attr_reader :users
    end

    depends_on :user_repository, Admin::UserRepository
    depends_on :audit_logger, Admin::AuditLogger
    depends_on :logger, Logger # ルートからフォールバック解決される

    # @rbs!
    #   def user_repository: () -> Admin::UserRepository
    #   def audit_logger: () -> Admin::AuditLogger
    #   def logger: () -> Logger

    input Input
    output Output

    #: (Input) -> SenroUsecaser::Result[Output]
    def call(_input)
      logger.info("Admin ユーザー一覧を取得")

      # 管理者操作なので監査ログを記録
      admin = user_repository.find(100)
      audit_logger.log(action: "list_admin_users", performed_by: admin) if admin

      users = user_repository.all
      success(Output.new(users: users))
    end
  end

  # Admin::Reports namespace の UseCase（ネストした namespace）
  class GenerateUserReportUseCase < SenroUsecaser::Base
    namespace "admin::reports"

    class Input
      #: (report_type: String) -> void
      def initialize(report_type:)
        @report_type = report_type #: String
      end

      #: () -> String
      attr_reader :report_type
    end

    class Output
      #: (report: String) -> void
      def initialize(report:)
        @report = report #: String
      end

      #: () -> String
      attr_reader :report
    end

    depends_on :report_generator, Admin::Reports::ReportGenerator
    depends_on :report_exporter, Admin::Reports::ReportExporter
    depends_on :user_repository, Admin::UserRepository # admin namespace からフォールバック
    depends_on :audit_logger, Admin::AuditLogger       # admin namespace からフォールバック
    depends_on :logger, Logger                         # ルートからフォールバック

    # @rbs!
    #   def report_generator: () -> Admin::Reports::ReportGenerator
    #   def report_exporter: () -> Admin::Reports::ReportExporter
    #   def user_repository: () -> Admin::UserRepository
    #   def audit_logger: () -> Admin::AuditLogger
    #   def logger: () -> Logger

    input Input
    output Output

    #: (Input) -> SenroUsecaser::Result[Output]
    def call(input)
      logger.info("レポート生成開始: #{input.report_type}")

      users = user_repository.all
      report = report_generator.generate(input.report_type, { users: users, count: users.length })
      exported = report_exporter.export(report, :pdf)

      admin = user_repository.find(100)
      audit_logger.log(action: "generate_report:#{input.report_type}", performed_by: admin) if admin

      success(Output.new(report: exported))
    end
  end

  # リクエストスコープで current_user を注入しつつ、namespace を活用
  class AdminActionUseCase < SenroUsecaser::Base
    namespace :admin

    class Input
      #: (**untyped) -> void
      def initialize(**_rest)
      end
    end

    class Output
      #: (message: String) -> void
      def initialize(message:)
        @message = message #: String
      end

      #: () -> String
      attr_reader :message
    end

    depends_on :current_user, User
    depends_on :audit_logger, Admin::AuditLogger
    depends_on :notification_service, Admin::NotificationService

    # @rbs!
    #   def current_user: () -> User
    #   def audit_logger: () -> Admin::AuditLogger
    #   def notification_service: () -> Admin::NotificationService

    input Input
    output Output

    #: (Input) -> SenroUsecaser::Result[Output]
    def call(_input)
      audit_logger.log(action: "admin_action", performed_by: current_user)
      notification_service.notify(current_user, "アクションを実行しました")
      success(Output.new(message: "#{current_user.name} がアクションを実行"))
    end
  end
end

# =============================================================================
# infer_namespace_from_module のデモ用 UseCase
# =============================================================================
# NamespaceDemo モジュールの外に定義することで、
# モジュール名がそのまま namespace として推論される

# Public::InferredUseCase → namespace "public" として推論
module Public
  class InferredUseCase < SenroUsecaser::Base
    # namespace を明示的に設定しない！
    # infer_namespace_from_module = true の場合、モジュール名 "Public" から
    # namespace "public" が自動的に推論される

    class Input
      #: (**untyped) -> void
      def initialize(**_rest)
      end
    end

    class Output
      #: (message: String) -> void
      def initialize(message:)
        @message = message #: String
      end

      #: () -> String
      attr_reader :message
    end

    depends_on :user_repository, NamespaceDemo::Public::UserRepository
    depends_on :logger, NamespaceDemo::Logger

    # @rbs!
    #   def user_repository: () -> NamespaceDemo::Public::UserRepository
    #   def logger: () -> NamespaceDemo::Logger

    input Input
    output Output

    #: (Input) -> SenroUsecaser::Result[Output]
    def call(_input)
      logger.info("InferredUseCase: namespace を自動推論して実行")
      users = user_repository.all
      success(Output.new(message: "#{users.length} 人のユーザーを取得（namespace 自動推論）"))
    end
  end
end

# Admin::Reports::InferredReportUseCase → namespace "admin::reports" として推論
module Admin
  module Reports
    class InferredReportUseCase < SenroUsecaser::Base
      # namespace を明示的に設定しない！
      # infer_namespace_from_module = true の場合、モジュール名から
      # namespace "admin::reports" が自動的に推論される

      class Input
        #: (**untyped) -> void
        def initialize(**_rest)
        end
      end

      class Output
        #: (message: String) -> void
        def initialize(message:)
          @message = message #: String
        end

        #: () -> String
        attr_reader :message
      end

      depends_on :report_generator, NamespaceDemo::Admin::Reports::ReportGenerator
      depends_on :user_repository, NamespaceDemo::Admin::UserRepository
      depends_on :logger, NamespaceDemo::Logger

      # @rbs!
      #   def report_generator: () -> NamespaceDemo::Admin::Reports::ReportGenerator
      #   def user_repository: () -> NamespaceDemo::Admin::UserRepository
      #   def logger: () -> NamespaceDemo::Logger

      input Input
      output Output

      #: (Input) -> SenroUsecaser::Result[Output]
      def call(_input)
        logger.info("InferredReportUseCase: ネストした namespace を自動推論して実行")
        users = user_repository.all
        report = report_generator.generate("inferred_report", { count: users.length })
        success(Output.new(message: "レポート生成完了: #{report}（namespace 自動推論）"))
      end
    end
  end
end

# =============================================================================
# infer_namespace_from_module を使った Provider のデモ
# =============================================================================
# Provider もモジュール名から namespace を自動推論できる

# Inferred::ServiceProvider → namespace "inferred" として推論
module Inferred
  class ServiceProvider < SenroUsecaser::Provider
    # namespace を明示的に設定しない！
    # infer_namespace_from_module = true の場合、モジュール名 "Inferred" から
    # namespace "inferred" が自動的に推論される

    #: (SenroUsecaser::Container) -> void
    def register(container)
      container.register(:inferred_service, "This service was registered in inferred namespace")
    end
  end
end

# =============================================================================
# テスト実行
# =============================================================================

puts "=" * 70
puts "SenroUsecaser Namespace デモ"
puts "=" * 70
puts

# 状態をリセット
SenroUsecaser.reset!

# Provider を設定
SenroUsecaser.configure do |config|
  config.providers = [
    NamespaceDemo::CoreProvider,
    NamespaceDemo::PublicProvider,
    NamespaceDemo::AdminProvider,
    NamespaceDemo::AdminReportsProvider
  ]
end

puts "1. Provider の起動とnamespace登録"
puts "-" * 70
SenroUsecaser.boot!
puts

# -----------------------------------------------------------------------------
puts "2. Container の namespace 構造確認"
puts "-" * 70

container = SenroUsecaser.container
puts "  登録済みキー:"
container.keys.sort.each do |key|
  puts "    - #{key}"
end
puts

# -----------------------------------------------------------------------------
puts "3. namespace フォールバック確認"
puts "-" * 70

# admin namespace から logger（ルートに登録）を解決
puts "  admin namespace から logger を解決:"
admin_logger = container.resolve_in(:admin, :logger) #: NamespaceDemo::Logger
admin_logger.info("admin namespace から解決された logger です")

# admin::reports namespace から audit_logger（admin に登録）を解決
puts "  admin::reports namespace から audit_logger を解決:"
reports_audit_logger = container.resolve_in("admin::reports", :audit_logger) #: NamespaceDemo::Admin::AuditLogger
admin = container.resolve_in(:admin, :user_repository).find(100) #: NamespaceDemo::User?
reports_audit_logger.log(action: "test_fallback", performed_by: admin) if admin
puts

# -----------------------------------------------------------------------------
puts "4. Public namespace UseCase 実行"
puts "-" * 70

result = NamespaceDemo::ListPublicUsersUseCase.call(NamespaceDemo::ListPublicUsersUseCase::Input.new)
if result.success?
  output = result.value!
  puts "  取得したユーザー数: #{output.users.length}"
  output.users.each do |user|
    puts "    - #{user.name} (#{user.role})"
  end
end
puts

# -----------------------------------------------------------------------------
puts "5. Admin namespace UseCase 実行"
puts "-" * 70

result = NamespaceDemo::ListAdminUsersUseCase.call(NamespaceDemo::ListAdminUsersUseCase::Input.new)
if result.success?
  output = result.value!
  puts "  取得した管理者数: #{output.users.length}"
  output.users.each do |user|
    puts "    - #{user.name} (#{user.role})"
  end
end
puts

# -----------------------------------------------------------------------------
puts "6. Admin::Reports namespace UseCase 実行（ネストした namespace）"
puts "-" * 70

input = NamespaceDemo::GenerateUserReportUseCase::Input.new(report_type: "monthly_summary")
result = NamespaceDemo::GenerateUserReportUseCase.call(input)
if result.success?
  output = result.value!
  puts "  生成されたレポート: #{output.report}"
end
puts

# -----------------------------------------------------------------------------
puts "7. 同じキーの異なる namespace 解決確認"
puts "-" * 70

public_repo = container.resolve_in(:public, :user_repository) #: NamespaceDemo::Public::UserRepository
admin_repo = container.resolve_in(:admin, :user_repository) #: NamespaceDemo::Admin::UserRepository

puts "  Public UserRepository:"
public_repo.all.each do |user|
  puts "    - #{user.name}"
end

puts "  Admin UserRepository:"
admin_repo.all.each do |user|
  puts "    - #{user.name}"
end
puts

# -----------------------------------------------------------------------------
puts "8. Scoped Container と namespace の組み合わせ"
puts "-" * 70

# リクエストスコープのコンテナを作成（admin namespace に current_user を追加）
current_admin = NamespaceDemo::User.new(id: 100, name: "現在の管理者", role: "admin")

scoped_container = container.scope do
  # @type self: SenroUsecaser::Container
  namespace(:admin) do
    # @type self: SenroUsecaser::Container
    register(:current_user, current_admin)
  end
end

result = NamespaceDemo::AdminActionUseCase.call(NamespaceDemo::AdminActionUseCase::Input.new, container: scoped_container)
if result.success?
  output = result.value!
  puts "  結果: #{output.message}"
end
puts

# -----------------------------------------------------------------------------
puts "9. registered? と registered_in? の確認"
puts "-" * 70

puts "  container.registered_in?(:admin, :user_repository) = #{container.registered_in?(:admin, :user_repository)}"
puts "  container.registered_in?(:public, :user_repository) = #{container.registered_in?(:public, :user_repository)}"
puts "  container.registered_in?(:admin, :logger) = #{container.registered_in?(:admin, :logger)} (ルートからフォールバック)"
puts "  container.registered_in?(\"admin::reports\", :report_generator) = #{container.registered_in?("admin::reports",
                                                                                                     :report_generator)}"
puts "  container.registered_in?(\"admin::reports\", :audit_logger) = #{container.registered_in?("admin::reports",
                                                                                                 :audit_logger)} (adminからフォールバック)"
puts "  container.registered_in?(:public, :audit_logger) = #{container.registered_in?(:public, :audit_logger)} (存在しない)"
puts

# -----------------------------------------------------------------------------
puts "10. infer_namespace_from_module の確認"
puts "-" * 70

# 設定を有効化
SenroUsecaser.configuration.infer_namespace_from_module = true
puts "  infer_namespace_from_module = true に設定"

# Public::InferredUseCase は namespace を明示していないが、
# モジュール名から "public" namespace が推論される
puts "  Public::InferredUseCase を実行（namespace 自動推論）:"
result = Public::InferredUseCase.call(Public::InferredUseCase::Input.new)
if result.success?
  output = result.value!
  puts "    結果: #{output.message}"
end

# Admin::Reports::InferredReportUseCase はネストしたモジュールから
# "admin::reports" namespace が推論される
puts "  Admin::Reports::InferredReportUseCase を実行（ネストした namespace 自動推論）:"
result = Admin::Reports::InferredReportUseCase.call(Admin::Reports::InferredReportUseCase::Input.new)
if result.success?
  output = result.value!
  puts "    結果: #{output.message}"
end
puts

# Provider も同様にモジュール名から namespace を推論できる
puts "  Provider の namespace 自動推論:"
# Inferred::ServiceProvider を登録（namespace "inferred" が推論される）
Inferred::ServiceProvider.call(SenroUsecaser.container)
puts "    Inferred::ServiceProvider を登録"

# 登録されたキーを確認
inferred_keys = SenroUsecaser.container.keys.select { |k| k.start_with?("inferred") }
puts "    登録されたキー: #{inferred_keys.join(", ")}"

# 値を取得
value = SenroUsecaser.container.resolve_in(:inferred, :inferred_service)
puts "    取得した値: #{value}"

# 設定を元に戻す
SenroUsecaser.configuration.infer_namespace_from_module = false
puts

# -----------------------------------------------------------------------------
puts "11. シャットダウン"
puts "-" * 70
SenroUsecaser.shutdown!
puts "  完了"
puts

puts "=" * 70
puts "Namespace デモ完了"
puts "=" * 70
