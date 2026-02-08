# テスト戦略: JavaScriptバックエンド対応

## ドキュメント情報
- **作成日**: 2026-02-08
- **作成者**: Orchestrator Agent (Test Architect役)
- **ステータス**: 戦略確定
- **関連ドキュメント**:
  - Steering: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/steering/javascript_backend_support_20260208.md`
  - Technical Design: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/design/javascript_backend_technical_design_20260208.md`

## テスト戦略の概要

### 基本方針

**2層テスト戦略**により、Docker依存とDocker非依存のテストを明確に分離します:

```
┌────────────────────────────────────────────────────┐
│           Test Pyramid                              │
│                                                      │
│  ┌──────────────────────────────────────┐          │
│  │   Integration Tests (Native Only)    │          │
│  │   - Docker lifecycle                 │          │
│  │   - Wait strategies                  │          │
│  │   - Volume mounts                    │          │
│  └──────────────────────────────────────┘          │
│                    ▲                                │
│                    │                                │
│  ┌────────────────────────────────────────────┐   │
│  │   Unit Tests (Native + JavaScript)        │   │
│  │   - Business logic                        │   │
│  │   - Data validation                       │   │
│  │   - Parsers & formatters                  │   │
│  │   - Error handling                        │   │
│  └────────────────────────────────────────────┘   │
│                                                      │
└────────────────────────────────────────────────────┘
```

### テストカバレッジ目標

| レイヤー | Native | JavaScript | 目標カバレッジ |
|---------|--------|-----------|--------------|
| ユニットテスト | 100% | 100% | 70%以上 |
| 統合テスト | 100% | 0% | 85%以上（Native） |
| **全体** | **100%** | **25-30%** | **80%以上** |

## テスト分類

### Layer 1: ユニットテスト（JavaScript対応）

#### 1.1 型定義とビルダーパターンのテスト

**目的**: `ContainerImage`および関連型の正常動作を検証

**テストファイル**: `tests/unit/types_test.mbt`

**テストケース**:
```moonbit
// Test 1: 基本的なコンテナイメージ生成
test "ContainerImage::new creates valid image" {
  let image = ContainerImage::new("redis", "7.2.4")
  inspect(image.name, content="redis")
  inspect(image.tag, content="7.2.4")
  inspect(image.exposed_ports.length(), content="0")
}

// Test 2: ポート公開の設定
test "with_exposed_port adds port correctly" {
  let image = ContainerImage::new("redis", "latest")
    .with_exposed_port(6379)
    .with_exposed_port(6380)
  inspect(image.exposed_ports.length(), content="2")
  inspect(image.exposed_ports[0], content="6379")
  inspect(image.exposed_ports[1], content="6380")
}

// Test 3: 環境変数の設定
test "with_env_var adds environment variable" {
  let image = ContainerImage::new("postgres", "15")
    .with_env_var("POSTGRES_USER", "testuser")
    .with_env_var("POSTGRES_PASSWORD", "testpass")
  inspect(image.env_vars.length(), content="2")
}

// Test 4: ボリュームマウントの設定
test "with_volume adds volume mount" {
  let image = ContainerImage::new("nginx", "latest")
    .with_volume("/host/path", "/container/path", read_only=true)
  inspect(image.volumes.length(), content="1")
  let volume = image.volumes[0]
  inspect(volume.host_path, content="/host/path")
  inspect(volume.container_path, content="/container/path")
  inspect(volume.read_only, content="true")
}

// Test 5: 待機戦略の設定
test "with_wait_for sets wait strategy" {
  let image = ContainerImage::new("redis", "latest")
    .with_wait_for(WaitStrategy::TcpPort(6379))
  match image.wait_strategy {
    Some(WaitStrategy::TcpPort(port)) => inspect(port, content="6379")
    _ => abort("Wait strategy not set correctly")
  }
}

// Test 6: チェーンメソッド呼び出し
test "builder pattern chaining" {
  let image = ContainerImage::new("app", "1.0")
    .with_exposed_port(8080)
    .with_env_var("ENV", "test")
    .with_wait_timeout(60)
  inspect(image.exposed_ports.length(), content="1")
  inspect(image.env_vars.length(), content="1")
  inspect(image.wait_timeout, content="60")
}
```

**実行方法**:
```bash
moon test --target native tests/unit/types_test.mbt
moon test --target js tests/unit/types_test.mbt
```

#### 1.2 パーサーロジックのテスト

**目的**: ポートマッピングやログ出力のパース処理を検証

**テストファイル**: `tests/unit/parser_test.mbt`

