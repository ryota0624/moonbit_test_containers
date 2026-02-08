# 完了報告: Testcontainers MoonBit実装の調査

## 作業日
2026-02-07

## 実装内容

testcontainersライブラリをMoonBit言語で実装するための包括的な技術調査を完了しました。

### 調査項目

1. **Testcontainersの基本概念**
   - testcontainersの目的と利点の理解
   - 自動クリーンアップ、Wait Strategies、ネットワーキング機能の調査
   - 対応言語と実装状況の確認

2. **他言語の実装パターン**
   - Rust実装（testcontainers-rs）の詳細調査
   - Go実装（testcontainers-go）の調査
   - 共通のアーキテクチャパターンの抽出
     - Image定義レイヤー
     - 設定レイヤー（Builder/Fluent API）
     - 実行レイヤー
     - Wait Strategies
     - リソース管理

3. **MoonBitの技術的機能**
   - 外部プロセス実行機能の確認
     - `@process.collect_output_merged`: Docker CLIコマンド実行に使用可能
     - `@process.run`: より細かい制御が必要な場合に使用
   - FFI（Foreign Function Interface）の調査
     - C-FFI、JavaScript FFI、WebAssembly FFIのサポート確認
   - ファイルシステム操作機能の確認
   - 非同期プログラミングのサポート確認

4. **Docker操作の要件**
   - 基本的なライフサイクルコマンドの整理
     - `docker run`: コンテナ起動
     - `docker stop`: コンテナ停止
     - `docker kill`: 強制停止
     - `docker rm`: コンテナ削除
   - ポートマッピングの仕組み
   - ネットワーク設定の方法

## 技術的な決定事項

### 1. 実装アプローチ: Docker CLIラッパー

**決定**: Docker Engine APIではなく、Docker CLIをラップする方式を採用

**理由**:
- MoonBitの`@process.collect_output_merged`を使用して簡単に実装可能
- Docker CLIの全機能を利用できる
- 実装とメンテナンスが容易
- HTTPクライアントライブラリの依存を避けられる

**トレードオフ**:
- Docker CLIのインストールが必須
- パフォーマンスが多少劣る可能性（実用上は問題なし）

### 2. API設計: Builderパターン

**決定**: Rustの実装を参考にしたBuilderパターンを採用

**理由**:
- 直感的で読みやすいコード
- 柔軟な設定が可能
- 他のtestcontainers実装との一貫性

**例**:
```moonbit
ContainerImage::new("redis", "7.2.4")
  .with_exposed_port(6379)
  .with_env_var("DEBUG", "1")
  .with_wait_for(WaitStrategy::LogMessage("Ready to accept connections"))
  .start()
```

### 3. 段階的な実装計画

**フェーズ1（MVP）**: 基本的なコンテナ起動・停止
**フェーズ2**: Wait Strategies
**フェーズ3**: 高度な機能（ネットワーク、ボリューム、モジュール）

## 変更ファイル一覧

### 追加

- `docs/steering/testcontainers_implementation.md`
  - 作業の方向性と目標を定義するsteeringドキュメント

- `docs/research/testcontainers_investigation.md`
  - 調査結果の包括的なドキュメント（9セクション構成）
  - testcontainersの概要と利点
  - 他言語実装例（Rust、Go）
  - MoonBitの技術的機能の詳細
  - Docker操作の要件
  - 実装方針とAPI設計の提案
  - 技術的課題と考慮事項
  - 次のステップと検証項目
  - 参考資料リスト
  - まとめと実現可能性の評価

- `docs/completed/testcontainers_investigation.md`
  - 本完了報告ドキュメント

### 変更

なし（調査作業のため、既存コードへの変更なし）

## 調査結果のハイライト

### ✅ 実現可能性の確認

MoonBitでtestcontainersを実装することは**技術的に実現可能**であることを確認しました。

### 主要な知見

1. **MoonBitの外部プロセス実行機能**
   - `moonbitlang/async`ライブラリの`@process.collect_output_merged`を使用
   - Docker CLIコマンドを実行してコンテナを管理可能

