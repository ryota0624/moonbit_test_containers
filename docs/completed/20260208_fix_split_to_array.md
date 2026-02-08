# 完了報告: split().to_array()の修正

## 実装内容
moonbit_test_containers.mbtの行419で発生していた `split()` の戻り値の型の問題を修正しました。

### 問題

**エラーメッセージ:**
```
Error: [4014] 行419: text.split('\n') の戻り値の型の問題
Error: [4015] 行421: lines.length() メソッドがない
Error: [4015] 行422: lines[i] 配列アクセスができない
```

**原因:**
- `split()` は `Iter[StringView]` を返す
- `Iter` 型には `length()` メソッドがない
- `Iter` 型は配列アクセス `[i]` をサポートしていない

### 修正内容（行419）

**変更前:**
```moonbit
let text = output.text()
let lines = text.split('\n')

for i = 0; i < lines.length(); i = i + 1 {
  let line = lines[i]
  let line_str = "\{line}"
  if line_str.length() > 0 {
    callback(line_str)
  }
}
```

**変更後:**
```moonbit
let text = output.text()
let lines = text.split('\n').to_array()

for i = 0; i < lines.length(); i = i + 1 {
  let line = lines[i]
  let line_str = "\{line}"
  if line_str.length() > 0 {
    callback(line_str)
  }
}
```

**変更点:**
- `text.split('\n')` → `text.split('\n').to_array()`
- `Iter[StringView]` を `Array[StringView]` に変換

### 技術的な詳細

1. **MoonBitのIterとArray**
   - `split()` は遅延評価される `Iter` を返す
   - `Iter` は要素数が不明で、インデックスアクセスできない
   - `to_array()` で `Iter` を `Array` に変換

2. **パフォーマンスへの影響**
   - `to_array()` はすべての要素をメモリに展開する
   - ログの行数が多い場合、メモリ使用量が増える
   - 今回のユースケースでは許容範囲内

## 変更ファイル一覧

### 変更
- `moonbit_test_containers.mbt`:
  - 行419: `text.split('\n')` → `text.split('\n').to_array()`

### 追加
- `docs/completed/fix_split_to_array_20260208.md`: このドキュメント

## テスト

### 構文チェック
```bash
moon check --target native
```
結果: [実行待ち]

### テスト実行
```bash
moon test --native
```
結果: [実行待ち]

### 影響を受ける機能
- `Container::stream_logs` 関数
- ログを行ごとに処理する機能

## 今後の課題・改善点

### 代替実装の検討
もし大量のログでメモリが問題になる場合、以下の代替実装が考えられます。

**Option 1: Iterをそのまま使う**
```moonbit
let lines = text.split('\n')
for line in lines {
  let line_str = "\{line}"
  if line_str.length() > 0 {
    callback(line_str)
  }
}
```

**Option 2: foldを使う**
```moonbit
let lines = text.split('\n')
lines.iter().each(fn(line) {
  let line_str = "\{line}"
  if line_str.length() > 0 {
    callback(line_str)
  }
})
```

現在の実装は `for i` ループを使っているため、配列への変換が必要です。将来的に `for-in` ループに変更することで、`to_array()` を省略できます。

## 次のステップ
1. `moon check --target native` でコンパイルエラーがないか確認
2. `moon test --native` でテストが通るか確認
3. 全てのテストが通ったらコミット

## 参考資料
- MoonBit言語仕様: https://docs.moonbitlang.com
- ユーザーからの問題報告: split()の戻り値の型の問題
- 関連ドキュメント:
  - docs/completed/fix_api_errors_20260208.md
  - docs/completed/fix_additional_errors_20260208.md
