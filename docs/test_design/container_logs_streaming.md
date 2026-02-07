# テスト設計: コンテナログのストリーミング機能

## 作成日
2026-02-08

## テスト戦略

### テスト範囲

- **対象機能**: コンテナログの取得とストリーミング
- **テストレベル**: 統合テスト（実際の Docker コンテナを使用）
- **カバレッジ目標**: 新規追加コードの 85% 以上

### テスト方針

1. **実際のコンテナを使用**: モックではなく、実際の Docker コンテナでテスト
2. **短時間で終了**: 各テストは数秒以内に完了させる
3. **決定的な結果**: ランダム性を排除し、再現可能なテストにする
4. **独立性**: 各テストは独立して実行可能
5. **段階的実装**: Phase ごとにテストを追加

## テストケース

### 正常系

| ID | テストケース | 入力 | 期待結果 | 優先度 | Phase |
|----|------------|------|---------|--------|-------|
| TC001 | 基本的なログ取得 | Alpine コンテナで `echo "test"` を実行 | ログに "test" が含まれる | 高 | 1 |
| TC002 | 複数行のログ取得 | Alpine コンテナで複数行を出力 | 全ての行が取得できる | 高 | 1 |
| TC003 | 空のログ取得 | コンテナを起動後すぐに停止 | 空文字列またはエラーなし | 中 | 1 |
| TC004 | tail オプション | 100行出力し、tail=10 で取得 | 最後の10行のみ取得 | 中 | 2 |
| TC005 | timestamps オプション | timestamps=true で取得 | タイムスタンプ付きログを取得 | 中 | 2 |
| TC006 | ログストリーミング | Redis コンテナの起動ログをストリーミング | 各行がコールバックで受信される | 高 | 3 |
| TC007 | ストリーミングの終了 | 有限のログを出力するコンテナ | EOF に到達して正常終了 | 高 | 3 |
| TC008 | ストリーミングのコールバック | 各行をカウント | 正しい行数がカウントされる | 高 | 3 |

### 異常系

| ID | テストケース | 入力 | 期待結果 | 優先度 | Phase |
|----|------------|------|---------|--------|-------|
| TC101 | 存在しないコンテナのログ取得 | 無効なコンテナID | `ContainerNotFound` エラー | 高 | 1 |
| TC102 | 削除されたコンテナのログ取得 | 削除済みコンテナID | `DockerCommandFailed` エラー | 中 | 1 |
| TC103 | follow オプションと get_logs_with_options | follow=true で get_logs_with_options を呼び出し | エラーまたは警告 | 中 | 2 |
| TC104 | 無効な tail 値 | tail=-1 などの無効値 | エラーまたは無視 | 低 | 2 |
| TC105 | ストリーミング中のコンテナ停止 | ストリーミング中にコンテナを停止 | EOF で正常終了 | 中 | 3 |

### エッジケース

| ID | テストケース | 入力 | 期待結果 | 優先度 | Phase |
|----|------------|------|---------|--------|-------|
| TC201 | 非常に長いログ行 | 10,000文字の1行ログ | 正しく取得できる | 低 | 1 |
| TC202 | Unicode 文字を含むログ | 日本語、絵文字などを出力 | 正しくデコードされる | 中 | 1 |
| TC203 | ログなしのコンテナ | 何も出力しないコンテナ | 空の結果を返す | 中 | 1 |
| TC204 | tail=0 | tail=0 で取得 | 空の結果を返す | 低 | 2 |
| TC205 | 大量のログ出力 | 10,000行のログ | メモリエラーなく処理できる | 中 | 3 |
| TC206 | 高速なログ出力 | 高頻度でログを出力 | 全ての行をキャッチできる | 中 | 3 |

## テスト環境要件

### テストフレームワーク

- **MoonBit Test Framework**: `moon test --target native`
- **Async テスト**: `@async.run` または `async test` 構文

### 必要な Docker イメージ

1. **alpine:latest**
   - 用途: 基本的なログ取得テスト
   - 理由: 軽量、高速起動

2. **redis:7.2**
   - 用途: ログストリーミングテスト
   - 理由: 起動時に複数行のログを出力

3. **postgres:16**（オプション）
   - 用途: 長時間実行のストリーミングテスト
   - 理由: 起動ログが豊富

### テストデータ

#### 基本的なログ出力スクリプト

```bash
# 単一行
echo "test log message"

# 複数行
echo "line 1"
echo "line 2"
echo "line 3"

# 100行の出力
for i in $(seq 1 100); do echo "Log line $i"; done

# Unicode 文字
echo "こんにちは世界 🌍"
```

