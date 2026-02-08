# 技術設計 v2: JavaScriptバックエンドでのテスト実行サポート（FFIアプローチ）

## ドキュメント情報
- **作成日**: 2026-02-08（v2: 更新）
- **作成者**: Orchestrator Agent
- **ステータス**: 設計完了（v2 - FFIアプローチ）
- **関連Steering**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/steering/javascript_backend_support_20260208.md`
- **前バージョン**: `javascript_backend_technical_design_20260208.md`（2層戦略アプローチ）

## エグゼクティブサマリー

### アプローチの変更

**v1（旧アプローチ）**: Docker依存テストはNative専用、ユニットテストのみJavaScript対応
**v2（新アプローチ）**: JavaScript FFIを使用してDocker CLI実行を実装し、**統合テストを両バックエンドで実行可能**にする

### 新しい戦略の概要

```
┌────────────────────────────────────────────────┐
│  統合テスト（Docker依存）                      │
│  ✓ Native: @process経由でDocker CLI実行       │
│  ✓ JavaScript: FFI経由でDocker CLI実行        │
│  → 両バックエンドで同じテストが実行可能       │
└────────────────────────────────────────────────┘
          ↓ Configuration Attribute
┌─────────────────┬──────────────────────────────┐
│ Native実装      │ JavaScript実装               │
│ @process使用    │ FFI使用（Node.js）           │
│ 同じ関数名      │ 同じ関数名                   │
└─────────────────┴──────────────────────────────┘
```

### 重要な発見

1. **MoonBitのConfiguration Attribute**: `#cfg(target="native")`と`#cfg(target="js")`でバックエンド別実装が可能
2. **JavaScript FFI**: `extern "js" fn`でNode.jsのchild_processモジュールを呼び出し可能
3. **moonbitlang/asyncの先例**: `integration.mbt`で同様のパターンを使用

## 技術調査結果

### 1. Configuration Attributeの使用方法

#### MoonBit公式ドキュメント
参考: https://docs.moonbitlang.com/en/stable/language/attributes.html#configuration-attribute

#### moonbitlang/asyncでの実装例

**ファイル**: `.moonbit-async/src/integration.mbt`

```moonbit
///|
/// This function is used for integration of `moonbitlang/async`
/// into the MoonBit toolchain, do not call directly.
#coverage.skip
#cfg(target="native")
pub fn run_async_main(main : async () -> Unit) -> Unit {
  @event_loop.with_event_loop(() => main()) catch {
    err => {
      println(err)
      exit(1)
    }
  }
}

///|
#cfg(target="native")
extern "C" fn exit(code : Int) = "exit"

///|
#cfg(target="js")
pub fn run_async_main(main : async () -> Unit) -> Unit {
  let _ = @coroutine.spawn(main)
  @event_loop.reschedule()
}
```

**ポイント**:
- 同じ関数名`run_async_main`が両バックエンドで定義されている
- `#cfg(target="native")`と`#cfg(target="js")`で実装を切り替え
- 関数シグネチャ（引数と戻り値）は同一

### 2. JavaScript FFIの使用方法

#### FFIの基本構文

**ファイル**: `.moonbit-async/src/js_async/js_async.mbt`

```moonbit
///|
/// Create a new abort controller
pub extern "js" fn AbortController::new() -> AbortController =
  #| () => new AbortController()

///|
extern "js" fn set_timeout(duration : Int, f : () -> Unit) -> Timer =
  #| (duration, f) => setTimeout(f, duration)
```

**構文**:
```moonbit
extern "js" fn function_name(args) -> ReturnType =
  #| (js_args) => { JavaScript code here }
```

#### JavaScript側のPromise処理

```moonbit
extern "js" fn JsValue::new_promise(
  f : ((JsValue) -> Unit, (JsValue) -> Unit) -> Unit,
) -> JsValue =
  #| (f) => new Promise(f)

pub async fn[X] Promise::wait(
  promise : Promise[X],
  abort_controller? : AbortController,
) -> X {
  // Promise解決を待機
  // ...
}
```

### 3. Node.js child_processモジュールの使用

#### Node.jsでのDocker CLI実行

JavaScriptバックエンド（Node.js環境）では、`child_process.execSync`または`child_process.spawn`を使用してDocker CLIを実行できます。

```javascript
// Node.js例
const { execSync } = require('child_process');

function runDockerCommand(args) {
  try {
    const result = execSync('docker ' + args.join(' '), {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return { status: 0, output: result };
  } catch (error) {
    return { status: error.status || 1, output: error.stderr || error.message };
  }
}
```

## 新しい実装アプローチ

### アーキテクチャ概要

