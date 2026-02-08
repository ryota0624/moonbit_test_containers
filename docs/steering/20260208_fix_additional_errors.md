# Steering: 追加のAPIエラーの修正

## 目的・背景
初回の修正後、追加で4つの構文エラーが発見されました。これらを修正して、正常にコンパイルが通る状態にします。

## ゴール
- 全てのコンパイルエラーを解消
- `moon check --target native` が成功する
- `moon test --native` が成功する

## 問題と修正方針

### 問題1: ReadFromProcessにread_line()メソッドがない

**問題:**
```moonbit
async fn read_logs_line_by_line(
  reader : @process.ReadFromProcess,
  callback : (String) -> Unit
) -> Result[Unit, TestContainerError]
```

`reader.read_line()` を呼び出しているが、`@process.ReadFromProcess` には `read_line()` メソッドがない。

**原因分析:**
- `@process.ReadFromProcess` は `@io.Reader` トレイトを実装している可能性が高い
- しかし、直接 `read_line()` メソッドは提供されていない
- `@io` モジュールのユーティリティ関数を使う必要がある

**修正方法:**
1. `@io.Reader` を使ってバイトを読み取る
2. 改行まで読み取る処理を自分で実装する
3. または、`@process.collect_output_merged` の結果を行ごとに分割する

**推奨アプローチ:** ストリーミングではなく、プロセスの完了を待って出力を行ごとに処理する方法に変更。

```moonbit
// 新しいアプローチ：プロセスの出力を収集してから行ごとに処理
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options? : LogOptions
) -> Result[Unit, TestContainerError] {
  let options = match options {
    Some(opts) => opts
    None => LogOptions::default()
  }

  let stream_options = { ..options, follow: true }
  let args = build_logs_args(self.id, stream_options)

  try {
    // Run docker logs and collect output
    let (status, output) = @process.collect_output_merged("docker", args)

    if status != 0 {
      return Err(DockerCommandFailed("Docker logs exited with code \{status}"))
    }

    // Process output line by line
    let text = output.text()
    let lines = text.split('\n')

    for i = 0; i < lines.length(); i = i + 1 {
      let line = lines[i]
      if line.length() > 0 {
        callback("\{line}")
      }
    }

    Ok(())
  } catch {
    e => Err(DockerCommandFailed("Failed to stream logs: \{e.to_string()}"))
  }
}
```

**トレードオフ:**
- メリット: 実装がシンプル、エラーハンドリングが簡単
- デメリット: 真のストリーミングではなく、プロセス完了後に処理（followオプションの場合は問題になる可能性）

**follow=trueの場合の対応:**
- `follow=true` の場合、プロセスは終了しないため、この方法は使えない
- `follow=true` の場合はエラーを返すか、タイムアウトを設定する必要がある

### 問題2: whileループの戻り値の問題

**問題:**
```moonbit
while true {
  match reader.read_line() {
    Ok(line) => { ... }
    Err(@io.EOF) => break Ok(())
    Err(e) => return Err(...)
  }
}
```

**MoonBitの仕様:**
- `while` ループは `else` ブランチを持つ必要がある
- `while condition { ... } else { ... }` の形式

**修正方法:**
問題1の修正により、このループ自体が不要になるため、削除します。

### 問題3: @async.with_task_groupの使い方

**問題:**
```moonbit
@async.with_task_group(fn(tg) {
  tg.spawn(fn() {
    @process.run("docker", args, stdout=writer)
  })

  let result = read_logs_line_by_line(reader, callback)
  let exit_code = tg.wait()[0]
  ...
})
```

**原因分析:**
- `@async.with_task_group` のAPI仕様が不明
- タスクの待機方法が正しくない可能性

**修正方法:**
問題1の修正により、`@async.with_task_group` を使う必要がなくなります。`@process.collect_output_merged` を使うことで、同期的に処理できます。

### 問題4: テストファイルのfold問題

**問題 (moonbit_test_containers_wbtest.mbt 行561):**
```moonbit
let all_text = lines.iter().fold("", fn(acc, line) { acc + line })
```

**原因分析:**
- `fold` の初期値とaccumulatorの型が不明確
- MoonBitでは型推論が効かない場合がある

**修正方法:**
```moonbit
let all_text = lines.iter().fold(init="", fn(acc, line) { acc + line })
```

または、単純なループを使う:
```moonbit
let mut all_text = ""
for i = 0; i < lines.length(); i = i + 1 {
  all_text = all_text + lines[i]
}
```

## アプローチの変更

### 元の設計
- `@process.read_from_process()` でパイプを作成
- `@process.run()` でプロセスを起動し、stdoutをパイプに書き込む
- パイプから行ごとに読み取ってコールバックを呼び出す

### 新しい設計
- `@process.collect_output_merged()` でプロセスを実行し、完了を待つ
- 出力を受け取ってから、行ごとに分割してコールバックを呼び出す
- `follow=true` の場合は特別な処理が必要（タイムアウトまたはエラー）

## スコープ

### 含む
- 上記4つのエラー修正
- `stream_logs` 関数の実装方法の変更
- `read_logs_line_by_line` 関数の削除
- テストファイルの `fold` 修正

### 含まない
- 真のストリーミング実装（将来の改善として残す）
- パフォーマンス最適化

## 影響範囲

### 変更ファイル
- `moonbit_test_containers.mbt`:
  - `read_logs_line_by_line` 関数の削除
  - `Container::stream_logs` 関数の実装変更
- `moonbit_test_containers_wbtest.mbt`:
  - `fold` の修正（2箇所）

## 技術的な制約
- `@process.ReadFromProcess` のAPIが期待したものと異なる
- MoonBitのストリーミングAPIが限定的
- `follow=true` の場合、真のストリーミングは難しい

## リスク
- `follow=true` の場合、プロセスが終了しないため、タイムアウトが必要
- 大量のログがある場合、メモリ使用量が増える可能性

## 成功基準
1. `moon check --target native` がエラーなく完了
2. `moon test --native` が全てパス
3. ログ取得機能が正しく動作する