### テスト実行環境

- **Docker**: 実行中であること
- **プラットフォーム**: Linux または macOS
- **権限**: Docker コマンドの実行権限
- **ネットワーク**: Docker イメージのプル可能であること

## 合格基準

### 必須（Phase 1-3）

- [ ] 全テストケース（TC001-TC008, TC101-TC105）がパス
- [ ] コードカバレッジが 85% 以上
- [ ] メモリリークがないこと
- [ ] ビルドが成功すること (`moon check --target native`)

### 推奨（エッジケース）

- [ ] TC201-TC206 の大部分がパス
- [ ] Unicode 文字が正しく処理される
- [ ] 大量ログでもメモリ効率が良い

### パフォーマンス基準

- [ ] 基本的なログ取得: 1秒以内
- [ ] 100行のログ取得: 2秒以内
- [ ] ストリーミング: オーバーヘッドが最小限

## 実装ガイドライン

### テストコードの配置

- **ファイル**: `moonbit_test_containers_test.mbt`
- **セクション**: 既存テストの後に追加

### 命名規則

```moonbit
// Phase 1: 基本的なログ取得
async test "get_logs - basic" { ... }
async test "get_logs - multiple lines" { ... }
async test "get_logs - empty log" { ... }
async test "get_logs - container not found" { ... }

// Phase 2: オプション指定
async test "get_logs_with_options - tail" { ... }
async test "get_logs_with_options - timestamps" { ... }

// Phase 3: ストリーミング
async test "stream_logs - basic" { ... }
async test "stream_logs - callback count" { ... }
async test "stream_logs - container stopped" { ... }
```

### テストヘルパー関数

共通処理をヘルパー関数として抽出:

```moonbit
/// Create a test container with echo commands
async fn create_echo_container(messages : Array[String]) -> Result[Container, TestContainerError] {
  let cmd = ["sh", "-c", "echo '\{messages.join("\\n")}'"]
  ContainerImage::new("alpine", "latest")
    .with_cmd(cmd)
    .start()
}

/// Count lines in a log string
fn count_log_lines(log : String) -> Int {
  log.split("\n").length()
}

/// Assert that log contains expected text
fn assert_log_contains(log : String, expected : String) -> Unit {
  @test.assert_true(log.contains(expected), message="Log should contain: \{expected}")
}
```

### エラーハンドリングのテスト

```moonbit
async test "get_logs - error handling" {
  let invalid_container = {
    id: "nonexistent_container_id",
    image: ContainerImage::new("alpine", "latest"),
    port_mappings: [],
  }

  match invalid_container.get_logs() {
    Err(_) => @test.pass() // エラーが期待される
    Ok(_) => @test.fail("Should return error for invalid container")
  }
}
```

### ストリーミングのテスト

```moonbit
async test "stream_logs - callback invocation" {
  let container = ContainerImage::new("alpine", "latest")
    .with_cmd(["sh", "-c", "echo 'line1'; echo 'line2'; echo 'line3'"])
    .start()

  match container {
    Ok(c) => {
      let count = Ref::new(0)
      let lines : Array[String] = []

      let callback = fn(line : String) {
        count.val = count.val + 1
        lines.push(line)
      }

      match c.stream_logs(callback) {
        Ok(_) => {
          @test.assert_eq(count.val, 3, message="Should receive 3 lines")
          @test.assert_true(lines[0].contains("line1"))
        }
        Err(e) => @test.fail("Stream failed: \{e.to_string()}")
      }

      let _ = c.cleanup()
    }
    Err(e) => @test.fail("Failed to start container: \{e.to_string()}")
  }
}
```

### リソースクリーンアップ

各テストで確実にクリーンアップを実行:

```moonbit
async test "get_logs - with cleanup" {
  let container = create_test_container()

  match container {
    Ok(c) => {
      // テスト処理
      let result = c.get_logs()

      // 必ずクリーンアップ
      let _ = c.cleanup()

      // アサーション
      match result {
        Ok(log) => @test.assert_true(log.length() > 0)
        Err(e) => @test.fail("\{e.to_string()}")
      }
    }
    Err(e) => @test.fail("Setup failed: \{e.to_string()}")
  }
}
```

## テスト実装の段階的アプローチ

### Phase 1: 基本的なログ取得

**実装するテスト**: TC001, TC002, TC003, TC101, TC102, TC201, TC202, TC203

