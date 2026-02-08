# Steering: ボリュームマウントテストのエラー修正

## 作成日
2026-02-08

## 目的・背景

volume_mount_wbtest.mbtで以下の問題が発生している:

1. **PostgreSQL テスト (Line 111-141)**:
   - コメントには「mount /tmp」と書かれているが、実際には `with_volume()` が呼ばれていない
   - ボリュームマウントをテストしていない（単に PostgreSQL を起動しているだけ）

2. **Docker エラー**:
   - テスト統合実行時に「Error response from daemon: 404 page not found」が発生
   - volume_mount_wbtest.mbt:139 で PostgreSQL 起動失敗
   - 「RUNTIME ERROR: abort() called」

3. **成功しているテスト**:
   - basic_lifecycle_wbtest.mbt (4テスト) ✅
   - wait_strategies_wbtest.mbt (5テスト) ✅
   - volume_mount_wbtest.mbtの最初の3テスト（basic, readonly, multiple volumes）は成功

## ゴール

1. volume_mount_wbtest.mbtの4番目のテスト（PostgreSQL with init script）を修正し、実際にボリュームマウントをテストする
2. すべてのテストが個別・統合で成功することを確認する
3. エラーの根本原因を特定し、適切な修正を行う

## アプローチ

### Phase 1: 問題の調査

1. **PostgreSQL テストの現状確認**:
   - テスト名が「volume mount - postgresql init script」だが、実際にはボリュームマウントを使用していない
   - `with_volume()` メソッドの呼び出しが欠落している
   - コメントに「mount /tmp」と書かれているが、実装されていない

2. **Docker エラーの調査**:
   - 「Error response from daemon: 404 page not found」の原因を特定
   - 他のテストは成功しているため、PostgreSQL テスト固有の問題の可能性

3. **ログの確認**:
   - PostgreSQL コンテナが実際に起動しているか
   - get_logs() でエラーメッセージを取得
   - 「database system is ready」メッセージが含まれているか

### Phase 2: テストの修正

1. **PostgreSQL テストの設計を明確化**:
   - **オプション A**: ボリュームマウントを実際に使用する（テスト名に沿った実装）
     - ホストディレクトリに初期化スクリプト（.sql）を配置
     - `/docker-entrypoint-initdb.d` にマウント
     - 初期化スクリプトが実行されたことをログで確認
   - **オプション B**: テスト名を変更し、単純な PostgreSQL 起動テストにする
     - ボリュームマウントを使用しない
     - 単にコンテナが正常に起動するかをテスト

2. **推奨アプローチ（オプション A）**:
   - ボリュームマウント機能をテストする本来の目的に沿う
   - 一時ディレクトリに初期化スクリプトを作成
   - スクリプトをマウントしてコンテナを起動
   - ログでスクリプト実行を確認

3. **代替アプローチ（オプション B）**:
   - 複雑な初期化スクリプトの作成を避ける
   - 別の簡単なテストケースでボリュームマウントを確認
   - PostgreSQL テストは単純な起動テストに変更

### Phase 3: エラーハンドリングの改善

1. **エラーメッセージの改善**:
   - Docker エラーの詳細をログに出力
   - コンテナが起動しない場合の原因を特定しやすくする

2. **タイムアウトの調整**:
   - PostgreSQL の起動には時間がかかる可能性
   - wait_timeout を適切に設定（現在は30秒）

3. **クリーンアップの確認**:
   - テスト失敗時も確実にコンテナをクリーンアップ
   - リソースリークを防ぐ

## スコープ

### 含む

1. volume_mount_wbtest.mbtの4番目のテスト（PostgreSQL）の修正
2. テスト名とテストコードの整合性確保
3. Docker エラーの原因特定と修正
4. すべてのテストの成功確認

### 含まない

1. ボリュームマウントの基本機能の変更（既に実装済み、最初の3テストは成功）
2. PostgreSQL 以外のテストの変更（既に成功している）
3. 新機能の追加
4. パフォーマンス最適化

## 影響範囲

### 変更が必要なファイル

- **volume_mount_wbtest.mbt**: 4番目のテスト（Line 111-141）の修正

### 影響を受けないファイル

- types.mbt, error.mbt, docker.mbt, wait_strategy.mbt, logs.mbt, container.mbt
  - これらのファイルは既に正常に動作している
  - 最初の3つのボリュームマウントテストが成功していることから、実装自体は問題ない

## 技術的な考慮事項

### PostgreSQL の初期化スクリプト

PostgreSQL の公式イメージは `/docker-entrypoint-initdb.d` ディレクトリにマウントされた `.sql`, `.sh`, `.sql.gz` ファイルを自動的に実行する。

**使用例**:
```moonbit
// 一時ディレクトリに初期化スクリプトを作成
// 実際のテストでは、既存のディレクトリ（/tmp など）を使用

let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "testdb")
  .with_volume("/path/to/init/scripts", "/docker-entrypoint-initdb.d")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .with_wait_timeout(30)
  .start()
```

### MoonBit でのファイル操作

- MoonBit の `@async/fs` パッケージでファイル作成が可能
- または、既存のディレクトリ（`/tmp`）を使用する方が簡単

### テスト戦略の選択

**推奨**: 最初の3つのテストでボリュームマウントの基本機能は確認済みなので、4番目のテストは以下のいずれかに変更する:

1. **実用的な例（推奨）**: PostgreSQL を起動し、ログで初期化完了を確認
   - ボリュームマウントは使用しない（既に他のテストで確認済み）
   - テスト名を「postgresql basic startup」に変更
   - 実用的なユースケースを示す

2. **フル機能テスト**: ボリュームマウントと PostgreSQL の組み合わせ
   - 一時スクリプトを作成してマウント
   - 複雑だが、完全な統合テストになる

## リスク

1. **PostgreSQL 起動の遅さ**:
   - イメージのダウンロードに時間がかかる可能性
   - タイムアウトの調整が必要かもしれない

2. **ファイルシステム操作**:
   - MoonBit でのファイル作成・削除が必要な場合、追加の実装が必要

3. **Docker の状態**:
   - 前回のテスト失敗でコンテナが残っている可能性
   - テスト開始前にクリーンアップを確認

## 成功基準

1. ✅ volume_mount_wbtest.mbtの全4テストが成功する
2. ✅ basic_lifecycle_wbtest.mbtの全4テストが成功する（既存）
3. ✅ wait_strategies_wbtest.mbtの全5テストが成功する（既存）
4. ✅ `moon test --native` で全テストが成功する
5. ✅ テスト名とテストコードの内容が一致している
6. ✅ エラーメッセージが明確で、問題の特定が容易
7. ✅ 完了ドキュメントが作成される

## 次のステップ

1. **調査フェーズ**:
   - PostgreSQL テストのコードを詳細に確認
   - Docker エラーの原因を特定
   - ログの確認

2. **修正フェーズ**:
   - テストコードの修正（オプション A または B）
   - エラーハンドリングの改善
   - コメントの更新

3. **検証フェーズ**:
   - 個別テストの実行
   - 統合テストの実行
   - すべてのテストケースの成功確認

4. **ドキュメント作成**:
   - 完了ドキュメントの作成
   - 変更内容の記録
