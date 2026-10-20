# 設計メモ

要件の正本は `docs/brief.md`（依頼書のコピー）。この文書は実装上の決定を記録する。

## 構成

| ファイル | 役割 |
| --- | --- |
| `src/ssh-file-drop-send` | 転送ヘルパー（bash 3.2 互換）。UI を持たない。 |
| `src/droplet.applescript` | ドロップレット。Host 選択、進捗、キャンセル、結果表示、クリップボード。 |
| `scripts/build.sh` | `osacompile` で `.app` を作り、ヘルパーを `Contents/Resources` に入れ、ad-hoc 署名する。 |
| `tests/` | ヘルパーの自動テスト。 |

## ヘルパーの契約

呼び出し: `ssh-file-drop-send HOST FILE`

stdout は次の形式のみ。区切りはタブ。

- 成功: `OK<TAB>/tmp/ssh-file-drop.xxxxxxxx/name`
- 失敗: `ERR<TAB>CATEGORY<TAB>message`
- 後始末の状態（失敗時のみ、ERR の次の行）: `CLEANUP<TAB>none|done|failed|unknown`

stderr は診断用。ファイル内容と秘密は出さない。

終了コード: 0 成功、2 入力拒否、3 接続・認証・ホスト鍵、4 リモート準備、5 アップロード、6 検証、7 確定、130 キャンセル。

ERR の CATEGORY: `INPUT`, `CONNECT`, `REMOTE_SETUP`, `UPLOAD`, `VERIFY`, `FINALIZE`, `CANCELLED`。

### 状態機械

フェーズは `VALIDATE → MKDIR → UPLOAD → VERIFY → FINALIZE → DONE` の一方向。

- 変数 `OWNED_DIR` は、`mktemp -d` の出力が `^/tmp/ssh-file-drop\.[A-Za-z0-9]+$` に一致した後にだけ設定する。
- 後始末は `OWNED_DIR` が設定済みで、フェーズが FINALIZE 完了前のときだけ実行する。
- 後始末は `rm -f DIR/.ssh-file-drop.partial` と `rmdir DIR` だけ。`rm -rf` と、ワイルドカードは使わない。
- 確定（rename）の成否が不明な失敗では、削除しない。`CLEANUP unknown` を返す。

### 入力検証（境界）

- FILE は通常ファイルの一つだけ。ディレクトリ、シンボリックリンク（最後の要素）、存在しないパスは `INPUT` で拒否。
- ベース名に改行・制御文字（0x00-0x1f, 0x7f）を含む場合、255 バイト超の場合、予約名 `.ssh-file-drop.partial` の場合は拒否。
- HOST は `^[A-Za-z0-9_][A-Za-z0-9._@:%+-]*$` に一致するものだけ。先頭 `-`、空白、制御文字は拒否。ssh へは `--` の後ろに渡す。

### SSH 呼び出し

- 実行ファイルは `/usr/bin/ssh` と `/usr/bin/scp`。PATH に依存しない。
- 共通オプション: `BatchMode=yes`, `StrictHostKeyChecking=yes`, `ConnectTimeout=10`, `ServerAliveInterval=5`, `ServerAliveCountMax=3`, `ClearAllForwardings=yes`, ssh には `-T`。
- 環境変数 `SSH_FILE_DROP_SSH_CONFIG` があれば `-F` で渡す（テスト用。通常は未設定）。
- リモートコマンドは固定のシェルスクリプトを `sh -c '<script>' sh <args...>` で渡す。全ての引数とスクリプトを同一のシングルクォート関数で引用する。ファイル名を文字列連結でコマンドに埋め込まない。
- アップロードは `scp` で、リモート側のパスは生成した固定名（`DIR/.ssh-file-drop.partial`）だけ。ユーザー由来の名前はリモートの scp パス解釈に触れない。ローカル側は絶対パスで渡し、`host:` 形式と誤認されないようにする。

### 手順

1. `mktemp -d /tmp/ssh-file-drop.XXXXXXXX`（`umask 077`）。出力を検証して `OWNED_DIR` に設定。
2. `scp` で `.ssh-file-drop.partial` へ。開始前にローカルの size と mtime を記録。
3. 検証: ローカルの size/mtime が変わっていないこと、リモートの `wc -c` が一致すること。
4. 確定: `chmod 600 partial && mv -- partial 'name'`、`test -f` で存在確認。ディレクトリは 0700 のまま。
5. `OK` を出力。

### キャンセル

- TERM と INT を trap する。子プロセスはバックグラウンドで起動して `wait` し、trap が即時に動くようにする。
- 子プロセスを止め、必要なら後始末をして `ERR CANCELLED` と `CLEANUP` 行を出し、130 で終了する。

## ドロップレット

- `on open`: 入力が一つだけの通常ファイルかを確認する。複数・ディレクトリ・リンクは理由を表示して終了。
- Host 一覧は `~/.config/ssh-file-drop/hosts`（1 行 1 エイリアス、`#` コメント可）。前回成功した Host は `~/.config/ssh-file-drop/last_host`。
- `choose from list` のプロンプトにファイル名を出し、ボタンを「転送」「キャンセル」にする。一覧の末尾に「Host を追加…」を置く。追加された Host はヘルパー側の検証と同じ規則で確認する。
- ヘルパーをバックグラウンドで起動し、stdout を一時ファイルへ出す。`progress total steps` と `progress description` でスピナーを出し、`kill -0` で終了を待つ。Stop は AppleScript のエラー -128 になるので、ヘルパーへ TERM を送り、終了を待ってからキャンセルを表示する。
- 成功後にだけクリップボードへ設定する。設定に失敗したら、パスを表示して「コピー」を再試行できるようにする。転送は再実行しない。
- 失敗の表示は CATEGORY ごとに文言を分ける。`CONNECT` では「Terminal で `ssh HOST` を実行して接続とホスト鍵を確認してください」と案内する。
- `CLEANUP` が `failed` または `unknown` のときは、「リモートに未完成のディレクトリが残っている可能性があります」と表示する。

## 採用しなかった案

| 案 | 採らない理由 |
| --- | --- |
| `ssh host 'cat > path'` で転送 | `scp` で足りる。依頼書は `scp` を指定している。 |
| ユーザー由来のファイル名を `scp` のリモートパスに使う | `scp` の版（SFTP／旧方式）でパス解釈が違う。固定名でアップロードして `mv` で改名する。 |
| `~/.ssh/config` の `Host` 行を自動で拾う | `Include`、`Match`、ワイルドカードを扱えない。明示登録にする。 |
| Python や Node のヘルパー | 外部ランタイムを避ける。bash と AppleScript だけで足りる。 |
