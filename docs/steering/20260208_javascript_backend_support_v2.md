# Steering v2: JavaScriptバックエンドでのテスト実行サポート（FFIアプローチ）

## 目的・背景

現在、moonbit_test_containersプロジェクトのテストは`moon test --target native`コマンドでのみ実行可能です。MoonBitはマルチバックエンド対応言語であり、JavaScript（Node.js）バックエンドでもテストを実行できるようにすることで、以下のメリットがあります:

1. **完全なクロスプラットフォーム対応**: 両バックエンドで統合テストを含む全テストが実行可能
2. **開発者体験の向上**: Node.js環境でも同じテストが実行できる
3. **バックエンド間の互換性検証**: Native実装とJS実装の挙動の一致を確認
4. **CI/CD環境の柔軟性**: 環境に応じてバックエンドを選択可能

## ゴール

以下の状態を達成する:

1. **両バックエンドで全テストが実行可能**
   - `moon test --target native`: @process経由でDocker CLI実行
   - `moon test --target js`: FFI経由でDocker CLI実行（Node.js child_process使用）
   - 既存のテストケースが両バックエンドで動作する

2. **実装の明確な分離**
   - Configuration Attribute (`#cfg(target="...")`) でバックエンド別実装を切り替え
   - 同じ関数名で異なる実装を提供
   - コードの重複がない

3. **後方互換性の維持**
   - 既存の`moon test --target native`は引き続き正常に動作する
   - 既存のテストコードへの変更を最小限に抑える

## アプローチ

### 1. Configuration Attributeによる実装分離

MoonBitの標準機能である`#cfg(target="...")`を使用して、バックエンド別の実装を分離:

```moonbit
// Native実装
#cfg(target="native")
pub async fn exec_docker(args) -> Result[String, Error] {
  @process.collect_output_merged("docker", args)
  // ...
}

// JavaScript実装
#cfg(target="js")
pub async fn exec_docker(args) -> Result[String, Error] {
  // FFI経由でNode.js child_process使用
  // ...
}
```

**メリット**:
- 同じ関数名で異なる実装が可能
- ビルド時に適切な実装が自動選択される
- コードが明確に分離される

### 2. JavaScript FFIによるDocker CLI実行

Node.jsの`child_process`モジュールを使用してDocker CLIを実行:

```javascript
const { execSync } = require('child_process');

function runDocker(args) {
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

**メリット**:
- Native実装と同等の機能を提供
- Node.jsの標準モジュールを使用（追加依存なし）
- エラーハンドリングが一貫している

### 3. ファイル構成の設計

```
moonbit_test_containers/
├── types.mbt                    # 型定義（両対応）
├── error.mbt                    # エラー処理（両対応）
├── docker_executor.mbt          # インターフェース定義（両対応）
├── docker_native.mbt            # Native実装（#cfg(target="native")）
├── docker_js.mbt                # JavaScript実装（#cfg(target="js")）
├── container.mbt                # コンテナ管理（両対応）
├── wait_strategy.mbt            # 待機戦略（両対応）
├── logs.mbt                     # ログ機能（両対応）
└── *_wbtest.mbt                 # 統合テスト（両対応）
```

**moon.pkg.jsonの設定**:
```json
{
  "targets": {
    "docker_native.mbt": ["native"],
    "docker_js.mbt": ["js"]
  }
}
```

### 4. 実装フェーズ

#### Phase 1: リファクタリング
1. 既存の`docker.mbt`を`docker_native.mbt`に移動
2. `docker_executor.mbt`にインターフェース定義を追加
3. `#cfg(target="native")`を追加

#### Phase 2: JavaScript実装
4. `docker_js.mbt`を新規作成
5. FFIを使用してNode.js child_processを呼び出し
6. Native実装と同じエラーハンドリング

#### Phase 3: テスト実行
7. `moon test --target native`で既存テスト実行
8. `moon test --target js`で新規実装をテスト
9. 両バックエンドで同じ結果を確認

#### Phase 4: 最適化とドキュメント
10. パフォーマンスチューニング（必要に応じて）
11. エラーハンドリングの改善
12. README.mbt.md更新

## スコープ

### 含むこと
- Configuration Attributeによる実装分離
- JavaScript FFIを使用したDocker CLI実行
- 両バックエンドでの統合テスト実行
- ビルド設定の更新
- ドキュメントの更新

### 含まないこと
- ブラウザ環境での実行（Node.js環境のみ）
- Docker Desktopの代替実装
- パフォーマンス最適化（基本動作の確認が優先）
- Docker REST APIの実装

## 影響範囲

### 変更が必要なファイル
- `docker.mbt` → `docker_native.mbt`にリネーム、`#cfg`追加
- `docker_executor.mbt` → 新規作成（インターフェース定義）
- `docker_js.mbt` → 新規作成（JavaScript実装）
- `moon.pkg.json` → `targets`設定追加
- `README.mbt.md` → バックエンド対応状況を更新

