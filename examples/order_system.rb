#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable all

# rbs_inline: enabled

require_relative "../lib/senro_usecaser"

# =============================================================================
# サンプル: ECサイトの注文システム
# =============================================================================
#
# このサンプルでは以下の機能を検証します:
#   1. 基本的な UseCase と Result
#   2. DI Container（依存性注入）
#   3. Provider パターン（依存関係、ライフサイクル、enabled_if）
#   4. Pipeline composition（organize, step, 条件分岐）
#   5. Hooks（before/after/around）
#   6. Scoped Container（リクエストスコープ）
#   7. Input/Output スキーマ
#   8. Accumulated Context
#
# =============================================================================

puts "=" * 70
puts "SenroUsecaser サンプルプログラム: ECサイト注文システム"
puts "=" * 70
puts

# =============================================================================
# モデル
# =============================================================================

# ユーザーモデル
class User
  #: Integer
  attr_reader :id

  #: String
  attr_reader :name

  #: String
  attr_reader :email

  #: bool
  attr_reader :premium

  #: (id: Integer, name: String, email: String, premium: bool) -> void
  def initialize(id:, name:, email:, premium:)
    @id = id
    @name = name
    @email = email
    @premium = premium
  end

  #: () -> bool
  def premium?
    @premium
  end
end

# 商品モデル
class Product
  #: Integer
  attr_reader :id

  #: String
  attr_reader :name

  #: Integer
  attr_reader :price

  #: Integer
  attr_reader :stock

  #: (id: Integer, name: String, price: Integer, stock: Integer) -> void
  def initialize(id:, name:, price:, stock:)
    @id = id
    @name = name
    @price = price
    @stock = stock
  end
end

# 注文モデル
class Order
  #: Integer
  attr_reader :id

  #: Integer
  attr_reader :user_id

  #: Array[Integer]
  attr_reader :items

  #: Integer
  attr_reader :subtotal

  #: Integer
  attr_reader :tax

  #: Integer
  attr_reader :discount

  #: Integer
  attr_reader :total

  #: String
  attr_reader :status

  #: (id: Integer, user_id: Integer, items: Array[Integer], subtotal: Integer, tax: Integer, discount: Integer, total: Integer, status: String) -> void
  def initialize(id:, user_id:, items:, subtotal:, tax:, discount:, total:, status:)
    @id = id
    @user_id = user_id
    @items = items
    @subtotal = subtotal
    @tax = tax
    @discount = discount
    @total = total
    @status = status
  end
end

# =============================================================================
# 共有 Output 型定義（複数 UseCase で使用）
# =============================================================================

class CreateOrderOutput
  #: (order: Order) -> void
  def initialize(order:)
    @order = order #: Order
  end

  #: () -> Order
  attr_reader :order
end

class GreetingOutput
  #: (greeted: String) -> void
  def initialize(greeted:)
    @greeted = greeted #: String
  end

  #: () -> String
  attr_reader :greeted
end

class AccumulatedOutput
  #: (counter: Integer, final: bool) -> void
  def initialize(counter:, final:)
    @counter = counter #: Integer
    @final = final #: bool
  end

  #: () -> Integer
  attr_reader :counter

  #: () -> bool
  attr_reader :final
end

# =============================================================================
# リポジトリ（インメモリ実装）
# =============================================================================

class UserRepository
  #: () -> void
  def initialize
    @users = {
      1 => User.new(id: 1, name: "田中太郎", email: "tanaka@example.com", premium: true),
      2 => User.new(id: 2, name: "佐藤花子", email: "sato@example.com", premium: false)
    } #: Hash[Integer, User]
  end

  #: (Integer) -> User?
  def find(id)
    @users[id]
  end
end

