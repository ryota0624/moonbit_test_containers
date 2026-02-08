# Steering: moonbit_test_containers.mbtのファイル分割

## 目的・背景

現在のmoonbit_test_containers.mbtは約616行あり、以下の複数の責務が混在している。

- 型定義（WaitStrategy, TestContainerError, ContainerImage, Container, LogOptions）
- エラーハンドリング（TestContainerError::to_string）
- Docker CLI実行（exec_docker, parse_port_mapping）
- 待機戦略の実装（wait_for_tcp_port, wait_for_http_endpoint等）
- ログ関連機能（get_logs, stream_logs等）
- コンテナ管理（start, stop, remove等）

コードの保守性と可読性を向上させるため、責務ごとにファイルを分割する必要がある。

## ゴール

- 責務ごとに明確に分割された6つのファイル構成
- 既存の機能を維持したまま、テストが全てパスする状態
- moon fmt, moon infoの実行により、フォーマットと型情報が適切に更新される
- ブロック区切り（///|）が適切に配置される

## アプローチ

### ファイル分割方針

1. **types.mbt** (行1-147)
   - WaitStrategy enum
   - TestContainerError enum
   - LogOptions struct + メソッド
   - ContainerImage struct + メソッド
   - Container struct

2. **error.mbt** (行20-29)
   - TestContainerError::to_string

3. **docker.mbt** (行149-166, 539-569)
   - exec_docker
   - parse_port_mapping

4. **wait_strategy.mbt** (行168-315)
   - check_tcp_port
   - check_http_endpoint
   - wait_for_tcp_port
   - wait_for_http_endpoint
   - wait_for_container

5. **logs.mbt** (行318-444)
   - build_logs_args
   - Container::get_logs
   - Container::get_logs_with_options
   - read_logs_line_by_line
   - Container::stream_logs

6. **container.mbt** (行447-616)
   - ContainerImage::start
   - Container::update_port_mappings
   - Container::get_host_port
   - Container::get_id
   - Container::stop
   - Container::remove
   - Container::cleanup

### ブロック区切り配置

- types.mbtは複数のブロックに分割（WaitStrategy/TestContainerError、LogOptions、ContainerImage/Container）
- 他のファイルは単一ブロックまたは機能ごとのブロック分け
- ///| を使用して各ブロックを明確に区切る

### 実装手順

1. steeringドキュメントの作成
2. 各ファイルの作成（元ファイルから該当部分をコピー＆編集）
3. 元のmoonbit_test_containers.mbtの削除
4. moon fmt でフォーマット
5. moon info で型情報更新
6. moon test --native でテスト実行
7. 完了ドキュメントの作成

## スコープ

### 含む

- 6つのファイルへの分割
- ブロック区切りの適切な配置
- フォーマットと型情報の更新
- テストの実行確認

### 含まない

- 機能の追加や変更
- テストコードの変更
- パフォーマンス最適化

## 影響範囲

- moonbit_test_containers.mbt（削除）
- 新規ファイル6つ（types.mbt, error.mbt, docker.mbt, wait_strategy.mbt, logs.mbt, container.mbt）
- .mbti（型情報ファイル、自動生成）
- テストファイル（moonbit_test_containers_wbtest.mbt）は影響なし（パブリックAPIは不変）

## 技術的な考慮事項

### 依存関係

- types.mbtは他の全てのファイルから参照される基盤
- error.mbtはtypes.mbtに依存
- docker.mbtはtypes.mbtに依存
- wait_strategy.mbtはtypes.mbt, docker.mbtに依存
- logs.mbtはtypes.mbt, docker.mbtに依存
- container.mbtはtypes.mbt, docker.mbt, wait_strategy.mbtに依存

MoonBitでは同一パッケージ内のファイルはお互いに参照可能なため、特別なimport文は不要。

### ブロック区切り

MoonBitのコーディング規約に従い、各ファイルで論理的なブロックを///|で区切る。
- 型定義とメソッド実装は別ブロックにする場合がある
- 関連する関数群は同じブロック内にまとめる

## リスク

- ファイル分割によるコンパイルエラーの可能性 → moon infoで即座に検出可能
- テストの失敗 → moon test --nativeで確認
- フォーマットの崩れ → moon fmtで自動修正

## 成功基準

1. 6つのファイルが作成され、元のファイルが削除されている
2. moon fmtがエラーなく実行できる
3. moon infoがエラーなく実行でき、.mbtiに予期しない変更がない
4. moon test --nativeで全てのテストがパスする
5. 完了ドキュメントが作成されている
