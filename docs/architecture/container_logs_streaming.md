# 技術設計: コンテナログのストリーミング機能

## 作成日
2026-02-08

## 概要

Docker コンテナのログをリアルタイムで取得・ストリーミングする機能を実装します。`docker logs` コマンドを活用し、MoonBit の `@process` パッケージを使用して非同期でログを処理します。

### 実現する機能

1. **基本的なログ取得**: コンテナの全ログを一度に取得
2. **リアルタイムストリーミング**: ログを行単位でストリーミング
3. **オプション指定**: タイムスタンプ、tail、follow などのオプションをサポート

## アーキテクチャ

### ファイル構成

すべての変更は既存ファイルに追加する形で実装します。新しいファイルは作成しません。

- **moonbit_test_containers.mbt**: ログ機能の実装
  - `LogOptions` 構造体の追加
  - `Container` の新しいメソッド追加
  - ヘルパー関数の追加

- **moonbit_test_containers_test.mbt**: テストコードの追加
  - ログ取得のテスト
  - ストリーミングのテスト

- **README.mbt.md**: ドキュメント更新
  - API リファレンスの追加
  - 使用例の追加

### コンポーネント設計

#### 1. LogOptions 構造体

ログ取得のオプションを定義します。

```moonbit
pub struct LogOptions {
  follow : Bool           // -f: follow log output (stream mode)
  timestamps : Bool       // -t: show timestamps
  tail : Option[Int]      // --tail N: show last N lines
  since : Option[String]  // --since: show logs since timestamp
  until : Option[String]  // --until: show logs until timestamp
}
```

**デフォルト値**:
```moonbit
pub fn LogOptions::default() -> LogOptions {
  {
    follow: false,
    timestamps: false,
    tail: None,
    since: None,
    until: None,
  }
}
```

**ビルダーメソッド**:
```moonbit
pub fn LogOptions::with_follow(self : LogOptions, follow : Bool) -> LogOptions
pub fn LogOptions::with_timestamps(self : LogOptions, timestamps : Bool) -> LogOptions
pub fn LogOptions::with_tail(self : LogOptions, lines : Int) -> LogOptions
pub fn LogOptions::with_since(self : LogOptions, timestamp : String) -> LogOptions
pub fn LogOptions::with_until(self : LogOptions, timestamp : String) -> LogOptions
```

#### 2. Container のログメソッド

##### 基本的なログ取得

```moonbit
/// Get all logs from the container
pub async fn Container::get_logs(
  self : Container
) -> Result[String, TestContainerError]
```

- `docker logs <container_id>` を実行
- `exec_docker` を使用
- 全ログを文字列として返す

##### オプション付きログ取得

```moonbit
/// Get logs with specified options
pub async fn Container::get_logs_with_options(
  self : Container,
  options : LogOptions
) -> Result[String, TestContainerError]
```

- `LogOptions` に基づいて Docker CLI 引数を構築
- `follow: true` の場合は `stream_logs` の使用を推奨（エラーを返すか、内部で切り替え）

##### ログストリーミング

```moonbit
/// Stream logs line by line with a callback
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options? : LogOptions = LogOptions::default()
) -> Result[Unit, TestContainerError]
```

- `docker logs -f <container_id>` を実行
- `@process.read_from_process()` を使用してパイプを作成
- 行単位でログを読み取り、コールバックを呼び出す

#### 3. ヘルパー関数

##### Docker CLI 引数の構築

```moonbit
/// Build docker logs command arguments from LogOptions
fn build_logs_args(container_id : String, options : LogOptions) -> Array[String]
```

- `LogOptions` の各フィールドを Docker CLI の引数に変換
- 例: `follow: true` → `"-f"`、`tail: Some(100)` → `"--tail", "100"`

##### 行単位のログ読み取り

```moonbit
/// Read logs line by line from a process output
async fn read_logs_line_by_line(
  reader : @process.ReadFromProcess,
  callback : (String) -> Unit
) -> Result[Unit, TestContainerError]
```

- `@io.Reader` の機能を使用して行単位で読み取り
- 各行を `callback` に渡す
- EOF に到達したら終了

## データフロー

### 基本的なログ取得 (`get_logs`)

```
Container
  ↓
get_logs()
  ↓
exec_docker(["logs", container_id])
  ↓
@process.collect_output_merged()
  ↓
Result[String, TestContainerError]
```

### ログストリーミング (`stream_logs`)