class ProductRepository
  #: () -> void
  def initialize
    @products = {
      101 => Product.new(id: 101, name: "ノートPC", price: 120_000, stock: 5),
      102 => Product.new(id: 102, name: "マウス", price: 3_000, stock: 50),
      103 => Product.new(id: 103, name: "キーボード", price: 8_000, stock: 0)
    } #: Hash[Integer, Product]
  end

  #: (Integer) -> Product?
  def find(id)
    @products[id]
  end

  #: (Array[Integer]) -> Array[Product]
  def find_all(ids)
    ids.filter_map { |id| @products[id] }
  end
end

class OrderRepository
  #: () -> void
  def initialize
    @orders = {} #: Hash[Integer, Order]
    @next_id = 1 #: Integer
  end

  #: (user_id: Integer, items: Array[Integer], subtotal: Integer, tax: Integer, discount: Integer, total: Integer) -> Order
  def create(user_id:, items:, subtotal:, tax:, discount:, total:)
    order = Order.new(
      id: @next_id,
      user_id: user_id,
      items: items,
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      total: total,
      status: "pending"
    )
    @orders[@next_id] = order
    @next_id += 1
    order
  end
end

# =============================================================================
# サービス
# =============================================================================

# 決済結果
class PaymentResult
  #: String
  attr_reader :transaction_id

  #: Time
  attr_reader :charged_at

  #: (transaction_id: String, charged_at: Time) -> void
  def initialize(transaction_id:, charged_at:)
    @transaction_id = transaction_id
    @charged_at = charged_at
  end
end

class PaymentService
  #: (user: User, amount: Integer) -> PaymentResult
  def charge(user:, amount:)
    puts "    [PaymentService] #{user.name} に ¥#{amount} を請求"
    PaymentResult.new(transaction_id: "TXN-#{rand(10_000..99_999)}", charged_at: Time.now)
  end
end

class NotificationService
  #: (to: String, subject: String, body: String) -> bool
  def send_email(to:, subject:, body:)
    puts "    [NotificationService] メール送信: #{to} - #{subject}"
    true
  end
end

class DiscountService
  #: (Integer) -> Integer
  def calculate_premium_discount(subtotal)
    (subtotal * 0.1).round
  end
end

class Logger
  #: (String) -> void
  def info(message)
    puts "    [LOG] #{message}"
  end
end

# =============================================================================
# Provider 定義
# =============================================================================

# コアプロバイダー: 基本サービスを登録
class CoreProvider < SenroUsecaser::Provider
  #: (SenroUsecaser::Container) -> void
  def register(container)
    container.register(:logger, Logger.new)
  end
end

# インフラプロバイダー: リポジトリを登録
class InfrastructureProvider < SenroUsecaser::Provider
  depends_on CoreProvider

  #: (SenroUsecaser::Container) -> void
  def register(container)
    container.register_singleton(:user_repository) { |_c| UserRepository.new }
    container.register_singleton(:product_repository) { |_c| ProductRepository.new }
    container.register_singleton(:order_repository) { |_c| OrderRepository.new }
  end

  #: (SenroUsecaser::Container) -> void
  def after_boot(container)
    logger = container.resolve(:logger) #: Logger
    logger.info("InfrastructureProvider: リポジトリ初期化完了")
  end
end

# サービスプロバイダー: ビジネスサービスを登録
class ServiceProvider < SenroUsecaser::Provider
  depends_on CoreProvider

  #: (SenroUsecaser::Container) -> void
  def register(container)
    container.register_singleton(:payment_service) { |_c| PaymentService.new }
    container.register_singleton(:notification_service) { |_c| NotificationService.new }
    container.register_singleton(:discount_service) { |_c| DiscountService.new }
  end
end

# 開発環境用プロバイダー: 開発環境でのみ有効
class DevelopmentProvider < SenroUsecaser::Provider
  enabled_if { SenroUsecaser.env.development? }

  #: (SenroUsecaser::Container) -> void
  def register(container)
    container.register(:debug_mode, true)
  end
end

# =============================================================================
# パイプライン Input インターフェース
# =============================================================================
# パイプラインでは前のステップの Output が次のステップの Input になります。
# 各ステップが期待する属性をインターフェースとして定義し、
# `input InterfaceModule` で型チェックを行います。