```
┌─────────────────────────────────────────────────┐
│  Application Layer                              │
│  - container.mbt                                │
│  - wait_strategy.mbt                            │
│  - logs.mbt                                     │
│  └─ 呼び出し: exec_docker(args)                │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  Abstraction Layer (docker_executor.mbt)        │
│  - 両バックエンドで共通のインターフェース      │
│  - pub async fn exec_docker(args) -> Result     │
└─────────────────────────────────────────────────┘
          ↓ Configuration Attribute
┌──────────────────────┬──────────────────────────┐
│ Native実装           │ JavaScript実装           │
│ (docker_native.mbt)  │ (docker_js.mbt)          │
│                      │                          │
│ #cfg(target="native")│ #cfg(target="js")        │
│ @process使用         │ FFI + child_process使用  │
└──────────────────────┴──────────────────────────┘
```

### ファイル構成

```
moonbit_test_containers/
├── types.mbt                    # 型定義（両対応）
├── error.mbt                    # エラー処理（両対応）
├── docker_executor.mbt          # 抽象化レイヤー（両対応）
├── docker_native.mbt            # Native実装
│   └── #cfg(target="native")
│       └── @process使用
├── docker_js.mbt                # JavaScript実装
│   └── #cfg(target="js")
│       └── FFI + Node.js child_process
├── container.mbt                # コンテナ管理（両対応）
├── wait_strategy.mbt            # 待機戦略（両対応）
├── logs.mbt                     # ログ機能（両対応）
└── *_wbtest.mbt                 # 統合テスト（両対応）
```

### 実装の詳細

#### 1. 抽象化レイヤー（docker_executor.mbt）

```moonbit
// docker_executor.mbt
// Both Native and JavaScript backends

///|
/// Execute docker command and return output
/// This function is implemented separately for each backend
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise
```

**ポイント**:
- 関数シグネチャのみ定義（実装なし）
- 両バックエンドで共通のインターフェース
- 実際の実装はバックエンド別のファイルに記述

#### 2. Native実装（docker_native.mbt）

```moonbit
// docker_native.mbt
// Native backend only

///|
#cfg(target="native")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  try {
    let (status, output) = @process.collect_output_merged(command, args)
    if status == 0 {
      Ok(output.trim_end())
    } else {
      Err(
        DockerCommandFailed(
          command=args.join(" "),
          exit_code=status,
          output=output,
        ),
      )
    }
  } catch {
    e => Err(DockerCommandFailed(command=args.join(" "), exit_code=-1, output=e.to_string()))
  }
}
```

**ポイント**:
- `#cfg(target="native")`で条件付きコンパイル
- `@process.collect_output_merged`を使用
- 既存の実装を維持

#### 3. JavaScript実装（docker_js.mbt）

```moonbit
// docker_js.mbt
// JavaScript backend only

///|
#external
priv type JsBuffer

///|
#external
priv type JsError

///|
/// Node.js child_process.execSync wrapper
extern "js" fn exec_docker_sync(
  command : String,
  args : Array[String],
) -> (Int, String) =
  #| (command, args) => {
  #|   const { execSync } = require('child_process');
  #|   try {
  #|     const argsStr = args.join(' ');
  #|     const fullCommand = command + ' ' + argsStr;
  #|     const output = execSync(fullCommand, {
  #|       encoding: 'utf8',
  #|       stdio: ['pipe', 'pipe', 'pipe'],
  #|       maxBuffer: 10 * 1024 * 1024  // 10MB
  #|     });
  #|     return [0, output];
  #|   } catch (error) {
  #|     const status = error.status || 1;
  #|     const output = error.stderr ? error.stderr.toString() : error.message;
  #|     return [status, output];
  #|   }
  #| }

///|
#cfg(target="js")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  let (status, output) = exec_docker_sync(command, args)

  if status == 0 {
    Ok(output.trim_end())
  } else {
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
- `#cfg(target="js")`で条件付きコンパイル
- `extern "js" fn`でNode.jsのchild_processを使用
- Nativeと同じ関数シグネチャとエラー処理
- 同期実行（execSync）を使用して実装を簡素化

#### 4. 非同期実装の代替案（Promiseベース）

より高度な実装では、非同期のchild_process.execを使用:

```moonbit
// docker_js.mbt (非同期版)

///|
#external
priv type JsPromise

///|
extern "js" fn exec_docker_async(
  command : String,
  args : Array[String],
) -> JsPromise =
  #| (command, args) => {
  #|   const { exec } = require('child_process');
  #|   const { promisify } = require('util');
  #|   const execPromise = promisify(exec);
  #|
  #|   return (async () => {
  #|     try {
  #|       const argsStr = args.join(' ');
  #|       const fullCommand = command + ' ' + argsStr;
  #|       const { stdout, stderr } = await execPromise(fullCommand, {
  #|         maxBuffer: 10 * 1024 * 1024
  #|       });
  #|       return [0, stdout || ''];
  #|     } catch (error) {
  #|       const status = error.code || 1;
  #|       const output = error.stderr || error.message;
  #|       return [status, output];
  #|     }
  #|   })();
  #| }

///|
#cfg(target="js")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  let promise = exec_docker_async(command, args)

  // JsPromiseをMoonBitのPromiseに変換
  let (status, output) = @js_async.Promise::wait(promise)

  if status == 0 {
    Ok(output.trim_end())
  } else {
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

### 5. moon.pkg.jsonの設定

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

**ポイント**:
- `docker_native.mbt`はNative専用
- `docker_js.mbt`はJavaScript専用
- その他のファイルは両対応（デフォルト）

## 実装戦略

### Phase 1: リファクタリング（優先度: 最高）

#### ステップ 1.1: 既存のdocker.mbtを分割

**現在**:
```
docker.mbt
└── exec_docker()実装（@process使用）
```

**変更後**:
```
docker_executor.mbt     # インターフェース定義
docker_native.mbt       # Native実装
docker_js.mbt          # JavaScript実装（新規）
```

#### ステップ 1.2: 既存コードの移行

1. `docker.mbt`の`exec_docker`関数を`docker_native.mbt`に移動
2. `#cfg(target="native")`を追加
3. `docker_executor.mbt`にインターフェース定義を追加

### Phase 2: JavaScript実装（優先度: 高）

#### ステップ 2.1: 基本的な同期実装

```moonbit
// docker_js.mbt
#cfg(target="js")
pub async fn exec_docker(args : Array[String]) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  let (status, output) = exec_docker_sync(command, args)
  // ... エラーハンドリング
}
```

#### ステップ 2.2: テスト実行

```bash
# Nativeテスト
moon test --target native

# JavaScriptテスト
moon test --target js

# 両方のテストが同じ結果を出力することを確認
```

### Phase 3: 最適化（優先度: 中）

#### ステップ 3.1: 非同期実装への移行（オプション）

同期版で動作確認後、非同期版に移行してパフォーマンス向上

#### ステップ 3.2: エラーハンドリングの改善

JavaScript特有のエラー処理の追加

### Phase 4: ドキュメント更新（優先度: 高）

#### ステップ 4.1: README.mbt.md更新

```markdown
## Backend Support

- **Native/LLVM Backend**: Full support using native process execution
- **JavaScript Backend**: Full support using Node.js child_process

Both backends can run the complete test suite including Docker integration tests.

### Requirements

- Docker Engine installed and running
- For JavaScript backend: Node.js runtime
```

## 技術的な考慮事項

### 1. パフォーマンス

| バックエンド | 実装 | パフォーマンス | 備考 |
|-------------|------|--------------|------|
| Native | @process | 高速 | ネイティブシステムコール |
| JavaScript（同期） | execSync | 中速 | Node.jsのオーバーヘッド |
| JavaScript（非同期） | exec + Promise | 中速〜高速 | 非ブロッキング |

**推奨**: Phase 2では同期版、Phase 3で非同期版に移行

### 2. エラーハンドリング

#### Native実装
```moonbit
@process.collect_output_merged(command, args)
→ Result[(Int, String), Error]
```

#### JavaScript実装
```javascript
try {
  execSync(...)
  return [0, stdout]
} catch (error) {
  return [error.status, error.stderr]
}
```

両方で同じエラー形式に変換:
```moonbit
Err(DockerCommandFailed(command, exit_code, output))
```

### 3. バッファサイズ

Node.jsのexecSyncはデフォルトで1MBのバッファ制限があります。

```javascript
execSync(command, {
  maxBuffer: 10 * 1024 * 1024  // 10MB
})
```

大きな出力（ログストリーミング等）では調整が必要。

### 4. プラットフォーム依存性

| 機能 | Native | JavaScript |
|------|--------|-----------|
| Docker CLI実行 | ✓ | ✓ |
| 標準入出力 | ✓ | ✓ |
| 環境変数 | ✓ | ✓ |
| 作業ディレクトリ | ✓ | ✓ |
| シグナル処理 | ✓ | △（制限あり） |

## リスク評価と緩和策

### 高リスク

**R1: Node.js環境の要件**
- **影響**: JavaScriptバックエンドはNode.js必須
- **緩和策**: README.mdに要件を明記、ブラウザ環境では使用不可と文書化

### 中リスク

**R2: execSyncのバッファ制限**
- **影響**: 大量のログ出力でエラー
- **緩和策**: maxBuffer設定、必要に応じてストリーミング実装

**R3: バックエンド間の挙動差異**
- **影響**: テスト結果が異なる可能性
- **緩和策**: 両バックエンドでのテスト実行、差異の文書化

### 低リスク

**R4: 実装の複雑性**
- **影響**: コード量の増加
- **緩和策**: Configuration Attributeで分離、保守性を維持

## 成功指標