```
Container
  ↓
stream_logs(callback, options)
  ↓
build_logs_args(container_id, options)
  ↓
@process.read_from_process()  // パイプの作成
  ↓
@process.run("docker", args, stdout=pipe_write)  // プロセス起動
  ↓
read_logs_line_by_line(pipe_read, callback)  // 行単位で読み取り
  ↓
callback("log line 1")
callback("log line 2")
callback("log line 3")
...
  ↓
Result[Unit, TestContainerError]
```

### オプション付きログ取得 (`get_logs_with_options`)

```
Container
  ↓
get_logs_with_options(options)
  ↓
build_logs_args(container_id, options)
  ↓
if options.follow:
  error (use stream_logs instead)
else:
  exec_docker(args)
  ↓
  Result[String, TestContainerError]
```

## 技術的決定事項

### 1. ログストリーミングの実装方法

**決定**: `@process.read_from_process()` と `@process.run()` を組み合わせる

**理由**:
- `@process.read_from_process()` は stdout をパイプ経由で読み取る標準的な方法
- `@io.Reader` トレイトを実装しており、行単位の読み取りが可能
- 非同期で動作し、ブロッキングしない
- MoonBit の async エコシステムと統合されている

**代替案**:
- `@process.collect_output_merged()` の使用: プロセス終了まで待機するため、ストリーミングには不適切
- 独自のパイプ実装: 複雑でメンテナンスが困難

### 2. コールバック方式の採用

**決定**: 行ごとに `(String) -> Unit` 型のコールバックを呼び出す

**理由**:
- シンプルで理解しやすい
- ユーザーが柔軟にログ処理を実装可能
- メモリ効率が良い（全ログをメモリに保持しない）

**代替案**:
- Iterator パターン: MoonBit での実装が複雑
- Channel/Queue: 実装コストが高い

### 3. LogOptions の設計

**決定**: Builder パターンでオプションを設定

**理由**:
- 既存の `ContainerImage` と一貫性がある
- 可読性が高い
- デフォルト値の管理が容易

**代替案**:
- 個別の関数パラメータ: パラメータ数が多くなり、可読性が低下

### 4. follow オプションの扱い

**決定**: `follow: true` の場合は `stream_logs` の使用を推奨

**理由**:
- `get_logs_with_options` は文字列を返すため、無限ストリームには不適切
- `stream_logs` はコールバック方式で、無限ストリームに対応可能
- API の意図を明確にする

**実装**:
- `get_logs_with_options` で `follow: true` が指定された場合、エラーを返す
- エラーメッセージで `stream_logs` の使用を推奨

### 5. エラーハンドリング

**決定**: 既存の `TestContainerError` enum を拡張

**理由**:
- 既存のエラー型との一貫性
- `DockerCommandFailed` でログ関連エラーもカバー可能

**追加の検討**:
- 必要に応じて `LogStreamingFailed` などの新しいエラーバリアントを追加

### 6. 行の区切り処理

**決定**: `@io.Reader` の `read_line()` を使用

**理由**:
- 標準的な方法で、行単位の読み取りをサポート
- LF/CRLF の両方に対応
- バッファリングが効率的

**実装詳細**:
```moonbit
async fn read_logs_line_by_line(
  reader : @process.ReadFromProcess,
  callback : (String) -> Unit
) -> Result[Unit, TestContainerError] {
  try {
    loop {
      match reader.read_line() {
        Ok(line) => callback("\{line}")
        Err(@io.EOF) => break
        Err(e) => return Err(DockerCommandFailed("Failed to read log line: \{e}"))
      }
    }
    Ok(())
  } catch {
    e => Err(DockerCommandFailed("Log streaming error: \{e.to_string()}"))
  }
}
```

## 実装時の注意事項

### 1. Async 関数の統合

- すべてのログ関連メソッドは `async fn` として実装
- `@process.run()` は async 関数のため、呼び出し側も async である必要がある
- テストコードでは `@async.run` または `@test.async` を使用

### 2. リソース管理

- `@process.ReadFromProcess` はリソースを保持するため、使用後に `close()` を呼び出す
- `try-finally` パターンでクリーンアップを保証（MoonBit が finally をサポートしている場合）
- プロセスが終了すると、パイプも自動的にクローズされる

### 3. エラーハンドリング

- `docker logs` コマンドのエラーは `exec_docker` / `@process.run` でキャッチ
- パイプの読み取りエラーは `@io.EOF` と区別して処理
- コールバック内でのエラーは呼び出し元で処理（コールバックは Unit を返す）