# 最初のステップ用（user_id, product_ids）
module OrderRequestInput
  #: () -> Integer
  def user_id = raise NotImplementedError

  #: () -> Array[Integer]
  def product_ids = raise NotImplementedError
end

# ユーザー検証後（user, product_ids）
module ValidatedUserInput
  #: () -> User
  def user = raise NotImplementedError

  #: () -> Array[Integer]
  def product_ids = raise NotImplementedError
end

# 商品検証後（user, items, subtotal）
module ValidatedProductsInput
  #: () -> User
  def user = raise NotImplementedError

  #: () -> Array[Product]
  def items = raise NotImplementedError

  #: () -> Integer
  def subtotal = raise NotImplementedError
end

# 税計算後（user, items, subtotal, tax）
module TaxCalculatedInput
  #: () -> User
  def user = raise NotImplementedError

  #: () -> Array[Product]
  def items = raise NotImplementedError

  #: () -> Integer
  def subtotal = raise NotImplementedError

  #: () -> Integer
  def tax = raise NotImplementedError
end

# 割引適用後（user, items, subtotal, tax, discount）
# TaxCalculatedInput を継承
module DiscountAppliedInput
  include TaxCalculatedInput

  #: () -> Integer
  def discount = raise NotImplementedError
end

# 合計計算後（user, items, subtotal, tax, discount, total）
# DiscountAppliedInput を継承（TaxCalculatedInput も含む）
module TotalCalculatedInput
  include DiscountAppliedInput

  #: () -> Integer
  def total = raise NotImplementedError
end

# 注文作成後（user, order）
module OrderCreatedInput
  #: () -> User
  def user = raise NotImplementedError

  #: () -> Order
  def order = raise NotImplementedError
end

# 最終出力用（order）
module FinalOrderInput
  #: () -> Order
  def order = raise NotImplementedError
end

# =============================================================================
# 個別 UseCase（パイプラインステップ）
# =============================================================================

# ユーザー検証
class ValidateUserUseCase < SenroUsecaser::Base
  class Input
    include OrderRequestInput

    #: (user_id: Integer, product_ids: Array[Integer], **untyped) -> void
    def initialize(user_id:, product_ids:, **_rest)
      @user_id = user_id #: Integer
      @product_ids = product_ids #: Array[Integer]
    end

    #: () -> Integer
    attr_reader :user_id

    #: () -> Array[Integer]
    attr_reader :product_ids
  end

  class Output
    include ValidatedUserInput

    #: (user: User, product_ids: Array[Integer], **untyped) -> void
    def initialize(user:, product_ids:, **_rest)
      @user = user #: User
      @product_ids = product_ids #: Array[Integer]
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Integer]
    attr_reader :product_ids
  end

  depends_on :user_repository, UserRepository

  # @rbs!
  #   def user_repository: () -> UserRepository

  input OrderRequestInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    user = user_repository.find(input.user_id)
    return failure(SenroUsecaser::Error.new(code: :user_not_found, message: "ユーザーが見つかりません")) unless user

    success(Output.new(user: user, product_ids: input.product_ids))
  end
end

# 商品検証と在庫チェック
class ValidateProductsUseCase < SenroUsecaser::Base
  class Input
    include ValidatedUserInput

    #: (user: User, product_ids: Array[Integer], **untyped) -> void
    def initialize(user:, product_ids:, **_rest)
      @user = user #: User
      @product_ids = product_ids #: Array[Integer]
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Integer]
    attr_reader :product_ids
  end

  class Output
    include ValidatedProductsInput

    #: (user: User, items: Array[Product], subtotal: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal
  end

  depends_on :product_repository, ProductRepository

  # @rbs!
  #   def product_repository: () -> ProductRepository

  input ValidatedUserInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    products = product_repository.find_all(input.product_ids)

    if products.length != input.product_ids.length
      return failure(SenroUsecaser::Error.new(code: :product_not_found, message: "商品が見つかりません"))
    end

    out_of_stock = products.select { |p| p.stock <= 0 }
    if out_of_stock.any?
      return failure(SenroUsecaser::Error.new(
                       code: :out_of_stock,
                       message: "在庫切れ: #{out_of_stock.map(&:name).join(", ")}"
                     ))
    end

    subtotal = products.sum(&:price)
    success(Output.new(user: input.user, items: products, subtotal: subtotal))
  end
