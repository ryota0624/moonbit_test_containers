# Steering: テストファイルの分割

## 目的・背景

現在、すべてのテストが `moonbit_test_containers_wbtest.mbt` という1つのファイル（約830行）にまとまっている。これを機能ごとに複数のファイルに分割し、テストの保守性と可読性を向上させる必要がある。

テストファイルを分割することで以下のメリットが得られる。
- 各機能のテストが独立して実行可能になる
- テストの内容が理解しやすくなる
- 問題が発生した際に該当するテストファイルを特定しやすくなる
- 並列テスト実行の可能性が広がる

## ゴール

- テストファイルを機能ごとに5つのファイルに分割
- 各テストファイルが独立して実行可能であることを確認
- 各テストファイルで `moon test --target native --file <ファイル名>` を実行して成功を確認
- すべてのテストファイルをまとめて実行（`moon test --target native`）しても成功することを確認

## アプローチ

### ファイル分割方針

テストを機能ごとに以下の5つのファイルに分割する。

1. **basic_lifecycle_wbtest.mbt** (行6-122)
   - redis container lifecycle
   - container with env vars
   - stop and remove container
   - invalid image error handling

2. **wait_strategies_wbtest.mbt** (行124-255)
   - wait strategy tcp port
   - wait strategy seconds
   - wait strategy http get
   - wait strategy http get custom path
   - wait strategy http get no ports

3. **logs_basic_wbtest.mbt** (行257-370)
   - get_logs - basic
   - get_logs - multiple lines
   - get_logs - empty log
   - get_logs - unicode characters

4. **logs_advanced_wbtest.mbt** (行372-528)
   - get_logs_with_options - tail
   - get_logs_with_options - timestamps
   - get_logs_with_options - follow error

5. **logs_streaming_wbtest.mbt** (行530-690)
   - stream_logs - basic
   - stream_logs - callback count
   - stream_logs - redis container

6. **volume_mount_wbtest.mbt** (行692-830)
   - volume mount - basic with tmpfs
   - volume mount - readonly
   - volume mount - multiple volumes
   - volume mount - postgresql init script

### 実装手順

1. Steeringドキュメントの作成（このドキュメント）
2. 各テストファイルの作成（元ファイルから該当部分をコピー）
3. 各テストファイルで個別にテスト実行して確認
   - `moon test --target native --file basic_lifecycle_wbtest.mbt`
   - `moon test --target native --file wait_strategies_wbtest.mbt`
   - `moon test --target native --file logs_basic_wbtest.mbt`
   - `moon test --target native --file logs_advanced_wbtest.mbt`
   - `moon test --target native --file logs_streaming_wbtest.mbt`
   - `moon test --target native --file volume_mount_wbtest.mbt`
4. すべてのテストをまとめて実行して確認
   - `moon test --target native`
5. 元のmoonbit_test_containers_wbtest.mbtの削除
6. moon fmtでフォーマット
7. 完了ドキュメントの作成

## スコープ

### 含む

- 6つのテストファイルへの分割
- 各テストファイルの個別実行確認
- すべてのテストファイルの統合実行確認
- フォーマットの実行

### 含まない

- テスト内容の変更や追加
- テストロジックの修正
- 実装コードの変更

## 影響範囲

- moonbit_test_containers_wbtest.mbt（削除）
- 新規ファイル6つ
  - basic_lifecycle_wbtest.mbt
  - wait_strategies_wbtest.mbt
  - logs_basic_wbtest.mbt
  - logs_advanced_wbtest.mbt
  - logs_streaming_wbtest.mbt
  - volume_mount_wbtest.mbt
- 実装コード（types.mbt, docker.mbt等）は影響なし

## 技術的な考慮事項

### MoonBitのテストファイル命名規則

- ホワイトボックステスト: `*_wbtest.mbt`
- ブラックボックステスト: `*_test.mbt`

今回はホワイトボックステストのため、全て `_wbtest.mbt` で終わる。

### テストの独立性

各テストは以下の特徴を持つ。
- Dockerコンテナを起動・停止する独立したテスト
- async testとして実行される
- テスト終了時にcleanup()を呼び出してコンテナを削除
- 他のテストに依存しない

したがって、ファイルを分割しても各テストは独立して実行可能である。

### ブロック区切り

MoonBitのコーディング規約に従い、各テスト関数は ///| で区切る。

## リスク

- ファイル分割後のテスト実行でエラーが発生する可能性 → 各ファイルを個別に実行して確認
- Docker環境に依存するため、実行環境によってはテストが失敗する可能性 → Docker起動を確認
- 非同期テストのため、タイムアウトが発生する可能性 → 適切な待機時間を設定済み

## 成功基準

1. 6つのテストファイルが作成され、元のファイルが削除されている
2. 各テストファイルが個別に実行でき、すべてのテストがパスする
   - `moon test --target native --file <ファイル名>` で成功
3. すべてのテストファイルをまとめて実行して成功する
   - `moon test --target native` で成功
4. moon fmtがエラーなく実行できる
5. 完了ドキュメントが作成されている
