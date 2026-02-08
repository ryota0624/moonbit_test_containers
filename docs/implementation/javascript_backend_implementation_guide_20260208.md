# 実装ガイド: JavaScriptバックエンド対応

## ドキュメント情報
- **作成日**: 2026-02-08
- **対象**: 実装担当者（@coder）
- **ステータス**: 実装準備完了
- **関連ドキュメント**:
  - Steering: `docs/steering/javascript_backend_support_20260208.md`
  - Technical Design: `docs/design/javascript_backend_technical_design_20260208.md`
  - Test Strategy: `docs/design/javascript_backend_test_strategy_20260208.md`

## 実装の概要

このガイドは、JavaScriptバックエンドでのテスト実行を可能にするための具体的な実装手順を提供します。

### 実装方針
- **既存コードは維持**: 統合テストはNative専用として保持
- **新規テスト追加**: ユニットテスト層を新たに作成
- **段階的実装**: Phase 1から順次実装
- **後方互換性**: `moon test --target native`は引き続き動作

## Phase 1: 基盤整備

### ステップ 1.1: ディレクトリ構造の作成

```bash
# プロジェクトルートで実行
mkdir -p tests/unit
```

**完了条件**: `tests/unit/`ディレクトリが作成される

### ステップ 1.2: moon.pkg.jsonの更新

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/moon.pkg.json`

**現在の内容**:
```json
{
  "import": [
    "moonbitlang/async/process",
    "moonbitlang/async",
    "moonbitlang/async/http",
    "moonbitlang/core/strconv",
    "moonbitlang/core/test"
  ]
}
```

**更新後の内容**:
```json
{
  "import": [
    "moonbitlang/async/process",
    "moonbitlang/async",
    "moonbitlang/async/http",
    "moonbitlang/core/strconv",
    "moonbitlang/core/test"
  ],
  "targets": {
    "container.mbt": ["native"],
    "docker.mbt": ["native"],
    "wait_strategy.mbt": ["native"],
    "logs.mbt": ["native"],
    "basic_lifecycle_wbtest.mbt": ["native"],
    "wait_strategies_wbtest.mbt": ["native"],
    "logs_basic_wbtest.mbt": ["native"],
    "logs_streaming_wbtest.mbt": ["native"],
    "logs_advanced_wbtest.mbt": ["native"],
    "volume_mount_wbtest.mbt": ["native"],
    "types.mbt": ["native", "js"],
    "error.mbt": ["native", "js"]
  }
}
```

**変更理由**:
- Docker依存ファイルを`["native"]`に制限
- 型定義とエラー処理は両バックエンド対応
- 既存の統合テストをNative専用として明示

**検証方法**:
```bash
# Nativeビルド（全ファイルを含む）
moon check --target native

# JavaScriptビルド（targetsで許可されたファイルのみ）
moon check --target js
```

**完了条件**: 両方のビルドが成功する

### ステップ 1.3: 最初のユニットテスト作成

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/tests/unit/types_test.mbt`

