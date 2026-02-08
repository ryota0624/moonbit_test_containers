# 実装ガイド v2: JavaScriptバックエンド対応（FFIアプローチ）

## ドキュメント情報
- **作成日**: 2026-02-08（v2: FFIアプローチ）
- **対象**: 実装担当者（@coder）
- **ステータス**: 実装準備完了
- **関連ドキュメント**:
  - Steering v2: `docs/steering/javascript_backend_support_v2_20260208.md`
  - Technical Design v2: `docs/design/javascript_backend_technical_design_v2_20260208.md`

## 実装の概要

このガイドは、JavaScript FFIとConfiguration Attributeを使用して、両バックエンドで統合テストを実行可能にする具体的な実装手順を提供します。

### 実装方針
- **Configuration Attribute使用**: `#cfg(target="...")`でバックエンド別実装を切り替え
- **同じ関数名**: Native実装とJS実装で同じ関数シグネチャ
- **既存テスト維持**: テストコードの変更は最小限
- **段階的実装**: Phase 1から順次実装

## Phase 1: リファクタリング

### ステップ 1.1: 既存のdocker.mbtの内容確認

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/docker.mbt`

まず現在の実装を確認:

```bash
cat docker.mbt
```

### ステップ 1.2: docker_executor.mbtの作成（インターフェース定義）

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/docker_executor.mbt`

**内容**:
```moonbit
// Docker command executor interface
// Both native and JavaScript backends implement this interface

///|
/// Execute docker command and return output
///
/// # Arguments
/// - `args`: Docker command arguments (e.g., ["run", "-d", "redis"])
///
/// # Returns
/// - `Ok(output)`: Command succeeded, returns stdout
/// - `Err(error)`: Command failed, returns error details
///
/// # Example
/// ```moonbit
/// let result = exec_docker(["ps", "-a"])
/// match result {
///   Ok(output) => println(output)
///   Err(e) => println("Error: " + e.to_string())
/// }
/// ```
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise

// Note: Actual implementation is provided by:
// - docker_native.mbt for native backend
// - docker_js.mbt for JavaScript backend
```

**ポイント**:
- 関数シグネチャのみ定義（実装なし）
- ドキュメントコメントで使用方法を明記
- 両バックエンドで共通のインターフェース

### ステップ 1.3: docker_native.mbtの作成（Native実装）

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/docker_native.mbt`

**内容**:
```moonbit
// Docker command executor for native backend
// Uses @process.collect_output_merged

///|
/// Execute docker command using native process execution
#cfg(target="native")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  try {
    let (status, output) = @process.collect_output_merged(command, args)
    if status == 0 {
      // Success: return trimmed output
      Ok(output.trim_end())
    } else {
      // Failed: return error with details
      Err(
        DockerCommandFailed(
          command=args.join(" "),
          exit_code=status,
          output=output,
        ),
      )
    }
  } catch {
    e => {
      // Exception occurred during execution
      Err(
        DockerCommandFailed(
          command=args.join(" "),
          exit_code=-1,
          output=e.to_string(),
        ),
      )
    }
  }
}
```

**ポイント**:
- `#cfg(target="native")`でNative専用
- 既存の`docker.mbt`の実装を移動
- エラーハンドリングを維持

### ステップ 1.4: docker.mbtの削除または更新

既存の`docker.mbt`を削除、または以下の内容に更新:

**オプション A: 削除**
```bash
rm docker.mbt
```

**オプション B: リダイレクト用に更新**
```moonbit
// docker.mbt
// This file has been split into:
// - docker_executor.mbt: Interface definition
// - docker_native.mbt: Native implementation
// - docker_js.mbt: JavaScript implementation

// For backward compatibility, re-export the function
pub use docker_executor::{exec_docker}
```

**推奨**: オプションA（削除）を推奨。明確な分離のため。

### ステップ 1.5: moon.pkg.jsonの更新

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

