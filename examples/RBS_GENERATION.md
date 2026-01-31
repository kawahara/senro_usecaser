# RBS Generation for Examples

Examples の RBS ファイルは `examples/sig/` に配置されます（`sig/generated/examples/` ではありません）。

## 生成コマンド

```bash
# examples ディレクトリから実行する
cd examples && bundle exec rbs-inline --output=sig order_system.rb namespace_demo.rb
```

## 注意

- `examples` ディレクトリに移動してから実行すること
- プロジェクトルートから `examples/` を指定すると `examples/sig/examples/` にサブディレクトリが作られてしまう
- 生成された RBS は `examples/sig/` 配下に出力される