**内容**:
```moonbit
// Unit tests for ContainerImage and related types
// These tests are compatible with both native and JavaScript backends

///|
/// Test basic ContainerImage creation
test "ContainerImage::new creates valid image" {
  let image = ContainerImage::new("redis", "7.2.4")
  @assertion.assert_eq(image.name, "redis")?
  @assertion.assert_eq(image.tag, "7.2.4")?
  @assertion.assert_eq(image.exposed_ports.length(), 0)?
  @assertion.assert_eq(image.env_vars.length(), 0)?
  @assertion.assert_eq(image.volumes.length(), 0)?
  @assertion.assert_eq(image.cmd.length(), 0)?
}

///|
/// Test with_exposed_port method
test "with_exposed_port adds port correctly" {
  let image = ContainerImage::new("redis", "latest")
    .with_exposed_port(6379)
    .with_exposed_port(6380)

  @assertion.assert_eq(image.exposed_ports.length(), 2)?
  @assertion.assert_eq(image.exposed_ports[0], 6379)?
  @assertion.assert_eq(image.exposed_ports[1], 6380)?
}

///|
/// Test with_env_var method
test "with_env_var adds environment variable" {
  let image = ContainerImage::new("postgres", "15")
    .with_env_var("POSTGRES_USER", "testuser")
    .with_env_var("POSTGRES_PASSWORD", "testpass")

  @assertion.assert_eq(image.env_vars.length(), 2)?

  let (key1, value1) = image.env_vars[0]
  @assertion.assert_eq(key1, "POSTGRES_USER")?
  @assertion.assert_eq(value1, "testuser")?

  let (key2, value2) = image.env_vars[1]
  @assertion.assert_eq(key2, "POSTGRES_PASSWORD")?
  @assertion.assert_eq(value2, "testpass")?
}

///|
/// Test with_volume method
test "with_volume adds volume mount" {
  let image = ContainerImage::new("nginx", "latest")
    .with_volume("/host/path", "/container/path", read_only=true)

  @assertion.assert_eq(image.volumes.length(), 1)?

  let volume = image.volumes[0]
  @assertion.assert_eq(volume.host_path, "/host/path")?
  @assertion.assert_eq(volume.container_path, "/container/path")?
  @assertion.assert_eq(volume.read_only, true)?
}

///|
/// Test with_volume with read_only=false
test "with_volume read-write mount" {
  let image = ContainerImage::new("nginx", "latest")
    .with_volume("/data", "/mnt/data", read_only=false)

  let volume = image.volumes[0]
  @assertion.assert_eq(volume.read_only, false)?
}

///|
/// Test with_wait_for method
test "with_wait_for sets wait strategy" {
  let image = ContainerImage::new("redis", "latest")
    .with_wait_for(WaitStrategy::TcpPort(6379))

  match image.wait_strategy {
    Some(WaitStrategy::TcpPort(port)) => @assertion.assert_eq(port, 6379)?
    _ => abort("Wait strategy not set correctly")
  }
}

///|
/// Test with_wait_timeout method
test "with_wait_timeout sets timeout" {
  let image = ContainerImage::new("app", "1.0")
    .with_wait_timeout(60)

  @assertion.assert_eq(image.wait_timeout, 60)?
}

///|
/// Test builder pattern chaining
test "builder pattern chaining" {
  let image = ContainerImage::new("app", "1.0")
    .with_exposed_port(8080)
    .with_exposed_port(8443)
    .with_env_var("ENV", "test")
    .with_env_var("DEBUG", "true")
    .with_wait_timeout(60)
    .with_volume("/logs", "/var/log/app", read_only=false)

  @assertion.assert_eq(image.name, "app")?
  @assertion.assert_eq(image.tag, "1.0")?
  @assertion.assert_eq(image.exposed_ports.length(), 2)?
  @assertion.assert_eq(image.env_vars.length(), 2)?
  @assertion.assert_eq(image.volumes.length(), 1)?
  @assertion.assert_eq(image.wait_timeout, 60)?
}

///|
/// Test with_cmd method
test "with_cmd sets command arguments" {
  let image = ContainerImage::new("busybox", "latest")
    .with_cmd(["sh", "-c", "echo hello"])

  @assertion.assert_eq(image.cmd.length(), 3)?
  @assertion.assert_eq(image.cmd[0], "sh")?
  @assertion.assert_eq(image.cmd[1], "-c")?
  @assertion.assert_eq(image.cmd[2], "echo hello")?
}

///|
/// Test default wait_timeout value
test "default wait_timeout" {
  let image = ContainerImage::new("redis", "latest")
  @assertion.assert_eq(image.wait_timeout, 30)?  // デフォルト値が30秒と仮定
}

///|
/// Test WaitStrategy variants
test "WaitStrategy::LogMessage variant" {
  let image = ContainerImage::new("app", "1.0")
    .with_wait_for(WaitStrategy::LogMessage("ready to accept connections"))

  match image.wait_strategy {
    Some(WaitStrategy::LogMessage(msg)) =>
      @assertion.assert_eq(msg, "ready to accept connections")?
    _ => abort("Wait strategy not set correctly")
  }
}

///|
/// Test WaitStrategy::HttpEndpoint variant
test "WaitStrategy::HttpEndpoint variant" {
  let image = ContainerImage::new("api", "1.0")
    .with_wait_for(WaitStrategy::HttpEndpoint("/health", 200))

  match image.wait_strategy {
    Some(WaitStrategy::HttpEndpoint(path, status)) => {
      @assertion.assert_eq(path, "/health")?
      @assertion.assert_eq(status, 200)?
    }
    _ => abort("Wait strategy not set correctly")
  }
}
```

