# Steering: Testcontainers プロトタイプ実装

## 目的・背景

調査結果に基づき、testcontainersのMoonBit実装のプロトタイプ（MVP）を作成する。このプロトタイプは、基本的なコンテナ起動・停止機能を実装し、実現可能性を検証する。

## ゴール

- シンプルなコンテナ起動・停止機能の実装
- Docker CLIラッパーの実装
- Builderパターンを使用した直感的なAPI
- 基本的なエラーハンドリング
- 統合テストの作成

## アプローチ

### 実装方針

1. **Docker CLIラッパー**
   - `@process.collect_output_merged`を使用してDocker CLIコマンドを実行
   - `docker run`, `docker stop`, `docker rm`, `docker port`コマンドのラッパー関数

2. **API設計**
   - `ContainerImage`構造体: イメージ定義と設定
   - `Container`構造体: 実行中のコンテナを表す
   - Builderパターン: `with_*`メソッドによるフルエントAPI

3. **基本機能**
   - コンテナの起動（デタッチモード）
   - ポートマッピング（ランダムポート割り当て）
   - 環境変数の設定
   - コンテナの停止と削除

4. **エラーハンドリング**
   - `Result`型を使用
   - Docker CLIの実行エラーを適切に処理

### 実装しない機能（スコープ外）

- Wait Strategies（次のフェーズ）
- ネットワーク管理（次のフェーズ）
- ボリューム管理（次のフェーズ）
- 複雑なコンテナ設定

## スコープ

### 含む

- Docker CLIラッパー関数の実装
- `ContainerImage`と`Container`構造体
- 基本的なコンテナライフサイクル管理
- ポートマッピングの取得
- 環境変数の設定
- 統合テスト（実際のDockerコンテナを使用）
- READMEの更新

### 含まない

- Wait Strategies
- 複数コンテナの連携
- ネットワーク/ボリュームの高度な管理
- 専用モジュール（PostgreSQL、Redisなど）
- パフォーマンス最適化

## 影響範囲

### 変更するファイル

- `moonbit_test_containers.mbt`: メイン実装
- `moonbit_test_containers_test.mbt`: テストコード
- `moon.mod.json`: 依存関係の追加（必要に応じて）
- `README.mbt.md`: 使用例とドキュメント

### 新規作成ファイル

- なし（既存ファイルを更新）

## 成功基準

- [ ] Docker CLIラッパー関数が正常に動作する
- [ ] コンテナを起動・停止できる
- [ ] ポートマッピングが取得できる
- [ ] 環境変数が正しく設定される
- [ ] テストが全てパスする
- [ ] READMEに使用例が記載されている
- [ ] エラーケースが適切にハンドリングされる

## リスクと対策

### リスク1: Docker CLIの出力形式が不安定

**対策**: JSON出力を使用（`docker inspect --format json`など）

### リスク2: ポートマッピングの取得が複雑

**対策**: `docker port`コマンドの出力をパースする

### リスク3: リソースリーク（コンテナが削除されない）

**対策**: テスト終了時に確実にクリーンアップする処理を実装

### リスク4: `moonbitlang/async`の依存関係

**対策**: `moon.mod.json`に正しく依存を追加