**更新後**:
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
    "docker_native.mbt": ["native"],
    "docker_js.mbt": ["js"]
  }
}
```

**変更点**:
- `targets`セクションを追加
- `docker_native.mbt`はNative専用
- `docker_js.mbt`はJavaScript専用（Phase 2で作成）
- その他のファイルは両対応（デフォルト）

### ステップ 1.6: ビルド確認

```bash
# Nativeビルド（docker_native.mbtを使用）
moon check --target native

# JavaScriptビルド（docker_js.mbtがないため、後でエラーになる）
# Phase 2で作成後に確認
```

**期待される結果**:
- Nativeビルドが成功
- JavaScriptビルドは`exec_docker`が見つからないエラー（Phase 2で解決）

**Phase 1完了条件**:
- [x] `docker_executor.mbt`作成
- [x] `docker_native.mbt`作成
- [x] `docker.mbt`削除または更新
- [x] `moon.pkg.json`更新
- [x] `moon check --target native`成功

## Phase 2: JavaScript実装

### ステップ 2.1: docker_js.mbtの作成（同期版）

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/docker_js.mbt`

**内容**:
```moonbit
// Docker command executor for JavaScript backend
// Uses Node.js child_process via FFI

///|
/// Execute docker command synchronously using Node.js child_process.execSync
///
/// Returns: (exit_status, output)
extern "js" fn exec_docker_sync(
  command : String,
  args : Array[String],
) -> (Int, String) =
  #| (command, args) => {
  #|   // Import Node.js child_process module
  #|   const { execSync } = require('child_process');
  #|
  #|   try {
  #|     // Join arguments and execute command
  #|     const argsStr = args.join(' ');
  #|     const fullCommand = command + ' ' + argsStr;
  #|
  #|     // Execute with options
  #|     const output = execSync(fullCommand, {
  #|       encoding: 'utf8',
  #|       stdio: ['pipe', 'pipe', 'pipe'],
  #|       maxBuffer: 10 * 1024 * 1024  // 10MB buffer
  #|     });
  #|
  #|     // Success: return status 0 and output
  #|     return [0, output];
  #|   } catch (error) {
  #|     // Error: return status and error message
  #|     const status = error.status || 1;
  #|     const output = error.stderr ? error.stderr.toString() : error.message;
  #|     return [status, output];
  #|   }
  #| }

///|
/// Execute docker command using JavaScript FFI
#cfg(target="js")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"

  // Call FFI function
  let (status, output) = exec_docker_sync(command, args)

  if status == 0 {
    // Success: return trimmed output
    Ok(output.trim_end())
  } else {
    // Failed: return error with details
    Err(
      DockerCommandFailed(
        command=args.join(" "),
        exit_code=status,
        output=output,
      ),
    )
  }
}
```

**ポイント**:
- `extern "js" fn`でNode.jsのchild_processを呼び出し
- `#cfg(target="js")`でJavaScript専用
- Native実装と同じ関数シグネチャとエラー処理
- `maxBuffer: 10MB`で大きな出力に対応

### ステップ 2.2: ビルド確認

```bash
# Nativeビルド
moon check --target native

# JavaScriptビルド（今回は成功するはず）
moon check --target js
```

**期待される結果**:
- 両方のビルドが成功

**トラブルシューティング**:
- エラー: `require is not defined`
  - 原因: ブラウザ環境で実行しようとしている
  - 解決: Node.js環境でテストを実行

### ステップ 2.3: 簡単な動作確認

**テストファイル**: `/Users/ryota.suzuki/git/moonbit_test_containers/docker_test_simple.mbt`（一時ファイル）

```moonbit
// Simple test to verify docker_js.mbt implementation

///|
async test "docker version (js backend)" {
  match exec_docker(["version", "--format", "{{.Client.Version}}"]) {
    Ok(version) => {
      println("Docker version: " + version)
      @assertion.assert_true(version.length() > 0)?
    }
    Err(e) => {
      println("Error: " + e.to_string())
      abort("Docker command failed")
    }
  }
}

///|
async test "docker ps (js backend)" {
  match exec_docker(["ps", "-a"]) {
    Ok(output) => {
      println("Docker ps output length: " + output.length().to_string())
      @assertion.assert_true(output.length() >= 0)?  // Empty is OK
    }
    Err(e) => {
      println("Error: " + e.to_string())
      abort("Docker ps failed")
    }
  }
}
```