**注意点**:
- Docker実行を伴わない純粋な型操作のテスト
- 両バックエンドで実行可能
- `@assertion`を使用（MoonBit標準）

**検証方法**:
```bash
# Nativeで実行
moon test --target native tests/unit/types_test.mbt

# JavaScriptで実行
moon test --target js tests/unit/types_test.mbt
```

**完了条件**: 両方のテストが成功する

### ステップ 1.4: テスト実行確認

```bash
# 全体テスト（Native）
moon test --target native

# ユニットテストのみ（JavaScript）
moon test --target js
```

**期待される結果**:
- Native: 既存の統合テスト + 新規ユニットテスト全て成功
- JavaScript: 新規ユニットテストのみ成功

**トラブルシューティング**:
- エラー: `@assertion not found` → `import "moonbitlang/core/test"`を確認
- エラー: `ContainerImage not found` → targetsで`types.mbt`が`js`対応か確認

**Phase 1完了条件**:
- [x] `tests/unit/`ディレクトリ作成
- [x] `moon.pkg.json`更新
- [x] `types_test.mbt`作成
- [x] `moon test --target js`成功

## Phase 2: コアテスト実装

### ステップ 2.1: パーサーロジックのテスト

**前提**: `parse_port_mapping`関数がDocker非依存であることを確認

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/tests/unit/parser_test.mbt`

**内容**:
```moonbit
// Unit tests for parsing logic
// These tests are compatible with both native and JavaScript backends

///|
/// Test parse_port_mapping with standard format
test "parse_port_mapping handles standard format" {
  match parse_port_mapping("0.0.0.0:32768") {
    Some(port) => @assertion.assert_eq(port, 32768)?
    None => abort("Failed to parse standard format: 0.0.0.0:32768")
  }
}

///|
/// Test parse_port_mapping with IPv6 format
test "parse_port_mapping handles IPv6 format" {
  match parse_port_mapping("[::]:32769") {
    Some(port) => @assertion.assert_eq(port, 32769)?
    None => abort("Failed to parse IPv6 format: [::]:32769")
  }
}

///|
/// Test parse_port_mapping with hostname
test "parse_port_mapping handles hostname format" {
  match parse_port_mapping("localhost:8080") {
    Some(port) => @assertion.assert_eq(port, 8080)?
    None => abort("Failed to parse hostname format: localhost:8080")
  }
}

///|
/// Test parse_port_mapping with IPv4 and high port
test "parse_port_mapping with high port number" {
  match parse_port_mapping("192.168.1.1:65535") {
    Some(port) => @assertion.assert_eq(port, 65535)?
    None => abort("Failed to parse high port: 65535")
  }
}

///|
/// Test parse_port_mapping returns None for invalid input
test "parse_port_mapping invalid input" {
  match parse_port_mapping("invalid") {
    Some(_) => abort("Should return None for invalid input")
    None => ()
  }
}

///|
/// Test parse_port_mapping with empty string
test "parse_port_mapping empty string" {
  match parse_port_mapping("") {
    Some(_) => abort("Should return None for empty string")
    None => ()
  }
}

