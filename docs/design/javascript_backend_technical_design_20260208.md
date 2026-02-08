# 技術設計: JavaScriptバックエンドでのテスト実行サポート

## ドキュメント情報
- **作成日**: 2026-02-08
- **作成者**: Orchestrator Agent
- **ステータス**: 設計完了
- **関連Steering**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/steering/javascript_backend_support_20260208.md`

## エグゼクティブサマリー

moonbit_test_containersプロジェクトは現在、Docker CLIを`@process`パッケージ経由で呼び出すため、**nativeバックエンド専用**です。JavaScriptバックエンドでの完全なテスト実行には、以下の根本的な制約があります:

### 重大な制約
- **moonbitlang/asyncの`@process`パッケージはnative専用**
- Docker CLI実行には`@process.collect_output_merged`が必須
- JavaScriptバックエンドでプロセス実行は未サポート

### 推奨アプローチ
Docker依存テストは**nativeバックエンド専用**とし、以下の2層戦略を採用:

1. **Layer 1: ユニットテスト層（JavaScript対応可能）**
   - ビジネスロジックのテスト
   - データ構造の検証
   - ユーティリティ関数のテスト

2. **Layer 2: 統合テスト層（Native専用）**
   - Docker依存の既存テスト
   - コンテナライフサイクルテスト

## 調査結果

### 1. moonbitlang/asyncのJavaScriptサポート状況

#### サポートされている機能
```moonbit
// integration.mbt より
#cfg(target="js")
pub fn run_async_main(main : async () -> Unit) -> Unit {
  let _ = @coroutine.spawn(main)
  @event_loop.reschedule()
}
```

- **非同期処理の基本機能**: `async/await`構文は動作
- **コルーチン**: JavaScriptイベントループ上で動作
- **タイマー**: `@async.sleep`などは利用可能
- **HTTP**: 一部機能が利用可能（`.moonbit-async/.github/workflows/check.yml`でJS targetテスト実行）

#### サポートされていない機能
```moonbit
// process/moon.pkg より
targets: {
  "basic_test.mbt": [ "native" ],
  "process.mbt": [ "native" ],
  // ... 全てのprocess関連ファイルがnative専用
}
```

- **プロセス実行**: `@process`パッケージ全体がnative専用
- **ファイルシステム**: 一部機能が制限される可能性
- **ネイティブFFI**: C言語FFIは使用不可

### 2. 現在のコードベースの依存関係

#### Docker CLI実行の実装（docker.mbt）
```moonbit
async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  try {
    let (status, output) = @process.collect_output_merged(command, args)
    // ...
  }
}
```

**結論**: 全てのコンテナ操作が`@process`に依存しているため、JavaScript移植は現実的でない。

#### テストファイルの分類

| ファイル名 | 機能 | Docker依存 | JS移植可能性 |
|-----------|------|-----------|------------|
| `basic_lifecycle_wbtest.mbt` | コンテナライフサイクル | ✓ | ✗ |
| `wait_strategies_wbtest.mbt` | 待機戦略 | ✓ | ✗ |
| `logs_*.mbt` | ログ機能 | ✓ | ✗ |
| `volume_mount_wbtest.mbt` | ボリュームマウント | ✓ | ✗ |
| `types.mbt` | 型定義 | ✗ | ✓ |
| `error.mbt` | エラー処理 | ✗ | ✓ |

### 3. 代替アプローチの評価

#### アプローチA: Docker REST API経由での実装
**概要**: HTTP経由でDocker Engineと通信

**メリット**:
- JavaScriptから実装可能（`@http`パッケージ使用）
- プラットフォーム独立性

**デメリット**:
- 大規模なリファクタリングが必要
- Docker REST APIの複雑性（認証、Unix socket通信など）
- メンテナンスコストが高い
- 開発工数: 40-80時間相当

**評価**: 費用対効果が低い

#### アプローチB: ユニットテスト層の分離（推奨）
**概要**: Docker非依存のロジックをJavaScript対応テストとして分離

**メリット**:
- 実装が容易
- 既存コードへの影響が最小限
- 段階的な実装が可能
- メンテナンスコストが低い

**デメリット**:
- Docker依存テストはnative専用のまま

**評価**: 実用的で効果的

#### アプローチC: モックベースのテスト
**概要**: Docker呼び出しをモック化してJavaScript対応

**メリット**:
- テストの高速化
- JavaScript環境で実行可能

**デメリット**:
- モックが複雑になる
- 実際のDocker動作との乖離リスク
- 統合テストの価値が低下

**評価**: 補助的な手段として有効だが、主要アプローチではない

## 採用アプローチ: 2層テスト戦略

### 戦略概要

```
┌─────────────────────────────────────────┐
│  Layer 1: ユニットテスト層              │
│  - ビジネスロジック                     │
│  - データ構造検証                       │
│  - ユーティリティ関数                   │
│  ✓ Native対応 ✓ JavaScript対応         │
└─────────────────────────────────────────┘
               ↓
