# Steering: ポートマッピング取得にリトライロジックを追加

## 目的・背景

PostgreSQL のような初期化に時間がかかるコンテナで、`docker port` コマンドが一時的に失敗する問題を解決する。

**問題の詳細:**
- コンテナ起動直後（`docker run -d` 成功後）に `docker port` を実行すると、404 エラーが返される
- PostgreSQL テストで観察されたが、他の初期化の遅いコンテナでも発生しうる
- 手動実行では成功するため、タイミングの問題と判明

## ゴール

- PostgreSQL テストを含む全23テストが成功すること
- 初期化が遅いコンテナでも確実にポートマッピングを取得できること
- 既存のテスト（Redis, Nginx等）に悪影響を与えないこと

## アプローチ

### 1. リトライロジックの追加

`container.mbt` の `update_port_mappings()` 関数を修正:

```moonbit
// 疑似コード
for i = 0; i < max_retries; i = i + 1 {
  match exec_docker(["port", container_id, port]) {
    Ok(output) => return parse_and_store_mapping(output)
    Err(e) => {
      if is_temporary_error(e) && i < max_retries - 1 {
        sleep(retry_interval)
        continue
      } else {
        return Err(e)
      }
    }
  }
}
```

### 2. リトライパラメータ

- **最大リトライ回数**: 5回
- **リトライ間隔**: 1秒（1000ms）
- **合計タイムアウト**: 約5秒
- **一時的エラーの判定**: "404" または "not found" を含むエラーメッセージ

### 3. エラーハンドリング戦略

**一時的エラー（リトライする）:**
- "404 page not found"
- "container not found"（コンテナ起動直後の状態）

**永続的エラー（即座に失敗）:**
- "no such container"（コンテナIDが完全に間違っている）
- その他の Docker コマンドエラー

## 実装の詳細

### 修正対象ファイル

**主な修正:**
- `container.mbt`: `update_port_mappings()` 関数

**補助的修正（必要に応じて）:**
- `error.mbt`: エラー判定用のヘルパー関数
- `docker.mbt`: リトライ用のスリープ関数（既存の sleep 使用）

### 実装ステップ

1. `container.mbt` の `update_port_mappings()` を修正
   - ポートマッピング取得のループ内にリトライロジックを追加
   - 一時的エラーかどうかを判定
   - リトライ間隔として sleep を追加

2. エラー判定ロジック
   - エラーメッセージに "404" または "not found" が含まれるかチェック
   - 一時的エラーの場合はリトライ

3. ログ出力（オプション）
   - リトライ時に警告メッセージを出力
   - デバッグに有用

## スコープ

### 含む
- `container.mbt` の `update_port_mappings()` 関数の修正
- リトライロジックの実装
- エラーハンドリングの改善
- 全テストの実行と確認

### 含まない
- `docker inspect` への切り替え（今回は実装しない）
- パフォーマンス最適化
- 新しいテストケースの追加
- 他のコンテナイメージのサポート

## 影響範囲

### 直接影響
- `container.mbt`: `update_port_mappings()` 関数

### 間接影響（確認必要）
- 全テストファイル（回帰テスト）
  - `basic_lifecycle_wbtest.mbt`
  - `wait_strategies_wbtest.mbt`
  - `volume_mount_wbtest.mbt`

## 成功の基準

1. **PostgreSQL テストが成功**
   - `volume_mount_wbtest.mbt` の "postgresql container - basic startup" が成功

2. **既存テストが引き続き成功**
   - 23テスト全てが成功
   - 特に以下を確認:
     - Redis テスト（TcpPort wait）
     - Nginx テスト（HttpGet wait）
     - Alpine テスト

3. **実行時間の増加が許容範囲内**
   - リトライロジック追加により多少の遅延は許容
   - PostgreSQL テスト: 約30秒以内（wait timeout 含む）

## テスト計画

### Phase 1: PostgreSQL テスト
```bash
moon test --target native volume_mount_wbtest.mbt
```
- "postgresql container - basic startup" が成功することを確認

### Phase 2: 全テスト
```bash
moon test --target native
```
- 全23テストが成功することを確認

### Phase 3: 複数回実行
```bash
# 安定性確認のため3回実行
for i in 1 2 3; do
  echo "Run $i"
  moon test --target native volume_mount_wbtest.mbt
done
```

## リスクと軽減策

### リスク1: リトライによる実行時間増加
- **影響**: テスト実行時間が数秒増加
- **軽減策**: リトライ回数を5回、間隔を1秒に制限
- **許容度**: 高（数秒の増加は許容範囲）

### リスク2: 他のテストへの影響
- **影響**: 既存のテストが失敗する可能性
- **軽減策**: 一時的エラーの判定を慎重に行う（404のみリトライ）
- **確認方法**: 全テストを実行して確認

### リスク3: デッドロックやハング
- **影響**: sleep 処理が原因でテストがハングする
- **軽減策**: 合計タイムアウトを5秒に制限
- **確認方法**: テスト実行時間をモニター

## 参考情報

### 関連する Steering ドキュメント
- `docs/steering/postgresql_test_failure_investigation_20260208.md`

### 観察されたエラーメッセージ
```
Failed to start PostgreSQL: Docker command failed: Error response from daemon: 404 page not found
```

### 成功している類似テスト
- Redis with TcpPort wait strategy (`wait_strategies_wbtest.mbt`)
- Nginx with HttpGet wait strategy (`wait_strategies_wbtest.mbt`)

## 実装後の確認事項

1. コードレビュー（reviewerエージェント）
2. 全テスト実行と成功確認
3. 完了ドキュメントの作成
4. Steering ドキュメントのアーカイブ