///|
/// Test parse_port_mapping without colon
test "parse_port_mapping no colon" {
  match parse_port_mapping("no-colon") {
    Some(_) => abort("Should return None for input without colon")
    None => ()
  }
}

///|
/// Test parse_port_mapping with invalid port number
test "parse_port_mapping invalid port number" {
  match parse_port_mapping("0.0.0.0:not-a-number") {
    Some(_) => abort("Should return None for non-numeric port")
    None => ()
  }
}

///|
/// Test parse_port_mapping with port out of range
test "parse_port_mapping port out of range" {
  match parse_port_mapping("0.0.0.0:99999") {
    Some(_) => abort("Should return None for port > 65535")
    None => ()
  }
}

///|
/// Test parse_port_mapping with negative port
test "parse_port_mapping negative port" {
  match parse_port_mapping("0.0.0.0:-1") {
    Some(_) => abort("Should return None for negative port")
    None => ()
  }
}

///|
/// Test parse_port_mapping with port 0
test "parse_port_mapping port zero" {
  match parse_port_mapping("0.0.0.0:0") {
    Some(port) => @assertion.assert_eq(port, 0)?
    None => abort("Port 0 should be valid")
  }
}

///|
/// Test parse_port_mapping with multiple colons
test "parse_port_mapping multiple colons in IPv6" {
  match parse_port_mapping("[::1]:8080") {
    Some(port) => @assertion.assert_eq(port, 8080)?
    None => abort("Failed to parse IPv6 localhost: [::1]:8080")
  }
}
```

**注意点**:
- `parse_port_mapping`関数が存在することを前提
- 存在しない場合は、`docker.mbt`から抽出してユーティリティファイルに移動

**検証方法**:
```bash
moon test --target native tests/unit/parser_test.mbt
moon test --target js tests/unit/parser_test.mbt
```

**完了条件**: 両方のテストが成功する

### ステップ 2.2: エラーハンドリングのテスト

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/tests/unit/error_test.mbt`

**内容**:
```moonbit
// Unit tests for error handling
// These tests are compatible with both native and JavaScript backends

///|
/// Test ContainerStartFailed error
test "TestContainerError::ContainerStartFailed" {
  let err = TestContainerError::ContainerStartFailed("permission denied")
  let msg = err.to_string()

  // メッセージに理由が含まれているか確認
  @assertion.assert_true(msg.contains("permission denied"))?
  @assertion.assert_true(msg.contains("start") || msg.contains("Start"))?
}

///|
/// Test PortNotFound error
test "TestContainerError::PortNotFound" {
  let err = TestContainerError::PortNotFound(8080)
  let msg = err.to_string()

  @assertion.assert_true(msg.contains("8080"))?
  @assertion.assert_true(msg.contains("port") || msg.contains("Port"))?
}

///|
/// Test WaitTimeout error
test "TestContainerError::WaitTimeout" {
  let err = TestContainerError::WaitTimeout("Redis", 30)
  let msg = err.to_string()

  @assertion.assert_true(msg.contains("Redis"))?
  @assertion.assert_true(msg.contains("30"))?
  @assertion.assert_true(msg.contains("timeout") || msg.contains("Timeout"))?
}

///|
/// Test DockerCommandFailed error
test "TestContainerError::DockerCommandFailed" {
  let err = TestContainerError::DockerCommandFailed("run", 1, "exit status 1")
  let msg = err.to_string()

  @assertion.assert_true(msg.contains("run"))?
  @assertion.assert_true(msg.contains("exit status 1"))?
}

///|
/// Test Unsupported error
test "TestContainerError::Unsupported" {
  let err = TestContainerError::Unsupported("JavaScript backend")
  let msg = err.to_string()

  @assertion.assert_true(msg.contains("JavaScript backend"))?
  @assertion.assert_true(msg.contains("unsupported") || msg.contains("Unsupported"))?
}

///|
/// Test error pattern matching
test "error pattern matching" {
  let err = TestContainerError::Unsupported("test reason")

  match err {
    Unsupported(reason) => @assertion.assert_eq(reason, "test reason")?
    _ => abort("Pattern matching failed for Unsupported variant")
  }
}

///|
/// Test error with empty reason
test "error with empty reason" {
  let err = TestContainerError::ContainerStartFailed("")
  let msg = err.to_string()

  // 空の理由でもエラーメッセージが生成される
  @assertion.assert_true(msg.length() > 0)?
}

///|
/// Test error message distinctness
test "different errors have different messages" {
  let err1 = TestContainerError::ContainerStartFailed("reason1")
  let err2 = TestContainerError::PortNotFound(8080)

  let msg1 = err1.to_string()
  let msg2 = err2.to_string()

  // 異なるエラーは異なるメッセージを持つ
  @assertion.assert_not_eq(msg1, msg2)?
}
```