end

# 税金計算
class CalculateTaxUseCase < SenroUsecaser::Base
  class Input
    include ValidatedProductsInput

    #: (user: User, items: Array[Product], subtotal: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal
  end

  class Output
    include TaxCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax
  end

  input ValidatedProductsInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    tax = (input.subtotal * 0.1).round
    success(Output.new(user: input.user, items: input.items, subtotal: input.subtotal, tax: tax))
  end
end

# プレミアム会員割引
class ApplyPremiumDiscountUseCase < SenroUsecaser::Base
  class Input
    include TaxCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax
  end

  class Output
    include DiscountAppliedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, discount: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount
  end

  depends_on :discount_service, DiscountService

  # @rbs!
  #   def discount_service: () -> DiscountService

  input TaxCalculatedInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    discount = discount_service.calculate_premium_discount(input.subtotal)
    success(Output.new(
              user: input.user, items: input.items, subtotal: input.subtotal, tax: input.tax, discount: discount
            ))
  end
end

# 合計計算
# Note: TaxCalculatedInput または DiscountAppliedInput のどちらも受け入れる
# discount がない場合はデフォルト値 0 を使用
class CalculateTotalUseCase < SenroUsecaser::Base
  class Input
    include TaxCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, ?discount: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount: 0, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount
  end

  class Output
    include TotalCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, discount: Integer, total: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount:, total:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
      @total = total #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount

    #: () -> Integer
    attr_reader :total
  end

  input TaxCalculatedInput
  output Output

  #: (TaxCalculatedInput) -> SenroUsecaser::Result[Output]
  def call(input)
    # ApplyPremiumDiscountUseCase がスキップされた場合は discount がない
    discount = input.respond_to?(:discount) ? input.discount : 0 # steep:ignore NoMethod
    total = input.subtotal + input.tax - discount
    success(Output.new(
              user: input.user, items: input.items, subtotal: input.subtotal,
              tax: input.tax, discount: discount, total: total
            ))
  end
end

# 決済処理
class ProcessPaymentUseCase < SenroUsecaser::Base
  class Input
    include TotalCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, discount: Integer, total: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount:, total:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
      @total = total #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount

    #: () -> Integer
    attr_reader :total
  end

  class Output
    include TotalCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, discount: Integer, total: Integer, payment: PaymentResult, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount:, total:, payment:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
      @total = total #: Integer
      @payment = payment #: PaymentResult
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount

    #: () -> Integer
    attr_reader :total

    #: () -> PaymentResult
    attr_reader :payment
  end

  depends_on :payment_service, PaymentService

  # @rbs!
  #   def payment_service: () -> PaymentService

  input TotalCalculatedInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    payment_result = payment_service.charge(user: input.user, amount: input.total)
    success(Output.new(
              user: input.user, items: input.items, subtotal: input.subtotal,
              tax: input.tax, discount: input.discount, total: input.total, payment: payment_result
            ))
  end
end

