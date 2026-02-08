# Steering: ボリュームマウント機能実装

## 作成日
2026-02-08

## 目的・背景

### なぜこの機能が必要か

現在のtestcontainersの実装では、コンテナの起動・停止・ポートマッピング・Wait Strategy・ログ取得が実装されていますが、**ホストのファイルやディレクトリをコンテナ内にマウントする機能**がありません。

統合テストにおいて、ボリュームマウントは以下の理由で重要です:

1. **初期化スクリプトの注入**: データベースの初期化SQLやセットアップスクリプトをコンテナに渡せる
2. **設定ファイルのカスタマイズ**: カスタム設定ファイルをコンテナ内のアプリケーションに適用できる
3. **テストデータの提供**: テスト用のファイルやデータセットをコンテナに提供できる
4. **出力ファイルの取得**: コンテナ内で生成されたファイルをホストで確認できる
5. **リアルな統合テスト**: 本番環境に近い形でボリュームマウントを使った動作を検証できる

### 解決しようとしている問題

- **現状**: ホストのファイルをコンテナに渡す手段がない
- **問題**: データベースの初期化スクリプトやカスタム設定を使えない
- **課題**: 統合テストの柔軟性が制限される

## ゴール

### 作業完了時に達成されるべき状態

1. **基本的なボリュームマウント機能**
   - ホストパスとコンテナパスを指定してマウントできる
   - `docker run -v host:container`の機能を提供

2. **複数ボリュームのサポート**
   - 1つのコンテナに複数のボリュームをマウントできる
   - ファイルとディレクトリの両方をサポート

3. **Read-Onlyオプション**
   - 読み取り専用マウントを指定できる（`:ro`オプション）
   - デフォルトは読み書き可能（`:rw`）

4. **Fluent API**
   - `.with_volume()`メソッドでボリュームを追加
   - メソッドチェーンによる直感的な設定

5. **テストコード**
   - ボリュームマウント機能の動作を確認するテスト
   - 実際のコンテナ（例: PostgreSQL、nginx）を使った統合テスト

### 成功の基準

- ✅ ホストのファイル/ディレクトリをコンテナにマウントできる
- ✅ 複数のボリュームマウントが可能
- ✅ 読み取り専用マウントをサポート
- ✅ Fluent APIで設定できる
- ✅ エラーハンドリングが適切に実装されている
- ✅ テストが全てパスする

## アプローチ

### 採用する技術的アプローチ

#### 1. Docker CLI の `-v` オプション活用

既存の`ContainerImage::start()`メソッドを拡張し、ボリュームマウントに対応:

```moonbit
// ボリュームマウントの追加
pub fn ContainerImage::with_volume(
  self : ContainerImage,
  host_path : String,
  container_path : String,
  readonly? : Bool
) -> ContainerImage

// 使用例
let container = ContainerImage::new("postgres", "16")
  .with_volume("./init.sql", "/docker-entrypoint-initdb.d/init.sql")
  .with_volume("./data", "/var/lib/postgresql/data", readonly=true)
  .start()
```

#### 2. データ構造の拡張

`ContainerImage`構造体に`volumes`フィールドを追加:

```moonbit
pub struct VolumeMount {
  host_path : String
  container_path : String
  readonly : Bool
}

pub struct ContainerImage {
  name : String
  tag : String
  exposed_ports : Array[Int]
  env_vars : Array[(String, String)]
  cmd : Array[String]
  wait_strategy : WaitStrategy?
  wait_timeout : Int
  volumes : Array[VolumeMount]  // 新規追加
}
```

#### 3. Docker コマンド生成

`ContainerImage::start()`内でボリュームマウントを`docker run`コマンドに追加:

```bash
docker run -d \
  -v /host/path:/container/path \
  -v /host/path2:/container/path2:ro \
  -P -e KEY=VALUE \
  image:tag
```

### 主要な実装方針