┌─────────────────────────────────────────┐
│  Layer 2: 統合テスト層                  │
│  - Docker依存テスト                     │
│  - コンテナライフサイクル               │
│  - 待機戦略                             │
│  ✓ Native対応 ✗ JavaScript非対応       │
└─────────────────────────────────────────┘
```

### 実装方針

#### Phase 1: ユニットテスト層の抽出（優先度: 高）

1. **型定義とバリデーションのテスト**
   - `ContainerImage`のbuilderパターンテスト
   - `WaitStrategy`のパラメータ検証
   - `VolumeMount`の設定検証
   - **JavaScript対応可能**: Docker実行不要

2. **パースロジックのテスト**
   - `parse_port_mapping`関数のテスト
   - ログパース処理のテスト
   - エラーメッセージパースのテスト
   - **JavaScript対応可能**: 純粋関数

3. **エラーハンドリングのテスト**
   - `TestContainerError`の生成テスト
   - エラーメッセージのフォーマットテスト
   - **JavaScript対応可能**: Docker非依存

**実装ファイル構成案**:
```
tests/
  unit/                        # JavaScript対応
    types_test.mbt
    parser_test.mbt
    error_test.mbt
    validation_test.mbt

  integration/                 # Native専用
    basic_lifecycle_wbtest.mbt
    wait_strategies_wbtest.mbt
    logs_*_wbtest.mbt
    volume_mount_wbtest.mbt
```

#### Phase 2: ビルド設定の更新（優先度: 高）

**moon.pkg.jsonの設定**:
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
    "*_lifecycle_wbtest.mbt": ["native"],
    "*_streaming_wbtest.mbt": ["native"],
    "*_mount_wbtest.mbt": ["native"],
    "types.mbt": ["native", "js"],
    "error.mbt": ["native", "js"]
  }
}
```

**テスト実行コマンド**:
```bash
# Native: 全てのテスト実行
moon test --target native

# JavaScript: ユニットテストのみ
moon test --target js

# CI/CD: 両方実行
moon test --target native && moon test --target js
```

#### Phase 3: テストの段階的移行（優先度: 中）

1. **既存のテストを分析**
   - Docker依存箇所を特定
   - 純粋関数部分を抽出

2. **新しいユニットテストを作成**
   - Docker非依存の部分をテスト
   - JavaScriptバックエンドで実行検証

3. **ドキュメント更新**
   - テスト戦略を文書化
   - 開発者ガイドの更新

#### Phase 4: CI/CD統合（優先度: 低）

**GitHub Actions設定例**:
```yaml
name: Test

jobs:
  test-native:
    runs-on: ubuntu-latest
    steps:
      - name: Run Native Tests
        run: moon test --target native

  test-javascript:
    runs-on: ubuntu-latest
    steps:
      - name: Run JavaScript Tests
        run: moon test --target js
```

## 実装の詳細

### 1. 条件コンパイルの活用

MoonBitの`#cfg`ディレクティブを使用してバックエンド別の実装を分離:

