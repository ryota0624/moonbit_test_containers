# GitHub依存関係の設定完了

## 日付
2026-02-08

## 問題

`moonbitlang/async` v0.16.5には`@process.collect_output_merged`と`@http.get_stream`が含まれていないため、コンパイルエラーが発生していました。

## 解決方法

GitHubリポジトリを直接参照するローカルパス依存関係を設定しました。

### 実装手順

1. **リポジトリのクローン**
```bash
git clone https://github.com/moonbitlang/async.git .moonbit-async
```

2. **moon.mod.jsonの更新**
```json
{
  "deps": {
    "moonbitlang/async": {
      "path": ".moonbit-async"
    },
    "moonbitlang/async/process": {
      "path": ".moonbit-async"
    },
    "moonbitlang/async/http": {
      "path": ".moonbit-async"
    }
  }
}
```

3. **.gitignoreへの追加**
```
.moonbit-async/
```

### 重要なポイント

- MoonBitは直接的なGit依存関係をサポートしていません
- 代わりにローカルパス依存関係を使用します
- サブモジュール（process、http）も明示的に指定する必要があります
- クローンしたリポジトリは`.gitignore`に追加してバージョン管理から除外します

## 結果

✅ コンパイル成功
✅ すべてのAPIが利用可能
- `@process.collect_output_merged`
- `@http.get_stream`

## セットアップ手順（他の開発者向け）

このプロジェクトをクローンした後：

```bash
# async リポジトリをクローン
git clone https://github.com/moonbitlang/async.git .moonbit-async

# 依存関係をインストール
moon install

# ビルド確認
moon check
```

## 技術的詳細

### 使用しているAPI

1. **@process.collect_output_merged**
   - コマンド実行と出力収集
   - 実装場所: `.moonbit-async/src/process/process.mbt`
   - 追加日: 2025年9月22日（コミット 44b7d12）

2. **@http.get_stream**
   - HTTPリクエストの送信
   - 実装場所: `.moonbit-async/src/http/`

### パッケージ構造

```
.moonbit-async/
├── moon.mod.json         # メインモジュール設定
├── src/
│   ├── process/          # プロセス管理
│   ├── http/             # HTTP通信
│   └── ...               # その他のモジュール
```

## 参考資料

- [MoonBit Module Configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)
- [moonbitlang/async GitHub](https://github.com/moonbitlang/async)
- プロジェクト内ドキュメント: `docs/steering/api_version_mismatch_20260208.md`

## 今後の対応

moonbitlang/async v0.17.0以降がリリースされたら：

1. `.moonbit-async`ディレクトリを削除
2. `moon.mod.json`を更新して通常のバージョン指定に戻す
```json
{
  "deps": {
    "moonbitlang/async": "0.17.0"
  }
}
```
3. `.gitignore`から`.moonbit-async/`の行を削除（オプション）