# 注文作成
class CreateOrderRecordUseCase < SenroUsecaser::Base
  class Input
    include TotalCalculatedInput

    #: (user: User, items: Array[Product], subtotal: Integer, tax: Integer, discount: Integer, total: Integer, **untyped) -> void
    def initialize(user:, items:, subtotal:, tax:, discount:, total:, **_rest)
      @user = user #: User
      @items = items #: Array[Product]
      @subtotal = subtotal #: Integer
      @tax = tax #: Integer
      @discount = discount #: Integer
      @total = total #: Integer
    end

    #: () -> User
    attr_reader :user

    #: () -> Array[Product]
    attr_reader :items

    #: () -> Integer
    attr_reader :subtotal

    #: () -> Integer
    attr_reader :tax

    #: () -> Integer
    attr_reader :discount

    #: () -> Integer
    attr_reader :total
  end

  class Output
    include OrderCreatedInput

    #: (user: User, order: Order, **untyped) -> void
    def initialize(user:, order:, **_rest)
      @user = user #: User
      @order = order #: Order
    end

    #: () -> User
    attr_reader :user

    #: () -> Order
    attr_reader :order
  end

  depends_on :order_repository, OrderRepository

  # @rbs!
  #   def order_repository: () -> OrderRepository

  input TotalCalculatedInput
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    order = order_repository.create(
      user_id: input.user.id,
      items: input.items.map(&:id),
      subtotal: input.subtotal,
      tax: input.tax,
      discount: input.discount,
      total: input.total
    )
    success(Output.new(user: input.user, order: order))
  end
end

# 通知送信
class SendOrderNotificationUseCase < SenroUsecaser::Base
  class Input
    include OrderCreatedInput

    #: (user: User, order: Order, **untyped) -> void
    def initialize(user:, order:, **_rest)
      @user = user #: User
      @order = order #: Order
    end

    #: () -> User
    attr_reader :user

    #: () -> Order
    attr_reader :order
  end

  class Output
    include FinalOrderInput

    #: (user: User, order: Order, notified: bool, **untyped) -> void
    def initialize(user:, order:, notified:, **_rest)
      @user = user #: User
      @order = order #: Order
      @notified = notified #: bool
    end

    #: () -> User
    attr_reader :user

    #: () -> Order
    attr_reader :order

    #: () -> bool
    attr_reader :notified
  end

  depends_on :notification_service, NotificationService

  # @rbs!
  #   def notification_service: () -> NotificationService

  input OrderCreatedInput
  output Output

  #: (OrderCreatedInput) -> SenroUsecaser::Result[Output]
  def call(input)
    notification_service.send_email(
      to: input.user.email,
      subject: "ご注文ありがとうございます（注文番号: #{input.order.id}）",
      body: "ご注文を承りました。"
    )
    success(Output.new(user: input.user, order: input.order, notified: true))
  end
end

# パイプライン最終出力をラップ
class WrapOrderOutputUseCase < SenroUsecaser::Base
  class Input
    include FinalOrderInput

    #: (order: Order, **untyped) -> void
    def initialize(order:, **_rest)
      @order = order #: Order
    end

    #: () -> Order
    attr_reader :order
  end

  input FinalOrderInput
  output CreateOrderOutput

  #: (Input) -> SenroUsecaser::Result[CreateOrderOutput]
  def call(input)
    success(CreateOrderOutput.new(order: input.order))
  end
end

# =============================================================================
# 複合 UseCase（Pipeline）
# =============================================================================

# ログ記録用 Extension
module LoggingExtension
  #: (untyped) -> void
  def self.before(input)
    puts "  [Logging] UseCase 開始: #{input.class.name}"
  end

  #: (untyped, SenroUsecaser::Result[untyped]) -> void
  def self.after(_input, result)
    status = result.success? ? "成功" : "失敗"
    puts "  [Logging] UseCase 終了: #{status}"
  end
end

# 注文作成パイプライン
class CreateOrderUseCase < SenroUsecaser::Base
  class Input
    include OrderRequestInput

    #: (user_id: Integer, product_ids: Array[Integer], **untyped) -> void
    def initialize(user_id:, product_ids:, **_rest)
      @user_id = user_id #: Integer
      @product_ids = product_ids #: Array[Integer]
    end

    #: () -> Integer
    attr_reader :user_id

    #: () -> Array[Integer]
    attr_reader :product_ids
  end

  extend_with LoggingExtension

  input Input
  output CreateOrderOutput

  # @rbs!
  #   def self.call: (Input, ?container: SenroUsecaser::Container) -> SenroUsecaser::Result[CreateOrderOutput]

  organize do
    step ValidateUserUseCase
    step ValidateProductsUseCase
    step CalculateTaxUseCase
    step ApplyPremiumDiscountUseCase, if: :premium_user?
    step CalculateTotalUseCase
    step ProcessPaymentUseCase
    step CreateOrderRecordUseCase
    step SendOrderNotificationUseCase, on_failure: :continue
    step WrapOrderOutputUseCase
  end

  #: (TaxCalculatedInput) -> bool
  def premium_user?(input)
    input.user.premium?
  end
