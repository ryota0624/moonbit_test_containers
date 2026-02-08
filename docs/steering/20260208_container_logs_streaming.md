# Steering: コンテナログのストリーミング機能実装

## 作成日
2026-02-08

## 目的・背景

### なぜこの機能が必要か

現在のtestcontainersの実装では、コンテナの起動・停止・ポートマッピングは実装されていますが、**コンテナのログをリアルタイムで取得する機能**がありません。

統合テストにおいて、コンテナのログは以下の理由で重要です:

1. **デバッグの効率化**: テストが失敗した際、コンテナのログを確認することで問題の原因を特定できる
2. **Wait Strategy の強化**: ログメッセージを監視して、コンテナの準備完了を判定できる（例: "ready to accept connections"）
3. **テストの可視性向上**: コンテナの動作状況をリアルタイムで確認できる
4. **エラー診断の改善**: コンテナ内で発生したエラーメッセージを即座に確認できる

### 解決しようとしている問題

- **現状**: コンテナが起動しても、内部で何が起きているか分からない
- **問題**: テスト失敗時に原因究明が困難
- **課題**: ログベースのWait Strategyが実装できない

## ゴール

### 作業完了時に達成されるべき状態

1. **基本的なログ取得機能**
   - `docker logs`コマンドを使用してコンテナログを取得できる
   - ログを文字列として返す機能を実装

2. **ログストリーミング機能**
   - `docker logs -f`を使用してリアルタイムでログをストリーミングできる
   - ログ行ごとにコールバック関数を呼び出す仕組み

3. **ログオプションのサポート**
   - ログの取得範囲を指定できる（最新N行、特定の時刻以降など）
   - stdout/stderrの区別をサポート
   - タイムスタンプの表示切り替え

4. **テストコード**
   - ログ取得機能の動作を確認するテストを実装
   - 実際のコンテナ（例: Redis, PostgreSQL）を使った統合テスト

### 成功の基準

- ✅ コンテナのログを取得できる
- ✅ リアルタイムでログをストリーミングできる
- ✅ ログ行ごとの処理が可能
- ✅ エラーハンドリングが適切に実装されている
- ✅ テストが全てパスする

## アプローチ

### 採用する技術的アプローチ

#### 1. Docker CLI の活用

既存の`exec_docker`関数を拡張し、ログ取得に対応:

```moonbit
// 基本的なログ取得
async fn Container::get_logs(self : Container) -> Result[String, TestContainerError]

// リアルタイムストリーミング（コールバック方式）
async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit
) -> Result[Unit, TestContainerError]
```

#### 2. ストリーミング実装

`docker logs -f`を使用して、`@process`パッケージで行単位の出力を処理:

- `@process.spawn`でプロセスを起動
- stdoutを行単位で読み取り
- 各行をコールバック関数に渡す
- コンテナ停止時にストリーミングを終了

#### 3. ログオプション

設定可能なオプションを構造体で定義:

```moonbit
pub struct LogOptions {
  follow : Bool           // -f: follow log output
  timestamps : Bool       // -t: show timestamps
  tail : Option[Int]      // --tail N: show last N lines
  since : Option[String]  // --since: show logs since timestamp
  stdout : Bool           // include stdout
  stderr : Bool           // include stderr
}
```

### 主要な実装方針

1. **段階的実装**
   - Phase 1: 基本的なログ取得（`docker logs`）
   - Phase 2: ログストリーミング（`docker logs -f`）
   - Phase 3: オプションのサポート

2. **既存コードとの統合**
   - `Container`構造体に新しいメソッドを追加
   - 既存の`exec_docker`関数を活用
   - エラーハンドリングの一貫性を保つ

3. **Async/Awaitの活用**
   - 全てのログ操作をasync関数として実装
   - `@process`パッケージの非同期APIを使用

## スコープ

### 含むもの

1. **ログ取得API**
   - `Container::get_logs()`: 全ログを取得
   - `Container::stream_logs(callback)`: ストリーミング
   - `Container::get_logs_with_options(options)`: オプション指定

2. **ログオプション**
   - `LogOptions`構造体の定義
   - 各オプションのDocker CLIへのマッピング

3. **エラーハンドリング**
   - ログ取得失敗時のエラー処理
   - ストリーミング中断時の処理

4. **テストコード**
   - ログ取得の基本テスト
   - ストリーミングのテスト
   - オプション指定のテスト

5. **ドキュメント**
   - READMEへのAPI追加
   - 使用例の記載

### 含まないもの

1. **ログのフィルタリング**
   - grep相当の正規表現フィルタ（将来の拡張項目）

2. **ログの保存機能**
   - ファイルへの自動保存（ユーザー側で実装可能）

3. **ログのパース処理**
   - JSON形式のログ解析（将来の拡張項目）

4. **Wait Strategy の拡張**
   - ログベースのWait Strategyは別タスクとして実装

5. **複数コンテナの同時ログ取得**
   - 将来の拡張項目

## 影響範囲

### 変更が影響するファイル

#### 追加予定のファイル

1. **docs/steering/container_logs_streaming.md** (本ドキュメント)
   - 実装のSteeringドキュメント

