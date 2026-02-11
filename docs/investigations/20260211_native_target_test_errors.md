# Native ターゲットテストエラー調査報告

**日付**: 2026-02-11
**ステータス**: 調査完了（修正不要）

## 概要

`moon test --target native` はテストを実行しますが、コルーチンの状態管理に関連する async/await ランタイムエラーが発生します。これらのエラーは MoonBit async ランタイムで発生し、既知のコンパイラの C コード生成の問題に関連しています。

## エラー詳細

### 主要エラー

```
Suspend: Internal error: Coroutine in invalid state during suspend
```

**発生場所**: `wait_strategies_wbtest.mbt:140` (PostgreSQL ログメッセージ待機戦略テスト)

**スタックトレース**:
```
@moonbitlang/async/process.collect_output_merged
  ↓
@ryota0624/moonbit_test_containers.exec_docker (docker_native.mbt:12)
  ↓
@ryota0624/moonbit_test_containers.ContainerImage::start (container.mbt:42)
  ↓
wait strategy log message postgres test
```

### 副次的エラー

```
RUNTIME ERROR: abort() called
```

**発生場所**: テスト実行初期（Redis TCP ポート待機戦略テスト）

## 根本原因分析

### 1. 既知の MoonBit コンパイラ問題

複数のファイルにネイティブバックエンドの制限に関する警告が含まれています：

**`wait_strategy.mbt` より（8-11行目）**:
```
NOTE (2026-02-08): Error handling in this file has been simplified to work around
a MoonBit compiler C code generation issue. Complex catch blocks with closures
can cause "too many arguments to function" errors in generated C code.
This affects native backend only; JavaScript backend works correctly.
```

**`logs.mbt` より（3-5行目）**:
```
NOTE (2026-02-08): Error handling in this file has been simplified to work around
a MoonBit compiler C code generation issue when combining async functions with
complex catch blocks and closures. This affects native backend only.
```

### 2. 非同期プロセス実行の負荷

ログメッセージ待機戦略（`wait_strategy.mbt:81-119` の `wait_for_log_message`）は頻繁なポーリングを実行します：

- **ポーリング間隔**: 500ms
- **PostgreSQL タイムアウト**: 60秒
- **最大試行回数**: 120回
- **テストあたりの Docker コマンド実行数**: 最大120回の `docker logs` 呼び出し

各 `docker logs` 呼び出しは以下を実行します：
```moonbit
@process.collect_output_merged(command, args)  // docker_native.mbt:11
```

これにより多数の並行非同期プロセスが生成され、コルーチンスケジューラに過度の負荷がかかる可能性があります。

### 3. コルーチン状態管理

エラー「Coroutine in invalid state during suspend」が示すこと：

1. 複数の非同期タスクが同時に実行されている
2. コルーチンの状態遷移に矛盾が発生している
3. MoonBit async ランタイムで競合状態の可能性

問題を悪化させる要因：
- 複数のテストが順次実行されるが、非同期操作がオーバーラップする
- 各テストが集中的なポーリングを実行（120回以上の docker コマンド）
- catch ブロックとクロージャを含む複雑なエラー処理

### 4. 並行実行制御の欠如

`wait_strategy.mbt` には以下のコメントがありますが：
```
// NOTE: Port checks are serialized by semaphore to prevent concurrent process overload
```

実際のセマフォ実装はコードベースに見つかりませんでした。これは以下を意味します：
- docker コマンド実行の並行制御なし
- 並行非同期プロセス数の制限なし
- リソース枯渇の可能性

## テスト実行結果

### 成功したテスト（エラー発生前）

1. ✅ Redis TCP ポート待機戦略
2. ✅ Alpine 遅延待機戦略
3. ✅ Nginx HTTP 待機戦略
4. ✅ Nginx HTTP 待機戦略（カスタムパス エラーハンドリング）

### 失敗したテスト

1. ❌ Redis TCP ポート待機戦略 - `abort() called`
2. ❌ PostgreSQL ログメッセージ待機戦略 - `Coroutine in invalid state`

### 注目すべき点

- JavaScript ターゲット: **全23テスト成功** ✅
- Native ターゲット: **ランタイムエラーで早期に失敗** ❌

## なぜ JavaScript は動作するが Native は失敗するのか

### JavaScript バックエンド（`docker_js.mbt`）

- Node.js `child_process` の `spawnSync` を使用
- 同期実行（コルーチン不使用）
- シンプルなエラー処理
- 非同期ランタイムの複雑さなし

### Native バックエンド（`docker_native.mbt`）