end

# =============================================================================
# サンプル実行
# =============================================================================

# 設定と起動
SenroUsecaser.configure do |config|
  config.providers = [
    CoreProvider,
    InfrastructureProvider,
    ServiceProvider,
    DevelopmentProvider
  ]
end

puts "1. Provider の起動"
puts "-" * 70
SenroUsecaser.boot!
puts

# -----------------------------------------------------------------------------
puts "2. Input Class の確認"
puts "-" * 70

input_class = CreateOrderUseCase.input_class
puts "  入力クラス: #{input_class}"
puts

# -----------------------------------------------------------------------------
puts "3. 正常ケース: プレミアム会員の注文"
puts "-" * 70

input = CreateOrderUseCase::Input.new(user_id: 1, product_ids: [101, 102])
result = CreateOrderUseCase.call(input)

if result.success?
  output = result.value!
  puts "  注文成功!"
  puts "  注文ID: #{output.order.id}"
  puts "  小計: ¥#{output.order.subtotal}"
  puts "  税金: ¥#{output.order.tax}"
  puts "  割引: ¥#{output.order.discount} (プレミアム会員)"
  puts "  合計: ¥#{output.order.total}"
else
  puts "  注文失敗: #{result.errors.map(&:message).join(", ")}"
end
puts

# -----------------------------------------------------------------------------
puts "4. 正常ケース: 一般会員の注文（割引なし）"
puts "-" * 70

input = CreateOrderUseCase::Input.new(user_id: 2, product_ids: [102])
result = CreateOrderUseCase.call(input)

if result.success?
  output = result.value!
  puts "  注文成功!"
  puts "  注文ID: #{output.order.id}"
  puts "  小計: ¥#{output.order.subtotal}"
  puts "  税金: ¥#{output.order.tax}"
  puts "  割引: ¥#{output.order.discount} (一般会員)"
  puts "  合計: ¥#{output.order.total}"
else
  puts "  注文失敗: #{result.errors.map(&:message).join(", ")}"
end
puts

# -----------------------------------------------------------------------------
puts "5. 失敗ケース: 存在しないユーザー"
puts "-" * 70

input = CreateOrderUseCase::Input.new(user_id: 999, product_ids: [101])
result = CreateOrderUseCase.call(input)

if result.failure?
  error = result.errors.first #: SenroUsecaser::Error?
  puts "  期待通り失敗: #{error&.code} - #{error&.message}" if error
end
puts

# -----------------------------------------------------------------------------
puts "6. 失敗ケース: 在庫切れ商品"
puts "-" * 70

input = CreateOrderUseCase::Input.new(user_id: 1, product_ids: [103])
result = CreateOrderUseCase.call(input)

if result.failure?
  error = result.errors.first #: SenroUsecaser::Error?
  puts "  期待通り失敗: #{error&.code} - #{error&.message}" if error
end
puts

# -----------------------------------------------------------------------------
puts "7. Scoped Container: リクエストスコープ"
puts "-" * 70

# リクエストごとに current_user を注入するパターン
class CurrentUserAwareUseCase < SenroUsecaser::Base
  # 空のInputクラス（入力不要なUseCase用）
  class Input
    #: (**untyped) -> void
    def initialize(**_rest)
    end
  end

  depends_on :current_user, User
  depends_on :logger, Logger

  # @rbs!
  #   def current_user: () -> User
  #   def logger: () -> Logger

  input Input
  output GreetingOutput

  #: (Input) -> SenroUsecaser::Result[GreetingOutput]
  def call(_input)
    logger.info("現在のユーザー: #{current_user.name}")
    success(GreetingOutput.new(greeted: "こんにちは、#{current_user.name}さん!"))
  end
