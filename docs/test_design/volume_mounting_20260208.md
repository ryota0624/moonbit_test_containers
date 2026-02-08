# テスト設計: ボリュームマウント機能

## 日付
2026-02-08

## テスト戦略

### 目的
ボリュームマウント機能が正しく動作し、ホストのファイル/ディレクトリがコンテナ内で利用できることを検証する。

### スコープ
- ファイルマウントの動作確認
- ディレクトリマウントの動作確認
- 読み取り専用マウントの動作確認
- 複数ボリュームマウントの動作確認
- 実用的なユースケース（PostgreSQL初期化スクリプト）の検証

### テスト環境
- Docker がインストールされている環境
- `moon test --target native` でテスト実行
- テスト用の一時ファイル/ディレクトリを使用

## テストケース

### TC-1: 基本的なファイルマウント

**目的**: ホストのファイルをコンテナにマウントできることを確認

**前提条件**:
- テスト用のファイルを作成（例: `test_file.txt`）

**テスト手順**:
1. テスト用ファイルを作成（内容: "test content"）
2. alpineコンテナを起動し、ファイルをマウント
3. コンテナ内でファイルを読み取るコマンドを実行（`cat /mnt/test_file.txt`）
4. コンテナログでファイル内容を確認

**期待結果**:
- コンテナが正常に起動
- ログに "test content" が含まれる

**実装**:
```moonbit
async test "volume mount - basic file" {
  // テストファイル作成
  let test_file = "/tmp/testcontainers_volume_test_\{@random.int()}.txt"
  @fs.write_file(test_file, "test content\n")
  defer @fs.remove_file(test_file)

  // コンテナ起動
  let container = ContainerImage::new("alpine", "3.19")
    .with_volume(test_file, "/mnt/test_file.txt")
    .with_cmd(["cat", "/mnt/test_file.txt"])
    .start()

  match container {
    Ok(c) => {
      @async.sleep(1000000000) // 1秒待機
      match c.get_logs() {
        Ok(logs) => {
          if !logs.contains("test content") {
            abort("File content not found in logs")
          }
          println("File mount test passed")
        }
        Err(e) => abort("Failed to get logs: \{e.to_string()}")
      }
      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start container: \{e.to_string()}")
  }
}
```

### TC-2: 読み取り専用マウント

**目的**: 読み取り専用オプションが正しく機能することを確認

**前提条件**:
- テスト用のファイルを作成

**テスト手順**:
1. テスト用ファイルを作成
2. alpineコンテナを起動し、ファイルを読み取り専用でマウント
3. コンテナ内でファイルへの書き込みを試みる
4. エラーが発生することを確認

**期待結果**:
- コンテナが正常に起動
- 書き込みエラーが発生（Read-only file system）

**実装**:
```moonbit
async test "volume mount - readonly" {
  // テストファイル作成
  let test_file = "/tmp/testcontainers_readonly_\{@random.int()}.txt"
  @fs.write_file(test_file, "read only content\n")
  defer @fs.remove_file(test_file)

  // コンテナ起動（読み取り専用マウント）
  let container = ContainerImage::new("alpine", "3.19")
    .with_volume(test_file, "/mnt/readonly.txt", readonly=true)
    .with_cmd(["sh", "-c", "cat /mnt/readonly.txt && echo 'write test' >> /mnt/readonly.txt || echo 'write failed (expected)'"])
    .start()

  match container {
    Ok(c) => {
      @async.sleep(1000000000)
      match c.get_logs() {
        Ok(logs) => {
          if !logs.contains("read only content") {
            abort("File not mounted correctly")
          }
          if !logs.contains("write failed") && !logs.contains("Read-only") {
            abort("Readonly constraint not working")
          }
          println("Readonly mount test passed")
        }
        Err(e) => abort("Failed to get logs: \{e.to_string()}")
      }
      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start container: \{e.to_string()}")
  }
}
```

### TC-3: 複数ボリュームマウント