### 機能要件
- [ ] JavaScriptバックエンドで`exec_docker`が動作する
- [ ] 両バックエンドで全ての統合テストが成功する
- [ ] エラーハンドリングが両バックエンドで一貫している

### 非機能要件
- [ ] テスト実行時間: JavaScript版がNative版の1.5倍以内
- [ ] コードの重複がない（Configuration Attributeで分離）
- [ ] ドキュメントが明確

### 品質要件
- [ ] コードレビュー完了
- [ ] 両バックエンドでテストカバレッジ80%以上
- [ ] README.mbt.md更新完了

## 実装工数見積もり

| タスク | 優先度 | 工数（時間） |
|-------|-------|------------|
| リファクタリング（docker.mbt分割） | 最高 | 2-3 |
| JavaScript FFI実装（同期版） | 高 | 4-6 |
| テスト実行と検証 | 高 | 2-3 |
| エラーハンドリング改善 | 中 | 2-3 |
| 非同期版への移行（オプション） | 中 | 3-4 |
| ドキュメント更新 | 高 | 1-2 |
| **合計** | | **14-21時間** |

**v1との比較**:
- v1（2層戦略）: 21-33時間
- v2（FFIアプローチ）: 14-21時間
- **工数削減**: 約30-40%（ユニットテスト抽出が不要なため）

## v1からの変更点

### アプローチの比較

| 項目 | v1（2層戦略） | v2（FFIアプローチ） |
|------|--------------|-------------------|
| 統合テスト | Native専用 | 両バックエンド対応 |
| ユニットテスト | 新規作成必要 | 不要（既存が動作） |
| コード変更量 | 大（新規テスト多数） | 中（リファクタリング） |
| テストカバレッジ | JS: 25-30% | JS: 100%（Native同等） |
| 工数 | 21-33時間 | 14-21時間 |

### メリット

1. **完全な機能対応**: 統合テストが両バックエンドで実行可能
2. **コード重複なし**: Configuration Attributeで実装を分離
3. **既存テスト維持**: 新規テスト作成が不要
4. **工数削減**: v1より30-40%削減

### デメリット

1. **Node.js依存**: JavaScriptバックエンドはNode.js必須
2. **若干の複雑性**: バックエンド別実装が必要
3. **パフォーマンス**: JS版はNative版より若干遅い可能性

## 次のステップ

1. **実装ガイドラインv2の作成**
   - Configuration Attributeの使用方法
   - JavaScript FFIの実装手順
   - リファクタリングの手順

2. **実装開始**
   - Phase 1: リファクタリング
   - Phase 2: JavaScript実装
   - Phase 3: テスト実行

3. **コードレビュー**
   - 両バックエンドでの動作確認
   - パフォーマンス測定
   - ドキュメント確認

## 参考資料

### MoonBit公式ドキュメント
- Configuration Attribute: https://docs.moonbitlang.com/en/stable/language/attributes.html#configuration-attribute
- JavaScript FFI: https://docs.moonbitlang.com/en/stable/ffi-and-wasm-host/js.html

### プロジェクト内部リソース
- `.moonbit-async/src/integration.mbt`: Configuration Attribute実装例
- `.moonbit-async/src/js_async/js_async.mbt`: JavaScript FFI実装例
- `.moonbit-async/src/internal/event_loop/event_loop.js.mbt`: Node.js統合例

### Node.js公式ドキュメント
- child_process: https://nodejs.org/api/child_process.html
- execSync: https://nodejs.org/api/child_process.html#child_processexecsynccommand-options

## 技術的決定の記録

### TD-1: FFIアプローチの採用
- **日付**: 2026-02-08
- **決定**: JavaScript FFIを使用してDocker CLI実行を実装
- **理由**: 両バックエンドで統合テスト実行が可能、コード重複を削減
- **影響**: Node.js環境が必須になる

### TD-2: Configuration Attributeの活用
- **日付**: 2026-02-08
- **決定**: `#cfg(target="native")`と`#cfg(target="js")`で実装を分離
- **理由**: MoonBitの標準機能、moonbitlang/asyncで実績あり
- **影響**: コードが明確に分離される

### TD-3: 同期実装を優先
- **日付**: 2026-02-08
- **決定**: Phase 2ではexecSyncを使用、Phase 3で非同期版を検討
- **理由**: 実装が簡単、早期にテスト実行可能
- **影響**: 若干のパフォーマンス低下の可能性

## 改訂履歴

| バージョン | 日付 | 変更内容 | 作成者 |
|----------|------|---------|-------|
| 1.0 | 2026-02-08 | 初版作成（2層戦略） | Orchestrator Agent |
| 2.0 | 2026-02-08 | FFIアプローチに変更 | Orchestrator Agent |

---

**このドキュメントはv2として更新され、実装フェーズで参照されます。**