### 影響を受けるコンポーネント
- ビルドシステム（Configuration Attribute対応）
- テストインフラ（両バックエンドでの実行）
- CI/CD設定（両バックエンドのテスト実行）

## 技術的な制約と考慮事項

### 1. Node.js環境の要件

**制約**: JavaScriptバックエンドはNode.js環境が必須
- ブラウザでは動作しない（child_processモジュール不使用のため）
- Node.js 14以上を推奨

**対応**: README.mdに要件を明記

### 2. パフォーマンス

**予想される差異**:
- Native: 高速（ネイティブシステムコール）
- JavaScript: 中速（Node.jsのオーバーヘッド、1.2〜1.5倍程度）

**対応**: 許容範囲として文書化、必要に応じて最適化

### 3. バッファサイズ制限

**制約**: Node.jsのexecSyncはデフォルトで1MBのバッファ制限
**対応**: maxBuffer設定で10MBに拡張

### 4. エラーハンドリングの一貫性

**要件**: 両バックエンドで同じエラー型を返す
**対応**: `TestContainerError`型で統一

## 成功基準

### 機能要件
1. `moon test --target native`が全て成功する
2. `moon test --target js`が全て成功する
3. 両バックエンドで同じテスト結果が得られる
4. エラーハンドリングが一貫している

### 非機能要件
1. テスト実行時間: JS版がNative版の1.5倍以内
2. コードの重複がない
3. ドキュメントが明確で分かりやすい

### 品質要件
1. コードレビュー完了
2. 両バックエンドでテストカバレッジ80%以上
3. CI/CDで両バックエンドのテストが自動実行される

## リスクと緩和策

### リスク1: Node.js環境の要件
- **確率**: 低
- **影響**: 中
- **緩和策**: README.mdに明記、GitHub ActionsでNode.js環境を使用

### リスク2: バックエンド間の挙動差異
- **確率**: 中
- **影響**: 中
- **緩和策**: 両バックエンドでのテスト実行、差異を文書化

### リスク3: パフォーマンスの低下
- **確率**: 低
- **影響**: 低
- **緩和策**: 1.5倍以内を許容、必要に応じて非同期版に移行

### リスク4: 実装の複雑性
- **確率**: 低
- **影響**: 低
- **緩和策**: Configuration Attributeで明確に分離、moonbitlang/asyncの実績

## 前アプローチ（v1）との比較

| 項目 | v1（2層戦略） | v2（FFIアプローチ） |
|------|--------------|-------------------|
| 統合テスト | Native専用 | 両バックエンド対応 |
| ユニットテスト | 新規作成必要 | 不要（既存が動作） |
| コード変更量 | 大 | 中 |
| テストカバレッジ（JS） | 25-30% | 100%（Native同等） |
| 工数 | 21-33時間 | 14-21時間 |
| Node.js依存 | なし | あり |

**v2の優位性**:
- 統合テストが両バックエンドで実行可能
- コード重複がない
- 工数が30-40%削減
- 既存テストをそのまま使用

**v2のトレードオフ**:
- Node.js環境が必須
- 若干の実装複雑性

## 次のステップ

1. **技術設計ドキュメントv2の確認**
   - Configuration Attributeの使用方法
   - JavaScript FFIの実装詳細
   - ファイル構成の詳細

2. **実装ガイドラインv2の作成**
   - リファクタリングの手順
   - FFI実装の手順
   - テスト実行方法

3. **実装開始**
   - Phase 1: リファクタリング
   - Phase 2: JavaScript実装
   - Phase 3: テスト実行
   - Phase 4: 最適化とドキュメント

4. **コードレビューと完了**
   - 両バックエンドでの動作確認
   - パフォーマンス測定
   - ドキュメント更新
   - 完了ドキュメント作成

## 関連ドキュメント

- 技術設計v2: `docs/design/javascript_backend_technical_design_v2_20260208.md`
- 実装ガイドv2: `docs/implementation/javascript_backend_implementation_guide_v2_20260208.md`（作成予定）
- MoonBit Configuration Attribute: https://docs.moonbitlang.com/en/stable/language/attributes.html#configuration-attribute
- MoonBit JavaScript FFI: https://docs.moonbitlang.com/en/stable/ffi-and-wasm-host/js.html
- Node.js child_process: https://nodejs.org/api/child_process.html

## 改訂履歴

| バージョン | 日付 | 変更内容 | 作成者 |
|----------|------|---------|-------|
| 1.0 | 2026-02-08 | 初版作成（2層戦略） | Orchestrator Agent |
| 2.0 | 2026-02-08 | FFIアプローチに変更 | Orchestrator Agent |

---

**このドキュメントはv2として更新され、新しいアプローチに基づいて作業を進めます。**