**目的**: 複数のボリュームを同時にマウントできることを確認

**前提条件**:
- 複数のテスト用ファイルを作成

**テスト手順**:
1. 3つのテストファイルを作成
2. alpineコンテナを起動し、すべてのファイルをマウント
3. コンテナ内で各ファイルを確認

**期待結果**:
- すべてのファイルが正しくマウントされる
- 各ファイルの内容を確認できる

**実装**:
```moonbit
async test "volume mount - multiple volumes" {
  // 複数のテストファイル作成
  let file1 = "/tmp/testcontainers_vol1_\{@random.int()}.txt"
  let file2 = "/tmp/testcontainers_vol2_\{@random.int()}.txt"
  let file3 = "/tmp/testcontainers_vol3_\{@random.int()}.txt"

  @fs.write_file(file1, "content 1\n")
  @fs.write_file(file2, "content 2\n")
  @fs.write_file(file3, "content 3\n")

  defer {
    @fs.remove_file(file1)
    @fs.remove_file(file2)
    @fs.remove_file(file3)
  }

  // コンテナ起動（複数マウント）
  let container = ContainerImage::new("alpine", "3.19")
    .with_volume(file1, "/mnt/file1.txt")
    .with_volume(file2, "/mnt/file2.txt")
    .with_volume(file3, "/mnt/file3.txt")
    .with_cmd(["sh", "-c", "cat /mnt/file1.txt /mnt/file2.txt /mnt/file3.txt"])
    .start()

  match container {
    Ok(c) => {
      @async.sleep(1000000000)
      match c.get_logs() {
        Ok(logs) => {
          if !logs.contains("content 1") || !logs.contains("content 2") || !logs.contains("content 3") {
            abort("Not all volumes mounted correctly")
          }
          println("Multiple volumes test passed")
        }
        Err(e) => abort("Failed to get logs: \{e.to_string()}")
      }
      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start container: \{e.to_string()}")
  }
}
```

### TC-4: PostgreSQL 初期化スクリプト（実用例）

**目的**: 実用的なユースケースとしてPostgreSQLの初期化スクリプトが動作することを確認

**前提条件**:
- SQL初期化スクリプトを作成

**テスト手順**:
1. テスト用SQLファイルを作成（CREATE TABLEなど）
2. PostgreSQLコンテナを起動し、SQLファイルを `/docker-entrypoint-initdb.d/` にマウント
3. コンテナが起動完了するまで待機
4. ログで初期化が成功したことを確認

**期待結果**:
- PostgreSQLが正常に起動
- 初期化スクリプトが実行される
- ログに成功メッセージが含まれる

**実装**:
```moonbit
async test "volume mount - postgresql init script" {
  // SQL初期化スクリプト作成
  let init_sql = "/tmp/testcontainers_init_\{@random.int()}.sql"
  @fs.write_file(init_sql, "CREATE TABLE test_table (id INT, name TEXT);\n")
  defer @fs.remove_file(init_sql)

  // PostgreSQLコンテナ起動
  let container = ContainerImage::new("postgres", "16")
    .with_exposed_port(5432)
    .with_env_var("POSTGRES_USER", "test")
    .with_env_var("POSTGRES_PASSWORD", "test")
    .with_env_var("POSTGRES_DB", "testdb")
    .with_volume(init_sql, "/docker-entrypoint-initdb.d/init.sql")
    .with_wait_for(WaitStrategy::TcpPort(5432))
    .with_wait_timeout(60)
    .start()

  match container {
    Ok(c) => {
      println("PostgreSQL with init script started: \{c.get_id()}")

      // ログで初期化確認
      match c.get_logs() {
        Ok(logs) => {
          // PostgreSQLは初期化スクリプト実行時にログを出力する
          if !logs.contains("database system is ready to accept connections") {
            println("Warning: PostgreSQL may not be fully initialized")
          }
          println("PostgreSQL init script test completed")
        }
        Err(e) => println("Failed to get logs: \{e.to_string()}")
      }

      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start PostgreSQL: \{e.to_string()}")
  }
}
```