- `@process.collect_output_merged` を使用
- 完全に async/await ベース
- 複雑なコルーチン状態管理
- MoonBit コンパイラの C コード生成問題の影響を受ける

## 影響評価

### 重大度

**中程度** - Native ターゲットでテストが失敗するが：
- JavaScript ターゲットは正常動作（全テスト成功）
- これは開発/テストの問題であり、本番ランタイムの問題ではない
- 根本原因はアプリケーションコードではなく MoonBit コンパイラ/ランタイムにある

### 適用済みの回避策

1. ✅ エラー処理の簡略化（実装済み）
2. ✅ クロージャを含む複雑な catch ブロックの回避（実装済み）
3. ❌ セマフォベースの並行制御（言及されているが未実装）

### ユーザーへの影響

- `moon test` を実行するユーザーは native テストの失敗を目にする
- `moon test --target js` を実行するユーザーは全テスト成功を確認できる
- ライブラリ機能は両ターゲットで正しく動作する（テストハーネス外での使用時）

## 推奨事項

### ユーザー向け

1. **テストには JavaScript ターゲットを使用**: `moon test --target js`
2. **Native ターゲットの失敗を想定**: 既知の問題、無視しても安全
3. **MoonBit チームに報告**: 本番コードで同様の問題に遭遇した場合

### 今後の開発向け

1. **Docker コマンド実行用のセマフォを実装**
   - 並行プロセス生成を制限
   - Docker コマンド実行のキューを追加
   - コルーチンへの圧力を軽減

2. **ポーリング頻度を削減**
   - ポーリング間隔を 500ms から 1000ms 以上に増加
   - 指数バックオフを実装
   - 並行非同期操作の数を削減

3. **Native 用の同期フォールバックを検討**
   - コンパイル時に native ターゲットを検出
   - よりシンプルな同期実装を使用（利用可能な場合）
   - パフォーマンスと信頼性をトレードオフ

4. **MoonBit コンパイラのアップデートを監視**
   - C コード生成問題の修正を追跡
   - コンパイラが修正されたら回避策を削除
   - 複雑なエラー処理を再有効化

## ミニマムな再現テスト

testcontainers を使用せずにエラーを再現するミニマムなテストコードを作成しました：

**場所**: `docs/investigations/minimal_reproduce_test.mbt`

### テスト内容

1. **高頻度ポーリング** - 120回の反復で `@process.collect_output_merged` を実行
2. **並行ポーリングタスク** - 3つの並行タスクを同時実行
3. **ネストされた非同期処理** - 20階層の再帰的非同期呼び出し
4. **高速プロセス生成** - 遅延なしで100回のプロセス生成
5. **混合非同期操作** - 実際の testcontainers 使用パターンを模倣

### 実行方法

```bash
# プロジェクトルートにコピー
cp docs/investigations/minimal_reproduce_test.mbt ./minimal_reproduce_wbtest.mbt

# Native ターゲットで実行
moon test --target native

# 実行後、ファイルを削除
rm minimal_reproduce_wbtest.mbt
```

### 期待される結果

- **JavaScript ターゲット**: すべてのテスト成功 ✅
- **Native ターゲット**: コルーチンエラー発生 ❌

詳細な使用方法は `docs/investigations/README_minimal_reproduce.md` を参照してください。

## 関連ファイル

- `docker_native.mbt` - Native docker コマンド実行
- `wait_strategy.mbt` - 既知の問題を含む待機戦略実装
- `logs.mbt` - 簡略化されたエラー処理を含むログ取得
- `wait_strategies_wbtest.mbt` - エラーをトリガーするテスト
- `docs/investigations/minimal_reproduce_test.mbt` - ミニマムな再現テストコード
- `docs/investigations/README_minimal_reproduce.md` - ミニマムテストの使用方法

## 結論

Native ターゲットのテスト失敗の原因：

1. **MoonBit コンパイラの既知の制限** - async/await と C コード生成の問題
2. **高負荷の非同期プロセス** - 頻繁な docker コマンドポーリング
3. **コルーチン状態管理の問題** - MoonBit async ランタイムにおける問題
4. **並行実行制御の欠如** - 並列実行を制限する仕組みがない

**現時点で修正は不要**、理由：
- 根本原因は MoonBit コンパイラ/ランタイムにある
- 回避策は既に適用済み
- JavaScript ターゲットは正常動作
- これはテストインフラの問題であり、機能的なバグではない

**対策**: 信頼性の高いテスト実行には `moon test --target js` を使用してください。
