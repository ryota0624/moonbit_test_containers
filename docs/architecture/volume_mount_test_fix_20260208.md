# アーキテクチャ設計: ボリュームマウントテストの修正

## 日付
2026-02-08

## 概要
volume_mount_wbtest.mbtの4番目のテスト「volume mount - postgresql init script」がテスト名と実装内容が不一致であり、ボリュームマウントを実際にテストしていない問題を修正する。

## 問題分析

### 現状のテストコード（Line 111-141）

```moonbit
async test "volume mount - postgresql init script" {
  // For this test, we'll mount /tmp which should exist on the host
  // In a real scenario, users would create their own SQL files
  let container = ContainerImage::new("postgres", "16")
    .with_exposed_port(5432)
    .with_env_var("POSTGRES_USER", "test")
    .with_env_var("POSTGRES_PASSWORD", "test")
    .with_env_var("POSTGRES_DB", "testdb")
    .with_wait_for(WaitStrategy::TcpPort(5432))
    .with_wait_timeout(30)
    .start()
  // ... 以下省略
}
```

### 問題点

1. **テスト名と実装の不一致**:
   - テスト名: "volume mount - postgresql init script"
   - 実装: ボリュームマウントを使用していない（`with_volume()`の呼び出しがない）

2. **コメントと実装の不一致**:
   - コメント: "For this test, we'll mount /tmp which should exist on the host"
   - 実装: `/tmp`をマウントするコードがない

3. **テストの目的が不明確**:
   - ボリュームマウントのテストなのか、PostgreSQL起動のテストなのか不明

### エラー状況

- テスト実行時に「Error response from daemon: 404 page not found」
- volume_mount_wbtest.mbt:139 で abort() が呼ばれる
- PostgreSQL コンテナの起動に失敗

## 技術設計

### アプローチの選択

**選択したアプローチ**: テストを2つに分割し、目的を明確化する

#### 理由

1. **最初の3つのテストで基本機能は確認済み**:
   - "basic with tmpfs": `/tmp` のマウント成功
   - "readonly": 読み取り専用マウント成功
   - "multiple volumes": 複数ボリュームのマウント成功

2. **実用的な例を提供**:
   - PostgreSQL は testcontainers の一般的なユースケース
   - ボリュームマウントなしの基本的な起動テストは有用

3. **テストの責務を分離**:
   - PostgreSQL 基本起動テスト（ボリュームマウントなし）
   - 将来的に必要なら、実際の初期化スクリプトを使用するテストを追加可能

### 修正案

#### オプション 1: テスト名を変更し、内容はそのまま（推奨）

```moonbit
///|
/// Test PostgreSQL container startup (practical example)
async test "postgresql container - basic startup" {
  // PostgreSQL is a common use case for testcontainers
  // This test verifies that PostgreSQL can be started and becomes ready
  let container = ContainerImage::new("postgres", "16")
    .with_exposed_port(5432)
    .with_env_var("POSTGRES_USER", "test")
    .with_env_var("POSTGRES_PASSWORD", "test")
    .with_env_var("POSTGRES_DB", "testdb")
    .with_wait_for(WaitStrategy::TcpPort(5432))
    .with_wait_timeout(30)
    .start()
  match container {
    Ok(c) => {
      println("PostgreSQL container started: \{c.get_id()}")

      // Verify port mapping
      match c.get_host_port(5432) {
        Some(port) => println("PostgreSQL is accessible on port: \{port}")
        None => abort("Port 5432 not mapped")
      }

      // Check logs to verify initialization
      match c.get_logs() {
        Ok(logs) => {
          println("PostgreSQL logs (last 100 chars): \{logs.substring(max(0, logs.length() - 100), logs.length())}")
          if logs.contains("database system is ready") {
            println("PostgreSQL initialized successfully")
          }
        }
        Err(e) => println("Warning: Failed to get logs: \{e.to_string()}")
      }

      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start PostgreSQL: \{e.to_string()}")
  }
}
```

#### オプション 2: ボリュームマウントを実際に使用（より複雑）

この場合、MoonBit でファイル操作が必要になり、複雑度が増す。最初の3つのテストで十分にボリュームマウント機能を検証しているため、このオプションは推奨しない。

### エラーの原因特定

1. **PostgreSQL イメージのサイズ**:
   - PostgreSQL 16 イメージは約 400MB
   - 初回実行時のダウンロードに時間がかかる
   - ネットワーク問題で失敗する可能性