end

# リクエストスコープのコンテナを作成
current_user = User.new(id: 1, name: "リクエストユーザー", email: "request@example.com", premium: false)
scoped_container = SenroUsecaser.container.scope do
  # @type self: SenroUsecaser::Container
  register(:current_user, current_user)
end

result = CurrentUserAwareUseCase.call(CurrentUserAwareUseCase::Input.new, container: scoped_container)
if result.success?
  value = result.value!
  puts "  #{value.greeted}"
end
puts

# -----------------------------------------------------------------------------
puts "8. Result の操作"
puts "-" * 70

success_result = SenroUsecaser::Result.success({ value: 42 })
failure_result = SenroUsecaser::Result.failure(
  SenroUsecaser::Error.new(code: :error1, message: "エラー1"),
  SenroUsecaser::Error.new(code: :error2, message: "エラー2")
)

puts "  success?: #{success_result.success?}, failure?: #{failure_result.failure?}"
puts "  value_or: #{failure_result.value_or("デフォルト値")}"

mapped_result = success_result.map do |v|
  hash = v #: Hash[Symbol, Integer]
  hash[:value] * 2
end
puts "  map: #{mapped_result.value}"
puts "  エラー数: #{failure_result.errors.length}"
puts

# -----------------------------------------------------------------------------
puts "9. Accumulated Context の確認"
puts "-" * 70

# Accumulated Context 用インターフェース
module InitialInput
  #: () -> String
  def initial = raise NotImplementedError
end

module Step1Output
  #: () -> String
  def step1_data = raise NotImplementedError

  #: () -> Integer
  def counter = raise NotImplementedError
end

module Step2Output
  include Step1Output

  #: () -> String
  def step2_data = raise NotImplementedError
end

module FinalAccumulatedInput
  #: () -> Integer
  def counter = raise NotImplementedError

  #: () -> bool
  def final = raise NotImplementedError
end

module Step3Output
  include Step2Output
  include FinalAccumulatedInput

  #: () -> String
  def step3_data = raise NotImplementedError
end


class Step1 < SenroUsecaser::Base
  class Input
    include InitialInput

    #: (initial: String, **untyped) -> void
    def initialize(initial:, **_rest)
      @initial = initial #: String
    end

    #: () -> String
    attr_reader :initial
  end

  class Output
    include Step1Output

    #: (step1_data: String, counter: Integer, **untyped) -> void
    def initialize(step1_data:, counter:, **_rest)
      @step1_data = step1_data #: String
      @counter = counter #: Integer
    end

    #: () -> String
    attr_reader :step1_data

    #: () -> Integer
    attr_reader :counter
  end

  input InitialInput
  output Output

  #: (InitialInput) -> SenroUsecaser::Result[Output]
  def call(_input)
    success(Output.new(step1_data: "from step1", counter: 1))
  end
end

class Step2 < SenroUsecaser::Base
  class Input
    include Step1Output

    #: (step1_data: String, counter: Integer, **untyped) -> void
    def initialize(step1_data:, counter:, **_rest)
      @step1_data = step1_data #: String
      @counter = counter #: Integer
    end

    #: () -> String
    attr_reader :step1_data

    #: () -> Integer
    attr_reader :counter
  end

  class Output
    include Step2Output

    #: (step1_data: String, step2_data: String, counter: Integer, **untyped) -> void
    def initialize(step1_data:, step2_data:, counter:, **_rest)
      @step1_data = step1_data #: String
      @step2_data = step2_data #: String
      @counter = counter #: Integer
    end

    #: () -> String
    attr_reader :step1_data

    #: () -> String
    attr_reader :step2_data

    #: () -> Integer
    attr_reader :counter
  end

  input Step1Output
  output Output

  #: (Step1Output) -> SenroUsecaser::Result[Output]
  def call(input)
    success(Output.new(step1_data: input.step1_data, step2_data: "from step2", counter: input.counter + 1))
  end