### 4. パフォーマンス考慮

- ログのストリーミングは長時間実行される可能性がある
- コールバックは軽量な処理にすることを推奨（ドキュメントに記載）
- バッファリングは `@io.Reader` が内部で処理

### 5. Docker CLI の互換性

- `docker logs` のオプションは Docker のバージョンによって異なる場合がある
- 基本的なオプション（`-f`, `-t`, `--tail`）はほぼすべてのバージョンでサポート
- `--since` と `--until` は比較的新しい機能（Docker 1.13+）

### 6. テストの実装

- 実際のコンテナを使用した統合テストを実装
- 短いログを出力するコンテナを使用（例: `alpine` + `echo` コマンド）
- ストリーミングのテストでは、有限のログ出力で終了することを確認

## MoonBit の @process API の使用方法

### 基本的なパターン

#### パイプの作成と使用

```moonbit
// 1. パイプの作成
let (reader, writer) = @process.read_from_process()

// 2. プロセスの起動（writer をstdoutに渡す）
let exit_code = @process.run(
  "docker",
  ["logs", "-f", container_id],
  stdout=writer
)

// 3. パイプから読み取り
loop {
  match reader.read_line() {
    Ok(line) => {
      // 行を処理
      callback("\{line}")
    }
    Err(@io.EOF) => break
    Err(e) => {
      // エラー処理
      return Err(DockerCommandFailed("\{e}"))
    }
  }
}

// 4. クリーンアップ
reader.close()
```

#### collect_output_merged の使用（非ストリーミング）

```moonbit
// シンプルな一括取得
let (exit_code, output) = @process.collect_output_merged(
  "docker",
  ["logs", container_id]
)

if exit_code == 0 {
  Ok("\{output.text()}")
} else {
  Err(DockerCommandFailed("\{output.text()}"))
}
```

### @io.Reader の使用

`ReadFromProcess` は `@io.Reader` トレイトを実装しているため、以下のメソッドが使用可能:

- `read_line()`: 1行読み取り（改行文字を含まない）
- `read_bytes(n)`: n バイト読み取り
- `read_all()`: EOF まで読み取り

## 実装の段階的アプローチ

### Phase 1: 基本的なログ取得（優先度: 高）

1. `Container::get_logs()` の実装
   - `exec_docker` を使用
   - シンプルな `docker logs <id>` の実行

2. テストの実装
   - Alpine コンテナで `echo "test"` を実行
   - ログ取得を確認

### Phase 2: オプションサポート（優先度: 中）

1. `LogOptions` 構造体の定義
2. `build_logs_args()` ヘルパー関数の実装
3. `Container::get_logs_with_options()` の実装
4. テストの追加

### Phase 3: ログストリーミング（優先度: 高）

1. `read_logs_line_by_line()` ヘルパー関数の実装
2. `Container::stream_logs()` の実装
3. 統合テストの実装（Redis コンテナなど）

### Phase 4: ドキュメント更新（優先度: 高）

1. README.mbt.md の更新
2. 使用例の追加
3. API リファレンスの更新

## 参考資料

### Docker CLI

- [docker logs command reference](https://docs.docker.com/engine/reference/commandline/logs/)
  - オプションの詳細
  - 出力フォーマット

### MoonBit

- [moonbitlang/async - process package](https://github.com/moonbitlang/async)
  - `@process.read_from_process()` の使用方法
  - `@io.Reader` トレイトの仕様

### 他言語の実装

- [testcontainers-rs - logs API](https://docs.rs/testcontainers/latest/testcontainers/)
  - Rust での実装例
- [testcontainers-go - logs support](https://github.com/testcontainers/testcontainers-go)
  - Go での実装例

## まとめ

### 技術スタック

- **言語**: MoonBit
- **外部コマンド**: Docker CLI (`docker logs`)
- **プロセス管理**: `moonbitlang/async/process`
- **I/O 処理**: `@io.Reader` トレイト

### 設計原則

1. **シンプルさ**: 既存の `@process` API を最大限活用
2. **一貫性**: 既存コードのパターンに従う（Builder パターン、async 関数）
3. **柔軟性**: コールバック方式でユーザーが自由にログ処理を実装可能
4. **効率性**: ストリーミングでメモリ使用量を最小化

### 次のステップ

このアーキテクチャ設計に基づいて:
1. テストアーキテクトがテスト戦略を策定
2. コーダーが実装を行う
3. レビュアーがコードレビューを実施