**検証項目**:
- `Container::get_logs()` が正しく動作する
- エラーハンドリングが適切
- 様々なログ形式に対応

**推定時間**: 2-3時間

### Phase 2: オプション指定

**実装するテスト**: TC004, TC005, TC103, TC104, TC204

**検証項目**:
- `LogOptions` が正しく Docker CLI 引数に変換される
- `build_logs_args()` が正しく動作する
- オプションの組み合わせが機能する

**推定時間**: 1-2時間

### Phase 3: ログストリーミング

**実装するテスト**: TC006, TC007, TC008, TC105, TC205, TC206

**検証項目**:
- コールバックが各行ごとに呼び出される
- EOF が正しく処理される
- リソースが正しく解放される
- 大量のログでも動作する

**推定時間**: 3-4時間

## 既知のリスクと対策

### リスク1: Docker イメージのプル時間

**リスク**: テスト初回実行時にイメージのプルに時間がかかる

**対策**:
- CI 環境で事前にイメージをプル
- ローカル開発では手動でプル: `docker pull alpine:latest redis:7.2`

### リスク2: 非同期テストのタイムアウト

**リスク**: ログストリーミングが長時間実行される可能性

**対策**:
- テストで使用するコンテナは短時間で終了するコマンドを実行
- タイムアウトを設定（MoonBit がサポートしている場合）

### リスク3: Docker 環境の差異

**リスク**: 開発環境によって Docker の動作が異なる

**対策**:
- Docker のバージョン要件をドキュメントに記載
- 基本的な Docker CLI オプションのみ使用

### リスク4: 並行テストの干渉

**リスク**: 複数のテストが同時に実行されると干渉する可能性

**対策**:
- 各テストで独立したコンテナを作成
- ユニークなコンテナ名を使用（自動生成される ID で十分）

## テスト実行手順

### ローカル開発環境

```bash
# 1. Docker が実行中であることを確認
docker ps

# 2. 必要なイメージを事前にプル（オプション）
docker pull alpine:latest
docker pull redis:7.2

# 3. テストの実行
moon test --target native

# 4. 特定のテストのみ実行（MoonBit がサポートしている場合）
moon test --target native -f "get_logs"
```

### CI 環境

```yaml
# GitHub Actions の例
steps:
  - name: Start Docker
    run: |
      sudo systemctl start docker

  - name: Pull Docker images
    run: |
      docker pull alpine:latest
      docker pull redis:7.2

  - name: Run tests
    run: moon test --target native
```

## 期待される成果物

### テストコードファイル

- `moonbit_test_containers_test.mbt`
  - Phase 1: 基本的なログ取得のテスト（8-10 テストケース）
  - Phase 2: オプション指定のテスト（5-7 テストケース）
  - Phase 3: ログストリーミングのテスト（6-8 テストケース）
  - ヘルパー関数（3-5 関数）

### テスト結果レポート

- 全テストの実行結果
- カバレッジレポート
- パフォーマンス測定結果

### ドキュメント

- テスト実行方法の README への追加
- トラブルシューティングガイド

## 参考資料

### MoonBit テスト

- [MoonBit Test Documentation](https://docs.moonbitlang.com/en/latest/)
- 既存の `moonbit_test_containers_test.mbt` のパターン

### Docker

- [Docker logs command](https://docs.docker.com/engine/reference/commandline/logs/)
- [Alpine Docker image](https://hub.docker.com/_/alpine)
- [Redis Docker image](https://hub.docker.com/_/redis)

### 他言語のテスト実装

- [testcontainers-rs tests](https://github.com/testcontainers/testcontainers-rs/tree/main/testcontainers/tests)
- [testcontainers-go tests](https://github.com/testcontainers/testcontainers-go/tree/main/docker_test.go)

## まとめ

### テスト戦略のポイント

1. **実践的**: 実際の Docker コンテナを使用
2. **段階的**: Phase ごとにテストを追加
3. **包括的**: 正常系、異常系、エッジケースをカバー
4. **効率的**: 短時間で完了するテスト
5. **保守的**: 読みやすく、メンテナンスしやすいテストコード

### 品質保証

- 高いカバレッジ（85%以上）
- 再現可能なテスト
- 適切なエラーハンドリングの検証
- リソース管理の確認

### 次のステップ

このテスト設計に基づいて:
1. コーダーが実装とテストを同時に進める
2. 各 Phase ごとにテストを実行し、品質を確認
3. レビュアーがテストの妥当性を検証