1. **段階的実装**
   - Phase 1: データ構造の定義（VolumeMount）
   - Phase 2: with_volume()メソッドの実装
   - Phase 3: docker runコマンドへの統合
   - Phase 4: テストの実装

2. **既存コードとの統合**
   - `ContainerImage`構造体を拡張
   - `ContainerImage::start()`メソッドを修正
   - 既存のFluent APIパターンを踏襲

3. **パスの扱い**
   - 絶対パスと相対パスの両方をサポート
   - 相対パスはホストのカレントディレクトリからの相対パス
   - Docker CLIにパスをそのまま渡す（Dockerが解釈）

4. **エラーハンドリング**
   - ホストパスが存在しない場合の警告（Dockerのエラーを返す）
   - コンテナパスの検証（空文字列チェック）

## スコープ

### 含むもの

1. **VolumeMount構造体**
   - host_path、container_path、readonlyフィールド
   - 基本的なデータ構造

2. **ContainerImage拡張**
   - volumesフィールドの追加
   - with_volume()メソッドの実装

3. **docker runコマンド統合**
   - -vオプションの生成
   - :roサフィックスの追加

4. **テストコード**
   - ファイルマウントのテスト
   - ディレクトリマウントのテスト
   - 読み取り専用マウントのテスト
   - PostgreSQL初期化スクリプトの実用例

5. **ドキュメント**
   - READMEへのAPI追加
   - 使用例の記載

### 含まないもの

1. **Dockerボリュームの作成**
   - `docker volume create`によるnamed volumeは対象外
   - bind mountのみをサポート

2. **パスの検証**
   - ホストパス存在チェックは行わない（Dockerに任せる）
   - パスの正規化は行わない

3. **tmpfs マウント**
   - メモリベースのマウントは将来の拡張項目

4. **ボリュームドライバー**
   - カスタムボリュームドライバーのサポートは対象外

5. **ボリュームの共有**
   - 複数コンテナ間でのボリューム共有は別タスク

## 影響範囲

### 変更が影響するファイル

#### 追加予定のファイル

1. **docs/steering/volume_mounting_20260208.md** (本ドキュメント)
   - 実装のSteeringドキュメント

2. **docs/completed/volume_mounting_20260208.md** (作業完了後)
   - 完了報告ドキュメント

#### 変更予定のファイル

1. **types.mbt**
   - `VolumeMount`構造体の追加
   - `ContainerImage`構造体の拡張（volumesフィールド追加）
   - `ContainerImage::with_volume()`メソッドの追加

2. **container.mbt**
   - `ContainerImage::start()`メソッドの修正
   - ボリュームマウントオプションの`docker run`コマンドへの追加

3. **moonbit_test_containers_wbtest.mbt**
   - ボリュームマウント機能のテストケース追加
   - PostgreSQL初期化スクリプトのテスト
   - nginx設定ファイルのテスト

4. **README.mbt.md**
   - API Referenceセクションにボリューム関連APIを追加
   - 使用例の追加（PostgreSQL初期化スクリプト）
   - Current Limitationsから「Volume mounting is not yet supported」を削除
   - Future Enhancementsから「Volume mounting」を削除

5. **.mbti**
   - パブリックAPIの更新（moon infoで自動生成）

### 他の機能への影響

#### 直接影響するもの

- **ContainerImage構造体**: 新しいフィールドとメソッドが追加される
- **Container起動処理**: docker runコマンドの引数が変更される

#### 間接的な影響

- **データベーステスト**: 初期化スクリプトを使えるようになる
- **設定ファイルテスト**: カスタム設定を適用できる

#### 影響なし

- **WaitStrategy**: 変更なし
- **ログ取得機能**: 変更なし
- **ポートマッピング**: 変更なし

## 技術的な検討事項

### Docker CLI の -v オプション

#### 基本構文

```bash
# 読み書き可能（デフォルト）
docker run -v /host/path:/container/path image

# 読み取り専用
docker run -v /host/path:/container/path:ro image

# 複数マウント
docker run -v /host/path1:/container/path1 \
           -v /host/path2:/container/path2:ro \
           image
```