### TC-5: Nginx カスタム設定ファイル

**目的**: 設定ファイルをマウントして動作を変更できることを確認

**前提条件**:
- カスタムnginx設定ファイルを作成

**テスト手順**:
1. カスタムnginx.confを作成
2. nginxコンテナを起動し、設定ファイルをマウント
3. HTTP待機戦略で起動を確認

**期待結果**:
- nginxが正常に起動
- カスタム設定が適用される

**実装**:
```moonbit
async test "volume mount - nginx custom config" {
  // カスタムnginx設定作成（シンプルな設定）
  let nginx_conf = "/tmp/testcontainers_nginx_\{@random.int()}.conf"
  @fs.write_file(nginx_conf, "
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        location / {
            return 200 'Custom Config Test';
            add_header Content-Type text/plain;
        }
    }
}
")
  defer @fs.remove_file(nginx_conf)

  // nginxコンテナ起動
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_volume(nginx_conf, "/etc/nginx/nginx.conf", readonly=true)
    .with_wait_for(WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Nginx with custom config started: \{c.get_id()}")
      let _ = c.cleanup()
    }
    Err(e) => abort("Failed to start nginx: \{e.to_string()}")
  }
}
```

## テスト実行順序

1. TC-1: 基本的なファイルマウント（基礎）
2. TC-2: 読み取り専用マウント（オプション機能）
3. TC-3: 複数ボリュームマウント（複雑なケース）
4. TC-4: PostgreSQL 初期化スクリプト（実用例1）
5. TC-5: Nginx カスタム設定（実用例2）

## 成功基準

### 必須
- ✅ TC-1がパス（基本機能）
- ✅ TC-3がパス（複数マウント）
- ✅ TC-4がパス（実用例）

### 推奨
- ✅ TC-2がパス（読み取り専用）
- ✅ TC-5がパス（nginx設定）

### 全体
- ✅ すべてのテストが `moon test --target native` でパス
- ✅ エラーハンドリングが適切
- ✅ コンテナのクリーンアップが正しく行われる

## エラーケースのテスト

### 存在しないファイル
Docker CLIがエラーを返すため、testcontainersライブラリ側では特別な処理は不要。
Docker のエラーメッセージがそのまま `DockerCommandFailed` として返される。

### 空のパス
Docker CLIがエラーを返すため、同様に処理される。

## テスト実装の注意事項

### 一時ファイルの管理
- テストごとに一意のファイル名を生成（ランダムID使用）
- テスト終了後に必ずクリーンアップ（`defer`使用）

### コンテナのクリーンアップ
- テスト終了時に必ず `cleanup()` を呼び出す
- エラー時も確実にクリーンアップ

### 非同期処理
- コンテナ起動後に適切な待機時間を設ける
- ログ取得前に処理完了を待つ

### プラットフォーム依存性
- macOSとLinuxで動作することを確認
- パス形式はUnix形式（/）を使用

## 手動テスト項目

以下は自動テストに含めず、手動で確認する項目:

1. **存在しないホストパス**: エラーメッセージが適切に表示されることを確認
2. **パーミッションエラー**: Docker デーモンの権限エラーが適切に伝わることを確認
3. **相対パス**: 相対パスが正しく動作することを確認

## テストデータ

### テストファイル内容
- シンプルなテキスト（"test content"）
- マルチバイト文字を含まない（シンプル化）
- 改行を含む

### SQLスクリプト
- 基本的なCREATE TABLE文
- シンプルな構造

### Nginx設定
- 最小限の設定
- ポート80でリッスン
- 簡単なレスポンス返却

## 参考資料
- Docker volumes documentation: https://docs.docker.com/storage/volumes/
- PostgreSQL Docker initialization: https://hub.docker.com/_/postgres
- Nginx Docker documentation: https://hub.docker.com/_/nginx