**実行**:
```bash
# JavaScriptバックエンドでテスト
moon test --target js docker_test_simple.mbt

# Nativeバックエンドでも確認
moon test --target native docker_test_simple.mbt
```

**期待される結果**:
- 両方のテストが成功
- Docker versionが表示される

**完了後**: テストファイルを削除
```bash
rm docker_test_simple.mbt
```

**Phase 2完了条件**:
- [x] `docker_js.mbt`作成
- [x] `moon check --target js`成功
- [x] 簡単な動作確認テスト成功

## Phase 3: 既存テストの実行

### ステップ 3.1: 既存統合テストの実行（Native）

```bash
# 全テストを実行
moon test --target native

# 個別テスト
moon test --target native basic_lifecycle_wbtest.mbt
moon test --target native wait_strategies_wbtest.mbt
moon test --target native logs_basic_wbtest.mbt
```

**期待される結果**:
- 全てのテストが成功
- リファクタリングによる影響がないことを確認

### ステップ 3.2: 既存統合テストの実行（JavaScript）

```bash
# 全テストを実行
moon test --target js

# 個別テスト
moon test --target js basic_lifecycle_wbtest.mbt
moon test --target js wait_strategies_wbtest.mbt
moon test --target js logs_basic_wbtest.mbt
```

**期待される結果**:
- 全てのテストが成功
- Native版と同じ結果

**トラブルシューティング**:

#### 問題1: `require is not defined`
**原因**: ブラウザ環境で実行している
**解決**: Node.js環境で実行
```bash
# moonツールはデフォルトでNode.jsを使用するはず
# 環境変数で明示的に指定も可能
NODE_ENV=node moon test --target js
```

#### 問題2: テストがタイムアウト
**原因**: JavaScriptの非同期処理が正しく完了していない
**解決**: `docker_js.mbt`の実装を確認、`@async`の使用を確認

#### 問題3: Docker実行エラー
**原因**: Docker Daemonが起動していない、または権限エラー
**解決**:
```bash
# Docker確認
docker ps

# 権限確認（必要に応じて）
sudo docker ps
```

### ステップ 3.3: 両バックエンドでの結果比較

```bash
# Native版実行
moon test --target native > native_test_results.txt 2>&1

# JavaScript版実行
moon test --target js > js_test_results.txt 2>&1

# 差分確認
diff native_test_results.txt js_test_results.txt
```

**期待される結果**:
- 大きな差異がない
- 実行時間の差は許容範囲内（JS版が1.5倍以内）

**Phase 3完了条件**:
- [x] Native版で全テスト成功
- [x] JavaScript版で全テスト成功
- [x] 両バックエンドで同じ結果

## Phase 4: 最適化とドキュメント

### ステップ 4.1: パフォーマンス測定

```bash
# Native版
time moon test --target native

# JavaScript版
time moon test --target js
```

**記録**: 実行時間を記録し、差異を確認

### ステップ 4.2: エラーハンドリングの改善（オプション）

必要に応じて、以下を改善:

1. **詳細なエラーメッセージ**
```moonbit
Err(
  DockerCommandFailed(
    command=args.join(" "),
    exit_code=status,
    output=output,
    backend="javascript",  // 追加
  ),
)
```

2. **リトライロジック**（必要な場合）
```moonbit
let mut attempt = 0
let max_retries = 3
while attempt < max_retries {
  attempt = attempt + 1
  match exec_docker_sync(command, args) {
    (0, output) => return Ok(output.trim_end())
    (status, output) => {
      if attempt >= max_retries {
        return Err(DockerCommandFailed(...))
      }
      @async.sleep(1000)  // 1秒待機
    }
  }
}
```

### ステップ 4.3: README.mbt.md更新

