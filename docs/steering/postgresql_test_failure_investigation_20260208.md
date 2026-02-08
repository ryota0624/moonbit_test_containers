# Steering: PostgreSQL テスト失敗の調査と修正

## 目的・背景

PostgreSQL コンテナのテストが一貫して失敗しているが、以下の特異な状況が観察されている:

1. **手動での Docker 実行は成功**している（コンテナは正常に起動）
2. **他のコンテナ（Redis, Nginx, Alpine）は成功**している
3. **PostgreSQL テストのみが失敗**し、エラーメッセージは `404 page not found`

## エラーの詳細

```
Failed to start PostgreSQL: Docker command failed: Error response from daemon: 404 page not found
at volume_mount_wbtest.mbt:153
```

## 観察された事実

### 成功するケース
- `wait_strategies_wbtest.mbt` の Redis テスト（TcpPort wait strategy 使用）✅
- `wait_strategies_wbtest.mbt` の Nginx テスト（HttpGet wait strategy 使用）✅
- `basic_lifecycle_wbtest.mbt` の全テスト ✅
- `volume_mount_wbtest.mbt` の Alpine テスト ✅

### 失敗するケース
- `volume_mount_wbtest.mbt` の PostgreSQL テスト ❌

### PostgreSQL テストの構成（volume_mount_wbtest.mbt:111-155）

```moonbit
ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "testdb")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .with_wait_timeout(30)
  .start()
```

### Redis テストの構成（wait_strategies_wbtest.mbt:8-12）- 成功している

```moonbit
ContainerImage::new("redis", "7.2.4")
  .with_exposed_port(6379)
  .with_wait_for(WaitStrategy::TcpPort(6379))
  .with_wait_timeout(30)
  .start()
```

## 仮説

### 仮説 1: Docker イメージの問題
- `postgres:16` イメージが存在しないか、ダウンロードに失敗している
- **反論**: 手動実行では成功しているため、この仮説は否定される

### 仮説 2: ポートマッピングのタイミング問題
- PostgreSQL の起動が遅く、ポートマッピングの取得時にコンテナがまだ準備できていない
- `docker port` コマンドが 404 エラーを返している可能性
- **根拠**: エラーが wait strategy 実行中ではなく、コンテナ起動時に発生している

### 仮説 3: 環境変数の問題
- 複数の環境変数設定が Docker API に問題を引き起こしている
- **反論**: Redis テストでも成功しており、環境変数が原因とは考えにくい

### 仮説 4: Docker API のバージョン互換性
- `docker port` コマンドがコンテナ起動直後に実行されると 404 を返す
- コンテナが完全に起動する前に port コマンドが実行されている

## 調査アプローチ

### Phase 1: エラー発生箇所の特定
1. `container.mbt` の `start()` 関数の実行フローを追跡
2. `update_port_mappings()` での `docker port` コマンド実行を確認
3. どの段階で 404 エラーが発生しているかを特定

### Phase 2: 再現と分離
1. PostgreSQL テストから要素を削除して最小再現ケースを作成
   - 環境変数を削除
   - wait strategy を削除
   - ポート expose を削除
2. どの要素が問題を引き起こしているかを特定

### Phase 3: 修正案の検討
1. `docker port` 実行前に短時間の待機を追加
2. `docker port` の失敗時にリトライロジックを追加
3. `docker inspect` を使用してポートマッピング情報を取得する代替方法

## ゴール

1. **問題の根本原因を特定**
2. **修正を実装**し、PostgreSQL テストが成功するようにする
3. **他のテストへの影響がない**ことを確認
4. **再発防止策を検討**（例：ロバストなエラーハンドリング、リトライロジック）

## スコープ

### 含む
- PostgreSQL テスト失敗の根本原因調査
- 修正の実装
- 既存テストの回帰テスト

### 含まない
- 他のコンテナイメージの追加
- パフォーマンス最適化
- 新機能の追加

## 影響範囲

### 直接影響
- `volume_mount_wbtest.mbt` - PostgreSQL テスト
- `container.mbt` - コンテナ起動ロジック（修正が必要な場合）
- `docker.mbt` - Docker コマンド実行ロジック（修正が必要な場合）

### 間接影響
- 他の全テストファイル（回帰テストで確認必要）
- Wait strategy 実装（タイミング調整が必要な場合）

## 次のステップ

1. **coderエージェントに調査依頼**
   - デバッグログを追加して、正確なエラー発生箇所を特定
   - 最小再現ケースを作成

2. **原因特定後、修正案を実装**
   - リトライロジック
   - または待機時間の追加
   - または `docker inspect` への切り替え

3. **reviewerエージェントに修正レビュー依頼**
   - 修正の妥当性確認
   - 他のテストへの影響確認