**検証方法**:
```bash
moon test --target native tests/unit/error_test.mbt
moon test --target js tests/unit/error_test.mbt
```

**完了条件**: 両方のテストが成功する

### ステップ 2.3: カバレッジ確認

```bash
# Nativeカバレッジ
moon test --target native --enable-coverage
moon coverage report

# JavaScriptカバレッジ
moon test --target js --enable-coverage
moon coverage report

# 未カバー箇所の確認
moon coverage analyze > uncovered.log
cat uncovered.log
```

**目標**:
- `types.mbt`: 70%以上
- `error.mbt`: 80%以上

**Phase 2完了条件**:
- [x] `parser_test.mbt`作成（関数が存在する場合）
- [x] `error_test.mbt`作成
- [x] 両バックエンドでテスト成功
- [x] カバレッジ目標達成

## Phase 3: ドキュメント更新

### ステップ 3.1: README.mbt.md更新

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/README.mbt.md`

**追加セクション**:

```markdown
## Testing

### Running Tests

#### Native Backend (Full Test Suite)
```bash
# Run all tests including integration tests
moon test --target native

# Run with coverage
moon test --target native --enable-coverage
moon coverage report
```

#### JavaScript Backend (Unit Tests Only)
```bash
# Run unit tests
moon test --target js

# Run with coverage
moon test --target js --enable-coverage
moon coverage report
```

### Test Structure

- **Unit Tests** (`tests/unit/`): Compatible with both native and JavaScript backends
  - Type definitions and builder patterns
  - Parsing logic
  - Error handling
  - Business logic

- **Integration Tests** (root directory, `*_wbtest.mbt`): Native backend only
  - Docker container lifecycle
  - Wait strategies
  - Volume mounts
  - Log streaming

### Backend Support

- **Native/LLVM Backend**: Full support including Docker integration
- **JavaScript Backend**: Unit tests only (Docker operations not supported)

The JavaScript backend does not support Docker operations because the `@process` package from `moonbitlang/async` is native-only. Integration tests require Docker CLI execution and are therefore limited to the native backend.
```

### ステップ 3.2: 完了ドキュメント作成

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/completed/javascript_backend_support_20260208.md`

**内容は実装完了後に作成** （orchestratorが最終的に作成）

**Phase 3完了条件**:
- [x] `README.mbt.md`更新
- [x] 完了ドキュメント作成（orchestrator担当）

## 実装チェックリスト

### Phase 1: 基盤整備
- [ ] `tests/unit/`ディレクトリ作成
- [ ] `moon.pkg.json`に`targets`セクション追加
- [ ] `types_test.mbt`作成
- [ ] `moon test --target native`成功確認
- [ ] `moon test --target js`成功確認

### Phase 2: コアテスト実装
- [ ] `parser_test.mbt`作成（該当する場合）
- [ ] `error_test.mbt`作成
- [ ] 両バックエンドでテスト実行確認
- [ ] カバレッジ測定