```moonbit
///|
/// Docker CLI execution (Native only)
#cfg(target="native")
async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  let (status, output) = @process.collect_output_merged(command, args)
  // ...
}

///|
/// Stub for JavaScript backend
#cfg(target="js")
async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  Err(Unsupported("Docker operations are not supported on JavaScript backend"))
}
```

### 2. テストの分類基準

#### ユニットテスト（JavaScript対応）の基準
- ✓ Docker CLI実行なし
- ✓ `@process`パッケージ不使用
- ✓ 純粋関数またはビジネスロジック
- ✓ 外部依存なし

#### 統合テスト（Native専用）の基準
- ✓ Docker CLI実行あり
- ✓ `@process`パッケージ使用
- ✓ 実際のコンテナ操作
- ✓ 外部依存あり（Docker Engine）

### 3. テストファイル命名規約

```
# ユニットテスト（両バックエンド対応）
types_test.mbt
parser_test.mbt
validation_test.mbt

# 統合テスト（Native専用）
*_lifecycle_wbtest.mbt
*_integration_wbtest.mbt
```

## 移植可能性マトリックス

| コンポーネント | Native | JavaScript | 実装方法 |
|--------------|--------|-----------|---------|
| 型定義（types.mbt） | ✓ | ✓ | そのまま |
| エラー処理（error.mbt） | ✓ | ✓ | そのまま |
| Docker実行（docker.mbt） | ✓ | ✗ | 条件コンパイル |
| コンテナ管理（container.mbt） | ✓ | ✗ | Native専用 |
| 待機戦略（wait_strategy.mbt） | ✓ | △ | 一部移植可能 |
| ログ機能（logs.mbt） | ✓ | ✗ | Native専用 |
| 統合テスト | ✓ | ✗ | Native専用 |
| ユニットテスト（新規） | ✓ | ✓ | 両対応 |

**凡例**: ✓=対応可能、△=部分対応、✗=対応不可

## リスク評価

### 高リスク
なし（採用アプローチはローリスク）

### 中リスク
**R1: ユニットテストカバレッジの不足**
- **影響**: JavaScript環境でのテストカバレッジが低くなる可能性
- **緩和策**: 段階的にユニットテストを追加、カバレッジ目標を設定

### 低リスク
**R2: 開発者の混乱**
- **影響**: テスト実行コマンドの使い分けが必要
- **緩和策**: ドキュメントを整備、Makefileやスクリプトで簡素化

## 成功指標

### 機能要件
- [x] JavaScriptバックエンドでビルドが成功する
- [ ] ユニットテストレイヤーが抽出される
- [ ] `moon test --target js`が成功する（最低1つのテスト）
- [ ] `moon test --target native`が引き続き全て成功する

### 非機能要件
- [ ] テストカバレッジ: ユニットテスト層で60%以上
- [ ] ドキュメント: テスト実行方法が明確に記載される
- [ ] CI/CD: 両バックエンドで自動テスト実行

### 品質要件
- [ ] コードレビュー完了
- [ ] READMEとCLAUDE.mdの更新
- [ ] 完了ドキュメントの作成

## 実装工数見積もり

| タスク | 優先度 | 工数（時間） |
|-------|-------|------------|
| ユニットテスト抽出 | 高 | 8-12 |
| ビルド設定更新 | 高 | 2-4 |
| パーサーロジックのテスト作成 | 中 | 4-6 |
| バリデーションテスト作成 | 中 | 3-5 |
| CI/CD統合 | 低 | 2-3 |
| ドキュメント作成 | 高 | 2-3 |
| **合計** | | **21-33時間** |

## 次のステップ

1. **テスト戦略ドキュメントの作成**
   - @test-architect に依頼
   - ユニットテスト層の詳細設計

2. **実装ガイドラインの作成**
   - @coder への指示書
   - 具体的なコード例を含める

3. **実装開始**
   - @coder に実装を依頼
   - Phase 1から順次実装

4. **コードレビュー**
   - @reviewer にレビューを依頼
   - 品質確認

## 参考資料