2. **docs/completed/container_logs_streaming.md** (作業完了後)
   - 完了報告ドキュメント

#### 変更予定のファイル

1. **moonbit_test_containers.mbt**
   - `LogOptions`構造体の追加
   - `Container::get_logs()`メソッドの追加
   - `Container::stream_logs()`メソッドの追加
   - `Container::get_logs_with_options()`メソッドの追加
   - ヘルパー関数の追加

2. **moonbit_test_containers_test.mbt**
   - ログ取得機能のテストケース追加
   - ストリーミング機能のテストケース追加
   - オプション指定のテストケース追加

3. **README.mbt.md**
   - API Referenceセクションにログ関連APIを追加
   - 使用例の追加
   - Future Enhancements から「Container logs streaming」を削除

4. **moon.pkg.json**
   - 必要に応じて追加の依存関係（現時点では不要の見込み）

### 他の機能への影響

#### 直接影響するもの

- **Container構造体**: 新しいメソッドが追加される
- **TestContainerErrorEnum**: ログ関連のエラーが追加される可能性

#### 間接的な影響

- **Wait Strategy機能**: 将来的にログベースのWait Strategyの基盤となる
- **デバッグ機能**: テストの診断が容易になる

#### 影響なし

- **ContainerImage**: 変更なし
- **ポートマッピング機能**: 変更なし
- **既存のテスト**: 既存のテストには影響なし

## 技術的な検討事項

### MoonBit の @process API

#### 既知の情報

- `@process.collect_output_merged(command, args)`: 完了まで待機して出力を取得
- async関数として動作
- 戻り値: `(status: Int, output: ProcessOutput)`

#### 調査が必要な項目

- `@process.spawn()`: プロセスを非同期で起動（ストリーミング用）
- プロセスのstdoutを行単位で読み取る方法
- プロセスの強制終了方法（ストリーミング停止時）

### Docker CLIコマンド

#### 使用予定のコマンド

```bash
# 全ログを取得
docker logs <container-id>

# リアルタイムでフォロー
docker logs -f <container-id>

# オプション付き
docker logs --tail 100 --timestamps -f <container-id>
```

#### オプション

- `-f, --follow`: ログ出力をフォロー
- `-t, --timestamps`: タイムスタンプを表示
- `--tail N`: 最新N行のみ表示
- `--since <timestamp>`: 指定時刻以降のログを表示

### エラーケース

1. **コンテナが存在しない**: `ContainerNotFound`
2. **Docker CLIエラー**: `DockerCommandFailed`
3. **ストリーミング中断**: 適切なクリーンアップ処理

## 実装の優先順位

### Phase 1: 基本的なログ取得（高優先度）

1. `Container::get_logs()`の実装
2. 基本的なテストコード
3. エラーハンドリング

### Phase 2: ログストリーミング（高優先度）

1. `Container::stream_logs()`の実装
2. コールバック方式の実装
3. ストリーミングのテスト

### Phase 3: オプションサポート（中優先度）

1. `LogOptions`構造体の定義
2. `Container::get_logs_with_options()`の実装
3. オプションのテスト

### Phase 4: ドキュメント更新（高優先度）

1. READMEの更新
2. 使用例の追加
3. 完了ドキュメントの作成

## リスクと対策

### リスク1: ストリーミング実装の複雑性

**リスク**: `@process`パッケージでの行単位の読み取りが複雑になる可能性

**対策**:
- まず基本的なログ取得を実装
- `@process`のドキュメントとサンプルコードを調査
- 必要に応じて段階的に実装

### リスク2: Async関数の統合

**リスク**: async関数とコールバックの統合が難しい可能性

**対策**:
- 既存の`wait_for_container`実装を参考にする
- シンプルなコールバック方式から始める

### リスク3: テストの実装

**リスク**: 非同期ストリーミングのテストが複雑になる可能性

**対策**:
- 実際のコンテナを使った統合テストを実装
- 小さなログ出力から始める（例: `echo`コマンド）

## 参考資料

### Docker CLI

- [Docker logs command reference](https://docs.docker.com/engine/reference/commandline/logs/)

### MoonBit

- [moonbitlang/async GitHub](https://github.com/moonbitlang/async)
- [moonbitlang/async/process documentation](https://mooncakes.io/docs/#/moonbitlang/async/process/)

### 他言語の実装

- [testcontainers-rs logs API](https://docs.rs/testcontainers/latest/testcontainers/)
- [testcontainers-go logs support](https://github.com/testcontainers/testcontainers-go)

## 次のステップ

1. **ソフトウェアアーキテクトへの依頼**
   - ログ取得・ストリーミングの詳細設計
   - `@process`パッケージの調査と実装方針の策定

2. **テストアーキテクトへの依頼**
   - テスト戦略の策定
   - 統合テストの設計

3. **コーダーへの依頼**
   - アーキテクトの方針に基づいた実装

4. **レビュアーへの依頼**
   - コードレビューと品質確認

---

このSteeringドキュメントは、コンテナログのストリーミング機能実装の指針として使用します。
