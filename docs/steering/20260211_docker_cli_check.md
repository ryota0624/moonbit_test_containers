# Steering: Docker CLIインストールチェック機能

## 目的・背景

現在の実装では、Docker CLIが未インストールの状態でテストコンテナを実行しようとすると、わかりにくいエラーメッセージが表示されます。ユーザーがDocker CLIをインストールする必要があることを明確に伝えるため、Docker CLIの存在チェックとインストール促進メッセージを実装します。

## ゴール

- Docker CLIが未インストールの場合、わかりやすいエラーメッセージを表示
- インストール方法を案内するメッセージを含める
- ネイティブバックエンドとJavaScriptバックエンドの両方をサポート
- 既存のコードの動作を変更しない（Docker CLIが存在する場合）

## アプローチ

### 1. Docker CLI存在チェック

以下のいずれかの方法でDocker CLIの存在を確認：

**Option A: 事前チェック方式**
- `docker --version` コマンドを実行
- 成功すれば Docker CLI が存在、失敗すればインストール促進メッセージを返す

**Option B: エラーハンドリング方式**
- 通常通りDockerコマンドを実行
- エラーが発生した場合、エラーメッセージを解析
- "command not found" や "not found" などのキーワードを検出
- 該当する場合はインストール促進メッセージに置き換え

**推奨**: Option A（事前チェック方式）
- より明確で予測可能
- エラーメッセージのパターンマッチングに依存しない

### 2. 実装箇所

以下のファイルを修正：

- `docker_native.mbt`: ネイティブバックエンド用の実装
- `docker_js.mbt`: JavaScriptバックエンド用の実装

### 3. エラーメッセージ

以下の情報を含めるエラーメッセージ：

```
Docker CLI is not installed or not available in PATH.

Please install Docker to use this library:
- macOS: https://docs.docker.com/desktop/install/mac-install/
- Windows: https://docs.docker.com/desktop/install/windows-install/
- Linux: https://docs.docker.com/desktop/install/linux-install/

After installation, make sure 'docker' command is available in your PATH.
```

### 4. 実装ステップ

1. Docker CLI存在チェック関数を追加
   - `check_docker_available() -> Result[Unit, TestContainerError]`
2. `exec_docker` 関数の開始時にチェックを実行
3. チェックが失敗した場合は、インストール促進エラーを返す
4. チェックが成功した場合は、既存の処理を継続

## スコープ

### 含む
- Docker CLI存在チェック機能
- ネイティブバックエンドの実装
- JavaScriptバックエンドの実装
- わかりやすいエラーメッセージ

### 含まない
- Docker Daemon（dockerd）の起動状態チェック
- Docker Desktopのインストール状態チェック
- 自動インストール機能
- Docker CLIのバージョンチェック

## 影響範囲

### 修正対象ファイル
- `docker_native.mbt`: ネイティブバックエンドの実装を修正
- `docker_js.mbt`: JavaScriptバックエンドの実装を修正

### テスト
- Docker CLIが存在しない環境での動作確認
- Docker CLIが存在する環境での既存動作確認（regression test）
- ネイティブバックエンドとJavaScriptバックエンドの両方

### 影響を受ける機能
- すべてのDocker操作（コンテナ起動、停止、ログ取得など）
- エラーメッセージの内容

## 技術的考慮事項

### パフォーマンス
- Docker CLI存在チェックは初回のみ実行するか、毎回実行するか
  - **推奨**: 毎回実行（シンプルで確実、パフォーマンス影響は小さい）
  - キャッシュする場合は状態管理が必要になり複雑化

### エラーハンドリング
- `check_docker_available()` のエラーは `DockerNotInstalled` などの新しいエラータイプを追加するか
  - **推奨**: 既存の `DockerCommandFailed` を使用し、メッセージで区別
  - シンプルで既存のエラーハンドリングと一貫性がある

### バックエンド差異
- ネイティブとJavaScriptで異なるエラー検出方法が必要
  - ネイティブ: `@process.collect_output_merged` のエラー
  - JavaScript: `execSync` の `ENOENT` エラー

## 参考資料

- Docker公式ドキュメント: https://docs.docker.com/
- MoonBit Process API: `@process.collect_output_merged`
- Node.js child_process: https://nodejs.org/api/child_process.html