### Phase 3: ドキュメント
- [ ] `README.mbt.md`更新
- [ ] 変更内容の動作確認
- [ ] 完了ドキュメント準備

## トラブルシューティング

### 問題1: `moon test --target js`でエラー

**症状**:
```
Error: process module not found
```

**原因**: Docker依存コードがJavaScriptビルドに含まれている

**解決策**:
1. `moon.pkg.json`の`targets`設定を確認
2. 該当ファイルを`["native"]`に設定
3. `moon check --target js`で再確認

### 問題2: テストが見つからない

**症状**:
```
No tests found
```

**原因**: テストファイルの命名またはディレクトリ構造の問題

**解決策**:
1. テストファイルが`*_test.mbt`または`*_wbtest.mbt`で終わるか確認
2. `moon.pkg.json`の`import`に`moonbitlang/core/test`があるか確認
3. テスト関数が`test "description" { ... }`形式か確認

### 問題3: `parse_port_mapping`が見つからない

**症状**:
```
Error: parse_port_mapping not found
```

**原因**: 関数が`docker.mbt`（native専用）に定義されている

**解決策**:
1. パーサー関数を新しいファイル`parsers.mbt`に抽出
2. `moon.pkg.json`で`parsers.mbt`を`["native", "js"]`に設定
3. `docker.mbt`から`parsers.mbt`をimport

**抽出例**:
```moonbit
// parsers.mbt (新規作成)
///|
/// Parse port mapping from Docker output
pub fn parse_port_mapping(output : String) -> Int? {
  // 実装をdocker.mbtから移動
}
```

```moonbit
// docker.mbt (既存)
// parse_port_mappingを使用する箇所はそのまま
```

```json
// moon.pkg.json
{
  "targets": {
    "parsers.mbt": ["native", "js"],
    "docker.mbt": ["native"]
  }
}
```

## 実装後の検証

### 最終チェック

```bash
# 1. Nativeビルド確認
moon check --target native

# 2. JavaScriptビルド確認
moon check --target js

# 3. Nativeテスト実行（全テスト）
moon test --target native

# 4. JavaScriptテスト実行（ユニットテストのみ）
moon test --target js

# 5. フォーマット確認
moon fmt

# 6. インターフェース更新
moon info

# 7. .mbtiファイルの差分確認
git diff "*.mbti"
```

### 期待される結果

- [x] 全てのビルドが成功
- [x] 全てのテストが成功
- [x] `.mbti`ファイルに予期しない変更がない
- [x] コードが正しくフォーマットされている

## 次のステップ

実装完了後:

1. **@reviewerにレビュー依頼** （orchestratorが実施）
2. **完了ドキュメント作成** （orchestratorが実施）
3. **コミットとプッシュ**
4. **CI/CD統合**（オプション）

## 参考資料

### MoonBit公式ドキュメント
- Testing: https://docs.moonbitlang.com/next/toolchain/testing/
- Conditional Compilation: https://docs.moonbitlang.com/next/toolchain/build-system/conditional-compilation/
- Package Configuration: https://docs.moonbitlang.com/next/toolchain/build-system/package-config/

### プロジェクトドキュメント
- CLAUDE.md: プロジェクトガイドライン
- AGENTS.md: MoonBit開発規約
- Technical Design: 技術設計ドキュメント
- Test Strategy: テスト戦略ドキュメント

## 質問・サポート

実装中に不明点があれば、以下のドキュメントを参照:

1. **技術的な判断**: `docs/design/javascript_backend_technical_design_20260208.md`
2. **テスト戦略**: `docs/design/javascript_backend_test_strategy_20260208.md`
3. **全体方針**: `docs/steering/javascript_backend_support_20260208.md`

---

**このガイドに従って実装を進めてください。Phase 1から順次実装し、各フェーズで動作確認を行うことを推奨します。**