**テストケース**:
```moonbit
// Test 1: 標準的なポートマッピングのパース
test "parse_port_mapping handles standard format" {
  match parse_port_mapping("0.0.0.0:32768") {
    Some(port) => inspect(port, content="32768")
    None => abort("Failed to parse standard format")
  }
}

// Test 2: IPv6形式のポートマッピング
test "parse_port_mapping handles IPv6 format" {
  match parse_port_mapping("[::]:32769") {
    Some(port) => inspect(port, content="32769")
    None => abort("Failed to parse IPv6 format")
  }
}

// Test 3: ホスト名付きポートマッピング
test "parse_port_mapping handles hostname format" {
  match parse_port_mapping("localhost:8080") {
    Some(port) => inspect(port, content="8080")
    None => abort("Failed to parse hostname format")
  }
}

// Test 4: 無効な入力
test "parse_port_mapping returns None for invalid input" {
  inspect(parse_port_mapping("invalid"), content="None")
  inspect(parse_port_mapping(""), content="None")
  inspect(parse_port_mapping("no-colon"), content="None")
}

// Test 5: エッジケース
test "parse_port_mapping edge cases" {
  inspect(parse_port_mapping("0.0.0.0:0"), content="Some(0)")
  inspect(parse_port_mapping("0.0.0.0:65535"), content="Some(65535)")
  inspect(parse_port_mapping("0.0.0.0:99999"), content="None") // invalid port
}
```

**実行方法**:
```bash
moon test --target native tests/unit/parser_test.mbt
moon test --target js tests/unit/parser_test.mbt
```

#### 1.3 バリデーションロジックのテスト

**目的**: 入力検証ロジックの正常動作を確認

**テストファイル**: `tests/unit/validation_test.mbt`

**テストケース**:
```moonbit
// Test 1: ポート番号の妥当性検証
test "validate_port rejects invalid ports" {
  inspect(validate_port(-1), content="false")
  inspect(validate_port(0), content="true")
  inspect(validate_port(80), content="true")
  inspect(validate_port(65535), content="true")
  inspect(validate_port(65536), content="false")
}

// Test 2: イメージ名の妥当性検証
test "validate_image_name checks format" {
  inspect(validate_image_name("redis"), content="true")
  inspect(validate_image_name("library/redis"), content="true")
  inspect(validate_image_name("gcr.io/project/image"), content="true")
  inspect(validate_image_name(""), content="false")
  inspect(validate_image_name("INVALID IMAGE"), content="false")
}

// Test 3: タグの妥当性検証
test "validate_tag checks format" {
  inspect(validate_tag("latest"), content="true")
  inspect(validate_tag("1.2.3"), content="true")
  inspect(validate_tag("v1.0-alpha"), content="true")
  inspect(validate_tag(""), content="false")
  inspect(validate_tag("invalid tag"), content="false")
}

// Test 4: パスの妥当性検証
test "validate_path checks format" {
  inspect(validate_path("/absolute/path"), content="true")
  inspect(validate_path("relative/path"), content="true")
  inspect(validate_path(""), content="false")
}
```

**実行方法**:
```bash
moon test --target native tests/unit/validation_test.mbt
moon test --target js tests/unit/validation_test.mbt
```

#### 1.4 エラーハンドリングのテスト

**目的**: エラー生成とメッセージフォーマットを検証

**テストファイル**: `tests/unit/error_test.mbt`

**テストケース**:
```moonbit
// Test 1: エラー型の生成
test "TestContainerError variants" {
  let err1 = TestContainerError::ContainerStartFailed("test reason")
  inspect(err1.to_string(), content="Container start failed: test reason")

  let err2 = TestContainerError::PortNotFound(8080)
  inspect(err2.to_string(), content="Port 8080 not found in port mappings")

  let err3 = TestContainerError::WaitTimeout("Redis", 30)
  inspect(err3.to_string(), content="Wait timeout: Redis did not become ready within 30 seconds")
}

// Test 2: エラーメッセージのフォーマット
test "error message formatting" {
  let err = TestContainerError::DockerCommandFailed("run", 1, "permission denied")
  let msg = err.to_string()
  // メッセージに必要な情報が含まれているか
  inspect(msg.contains("run"), content="true")
  inspect(msg.contains("permission denied"), content="true")
}

// Test 3: エラーのパターンマッチング
test "error pattern matching" {
  let err = TestContainerError::Unsupported("JavaScript backend")
  match err {
    Unsupported(reason) => inspect(reason, content="JavaScript backend")
    _ => abort("Pattern matching failed")
  }
}
```

