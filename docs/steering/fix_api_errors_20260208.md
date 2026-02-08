# Steering: APIエラーの修正

## 目的・背景
moonbit_test_containers.mbtにMoonBitの構文エラーが3箇所存在し、コンパイルが通らない状態。
これらのエラーを修正して、正常にビルドとテストができる状態にする。

## ゴール
- 全てのコンパイルエラーを解消
- `moon check --target native` が成功する
- `moon test --native` が成功する
- APIの動作は変更しない（構文のみ修正）

## アプローチ

### 問題1: デフォルト引数の構文エラー（行416）
**現状:**
```moonbit
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options : LogOptions = LogOptions::default()
) -> Result[Unit, TestContainerError]
```

**問題:** MoonBitではlabeled argumentでのみデフォルト値を使える

**修正方法:**
```moonbit
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options? : LogOptions
) -> Result[Unit, TestContainerError]
```

関数内で `options` の値を確定:
```moonbit
let options = match options {
  Some(opts) => opts
  None => LogOptions::default()
}
```

### 問題2: loop/breakの構文エラー（行395-405）
**現状:**
```moonbit
loop {
  match reader.read_line() {
    Ok(line) => { ... }
    Err(@io.EOF) => break
    Err(e) => return Err(...)
  }
}
```

**問題:** MoonBitの `loop` では `break` が使えない

**修正方法:** `while true` を使用し、`Err(@io.EOF)` で `break Ok(())` を返す
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

`while` の後に到達不能コードの警告を避けるため、whileの後には何も書かない。

### 問題3: @process.runの使い方が間違っている（行424-427）
**現状:**
```moonbit
let (reader, writer) = @process.read_from_process()
let exit_code = @process.run("docker", args, stdout=writer)
```

**問題:** `@process.run` はasync関数で、戻り値は `Int` だが同期的には取得できない。
プロセスの出力を読む間、プロセスは実行中なので、exit_codeを先に取得することはできない。

**修正方法:** `@async.with_task_group` を使って並行実行
```moonbit
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

## スコープ

### 含む
- 上記3箇所の構文エラー修正
- 修正後の動作確認（コンパイル、テスト）

### 含まない
- 新機能の追加
- パフォーマンス改善
- ドキュメント更新（必要に応じて別タスク）

## 影響範囲

### 変更ファイル
- `moonbit_test_containers.mbt`: 3箇所の構文修正

### テストファイル
- `moonbit_test_containers_wbtest.mbt`: ログストリーミングのテストを確認

## 技術的な制約
- MoonBitの構文ルールに従う
- 既存のAPIインターフェースを変更しない（labeled argumentへの変更は許容）
- async/awaitの正しい使い方を守る

## リスク
- labeled argumentへの変更により、既存の呼び出し側コードが影響を受ける可能性（確認が必要）
- `@async.with_task_group` のAPI仕様が想定と異なる可能性（ドキュメント確認が必要）

## 成功基準
1. `moon check --target native` がエラーなく完了
2. `moon test --native` が全てパス
3. 既存テストの動作が変わらない