#### パスの扱い

- **絶対パス**: そのまま使用
- **相対パス**: カレントディレクトリからの相対パス
- **~（ホームディレクトリ）**: Dockerが展開（サポートされない場合あり）

### エラーケース

1. **ホストパスが存在しない**: Dockerがエラーを返す（メッセージをそのまま伝える）
2. **コンテナパスが不正**: Dockerがエラーを返す
3. **パーミッションエラー**: Dockerがエラーを返す
4. **パスが空文字列**: InvalidConfiguration エラー

### PostgreSQL の初期化スクリプト

PostgreSQLコンテナでは、`/docker-entrypoint-initdb.d/`ディレクトリに配置された`.sql`ファイルが自動実行される:

```moonbit
let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "testdb")
  .with_volume("./init.sql", "/docker-entrypoint-initdb.d/init.sql")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .start()
```

## 実装の優先順位

### Phase 1: データ構造とAPI（高優先度）

1. `VolumeMount`構造体の定義
2. `ContainerImage`の拡張
3. `with_volume()`メソッドの実装

### Phase 2: Docker統合（高優先度）

1. `ContainerImage::start()`の修正
2. `-v`オプションの生成ロジック
3. エラーハンドリング

### Phase 3: テスト（高優先度）

1. 基本的なマウントテスト
2. 読み取り専用マウントテスト
3. 複数ボリュームマウントテスト
4. PostgreSQL初期化スクリプトテスト

### Phase 4: ドキュメント更新（高優先度）

1. READMEの更新
2. 使用例の追加
3. 完了ドキュメントの作成

## リスクと対策

### リスク1: パスの扱い

**リスク**: 絶対パス・相対パス・特殊なパスの扱いが複雑になる可能性

**対策**:
- パスをそのままDockerに渡す（Dockerに解釈を任せる）
- 最小限の検証（空文字列チェックのみ）
- Dockerのエラーメッセージをそのまま伝える

### リスク2: プラットフォーム依存性

**リスク**: Windows/Linux/macOSでパス形式が異なる

**対策**:
- ユーザーがプラットフォームに応じた正しいパスを指定する責任
- ドキュメントで注意事項を明記
- 現在の実装はLinux/macOSのみサポート（既存の方針通り）

### リスク3: テストの実装

**リスク**: マウントしたファイルの検証が複雑になる可能性

**対策**:
- PostgreSQLの初期化スクリプトなど実用的なテストケース
- コンテナログを使った動作確認
- シンプルなテストケースから始める

## 参考資料

### Docker CLI

- [Docker run -v option reference](https://docs.docker.com/engine/reference/commandline/run/#volume)
- [Docker volumes documentation](https://docs.docker.com/storage/volumes/)

### PostgreSQL Docker

- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)
- [Initialization scripts](https://github.com/docker-library/docs/tree/master/postgres#initialization-scripts)

### 他言語の実装

- [testcontainers-rs bind mounts](https://docs.rs/testcontainers/latest/testcontainers/)
- [testcontainers-go volume support](https://github.com/testcontainers/testcontainers-go)

## 次のステップ

このSteeringドキュメントに基づいて、以下のエージェントに作業を委譲します:

1. **ソフトウェアアーキテクトへの依頼**
   - VolumeMount構造体の詳細設計
   - with_volume()メソッドのAPI設計
   - docker runコマンド生成ロジックの設計

2. **テストアーキテクトへの依頼**
   - テスト戦略の策定
   - テストケースの設計
   - PostgreSQL初期化スクリプトテストの設計

3. **コーダーへの依頼**
   - アーキテクトの方針に基づいた実装
   - types.mbtとcontainer.mbtの修正
   - テストコードの実装

4. **レビュアーへの依頼**
   - コードレビューと品質確認
   - APIの一貫性チェック
   - ドキュメントのレビュー

---

このSteeringドキュメントは、ボリュームマウント機能実装の指針として使用します。
