# Testcontainers MoonBit実装の調査結果

## 調査日
2026-02-07

## 概要

このドキュメントは、MoonBit言語でtestcontainersライブラリを実装するための技術調査の結果をまとめたものです。testcontainersの基本概念、他言語での実装パターン、MoonBitの技術的機能、Docker操作の要件を調査しました。

---

## 1. Testcontainersとは

### 1.1 定義

[Testcontainers](https://testcontainers.com/)は、テスト時にDockerコンテナを簡単に起動・管理できるオープンソースライブラリです。データベース、メッセージブローカー、その他のサービスをDockerコンテナとして実行し、統合テストの品質と再現性を向上させます。

### 1.2 主要な利点

1. **本番環境と同じサービスを使用**
   - モックやインメモリサービスではなく、本番と同じデータベースやサービスを使用してテスト可能

2. **自動クリーンアップ**
   - テスト実行後、作成されたリソース（コンテナ、ボリューム、ネットワーク）を自動的に削除
   - テストが成功・失敗に関わらず、確実にクリーンアップを実行

3. **Wait Strategies（待機戦略）**
   - コンテナとその内部のアプリケーションが完全に初期化されるまで待機する機能
   - ログメッセージ、ポート開放、HTTPレスポンスなど、様々な待機条件に対応

4. **ネットワーキング**
   - コンテナのポートをホストマシンのランダムポートにマッピング
   - 複数のコンテナをDockerネットワークで接続可能

### 1.3 対応言語

Java、.NET、Go、Node.js、Python、Rust、Haskellなど、多くの言語で実装が存在します。

参考: [Testcontainers公式サイト](https://testcontainers.com/)

---

## 2. 他言語での実装例

### 2.1 Rust実装

[testcontainers-rs](https://github.com/testcontainers/testcontainers-rs)は、Rust言語の公式実装です。

#### 実装例

```rust
use testcontainers::{
    core::{IntoContainerPort, WaitFor},
    runners::SyncRunner,
    GenericImage,
    ImageExt
};

#[test]
fn test_redis() {
    let container = GenericImage::new("redis", "7.2.4")
        .with_exposed_port(6379.tcp())
        .with_wait_for(WaitFor::message_on_stdout("Ready to accept connections"))
        .with_network("bridge")
        .with_env_var("DEBUG", "1")
        .start()
        .expect("Failed to start Redis");
}
```

#### 特徴

- **Builder パターン**: `ImageExt`トレイトによるフルエントAPI
- **ランナーの分離**: `SyncRunner`と`AsyncRunner`の2種類のランナー
- **モジュールシステム**: コアライブラリと`testcontainers-modules`を分離
  - `GenericImage`: 汎用的なコンテナ
  - モジュール: Postgres、Redis、Kafkaなど、特定サービス向けの実装

参考: [Testcontainers for Rust](https://rust.testcontainers.org/)

### 2.2 Go実装

[testcontainers-go](https://github.com/testcontainers/testcontainers-go)は、Go言語の公式実装です。

#### 特徴

- シンプルで直感的なAPI
- コンテナの定義と実行をプログラマティックに制御
- テスト完了後のリソース自動クリーンアップ

参考: [Testcontainers for Go](https://golang.testcontainers.org/)

### 2.3 アーキテクチャの共通パターン

他言語の実装から共通するアーキテクチャパターンを抽出：

1. **Image定義レイヤー**
   - どのコンテナを実行するかを定義（イメージ名、タグ）

2. **設定レイヤー**
   - ポート、環境変数、ボリューム、ネットワークなどの設定
   - Builder/Fluent APIパターンの使用

3. **実行レイヤー**
   - コンテナの起動と管理
   - 同期/非同期実行のサポート

4. **Wait Strategies**
   - コンテナの準備完了を検出する仕組み

5. **リソース管理**
   - コンテナの自動停止とクリーンアップ

---

## 3. MoonBitの技術的機能

### 3.1 外部プロセス実行

MoonBitは`moonbitlang/async`ライブラリを通じて外部プロセスの実行をサポートしています。

#### `@process.collect_output_merged`

外部プログラムを実行し、出力（stdoutとstderrをマージ）を収集します。

```moonbit
let (status, output) = @process.collect_output_merged(
  command,
  arguments.map(fn(arg) { arg }),
)
let output_text = output.text()
```

- **戻り値**: `(status, output)`のタプル
- **status**: 終了ステータス
- **output**: 出力オブジェクト（`.text()`でテキストとして取得）

#### `@process.run`

より細かい制御が必要な場合、`@process.run`でstdin、stdout、stderrを個別に管理できます。

参考:
- [Write a Simple Code Agent using moonbitlang/async](https://www.moonbitlang.com/blog/moonbit-async-code-agent)
- [moonbitlang/async GitHub](https://github.com/moonbitlang/async)

### 3.2 FFI (Foreign Function Interface)

MoonBitは複数のバックエンドでFFIをサポートしています：

#### C-FFI

```moonbit
extern "C" fn moonbit_function_name(arg: Type) -> ReturnType = "c_function_name"
```

- 基本型の直接マッピング（`Int` ↔ `int32_t`、`Double` ↔ `double`）
- ポインタ処理（`Ref[T]`、`FixedArray[T]`）
- 不透明型（opaque types）のサポート

参考: [A Guide to MoonBit C-FFI](https://www.moonbitlang.com/pearls/moonbit-cffi)

#### その他のバックエンド

- **JavaScript**: JavaScript関数の呼び出し
- **WebAssembly**: Wasm関数のインポート

参考: [Foreign Function Interface (FFI)](https://docs.moonbitlang.com/en/latest/language/ffi.html)

### 3.3 ファイルシステム操作

`moonbitlang/async`ライブラリはファイルシステム操作もサポート：

- `@fs.read_text_file`: ファイル読み込み
- `@fs.write_text_file`: ファイル書き込み
- `@fs.open`: カスタムオプション付きファイルオープン

### 3.4 非同期プログラミング

MoonBitは非同期プログラミングをサポートしています。

参考: [Introducing Async Programming in MoonBit](https://www.moonbitlang.com/blog/moonbit-async)

---

## 4. Docker操作の要件

### 4.1 基本的なライフサイクルコマンド

testcontainersの実装に必要な主要なDockerコマンド：

#### コンテナ起動

```bash
docker run [options] <image>:<tag>
```

主要なオプション：
- `-d`: デタッチモード（バックグラウンド実行）
- `-p <host_port>:<container_port>`: ポートマッピング
- `-e <KEY>=<VALUE>`: 環境変数設定
- `--name <name>`: コンテナ名指定
- `--network <network>`: ネットワーク指定
- `--rm`: 終了時に自動削除

#### コンテナ停止

```bash
docker stop [options] <container_id_or_name>
```

- `-t, --time <seconds>`: タイムアウト時間（デフォルト: 10秒）
- 動作: SIGTERMシグナル送信 → タイムアウト後にSIGKILL

#### コンテナ強制停止

```bash
docker kill <container_id_or_name>
```

- 即座にSIGKILLシグナルを送信

#### コンテナ削除

```bash
docker rm <container_id_or_name>
```

- 停止したコンテナを削除
- 注意: 停止しただけではコンテナは残る

#### コンテナ情報取得

```bash
docker inspect <container_id_or_name>
docker port <container_id_or_name>
docker logs <container_id_or_name>
```

参考:
- [Docker Container Lifecycle Management](https://k21academy.com/kubernetes/docker-container-lifecycle-management/)
- [Docker CLI Documentation](https://docs.docker.com/reference/cli/docker/)

### 4.2 ポートマッピング

testcontainersでは、コンテナのポートをホストのランダムポートにマッピングします。

```bash
# ランダムポート割り当て
docker run -d -P <image>

# マッピングされたポートの確認
docker port <container_id>
```

### 4.3 ネットワーク

複数のコンテナを接続する場合、Dockerネットワークを使用：

```bash
docker network create <network_name>
docker run --network <network_name> <image>
```

---

## 5. MoonBitでの実装方針

### 5.1 実装アプローチ

MoonBitでtestcontainersを実装するための推奨アプローチ：

#### アプローチ1: Docker CLIラッパー（推奨）

**概要**: `@process.collect_output_merged`を使用してDocker CLIコマンドを実行

**利点**:
- 実装が簡単（外部プロセス実行のみ）
- Docker CLIの機能をすべて利用可能
- メンテナンスが容易

**欠点**:
- Docker CLIのインストールが必須
- パフォーマンスが多少劣る可能性

**実装例**:

```moonbit
pub fn docker_run(image: String, args: Array[String]) -> Result[String, String] {
  let command = "docker"
  let mut full_args = ["run", "-d"]
  full_args.append(args)
  full_args.push(image)

  let (status, output) = @process.collect_output_merged(command, full_args)
  let output_text = output.text()

  if status.success() {
    Ok(output_text.trim())  // コンテナID
  } else {
    Err(output_text)
  }
}

pub fn docker_stop(container_id: String) -> Result[Unit, String] {
  let (status, output) = @process.collect_output_merged(
    "docker",
    ["stop", container_id]
  )

  if status.success() {
    Ok(())
  } else {
    Err(output.text())
  }
}

pub fn docker_rm(container_id: String) -> Result[Unit, String] {
  let (status, output) = @process.collect_output_merged(
    "docker",
    ["rm", container_id]
  )

  if status.success() {
    Ok(())
  } else {
    Err(output.text())
  }
}
```

#### アプローチ2: Docker Engine APIの直接利用

**概要**: Docker Engine APIにHTTPリクエストを送信

**利点**:
- Docker CLIが不要
- より細かい制御が可能
- パフォーマンスが良い

**欠点**:
- 実装が複雑
- HTTPクライアントライブラリが必要
- APIバージョン管理が必要

**現状の制約**:
- MoonBitのHTTPクライアントライブラリの成熟度を確認する必要がある

### 5.2 推奨API設計

Rustの実装を参考にした、MoonBit向けのAPI設計：

```moonbit
// コンテナイメージの定義
pub struct ContainerImage {
  name: String
  tag: String
  exposed_ports: Array[Int]
  env_vars: Map[String, String]
  wait_strategy: Option[WaitStrategy]
}

// Wait Strategy
pub enum WaitStrategy {
  LogMessage(String)
  HttpStatusCode(Int, String)  // port, path
  TcpPort(Int)
  Delay(Int)  // milliseconds
}

// コンテナインスタンス
pub struct Container {
  id: String
  image: ContainerImage
  host_port: Int
}

// Builder パターン
pub impl ContainerImage {
  pub fn new(name: String, tag: String) -> Self {
    { name, tag, exposed_ports: [], env_vars: Map::new(), wait_strategy: None }
  }

  pub fn with_exposed_port(self, port: Int) -> Self {
    self.exposed_ports.push(port)
    self
  }

  pub fn with_env_var(self, key: String, value: String) -> Self {
    self.env_vars.insert(key, value)
    self
  }

  pub fn with_wait_for(self, strategy: WaitStrategy) -> Self {
    self.wait_strategy = Some(strategy)
    self
  }

  pub fn start(self) -> Result[Container, String] {
    // コンテナを起動
  }
}

// クリーンアップ
pub impl Container {
  pub fn stop(self) -> Result[Unit, String] {
    docker_stop(self.id)
  }

  pub fn remove(self) -> Result[Unit, String] {
    docker_rm(self.id)
  }

  pub fn get_host_port(self) -> Int {
    self.host_port
  }
}
```

使用例：

```moonbit
test "redis container" {
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_env_var("DEBUG", "1")
    .with_wait_for(WaitStrategy::LogMessage("Ready to accept connections"))
    .start()
    .expect("Failed to start Redis")

  // テスト処理
  let port = container.get_host_port()
  // Redis接続とテスト

  // クリーンアップ
  container.stop().expect("Failed to stop container")
  container.remove().expect("Failed to remove container")
}
```

### 5.3 実装の優先順位

#### フェーズ1: 最小限の実装（MVP）

1. **Docker CLI実行**
   - `docker run -d`でコンテナ起動
   - `docker stop`でコンテナ停止
   - `docker rm`でコンテナ削除
   - コンテナIDの取得

2. **基本的なコンテナ管理**
   - `ContainerImage`構造体
   - `Container`構造体
   - 起動と停止の基本メソッド

3. **ポートマッピング**
   - `-P`オプションでランダムポート割り当て
   - `docker port`でマッピングされたポートを取得

#### フェーズ2: Wait Strategies

1. **ログメッセージ待機**
   - `docker logs -f`で特定のメッセージを監視

2. **ポート待機**
   - TCPポートの開放を確認

3. **HTTPエンドポイント待機**
   - HTTPリクエストで準備完了を確認

#### フェーズ3: 高度な機能

1. **ネットワーク管理**
   - 複数コンテナの接続

2. **ボリューム管理**
   - データの永続化

3. **モジュールシステム**
   - PostgreSQL、Redis、MongoDB用の専用モジュール

---

## 6. 技術的な課題と考慮事項

### 6.1 エラーハンドリング

- Docker CLIの実行失敗
- コンテナ起動失敗
- タイムアウト処理
- リソースリーク防止

### 6.2 リソース管理

- テスト終了時の確実なコンテナ削除
- 異常終了時のクリーンアップ
- ファイナライザーの利用可能性

### 6.3 並行実行

- 複数テストの並行実行時の競合
- ポート番号の衝突回避
- コンテナ名の一意性

### 6.4 プラットフォーム対応

- Linux、macOS、Windows対応
- Docker Desktop vs Docker Engine
- Podmanなど代替ランタイムのサポート

---

## 7. 次のステップ

### 7.1 実装計画

1. **プロトタイプ作成**
   - シンプルなDocker CLIラッパーの実装
   - 基本的なコンテナ起動・停止機能

2. **テスト作成**
   - 単体テスト
   - 統合テスト（実際のDockerコンテナを使用）

3. **ドキュメント作成**
   - APIドキュメント
   - 使用例
   - トラブルシューティングガイド

4. **継続的改善**
   - Wait Strategiesの実装
   - エラーハンドリングの強化
   - パフォーマンス最適化

### 7.2 検証が必要な項目

- [ ] MoonBitの`@process`モジュールの詳細な仕様
- [ ] MoonBitでのリソース管理（ファイナライザー）
- [ ] MoonBitのHTTPクライアントライブラリの有無と機能
- [ ] MoonBitでの並行プログラミングのベストプラクティス

---

## 8. 参考資料

### Testcontainers

- [Testcontainers公式サイト](https://testcontainers.com/)
- [Testcontainers Getting Started](https://testcontainers.com/getting-started/)
- [Testcontainers GitHub Organization](https://github.com/testcontainers)
- [Testcontainers for Rust](https://rust.testcontainers.org/)
- [testcontainers-rs GitHub](https://github.com/testcontainers/testcontainers-rs)
- [Testcontainers for Go](https://golang.testcontainers.org/)
- [testcontainers-go GitHub](https://github.com/testcontainers/testcontainers-go)
- [Testcontainers for Java](https://java.testcontainers.org/)

### MoonBit

- [MoonBit公式サイト](https://www.moonbitlang.com/)
- [MoonBit FFI Documentation](https://docs.moonbitlang.com/en/latest/language/ffi.html)
- [A Guide to MoonBit C-FFI](https://www.moonbitlang.com/pearls/moonbit-cffi)
- [Write a Simple Code Agent using moonbitlang/async](https://www.moonbitlang.com/blog/moonbit-async-code-agent)
- [moonbitlang/async GitHub](https://github.com/moonbitlang/async)
- [Introducing Async Programming in MoonBit](https://www.moonbitlang.com/blog/moonbit-async)

### Docker

- [Docker CLI Documentation](https://docs.docker.com/reference/cli/docker/)
- [Docker Container Lifecycle Management](https://k21academy.com/kubernetes/docker-container-lifecycle-management/)
- [How to Stop and Remove Docker Containers](https://spacelift.io/blog/docker-stop-container)

---

## 9. まとめ

MoonBitでtestcontainersを実装することは**技術的に実現可能**です。

### 主要な知見

1. **MoonBitには外部プロセス実行機能がある**
   - `@process.collect_output_merged`を使用してDocker CLIを実行可能

2. **Docker CLIラッパーアプローチが最適**
   - シンプルで実装しやすい
   - 十分な機能を提供

3. **他言語の実装パターンが参考になる**
   - Rust、Goの実装からAPI設計を学べる
   - Builder パターンが有効

4. **段階的な実装が推奨される**
   - フェーズ1: 基本的なコンテナ起動・停止
   - フェーズ2: Wait Strategies
   - フェーズ3: 高度な機能

### 実装の実現可能性

- ✅ コンテナの起動・停止・削除
- ✅ ポートマッピング
- ✅ 環境変数の設定
- ⚠️ Wait Strategies（ログ監視など、追加の実装が必要）
- ⚠️ 複雑なネットワーク設定（要調査）

次の作業として、プロトタイプの実装に進むことを推奨します。