2. **実装の優先順位**
   - MVP: コンテナの起動・停止・削除、ポートマッピング
   - 次段階: Wait Strategies（ログ監視、ポート待機）
   - 将来: ネットワーク管理、専用モジュール

3. **API設計の方向性**
   - `ContainerImage`と`Container`構造体
   - Builderパターンによる直感的なAPI
   - `Result`型によるエラーハンドリング

### 参考にした実装

- **Rust (testcontainers-rs)**: アーキテクチャパターンとAPI設計
- **Go (testcontainers-go)**: シンプルなAPI設計

## 今後の課題・改善点

### すぐに取り組むべき項目

- [ ] プロトタイプの実装（MVP機能）
  - Docker CLIラッパー関数
  - `ContainerImage`構造体
  - `Container`構造体
  - 基本的な起動・停止メソッド

- [ ] 単体テストの作成
  - Docker CLI実行のモック
  - エラーハンドリングのテスト

- [ ] 統合テストの作成
  - 実際のDockerコンテナを使用したテスト
  - Redisコンテナの起動・停止テスト

### 検証が必要な項目

- [ ] MoonBitの`@process`モジュールの詳細な仕様
  - エラーハンドリングの詳細
  - タイムアウト処理
  - プロセス終了の検出

- [ ] リソース管理の実装方法
  - テスト終了時の自動クリーンアップ
  - 異常終了時のクリーンアップ
  - ファイナライザーの利用可能性

- [ ] MoonBitでの並行プログラミング
  - 複数テストの並行実行
  - 競合の回避方法

- [ ] MoonBitのHTTPクライアントライブラリ
  - Wait Strategies（HTTPエンドポイント待機）に必要
  - 利用可能なライブラリの調査

### 将来的な機能

- [ ] Wait Strategiesの実装
  - ログメッセージ待機
  - TCPポート待機
  - HTTPステータスコード待機

- [ ] ネットワーク管理
  - 複数コンテナの接続
  - カスタムネットワークの作成

- [ ] ボリューム管理
  - データの永続化
  - ホストディレクトリのマウント

- [ ] モジュールシステム
  - PostgreSQL、Redis、MongoDB用の専用モジュール
  - 各サービス固有の設定とヘルパー関数

## 参考資料

### Testcontainers

- [Testcontainers公式サイト](https://testcontainers.com/)
- [Testcontainers Getting Started](https://testcontainers.com/getting-started/)
- [Testcontainers for Rust](https://rust.testcontainers.org/)
- [testcontainers-rs GitHub](https://github.com/testcontainers/testcontainers-rs)
- [Testcontainers for Go](https://golang.testcontainers.org/)
- [testcontainers-go GitHub](https://github.com/testcontainers/testcontainers-go)

### MoonBit

- [MoonBit公式サイト](https://www.moonbitlang.com/)
- [MoonBit FFI Documentation](https://docs.moonbitlang.com/en/latest/language/ffi.html)
- [A Guide to MoonBit C-FFI](https://www.moonbitlang.com/pearls/moonbit-cffi)
- [Write a Simple Code Agent using moonbitlang/async](https://www.moonbitlang.com/blog/moonbit-async-code-agent)
- [moonbitlang/async GitHub](https://github.com/moonbitlang/async)
- [moonbitlang/async API Documentation](https://mooncakes.io/docs/moonbitlang/async)

### Docker

- [Docker CLI Documentation](https://docs.docker.com/reference/cli/docker/)
- [Docker Container Lifecycle Management](https://k21academy.com/kubernetes/docker-container-lifecycle-management/)

## まとめ

testcontainersのMoonBit実装に必要な技術調査が完了し、実現可能性が確認できました。

### 達成したこと

✅ testcontainersの概念と実装パターンの理解
✅ MoonBitでのDocker操作の実現可能性の確認
✅ 実装方針とAPI設計の策定
✅ 段階的な実装計画の立案
✅ 包括的な調査ドキュメントの作成

### 次のステップ

1. プロトタイプの実装（MVP機能）
2. テストの作成
3. ドキュメントの拡充
4. コミュニティフィードバックの収集

この調査により、MoonBitでtestcontainersを実装するための明確な道筋が立ちました。
