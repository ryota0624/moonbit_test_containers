# Steering: Wait Strategy - Log Message実装

## 目的・背景

コンテナのログ出力を監視して、特定のメッセージが出現するまで待機する機能を追加する。PostgreSQL、MySQL、Elasticsearchなどのデータベースやサービスは、起動時に「ready to accept connections」などのメッセージをログに出力するため、このメッセージを待つことで確実にサービスが準備完了した状態を検知できる。

現在実装されているTcpPort、HttpGet wait strategiesは、ポートが開いたりHTTPレスポンスが返ることを確認するが、実際にサービスが初期化を完了していない可能性がある。LogMessage wait strategyはより確実にサービスの準備完了を検知できる。

## ゴール

- コンテナログから特定のメッセージを検索する機能の実装
- 既存のwait strategiesと統一されたAPI設計
- タイムアウト機能の実装
- 複数バックエンド（native/JavaScript）対応
- PostgreSQL、MySQLなどの実用的なユースケースでの動作確認

## アプローチ

### 1. WaitStrategy列挙型の拡張

```moonbit
pub enum WaitStrategy {
  TcpPort(Int)
  Seconds(Int)
  HttpGet(String, Int)
  LogMessage(String)  // 新規追加：待機するログメッセージ
}
```

### 2. ログ取得機能の実装

既存の`Container::logs`メソッドを活用してログを取得し、特定メッセージが含まれているかを確認する。

```moonbit
// wait_strategy.mbt に追加
async fn wait_for_log_message(
  container : Container,
  message : String,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise
```

### 3. 実装方針

- **ポーリング方式**: 500ms間隔でログを取得し、メッセージの存在を確認
- **部分一致**: メッセージは部分一致で検索（contains）
- **タイムアウト**: 指定秒数待ってもメッセージが見つからない場合はエラー
- **バックエンド統一**: native/JavaScript両方で動作する実装

### 4. 技術的な詳細

**ログ取得方法:**
- `docker logs <container_id>` コマンドを実行
- stdoutとstderrの両方を取得
- 新規ログのみを確認（前回チェック以降のログ）

**効率化:**
- `--since` オプションを使用して前回チェック以降のログのみ取得
- または `--tail N` で最新N行のみ取得
- メモリ効率のため、全ログを毎回取得しない

**エラーハンドリング:**
- ログ取得失敗時は次のポーリングまで待つ（一時的な失敗として扱う）
- タイムアウト時は明確なエラーメッセージを返す

## スコープ

### 含む

- `WaitStrategy::LogMessage(String)` の追加
- `wait_for_log_message` 関数の実装
- `wait_for_container` 関数への統合
- native/JavaScript両バックエンド対応
- ユニットテスト（PostgreSQL、nginxなどで検証）
- ドキュメント更新（README、コード例）

### 含まない

- 正規表現によるログマッチング（将来的な拡張として検討）
- 複数メッセージの同時監視（ANDやOR条件）
- ログのフィルタリング（特定のログレベルのみ監視など）
- リアルタイムストリーミング（ポーリングで十分）

## 影響範囲

### 変更するファイル

1. **types.mbt**
   - `WaitStrategy` 列挙型に `LogMessage(String)` を追加

2. **wait_strategy.mbt**
   - `wait_for_log_message` 関数の追加
   - `wait_for_container` 関数に `LogMessage` ケースを追加

3. **wait_strategies_wbtest.mbt**
   - LogMessage wait strategyのテストケース追加
   - PostgreSQL、nginxでの実用例テスト

4. **README.mbt.md**
   - LogMessage使用例の追加
   - ユースケースの説明

### 新規作成ファイル

- なし（既存ファイルを拡張）

## 成功基準

- [ ] `WaitStrategy::LogMessage(String)` が定義されている
- [ ] PostgreSQLコンテナで "ready to accept connections" メッセージを待機できる
- [ ] nginxコンテナで起動完了メッセージを待機できる
- [ ] タイムアウトが正しく機能する（メッセージが出現しない場合）
- [ ] 既存のwait strategy テストが全てパスする
- [ ] 新規テストが全てパスする
- [ ] native/JavaScript両バックエンドで動作する
- [ ] READMEが更新されている

## 技術的な課題と対策

### 課題1: ログ取得のタイミング

コンテナ起動直後はログがまだ出力されていない可能性がある。

**対策:**
- 最初のログチェックは少し遅延させる（初回のみ1秒待つ）
- ログ取得エラーは一時的なものとして無視し、次回ポーリングを継続

### 課題2: 大量のログによるメモリ消費

長時間動作するコンテナや、大量のログを出力するコンテナで問題になる可能性。

**対策:**
- `--tail 100` などで最新のログのみ取得
- または `--since <timestamp>` で前回チェック以降のログのみ取得
- メッセージが見つかったら即座に終了

### 課題3: メッセージの部分一致vs完全一致

部分一致だと意図しないメッセージにマッチする可能性がある。

**対策:**
- 現時点では部分一致（`contains`）で実装
- ユーザーが十分に特徴的なメッセージ文字列を指定することを想定
- ドキュメントでベストプラクティスを説明

### 課題4: stderr/stdoutの両方を確認

一部のアプリケーションはstderrに出力する。

**対策:**
- `docker logs` はデフォルトでstdout/stderr両方を返すため問題なし
- 特別な処理は不要

## リスク評価

### リスク1: ポーリング間隔が適切でない

**影響**: 中
**対策**: 500ms間隔でバランスを取る。必要に応じてユーザーがタイムアウトを調整可能。

### リスク2: ログが大量に出力されるケース

**影響**: 低〜中
**対策**: `--tail` オプションで最新ログのみ取得。実用上問題ないはず。

### リスク3: 特殊文字を含むメッセージ

**影響**: 低
**対策**: シェルコマンドで適切にエスケープ。MoonBitの文字列補間は安全。

## 実装順序

1. `WaitStrategy::LogMessage(String)` の定義（types.mbt）
2. `wait_for_log_message` 関数の実装（wait_strategy.mbt）
3. `wait_for_container` 関数への統合
4. 基本的なテストケースの作成
5. PostgreSQLテストの作成
6. nginxテストの作成
7. タイムアウトテストの作成
8. READMEの更新
9. コード例の追加

## 期待される成果

- PostgreSQL、MySQLなどのデータベースコンテナで確実にサービス準備完了を待機できる
- 既存のTcpPort/HttpGet wait strategiesと統一されたAPI
- テストの信頼性向上（サービスが完全に起動してからテスト実行）
- 実用的なtestcontainersライブラリとしての完成度向上

## 参考実装

- testcontainers-java: `WaitForLogMessageStrategy`
- testcontainers-go: `Wait.ForLog()`
- testcontainers-rs: `WaitFor::message_on_stdout()`
