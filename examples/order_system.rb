#!/usr/bin/env ruby
# frozen_string_literal: true

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
# 個別 UseCase（パイプラインステップ）
# =============================================================================

# ユーザー検証
class ValidateUserUseCase < SenroUsecaser::Base
  class Input
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

  input Input
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

  input Input
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

  input Input
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

  input Input
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
class CalculateTotalUseCase < SenroUsecaser::Base
  class Input
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

  input Input
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    total = input.subtotal + input.tax - input.discount
    success(Output.new(
              user: input.user, items: input.items, subtotal: input.subtotal,
              tax: input.tax, discount: input.discount, total: total
            ))
  end
end

# 決済処理
class ProcessPaymentUseCase < SenroUsecaser::Base
  class Input
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

  input Input
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

  input Input
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

  input Input
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
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
    #: (order: Order, **untyped) -> void
    def initialize(order:, **_rest)
      @order = order #: Order
    end

    #: () -> Order
    attr_reader :order
  end

  input Input
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
  #: (Hash[Symbol, untyped]) -> void
  def self.before(context)
    puts "  [Logging] UseCase 開始: #{context.keys.join(", ")}"
  end

  #: (Hash[Symbol, untyped], SenroUsecaser::Result[untyped]) -> void
  def self.after(context, result)
    status = result.success? ? "成功" : "失敗"
    puts "  [Logging] UseCase 終了: #{status}"
  end
end

# 注文作成パイプライン
class CreateOrderUseCase < SenroUsecaser::Base
  class Input
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

  #: (Hash[Symbol, untyped]) -> bool
  def premium_user?(context)
    user = context[:user] #: User?
    user&.premium? || false
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
  depends_on :current_user, User
  depends_on :logger, Logger

  # @rbs!
  #   def current_user: () -> User
  #   def logger: () -> Logger

  output GreetingOutput

  #: (?untyped, **untyped) -> SenroUsecaser::Result[GreetingOutput]
  def call(_input = nil, **_args)
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

result = CurrentUserAwareUseCase.call(container: scoped_container)
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

class Step1 < SenroUsecaser::Base
  class Input
    #: (initial: String, **untyped) -> void
    def initialize(initial:, **_rest)
      @initial = initial #: String
    end

    #: () -> String
    attr_reader :initial
  end

  class Output
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

  input Input
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    success(Output.new(step1_data: "from step1", counter: 1))
  end
end

class Step2 < SenroUsecaser::Base
  class Input
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

  input Input
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    success(Output.new(step1_data: input.step1_data, step2_data: "from step2", counter: input.counter + 1))
  end
end

class Step3 < SenroUsecaser::Base
  class Input
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

  input Input
  output Output

  #: (Input) -> SenroUsecaser::Result[Output]
  def call(input)
    success(Output.new(
              step1_data: input.step1_data, step2_data: input.step2_data,
              step3_data: "from step3", counter: input.counter + 1, final: true
            ))
  end
end

class WrapAccumulatedOutputUseCase < SenroUsecaser::Base
  class Input
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

  input Input
  output AccumulatedOutput

  #: (Input) -> SenroUsecaser::Result[AccumulatedOutput]
  def call(input)
    success(AccumulatedOutput.new(counter: input.counter, final: input.final))
  end
end

class AccumulatedContextDemo < SenroUsecaser::Base
  class Input
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

  #: (Hash[Symbol, untyped]) -> bool
  def check_accumulated(_ctx)
    puts "    [AccumulatedContext] step1_data: #{accumulated_context[:step1_data]}"
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
