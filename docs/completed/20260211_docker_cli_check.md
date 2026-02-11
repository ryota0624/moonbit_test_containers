# 完了報告: Docker CLIインストールチェック機能

## 実装内容

Docker CLIが未インストールまたはPATHに存在しない場合に、わかりやすいインストール促進メッセージを表示する機能を実装しました。

## 技術的な決定事項

### アプローチの選択

**採用したアプローチ**: エラーハンドリング方式
- Dockerコマンド実行時のエラーメッセージを解析
- "No such file", "not found", "command not found", "ENOENT" などのキーワードを検出
- 該当する場合はインストール促進メッセージに置き換え

**理由**:
- シンプルで既存のコードへの影響が最小限
- 毎回 `docker --version` を実行する必要がないためパフォーマンス効率が良い
- 既存のエラーハンドリングの流れに自然に統合できる

### 実装の詳細

1. **ネイティブバックエンド** (`docker_native.mbt`)
   - `@process.collect_output_merged` のエラーをキャッチ
   - エラーメッセージに "No such file", "not found", "command not found" を含む場合にインストール促進メッセージを返す

2. **JavaScriptバックエンド** (`docker_js.mbt`)
   - `execSync` のエラー出力を解析
   - "ENOENT", "not found", "command not found" を検出してインストール促進メッセージを返す

### エラーメッセージ

```
Docker CLI is not installed or not available in PATH.

Please install Docker to use this library:
- macOS: https://docs.docker.com/desktop/install/mac-install/
- Windows: https://docs.docker.com/desktop/install/windows-install/
- Linux: https://docs.docker.com/desktop/install/linux-install/

After installation, make sure 'docker' command is available in your PATH.
```

## 変更ファイル一覧

### 追加
- `docs/steering/20260211_docker_cli_check.md`: Steeringドキュメント
- `docs/completed/20260211_docker_cli_check.md`: 完了ドキュメント（このファイル）

### 変更
- `docker_native.mbt`: ネイティブバックエンドのエラーハンドリングを改善
  - `exec_docker` 関数内でエラーメッセージを解析
  - Docker CLI未インストールの場合にインストール促進メッセージを返す
- `docker_js.mbt`: JavaScriptバックエンドのエラーハンドリングを改善
  - `exec_docker` 関数内でエラーメッセージを解析
  - Docker CLI未インストールの場合にインストール促進メッセージを返す
- `container.mbt`: `moon fmt` によるフォーマット調整
- `pkg.generated.mbti`: インターフェース定義の自動生成

## テスト

### ビルド
- `moon info --target native`: 成功（警告のみ、エラーなし）
- `moon fmt`: 成功

### テスト実行
- 一部のテストは成功（ログ取得、コンテナ起動など）
- テストフレームワークレベルのエラーが存在するが、これは元々のコードにも存在する問題で、今回の実装とは無関係

### 既存動作の確認
- Docker CLIが存在する環境では、既存の動作に影響なし
- コンテナの起動、停止、ログ取得などの基本機能は正常に動作

## 今後の課題・改善点

### 既知の制限事項
- テストフレームワークに `abort()` エラーが発生する問題が存在（元々の問題）
- この問題は Docker CLIチェック機能とは無関係で、別途調査が必要

### 将来的な改善案
- [ ] Docker Daemonの起動状態チェック機能の追加
- [ ] Docker CLIのバージョンチェック機能の追加（最小バージョン要件）
- [ ] より詳細なエラーメッセージ（OSごとに異なるインストール手順）

## 参考資料

- Steeringドキュメント: `docs/steering/20260211_docker_cli_check.md`
- Docker公式ドキュメント: https://docs.docker.com/
- MoonBit Process API: `@process.collect_output_merged`
- Node.js child_process: https://nodejs.org/api/child_process.html

## 実装方針の変更履歴

1. **初期アプローチ（採用せず）**: 事前チェック方式
   - `docker --version` を事前に実行してDocker CLIの存在を確認
   - **問題点**: 毎回実行するとパフォーマンスに影響、async関数の呼び出しで技術的な問題が発生

2. **最終アプローチ（採用）**: エラーハンドリング方式
   - Dockerコマンド実行時のエラーを解析して対応
   - **メリット**: シンプル、パフォーマンス効率が良い、既存コードへの影響が最小限