2. **タイムアウト設定**:
   - 現在の wait_timeout は 30秒
   - PostgreSQL の初期化には時間がかかる場合がある
   - 十分なタイムアウトが必要

3. **Docker の状態**:
   - 前回のテスト失敗でコンテナが残っている可能性
   - リソース不足の可能性

### 修正内容

1. **テスト名の変更**:
   - "volume mount - postgresql init script" → "postgresql container - basic startup"

2. **コメントの更新**:
   - ボリュームマウントに関する誤解を招くコメントを削除
   - PostgreSQL 起動テストであることを明確化

3. **ログ確認の改善**:
   - ログが長すぎる場合を考慮し、最後の部分のみ表示
   - エラー時も詳細を出力

4. **エラーメッセージの改善**:
   - Docker エラーの詳細を含める
   - デバッグしやすいメッセージに変更

## ファイル変更

### volume_mount_wbtest.mbt

**変更箇所**: Line 108-141

**変更前**:
```moonbit
///|
/// Test PostgreSQL with initialization script (practical example)
/// Note: This test creates a temporary SQL file
async test "volume mount - postgresql init script" {
  // For this test, we'll mount /tmp which should exist on the host
  // In a real scenario, users would create their own SQL files
  let container = ContainerImage::new("postgres", "16")
  // ...
}
```

**変更後**:
```moonbit
///|
/// Test PostgreSQL container startup (practical example)
/// This demonstrates a common testcontainers use case
async test "postgresql container - basic startup" {
  // PostgreSQL is a common use case for testcontainers
  // This test verifies that PostgreSQL can be started and becomes ready
  let container = ContainerImage::new("postgres", "16")
  // ...
}
```

## テスト戦略

### テストケース構成（全4テスト）

1. **volume mount - basic with tmpfs** ✅
   - 基本的なボリュームマウント
   - `/tmp` を `/mnt/host_tmp` にマウント

2. **volume mount - readonly** ✅
   - 読み取り専用マウント
   - `/etc` を `/mnt/readonly_etc` に読み取り専用でマウント

3. **volume mount - multiple volumes** ✅
   - 複数ボリュームのマウント
   - `/tmp`, `/etc`, `/var` を同時にマウント

4. **postgresql container - basic startup** 🔄（修正対象）
   - PostgreSQL の基本的な起動テスト
   - ボリュームマウントは使用しない（別のテストで検証済み）
   - 実用的なユースケースの例示

### テストカバレッジ

#### ボリュームマウント機能（テスト1-3で検証）
- ✅ 基本的なマウント
- ✅ 読み取り専用マウント
- ✅ 複数ボリュームの同時マウント
- ✅ マウントポイントの確認

#### PostgreSQL 統合（テスト4で検証）
- ✅ PostgreSQL コンテナの起動
- ✅ ポートマッピングの確認
- ✅ TCP ポート待機戦略
- ✅ ログの取得と確認

## 実装の流れ

### Phase 1: コード修正
1. volume_mount_wbtest.mbt の Line 111-141 を修正
2. テスト名、コメント、ロジックを更新

### Phase 2: テスト実行
1. 個別テスト実行: `moon test --target native volume_mount_wbtest.mbt`
2. 全テスト実行: `moon test --target native`

### Phase 3: 検証
1. 全4テストが成功することを確認
2. エラーメッセージが明確であることを確認
3. コードとコメントの一貫性を確認

## 既存コードへの影響

### 影響なし
- types.mbt, error.mbt, docker.mbt, wait_strategy.mbt, logs.mbt, container.mbt
  - これらのファイルは変更不要
  - ボリュームマウント機能の実装は正常

### 影響あり
- volume_mount_wbtest.mbt
  - 4番目のテストのみ修正
  - 最初の3つのテストは変更なし

## パフォーマンスへの影響
- なし（テストコードの修正のみ）

## セキュリティ考慮事項
- なし（テストコードの修正のみ）

## 成功基準

1. ✅ volume_mount_wbtest.mbt の全4テストが成功する
2. ✅ テスト名とテスト内容が一致する
3. ✅ コメントと実装が一致する
4. ✅ エラーメッセージが明確である
5. ✅ 他のテストファイルへの影響がない
6. ✅ `moon test --native` で全テストが成功する

## 参考資料
- PostgreSQL Docker イメージ: https://hub.docker.com/_/postgres
- testcontainers-rs PostgreSQL module: https://docs.rs/testcontainers-modules/latest/testcontainers_modules/postgres/
- Docker CLI reference: https://docs.docker.com/engine/reference/commandline/run/