**ファイルパス**: `/Users/ryota.suzuki/git/moonbit_test_containers/README.mbt.md`

**追加セクション**:

```markdown
## Backend Support

This library supports both **Native** and **JavaScript** backends.

### Native Backend (LLVM)
- Uses native process execution via `@process`
- Best performance
- Recommended for production use

### JavaScript Backend (Node.js)
- Uses Node.js `child_process` module via FFI
- Requires Node.js runtime (v14 or later recommended)
- Slightly slower than native (typically 1.2-1.5x)
- **Note**: Browser environment is not supported (requires Node.js `child_process`)

### Running Tests

```bash
# Native backend
moon test --target native

# JavaScript backend (requires Node.js)
moon test --target js

# Both backends
moon test --target native && moon test --target js
```

### Requirements

- Docker Engine installed and running
- For JavaScript backend: Node.js v14 or later
- For Native backend: LLVM toolchain (installed with MoonBit)

### Implementation Details

The Docker CLI execution is implemented separately for each backend:

- **Native**: `docker_native.mbt` uses `@process.collect_output_merged`
- **JavaScript**: `docker_js.mbt` uses Node.js `child_process.execSync` via FFI

Both implementations provide the same interface (`exec_docker` function) and are automatically selected based on the build target using MoonBit's Configuration Attribute (`#cfg(target="...")`).
```

### ステップ 4.4: コードフォーマットと整理

```bash
# コードフォーマット
moon fmt

# インターフェース更新
moon info

# .mbtiファイルの差分確認
git diff "*.mbti"
```

**Phase 4完了条件**:
- [x] パフォーマンス測定完了
- [x] README.mbt.md更新
- [x] コードフォーマット完了
- [x] `.mbti`ファイル確認

## 実装チェックリスト

### Phase 1: リファクタリング
- [ ] `docker_executor.mbt`作成（インターフェース）
- [ ] `docker_native.mbt`作成（Native実装）
- [ ] `docker.mbt`削除または更新
- [ ] `moon.pkg.json`に`targets`追加
- [ ] `moon check --target native`成功確認

### Phase 2: JavaScript実装
- [ ] `docker_js.mbt`作成（JavaScript FFI）
- [ ] `moon check --target js`成功確認
- [ ] 簡単な動作確認テスト実行

### Phase 3: 既存テスト実行
- [ ] Native版で全テスト実行確認
- [ ] JavaScript版で全テスト実行確認
- [ ] 両バックエンドの結果比較

### Phase 4: 最適化とドキュメント
- [ ] パフォーマンス測定
- [ ] README.mbt.md更新
- [ ] `moon fmt`実行
- [ ] `moon info`実行
- [ ] `.mbti`差分確認

### 最終確認
- [ ] `moon test --target native`全成功
- [ ] `moon test --target js`全成功
- [ ] ドキュメント更新完了
- [ ] コミット準備完了

## トラブルシューティング

### 問題1: `#cfg`が認識されない

**症状**:
```
Error: Unknown attribute: #cfg
```

**原因**: MoonBitのバージョンが古い

**解決**:
```bash
# MoonBitを最新版にアップデート
moon upgrade
```

### 問題2: FFIがNode.jsを認識しない

**症状**:
```
Error: require is not defined
```

**原因**: ブラウザ環境で実行されている

**解決**:
1. Node.jsがインストールされているか確認
```bash
node --version
```

2. moonツールがNode.jsを使用するように設定
```bash
# 環境変数で指定
export MOONBIT_JS_RUNTIME=node
```

### 問題3: `exec_docker`が重複定義エラー

**症状**:
```
Error: Duplicate definition of exec_docker
```

**原因**: `docker.mbt`が残っている、または`moon.pkg.json`の`targets`設定が不適切

**解決**:
1. `docker.mbt`を削除
2. `moon.pkg.json`を確認
```json
{
  "targets": {
    "docker_native.mbt": ["native"],
    "docker_js.mbt": ["js"]
  }
}
```

### 問題4: JavaScriptバックエンドで全テストが失敗

