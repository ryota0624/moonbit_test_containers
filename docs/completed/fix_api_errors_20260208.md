# 完了報告: APIエラーの修正

## 実装内容
moonbit_test_containers.mbtの3箇所の構文エラーを修正しました。

### 修正1: labeled argumentの使用（行415-422）
**変更前:**
```moonbit
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options : LogOptions = LogOptions::default()
) -> Result[Unit, TestContainerError]
```

**変更後:**
```moonbit
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options? : LogOptions
) -> Result[Unit, TestContainerError] {
  // Get options or use default
  let options = match options {
    Some(opts) => opts
    None => LogOptions::default()
  }
  // ...
}
```

**理由:** MoonBitではlabeled argumentでのみデフォルト値を使用できるため、`options?` に変更し、関数内で `None` の場合のデフォルト値を設定。

### 修正2: whileループの使用（行393-406）
**変更前:**
```moonbit
loop {
  match reader.read_line() {
    Ok(line) => { ... }
    Err(@io.EOF) => break
    Err(e) => return Err(...)
  }
}
Ok(())
```

**変更後:**
```moonbit
while true {
  match reader.read_line() {
    Ok(line) => {
      let line_str = "\{line}"
      callback(line_str)
    }
    Err(@io.EOF) => break Ok(())
    Err(e) => return Err(DockerCommandFailed("Failed to read log line: \{e}"))
  }
}
```

**理由:** MoonBitの `loop` では `break` に値を渡せないため、`while true` を使用し、`break Ok(())` で正常終了を返す。

### 修正3: @async.with_task_groupの使用（行430-449）
**変更前:**
```moonbit
let (reader, writer) = @process.read_from_process()
let exit_code = @process.run("docker", args, stdout=writer)
match read_logs_line_by_line(reader, callback) {
  Ok(_) => {
    if exit_code == 0 {
      Ok(())
    } else {
      Err(DockerCommandFailed("Docker logs exited with code \{exit_code}"))
    }
  }
  Err(e) => Err(e)
}
```

**変更後:**
```moonbit
let (reader, writer) = @process.read_from_process()

@async.with_task_group(fn(tg) {
  // Task 1: Run docker logs process
  tg.spawn(fn() {
    @process.run("docker", args, stdout=writer)
  })

  // Task 2: Read logs line by line
  let result = read_logs_line_by_line(reader, callback)

  // Wait for process to finish and get exit code
  let exit_code = tg.wait()[0]

  match result {
    Ok(_) => {
      if exit_code == 0 {
        Ok(())
      } else {
        Err(DockerCommandFailed("Docker logs exited with code \{exit_code}"))
      }
    }
    Err(e) => Err(e)
  }
})
```

**理由:** `@process.run` はasync関数で、プロセスの出力を読む間は実行中なので、exit_codeを先に取得することはできない。`@async.with_task_group` を使って、プロセス実行とログ読み取りを並行実行し、完了後にexit_codeを取得する。

## 技術的な決定事項

1. **labeled argument構文の採用**
   - MoonBitの構文規則に従い、`options?` を使用
   - デフォルト値は関数内でmatch式を使って設定
   - 呼び出し側は `stream_logs(callback)` または `stream_logs(callback, options)` で使用可能

2. **while trueループの採用**
   - `loop` の代わりに `while true` を使用
   - `break` に値を渡すことで、ループからの戻り値を返す
   - EOFの場合は `break Ok(())` で正常終了を返す

3. **task groupによる並行実行**
   - `@async.with_task_group` を使ってプロセス実行とログ読み取りを並行実行
   - `tg.spawn` でプロセスをバックグラウンド実行
   - `tg.wait()` でプロセスの完了を待ち、exit_codeを取得

## 変更ファイル一覧

### 追加
- `docs/steering/fix_api_errors_20260208.md`: Steeringドキュメント
- `docs/completed/fix_api_errors_20260208.md`: このドキュメント

### 変更
- `moonbit_test_containers.mbt`: 3箇所の構文修正
  - 行393-406: `read_logs_line_by_line` 関数の `while true` への変更
  - 行415-449: `Container::stream_logs` 関数のlabeled argumentと並行実行への変更

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

### 影響を受けるテスト
- `stream_logs - basic` (行532-581)
- `stream_logs - callback count` (行584-631)
- `stream_logs - redis container` (行634-684)

## 今後の課題・改善点

### 潜在的な問題
1. **labeled argumentの呼び出し方法**
   - テストコードで `c.stream_logs(callback, options)` と呼び出している箇所がある
   - labeled argumentを使う場合、`c.stream_logs(callback, options=options)` と明示的にラベルを指定する必要があるかもしれない
   - テスト実行で確認が必要

2. **task groupの動作確認**
   - `@async.with_task_group` の動作が想定通りか確認が必要
   - `tg.wait()` の戻り値が配列かどうか確認が必要
   - プロセスが異常終了した場合の挙動を確認が必要

3. **while trueループの動作確認**
   - `break Ok(())` の構文が正しいか確認が必要
   - ループからの戻り値が正しく返されるか確認が必要

### 次のステップ
1. `moon check --target native` でコンパイルエラーがないか確認
2. `moon test --native` でテストが通るか確認
3. エラーがあれば、テストコードまたは実装コードを修正
4. 全てのテストが通ったらコミット

## 参考資料
- MoonBit言語仕様: https://docs.moonbitlang.com
- ユーザーからの問題報告: moonbit_test_containers.mbtの3箇所の構文エラー
- Steeringドキュメント: docs/steering/fix_api_errors_20260208.md