### MoonBit公式ドキュメント
- [MoonBit Language Reference](https://docs.moonbitlang.com)
- [Conditional Compilation](https://docs.moonbitlang.com/next/toolchain/build-system/conditional-compilation/)
- [Testing Guide](https://docs.moonbitlang.com/next/toolchain/testing/)

### プロジェクト内部リソース
- `CLAUDE.md`: プロジェクトガイドライン
- `AGENTS.md`: MoonBitプロジェクト規約
- `README.mbt.md`: プロジェクト概要
- `.moonbit-async/README.md`: Asyncライブラリドキュメント
- `.moonbit-async/.github/workflows/check.yml`: CI/CD設定例

### 調査結果ファイル
- `.moonbit-async/src/integration.mbt`: JavaScript対応の実装例
- `.moonbit-async/src/process/moon.pkg`: Native専用設定の例
- `.moonbit-async/.github/workflows/check.yml`: JSテスト実行例

## 技術的決定の記録

### TD-1: Docker REST API実装を見送り
- **日付**: 2026-02-08
- **決定**: Docker REST APIを使用した完全なJavaScript移植は実施しない
- **理由**: 費用対効果が低い、メンテナンスコストが高い
- **代替案**: 2層テスト戦略を採用

### TD-2: ユニットテスト層の段階的抽出
- **日付**: 2026-02-08
- **決定**: 既存テストは維持し、新規ユニットテストを追加する方式
- **理由**: 後方互換性維持、リスク最小化
- **影響**: 実装工数が削減される

### TD-3: moon.pkg.jsonのtargets設定活用
- **日付**: 2026-02-08
- **決定**: ファイル単位でバックエンド対応を指定
- **理由**: MoonBitの標準機能、明確な制御が可能
- **実装**: `targets`セクションを追加

## 付録A: 実装チェックリスト

### Phase 1: ユニットテスト層の抽出
- [ ] `types_test.mbt`を作成（builder パターンテスト）
- [ ] `parser_test.mbt`を作成（parse_port_mapping等）
- [ ] `validation_test.mbt`を作成（入力検証）
- [ ] `error_test.mbt`を作成（エラー処理）

### Phase 2: ビルド設定
- [ ] `moon.pkg.json`に`targets`セクション追加
- [ ] JavaScriptバックエンドでビルド確認
- [ ] Nativeバックエンドで既存テスト確認

### Phase 3: ドキュメント
- [ ] `README.mbt.md`更新（テスト実行方法）
- [ ] `CLAUDE.md`更新（必要に応じて）
- [ ] 完了ドキュメント作成

### Phase 4: 検証
- [ ] `moon test --target native`実行成功
- [ ] `moon test --target js`実行成功
- [ ] コードレビュー完了
- [ ] CI/CD設定（オプション）

## 付録B: よくある質問（FAQ）

### Q1: なぜDocker REST APIを使わないのか？
**A**: 実装コストとメンテナンスコストが高く、費用対効果が低いためです。プロセス実行がnative専用である制約は、MoonBitのアーキテクチャに由来するため、回避は困難です。

### Q2: JavaScript対応のメリットは何か？
**A**: ビジネスロジックやユーティリティ関数のテストを、ブラウザやNode.js環境で実行できます。また、クロスプラットフォームでの動作確認が可能になります。

### Q3: 既存のテストは削除されるのか？
**A**: いいえ、既存の統合テストはNative専用として維持されます。新たにユニットテスト層が追加される形です。

### Q4: CI/CDでDocker環境が不要になるのか？
**A**: いいえ、統合テストにはDockerが必要です。ユニットテストのみJavaScriptで実行可能になります。

### Q5: 将来的に完全なJavaScript対応は可能か？
**A**: MoonBitの`@process`パッケージがJavaScript対応しない限り困難です。ただし、WebAssemblyの進化やMoonBitのバックエンド拡張により、将来的に可能性はあります。

## 改訂履歴

| バージョン | 日付 | 変更内容 | 作成者 |
|----------|------|---------|-------|
| 1.0 | 2026-02-08 | 初版作成 | Orchestrator Agent |

---

**このドキュメントは後続の実装フェーズで参照されます。**