**実行方法**:
```bash
moon test --target native tests/unit/error_test.mbt
moon test --target js tests/unit/error_test.mbt
```

### Layer 2: 統合テスト（Native専用）

#### 2.1 既存の統合テスト（維持）

以下のテストは**Native専用**として維持:

| ファイル名 | 機能 | 理由 |
|-----------|------|------|
| `basic_lifecycle_wbtest.mbt` | コンテナライフサイクル | Docker CLI必須 |
| `wait_strategies_wbtest.mbt` | 待機戦略 | 実際のコンテナ起動必須 |
| `logs_basic_wbtest.mbt` | ログ取得 | Docker CLI必須 |
| `logs_streaming_wbtest.mbt` | ログストリーミング | Docker CLI必須 |
| `logs_advanced_wbtest.mbt` | 高度なログ機能 | Docker CLI必須 |
| `volume_mount_wbtest.mbt` | ボリュームマウント | Docker CLI必須 |

**実行方法**:
```bash
moon test --target native  # 統合テストを含む全テスト
```

#### 2.2 統合テストの価値

統合テストは以下を保証するため、引き続き重要:

1. **実際のDocker環境での動作確認**
2. **コンテナライフサイクル全体の検証**
3. **ネットワーク・ストレージの統合動作**
4. **エンドツーエンドのシナリオ検証**

## テスト実装ガイドライン

### 命名規則

```
# ユニットテスト（JavaScript対応）
tests/unit/
  <機能名>_test.mbt

# 統合テスト（Native専用）
tests/integration/ または ルートディレクトリ
  <機能名>_wbtest.mbt
```

### ファイル構成

```
moonbit_test_containers/
├── tests/
│   └── unit/                      # 新規作成
│       ├── types_test.mbt         # JavaScript対応
│       ├── parser_test.mbt        # JavaScript対応
│       ├── validation_test.mbt    # JavaScript対応
│       └── error_test.mbt         # JavaScript対応
│
├── basic_lifecycle_wbtest.mbt     # Native専用（既存）
├── wait_strategies_wbtest.mbt     # Native専用（既存）
├── logs_basic_wbtest.mbt          # Native専用（既存）
├── logs_streaming_wbtest.mbt      # Native専用（既存）
├── logs_advanced_wbtest.mbt       # Native専用（既存）
└── volume_mount_wbtest.mbt        # Native専用（既存）
```

### moon.pkg.json設定

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
    // Native専用ファイル
    "container.mbt": ["native"],
    "docker.mbt": ["native"],
    "wait_strategy.mbt": ["native"],
    "logs.mbt": ["native"],
    "*_lifecycle_wbtest.mbt": ["native"],
    "*_streaming_wbtest.mbt": ["native"],
    "*_advanced_wbtest.mbt": ["native"],
    "*_mount_wbtest.mbt": ["native"],

    // 両バックエンド対応
    "types.mbt": ["native", "js"],
    "error.mbt": ["native", "js"],
    "tests/unit/*_test.mbt": ["native", "js"]
  }
}
```

## テスト実行方法

### 開発時

```bash
# 全テスト（Native）
moon test --target native

# ユニットテストのみ（JavaScript）
moon test --target js

# 特定のテストファイル
moon test --target native basic_lifecycle_wbtest.mbt
moon test --target js tests/unit/types_test.mbt

# カバレッジ付き
moon test --target native --enable-coverage
moon test --target js --enable-coverage
```

### CI/CD環境

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test-native:
    name: Native Backend Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Docker
        run: docker --version
      - name: Run Native Tests
        run: moon test --target native

  test-javascript:
    name: JavaScript Backend Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run JavaScript Tests
        run: moon test --target js
```

## 実装の優先順位

### Phase 1: 基盤整備（優先度: 最高）
1. `tests/unit/`ディレクトリ作成
2. `moon.pkg.json`の`targets`設定追加
3. 最初のユニットテスト作成（types_test.mbt）
4. JavaScript実行確認

**完了条件**: `moon test --target js`が成功する

### Phase 2: コアテスト実装（優先度: 高）
5. `parser_test.mbt`実装
6. `validation_test.mbt`実装
7. `error_test.mbt`実装
8. カバレッジ確認

**完了条件**: ユニットテスト層のカバレッジが60%以上

### Phase 3: 拡張と最適化（優先度: 中）
9. エッジケーステストの追加
10. パフォーマンステスト
11. ドキュメント整備

**完了条件**: カバレッジ70%以上、ドキュメント完成

