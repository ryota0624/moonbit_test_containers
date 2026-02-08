# Steering: HttpGet Wait Strategy 実装

## 目的・背景

現在のtestcontainersライブラリには2つのwait strategyが実装されています:
- `TcpPort`: TCPポートが開いているかを確認
- `Seconds`: 固定時間の待機

しかし、多くのWebサービスやAPIサーバーでは、TCPポートが開いていてもHTTPエンドポイントが準備完了していない場合があります。例えば:
- アプリケーションの初期化処理中
- データベース接続の確立中
- ヘルスチェックエンドポイントの準備中

このため、HTTPエンドポイントのステータスコードを確認する`HttpGet` wait strategyを追加します。

## ゴール

- `WaitStrategy::HttpGet(String, Int)` を実装（path, expected_status_code）
- HTTPリクエストを送信してステータスコードを確認
- タイムアウト機能付き（既存のwait_timeout設定を使用）
- 既存のTcpPort、Seconds wait strategiesと同様のエラーハンドリング
- nginxコンテナを使用した統合テスト
- README.mdへの使用例追加

## アプローチ

### 技術選択

MoonBitのasyncライブラリにはHTTPクライアント機能があるため、それを使用します。
- `moonbitlang/async/http` パッケージを使用
- HTTPリクエストは非同期関数として実装
- 既存のwait_for_tcp_portと同様のポーリング方式を採用

### 実装方針

1. **WaitStrategy enumの拡張**
   ```moonbit
   pub enum WaitStrategy {
     TcpPort(Int)
     Seconds(Int)
     HttpGet(String, Int)  // (path, expected_status_code)
   }
   ```

2. **HTTPヘルスチェック関数の追加**
   ```moonbit
   async fn check_http_endpoint(host : String, port : Int, path : String, expected_status : Int) -> Bool
   ```

3. **HTTPポーリング関数の追加**
   ```moonbit
   async fn wait_for_http_endpoint(
     host : String,
     port : Int,
     path : String,
     expected_status : Int,
     timeout_seconds : Int
   ) -> Result[Unit, TestContainerError]
   ```

4. **wait_for_container関数の拡張**
   - HttpGetケースを追加
   - コンテナのポートマッピングからホストポートを取得
   - wait_for_http_endpointを呼び出す

### ポーリング戦略

既存のTcpPort実装と同じ:
- ポーリング間隔: 500ms
- タイムアウト: with_wait_timeout()で設定された秒数（デフォルト60秒）
- 最大試行回数 = (timeout_seconds * 1000) / 500

## スコープ

### 含むもの

- `WaitStrategy::HttpGet` の実装
- HTTPリクエストを送信する関数
- nginxコンテナを使用した統合テスト
- README.mdへの使用例追加
- エラーハンドリング

### 含まないもの

- カスタムHTTPヘッダーの設定
- HTTPSサポート（将来的に追加可能）
- POST/PUT等のHTTPメソッド（GETのみ）
- レスポンスボディのチェック（ステータスコードのみ）
- リトライロジックのカスタマイズ（固定500msポーリング）

## 影響範囲

### 変更が必要なファイル

1. `/Users/ryota.suzuki/git/moonbit_test_containers/moonbit_test_containers.mbt`
   - `WaitStrategy` enumにHttpGet追加
   - `check_http_endpoint()` 関数追加
   - `wait_for_http_endpoint()` 関数追加
   - `wait_for_container()` にHttpGetケース追加

2. `/Users/ryota.suzuki/git/moonbit_test_containers/moonbit_test_containers_wbtest.mbt`
   - nginx containerを使用したHttpGet wait strategyテスト追加

3. `/Users/ryota.suzuki/git/moonbit_test_containers/moon.pkg.json`
   - `moonbitlang/async/http` 依存を追加

4. `/Users/ryota.suzuki/git/moonbit_test_containers/README.md`
   - HttpGet wait strategyの使用例追加
   - API Referenceセクションの更新

### 他の機能への影響

- 既存のTcpPortとSeconds wait strategiesには影響なし
- 既存のAPIとの互換性を完全に維持
- 新しいenum variantの追加のみ（breaking changeなし）

## 実装詳細

### エラーケース

1. **HTTPリクエスト失敗**
   - 接続エラー
   - タイムアウト
   - ネットワークエラー
   → 次のポーリングで再試行

2. **予期しないステータスコード**
   - 例: 200を期待しているが503が返ってくる
   → 次のポーリングで再試行

3. **タイムアウト**
   - 指定時間内にexpected_statusが返ってこない
   → `WaitStrategyTimeout` エラー

4. **ポートマッピングなし**
   - コンテナポートがマッピングされていない
   → `InvalidConfiguration` エラー

### テストケース

1. **基本的なHTTP endpointチェック**
   - nginxコンテナを起動
   - ルートパス "/" で200ステータスを期待
   - 成功を確認

2. **カスタムパスとステータスコード**
   - nginxで特定のパスを設定
   - 404等の異なるステータスコードをテスト

3. **タイムアウトテスト**
   - 到達不可能なエンドポイント
   - タイムアウトエラーを確認

## 実装順序

1. Steeringドキュメント作成（このドキュメント）✓
2. Git worktree作成とブランチ作成
3. WaitStrategy enumの拡張
4. HTTP関連関数の実装
5. wait_for_containerの拡張
6. moon.pkg.jsonの更新
7. テストの作成
8. moon test実行とデバッグ
9. README.mdの更新
10. moon info && moon fmtの実行
11. コミット
12. 完了ドキュメント作成

## 参考資料

- MoonBit async/http ドキュメント: https://docs.moonbitlang.com
- testcontainers-rs HttpWaitStrategy: https://docs.rs/testcontainers/latest/testcontainers/
- testcontainers-go wait.ForHTTP: https://golang.testcontainers.org/features/wait/http/
- 既存のTcpPort wait strategy実装（moonbit_test_containers.mbt lines 119-158）

## 既知の制限事項

- HTTPSはサポートしない（HTTP onlyのデフォルト）
- カスタムヘッダーはサポートしない
- GETメソッドのみサポート
- レスポンスボディの検証はサポートしない

これらの制限は将来のバージョンで拡張可能です。
