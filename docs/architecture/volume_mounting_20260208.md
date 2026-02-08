# アーキテクチャ設計: ボリュームマウント機能

## 日付
2026-02-08

## 概要
testcontainersライブラリにボリュームマウント機能を追加し、ホストのファイルやディレクトリをコンテナ内にマウントできるようにする。

## 技術設計

### 1. データ構造

#### VolumeMount 構造体

```moonbit
pub struct VolumeMount {
  host_path : String       // ホスト側のパス
  container_path : String  // コンテナ内のパス
  readonly : Bool          // 読み取り専用フラグ（デフォルト: false）
}
```

#### ContainerImage 構造体の拡張

```moonbit
pub struct ContainerImage {
  name : String
  tag : String
  exposed_ports : Array[Int]
  env_vars : Array[(String, String)]
  cmd : Array[String]
  wait_strategy : WaitStrategy?
  wait_timeout : Int
  volumes : Array[VolumeMount]  // ← 新規追加
}
```

### 2. API 設計

#### with_volume メソッド

```moonbit
///|
/// Add a volume mount to the container configuration
pub fn ContainerImage::with_volume(
  self : ContainerImage,
  host_path : String,
  container_path : String,
  readonly? : Bool
) -> ContainerImage {
  let readonly = match readonly {
    Some(ro) => ro
    None => false
  }
  let volumes = self.volumes.copy()
  volumes.push({ host_path, container_path, readonly })
  { ..self, volumes }
}
```

#### ContainerImage::new の拡張

```moonbit
pub fn ContainerImage::new(name : String, tag : String) -> ContainerImage {
  {
    name,
    tag,
    exposed_ports: [],
    env_vars: [],
    cmd: [],
    wait_strategy: None,
    wait_timeout: 60,
    volumes: [],  // ← 新規追加
  }
}
```

### 3. Docker CLI 統合

#### ContainerImage::start メソッドの拡張

container.mbt の `ContainerImage::start()` メソッドで、docker run コマンドにボリュームマウントオプションを追加:

```moonbit
pub async fn ContainerImage::start(
  self : ContainerImage,
) -> Result[Container, TestContainerError] {
  let args : Array[String] = ["run", "-d"]

  // Add port mappings (-P for random host ports)
  if self.exposed_ports.length() > 0 {
    args.push("-P")
  }

  // Add volume mounts  ← 新規追加
  for i = 0; i < self.volumes.length(); i = i + 1 {
    let volume = self.volumes[i]
    args.push("-v")
    if volume.readonly {
      args.push("\{volume.host_path}:\{volume.container_path}:ro")
    } else {
      args.push("\{volume.host_path}:\{volume.container_path}")
    }
  }

  // Add environment variables
  for i = 0; i < self.env_vars.length(); i = i + 1 {
    let (key, value) = self.env_vars[i]
    args.push("-e")
    args.push("\{key}=\{value}")
  }

  // ... 既存のコードが続く
}
```

### 4. エラーハンドリング

- **空のパス**: host_path または container_path が空文字列の場合、Docker CLIがエラーを返す
- **存在しないパス**: Docker CLIがエラーメッセージを返す（`DockerCommandFailed`）
- **パーミッションエラー**: Docker CLIがエラーメッセージを返す

エラーハンドリングは既存の仕組み（`exec_docker`によるDocker CLIエラーの捕捉）で対応。

### 5. ファイル配置

#### types.mbt
- `VolumeMount` 構造体の定義（pub）
- `ContainerImage::with_volume()` メソッドの追加（pub）
- `ContainerImage::new()` の volumes フィールド初期化追加

#### container.mbt
- `ContainerImage::start()` メソッドの拡張
- ボリュームマウントオプションの生成ロジック追加

## 実装の流れ

### Phase 1: types.mbt の変更
1. `VolumeMount` 構造体を定義
2. `ContainerImage` 構造体に `volumes` フィールドを追加
3. `ContainerImage::new()` を修正
4. `ContainerImage::with_volume()` メソッドを実装

### Phase 2: container.mbt の変更
1. `ContainerImage::start()` メソッドを修正
2. ボリュームマウントオプションを docker run コマンドに追加

### Phase 3: テストの実装
1. moonbit_test_containers_wbtest.mbt にテストケースを追加

### Phase 4: ドキュメント更新
1. README.mbt.md の更新

## 既存コードへの影響

### 破壊的変更
- なし（volumesフィールドはデフォルトで空配列）

### 非破壊的変更
- `ContainerImage` 構造体にフィールド追加
- `ContainerImage::new()` の初期化処理追加
- `ContainerImage::start()` のコマンド生成ロジック追加

### 互換性
- 既存のコードは変更なしで動作する
- volumesを指定しない場合、空配列として扱われる

## 使用例

### 基本的な使用例

```moonbit
let container = ContainerImage::new("nginx", "1.25-alpine")
  .with_volume("./nginx.conf", "/etc/nginx/nginx.conf")
  .with_exposed_port(80)
  .start()
```

### 読み取り専用マウント

```moonbit
let container = ContainerImage::new("myapp", "latest")
  .with_volume("./config", "/app/config", readonly=true)
  .start()
```

### PostgreSQL 初期化スクリプト

```moonbit
let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "testdb")
  .with_volume("./init.sql", "/docker-entrypoint-initdb.d/init.sql")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .start()
```

### 複数ボリューム

```moonbit
let container = ContainerImage::new("myapp", "latest")
  .with_volume("./config", "/app/config", readonly=true)
  .with_volume("./data", "/app/data")
  .with_volume("./logs", "/app/logs")
  .start()
```

## パフォーマンスへの影響
- ボリュームマウント自体はDocker CLIの機能なので、ライブラリのパフォーマンスへの影響はほぼなし
- docker runコマンドの引数が増えるが、実行時間への影響は無視できる

## セキュリティ考慮事項
- **パスインジェクション**: host_path と container_path をそのまま Docker CLI に渡すため、ユーザーが信頼できるパスを指定する責任がある
- **読み取り専用マウント**: 重要なファイルは `readonly=true` で保護することを推奨
- **ホスト側のパーミッション**: Docker デーモンのパーミッションに依存

## 今後の拡張性
- Named volumes のサポート（`docker volume create`）
- tmpfs マウントのサポート
- bind mount のオプション（`cached`, `delegated` など）
- ボリュームドライバーのサポート

## 参考実装
- testcontainers-rs: https://docs.rs/testcontainers/latest/testcontainers/
- testcontainers-go: https://github.com/testcontainers/testcontainers-go
- Docker CLI reference: https://docs.docker.com/engine/reference/commandline/run/#volume