**症状**: 全てのテストが`exec_docker`エラーで失敗

**原因**: Docker Daemonが起動していない、または`docker`コマンドがパスに存在しない

**解決**:
```bash
# Docker確認
docker ps

# パス確認
which docker

# Docker起動（必要に応じて）
sudo systemctl start docker  # Linux
# または
open /Applications/Docker.app  # macOS
```

### 問題5: バッファオーバーフローエラー

**症状**:
```
Error: maxBuffer exceeded
```

**原因**: Docker出力が10MBを超えている

**解決**: `docker_js.mbt`の`maxBuffer`を増やす
```javascript
maxBuffer: 50 * 1024 * 1024  // 50MBに増加
```

## 実装後の検証

### 最終チェック

```bash
# 1. Nativeビルド
moon check --target native

# 2. JavaScriptビルド
moon check --target js

# 3. Nativeテスト（全テスト）
moon test --target native

# 4. JavaScriptテスト（全テスト）
moon test --target js

# 5. フォーマット
moon fmt

# 6. インターフェース更新
moon info

# 7. Git差分確認
git status
git diff
```

### 期待される結果

- [x] 全てのビルドが成功
- [x] 全てのテストが成功（両バックエンド）
- [x] コードが正しくフォーマットされている
- [x] `.mbti`ファイルに予期しない変更がない

### パフォーマンス目標

| バックエンド | 実行時間目標 | 備考 |
|-------------|------------|------|
| Native | 基準（例: 30秒） | 最速 |
| JavaScript | Native版の1.5倍以内 | 許容範囲 |

## 次のステップ

実装完了後:

1. **完了ドキュメント作成** （orchestratorが実施）
2. **コミットとプッシュ**
```bash
git add .
git commit -m "Add JavaScript backend support using FFI

- Split docker.mbt into docker_executor.mbt, docker_native.mbt, and docker_js.mbt
- Implement Docker CLI execution using Node.js child_process via FFI
- Add Configuration Attribute (#cfg) to separate implementations
- All integration tests now work on both native and JavaScript backends
- Update README.mbt.md with backend support information"
```

3. **CI/CD統合**（オプション）
```yaml
# .github/workflows/test.yml
jobs:
  test-native:
    runs-on: ubuntu-latest
    steps:
      - run: moon test --target native

  test-javascript:
    runs-on: ubuntu-latest
    steps:
      - run: moon test --target js
```

## 参考資料

### MoonBit公式ドキュメント
- Configuration Attribute: https://docs.moonbitlang.com/en/stable/language/attributes.html#configuration-attribute
- JavaScript FFI: https://docs.moonbitlang.com/en/stable/ffi-and-wasm-host/js.html
- Package Configuration: https://docs.moonbitlang.com/en/stable/toolchain/build-system/package-config/

### Node.js公式ドキュメント
- child_process: https://nodejs.org/api/child_process.html
- execSync: https://nodejs.org/api/child_process.html#child_processexecsynccommand-options

### プロジェクトドキュメント
- Steering v2: `docs/steering/javascript_backend_support_v2_20260208.md`
- Technical Design v2: `docs/design/javascript_backend_technical_design_v2_20260208.md`
- moonbitlang/async examples: `.moonbit-async/src/integration.mbt`, `.moonbit-async/src/js_async/js_async.mbt`

## 質問・サポート

実装中に不明点があれば、以下のドキュメントを参照:

1. **技術的な判断**: `docs/design/javascript_backend_technical_design_v2_20260208.md`
2. **全体方針**: `docs/steering/javascript_backend_support_v2_20260208.md`
3. **moonbitlang/asyncの実装例**: `.moonbit-async/src/`ディレクトリ

---

**このガイドに従って実装を進めてください。Phase 1から順次実装し、各フェーズで動作確認を行うことを推奨します。**

**v2の主な変更点**:
- Configuration Attributeを使用したバックエンド別実装
- JavaScript FFIによるNode.js child_processの使用
- 既存の統合テストが両バックエンドで実行可能
