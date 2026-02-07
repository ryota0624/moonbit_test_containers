# Steering: Wait Strategies実装

## 目的・背景

コンテナが起動してもサービスが準備完了するまでに時間がかかる問題を解決するため、Wait Strategies（待機戦略）を実装する。現在のプロトタイプでは、コンテナ起動直後にテストが開始されるため、PostgreSQLやMySQLなどの起動に時間がかかるサービスでテストが失敗する可能性がある。

## ゴール

- コンテナがサービス準備完了状態になるまで待機する機能の実装
- 複数の待機戦略をサポート（TCPポート、ログメッセージ、遅延）
- タイムアウト機能の実装
- 既存のAPIに自然に統合される設計

## アプローチ

### 実装する待機戦略（優先順位順）

1. **TCPポート待機** (最優先)
   - 指定されたポートへのTCP接続を試行
   - 接続成功までポーリング
   - 最も汎用的で実装もシンプル

2. **シンプルな遅延**
   - 指定秒数だけ待機
   - 最もシンプルだが確実性は低い

3. **ログメッセージ待機** (次のフェーズ)
   - `docker logs`で特定メッセージを監視
   - PostgreSQL、MySQLなどで必須
   - ログのストリーミングが必要

### API設計

```moonbit
// WaitStrategy列挙型
pub enum WaitStrategy {
  TcpPort(Int)  // port
  Seconds(Int)  // duration
  // Future: LogMessage(String)
  // Future: HttpGet(String, Int)  // path, expected_status
}

// ContainerImageに追加
pub struct ContainerImage {
  // ... existing fields
  wait_strategy : Option[WaitStrategy]
  wait_timeout : Int  // seconds, default 60
}

// メソッド
pub fn ContainerImage::with_wait_for(
  self : ContainerImage,
  strategy : WaitStrategy
) -> ContainerImage

pub fn ContainerImage::with_wait_timeout(
  self : ContainerImage,
  timeout : Int
) -> ContainerImage
```

### 実装詳細

1. **TCPポート待機の実装**
   - moonbitlang/asyncのTCPソケット機能を調査
   - 利用不可の場合：`nc`コマンドを使用
   - ポーリング間隔：500ms
   - タイムアウト：デフォルト60秒

2. **待機ロジックの配置**
   - `ContainerImage::start`メソッド内で実行
   - コンテナ起動後、ポートマッピング取得後に待機
   - タイムアウト時はエラーを返す

3. **エラーハンドリング**
   - 新しいエラー型：`WaitStrategyTimeout`
   - タイムアウト時のコンテナクリーンアップ

## スコープ

### 含む (Phase 1)

- `WaitStrategy`列挙型の定義
- TCPポート待機の実装
- シンプルな遅延の実装
- タイムアウト機能
- `with_wait_for`、`with_wait_timeout`メソッド
- 既存テストの更新（Wait Strategiesを使用）
- 新規テスト（Wait Strategies専用）

### 含まない (今回のスコープ外)

- ログメッセージ待機（Phase 2）
- HTTPエンドポイント待機（Phase 2）
- 複雑なヘルスチェック
- カスタム待機関数

## 影響範囲

### 変更するファイル

- `moonbit_test_containers.mbt`
  - `WaitStrategy`列挙型の追加
  - `ContainerImage`構造体にフィールド追加
  - `with_wait_for`、`with_wait_timeout`メソッド追加
  - 待機ロジック関数の追加
  - `start`メソッドに待機処理を統合

- `moonbit_test_containers_test.mbt`
  - 既存テストに`with_wait_for`を追加（Redisなど）
  - Wait Strategies専用テストの追加

- `README.mbt.md`
  - Wait Strategiesの使用例を追加
  - APIドキュメントの更新

- `moon.pkg.json`
  - 必要に応じて追加インポート（TCPソケット等）

### 新規作成ファイル

- なし（既存ファイルを拡張）

## 成功基準

- [ ] `WaitStrategy`列挙型が定義されている
- [ ] TCPポート待機が正常に動作する
- [ ] タイムアウトが正しく機能する
- [ ] PostgreSQLコンテナで待機戦略が機能する
- [ ] Redisコンテナで待機戦略が機能する
- [ ] タイムアウト時にエラーが返される
- [ ] 既存テストが全てパスする
- [ ] 新規テストが全てパスする
- [ ] READMEが更新されている

## 技術的な課題と対策

### 課題1: MoonBitでのTCPソケット接続

**対策**:
- まず`moonbitlang/async/io`のTCP機能を調査
- 利用不可の場合：`nc -z host port`コマンドを使用
- 最悪の場合：`docker exec`でコンテナ内から接続テスト

### 課題2: ポーリング間隔とCPU使用率

**対策**:
- ポーリング間隔を500msに設定
- `@async.sleep`で待機

### 課題3: タイムアウト実装

**対策**:
- 開始時刻を記録
- 各ポーリングで経過時間をチェック
- タイムアウト時はエラーを返す

### 課題4: ポートマッピングされたポートへの接続

**対策**:
- `localhost:mapped_port`に接続
- `get_host_port`で取得したポートを使用

## リスク評価

### リスク1: MoonBitにTCPクライアント機能がない

**影響**: 高
**対策**: `nc`コマンドのフォールバック実装を準備

### リスク2: 待機時間が長すぎてテストが遅くなる

**影響**: 中
**対策**: デフォルトタイムアウトを60秒に設定、ユーザーがカスタマイズ可能に

### リスク3: 既存テストの互換性

**影響**: 低
**対策**: `wait_strategy`はOptional型なので、既存コードは変更不要

## 実装順序

1. `WaitStrategy`列挙型の定義
2. `ContainerImage`構造体の拡張
3. `with_wait_for`、`with_wait_timeout`メソッドの実装
4. シンプルな遅延（`Seconds`）の実装
5. TCPポート待機の実装
6. `start`メソッドへの統合
7. エラーハンドリングの追加
8. テストの作成
9. 既存テストの更新
10. READMEの更新

## 期待される成果

- PostgreSQL、MySQLなどの起動に時間がかかるサービスで安定したテストが可能になる
- テストの失敗率が減少
- ユーザーが任意の待機戦略を選択できる柔軟性
- 実用的なtestcontainersライブラリとしての品質向上