end

class Step3 < SenroUsecaser::Base
  class Input
    include Step2Output

    #: (step1_data: String, step2_data: String, counter: Integer, **untyped) -> void
    def initialize(step1_data:, step2_data:, counter:, **_rest)
      @step1_data = step1_data #: String
      @step2_data = step2_data #: String
      @counter = counter #: Integer
    end

    #: () -> String
    attr_reader :step1_data

    #: () -> String
    attr_reader :step2_data

    #: () -> Integer
    attr_reader :counter
  end

  class Output
    include Step3Output

    #: (step1_data: String, step2_data: String, step3_data: String, counter: Integer, final: bool, **untyped) -> void
    def initialize(step1_data:, step2_data:, step3_data:, counter:, final:, **_rest)
      @step1_data = step1_data #: String
      @step2_data = step2_data #: String
      @step3_data = step3_data #: String
      @counter = counter #: Integer
      @final = final #: bool
    end

    #: () -> String
    attr_reader :step1_data

    #: () -> String
    attr_reader :step2_data

    #: () -> String
    attr_reader :step3_data

    #: () -> Integer
    attr_reader :counter

    #: () -> bool
    attr_reader :final
  end

  # Step2がスキップされる場合を考慮してStep1Outputも受け付ける
  input Step1Output
  output Output

  #: (Step1Output) -> SenroUsecaser::Result[Output]
  def call(input)
    step2_data = input.respond_to?(:step2_data) ? input.step2_data : "skipped" # steep:ignore NoMethod
    success(Output.new(
              step1_data: input.step1_data, step2_data: step2_data,
              step3_data: "from step3", counter: input.counter + 1, final: true
            ))
  end
end

class WrapAccumulatedOutputUseCase < SenroUsecaser::Base
  class Input
    include FinalAccumulatedInput

    #: (counter: Integer, final: bool, **untyped) -> void
    def initialize(counter:, final:, **_rest)
      @counter = counter #: Integer
      @final = final #: bool
    end

    #: () -> Integer
    attr_reader :counter

    #: () -> bool
    attr_reader :final
  end

  input FinalAccumulatedInput
  output AccumulatedOutput

  #: (FinalAccumulatedInput) -> SenroUsecaser::Result[AccumulatedOutput]
  def call(input)
    success(AccumulatedOutput.new(counter: input.counter, final: input.final))
  end
end

class AccumulatedContextDemo < SenroUsecaser::Base
  class Input
    include InitialInput

    #: (initial: String, **untyped) -> void
    def initialize(initial:, **_rest)
      @initial = initial #: String
    end

    #: () -> String
    attr_reader :initial
  end

  input Input
  output AccumulatedOutput

  # @rbs!
  #   def self.call: (Input, ?container: SenroUsecaser::Container) -> SenroUsecaser::Result[AccumulatedOutput]

  organize do
    step Step1
    step Step2, if: :check_accumulated
    step Step3
    step WrapAccumulatedOutputUseCase
  end

  #: (untyped) -> bool
  def check_accumulated(ctx)
    puts "    [InputChaining] step1_data: #{ctx.step1_data}"
    true
  end
end

input = AccumulatedContextDemo::Input.new(initial: "value")
result = AccumulatedContextDemo.call(input) #: SenroUsecaser::Result[AccumulatedOutput]
if result.success?
  output = result.value!
  puts "  最終結果: counter=#{output.counter}, final=#{output.final}"
end
puts

# -----------------------------------------------------------------------------
puts "10. シャットダウン"
puts "-" * 70
SenroUsecaser.shutdown!
puts "  完了"
puts

puts "=" * 70
puts "すべてのサンプルが完了しました"
puts "=" * 70