### Phase 4: CI/CD統合（優先度: 低）
12. GitHub Actions設定
13. カバレッジレポート自動生成
14. バッジの追加

**完了条件**: CI/CD自動化完了

## テストデータ管理

### テストフィクスチャ

```moonbit
// tests/unit/fixtures.mbt
pub fn sample_container_image() -> ContainerImage {
  ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_env_var("REDIS_PASSWORD", "test123")
}

pub fn sample_port_mappings() -> Array[String] {
  ["0.0.0.0:32768", "[::]:32769", "localhost:8080"]
}

pub fn invalid_port_mappings() -> Array[String] {
  ["invalid", "", "no-colon", "0.0.0.0:99999"]
}
```

### モックデータ

統合テストのモック化は**現時点では対象外**とします。理由:

1. Docker操作のモック化は複雑
2. 実際の動作との乖離リスク
3. 統合テストの価値が低下

将来的な拡張として検討可能。

## カバレッジ目標と測定

### カバレッジ測定方法

```bash
# Native
moon test --target native --enable-coverage
moon coverage report

# JavaScript
moon test --target js --enable-coverage
moon coverage report

# 未カバー箇所の分析
moon coverage analyze > uncovered.log
```

### カバレッジ目標

| コンポーネント | 目標 | 理由 |
|--------------|------|------|
| types.mbt | 80% | ビジネスロジックの中核 |
| error.mbt | 90% | エラー処理は重要 |
| parser.mbt | 85% | データ変換ロジック |
| container.mbt | 70% | 統合テストでカバー |
| docker.mbt | 60% | 統合テストでカバー |

## リグレッション防止

### 既存テストの保護

```bash
# Phase 1完了後の確認
moon test --target native
# 全ての既存テストが成功することを確認

# 新しいテストの追加後
moon test --target native
moon test --target js
# 両方が成功することを確認
```

### テスト失敗時の対応

1. **Native失敗**: 既存機能の破壊 → 即座に修正
2. **JavaScript失敗**: 新規テストの問題 → 調査・修正
3. **両方失敗**: 共通コードの問題 → 優先的に修正

## 成功指標

### 定量的指標

- [ ] ユニットテストカバレッジ: 70%以上
- [ ] 統合テストカバレッジ: 85%以上（Native）
- [ ] 全体カバレッジ: 80%以上
- [ ] テスト実行時間: Native 5分以内、JavaScript 1分以内
- [ ] テスト成功率: 100%

### 定性的指標

- [ ] テストコードが理解しやすい
- [ ] エラーメッセージが明確
- [ ] 失敗時のデバッグが容易
- [ ] ドキュメントが充実している

## トラブルシューティング

### よくある問題と解決策

#### Q1: `moon test --target js`がエラーになる
```bash
# 原因: プロセス依存コードが含まれている
# 解決: moon.pkg.jsonのtargetsでファイルを除外

"targets": {
  "docker.mbt": ["native"]  // jsから除外
}
```

#### Q2: JavaScript環境でテストがスキップされる
```bash
# 原因: テストファイルがnative専用設定
# 解決: targets設定で両対応に変更

"tests/unit/*_test.mbt": ["native", "js"]
```

#### Q3: カバレッジが取得できない
```bash
# 確認: カバレッジフラグを付けているか
moon test --target native --enable-coverage

# レポート生成
moon coverage report
```

## まとめ

### 採用するアプローチ

1. **2層テスト戦略**: ユニットテストと統合テストを分離
2. **段階的実装**: 既存テストを維持しながら新規追加
3. **バックエンド別最適化**: Native/JavaScript それぞれの強みを活用

### 期待される効果

1. **開発速度向上**: ユニットテストの高速実行
2. **信頼性向上**: 両バックエンドでの動作保証
3. **保守性向上**: テスト分類の明確化

### 次のステップ

1. **実装ガイドライン作成**: @coder への詳細指示
2. **実装開始**: Phase 1から順次実装
3. **継続的改善**: カバレッジとフィードバックに基づく改善

## 参考資料

- MoonBit Testing Guide: https://docs.moonbitlang.com/next/toolchain/testing/
- AGENTS.md: プロジェクト開発規約
- CLAUDE.md: ガイドライン

## 改訂履歴

| バージョン | 日付 | 変更内容 | 作成者 |
|----------|------|---------|-------|
| 1.0 | 2026-02-08 | 初版作成 | Orchestrator Agent |

---

**このテスト戦略は技術設計ドキュメントと合わせて実装フェーズで参照されます。**
