# 設計メモ

要件の正本は `docs/brief.md`（依頼書のコピー）。この文書は実装上の決定を記録する。

## 構成

| ファイル | 役割 |
| --- | --- |
| `src/ssh-file-drop-send` | 転送ヘルパー（bash 3.2 互換）。UI を持たない。 |
| `src/droplet.applescript` | ドロップレット。Host 選択、進捗、キャンセル、結果表示、クリップボード。 |
| `scripts/build.sh` | `osacompile` で `.app` を作り、ヘルパーと `assets/AppIcon.icns` を組み込み、ad-hoc 署名する。既定アイコンが優先されるため、生成された `Assets.car` は除く。 |
| `scripts/make-icon.sh` | `assets/icon-1024.png` から標準サイズの `.iconset` を作り、`sips` と `iconutil` で `assets/AppIcon.icns` を再生成する。通常のビルドでは再生成しない。 |
| `scripts/install.sh` | ビルド後、インストール先のアプリを終了して待ち、`~/Applications/SSH File Drop.app` を置き換える。`SSH_FILE_DROP_INSTALL_DIR` でテスト用の保存先を指定できる。終了しない場合は 30 秒後に中止し、既存アプリを残す。待ち時間は `SSH_FILE_DROP_QUIT_TIMEOUT_SECONDS`（1〜300 秒）で変更できる。Dock と利用者の設定は変更しない。 |
| `tests/` | ヘルパーと Host 候補抽出の自動テスト。 |

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

## Droplet

- `on open` accepts one or more dropped items. It checks every item with `--check-file` before sending any file. If any item is not a regular file, the whole drop is rejected and the alert identifies the item and reason.
- The user chooses one host for the entire drop. Files are sent sequentially in drop order through the unchanged single-file helper. Progress names the current file and its position.
- Each helper call creates its own fresh remote directory, so equal basenames never overwrite one another.
- On full success, the clipboard contains every returned remote path in drop order, separated by line breaks with no trailing line break. A one-file drop still copies one path with no trailing line break.
- On failure or cancellation, sending stops at the current file. The helper's existing cleanup handles that file's partial remote upload. Previously completed paths are copied to the clipboard, one per line; when the first file fails, the clipboard is left unchanged. The alert identifies the failed file and reason, states the number of copied paths, and retains the helper's transfer-category and cleanup-failure details.
- Host 一覧は `~/.config/ssh-file-drop/hosts`（1 行 1 エイリアス、`#` コメント可）。前回成功した Host は `~/.config/ssh-file-drop/last_host`。
- 「Host を追加…」では `src/ssh-file-drop-host-candidates` が `~/.ssh/config` から候補を抽出する。Include は `~/.ssh` 基準で glob 展開し、最大深度 8 まで再帰する。同じファイルの再読込を避け、Match ブロックを無視する。`*`、`?`、先頭 `!` を含む名前と、転送ヘルパーの Host 検証に通らない名前は除く。抽出は単純な空白区切りの Include パスと glob に対応し、空白を含む引用パス、Match 条件の評価、Host パターンの実接続先への展開はしない。
- 候補から選ぶか手入力でき、選んだ Host だけを既存の検証に通して `hosts` へ追記する。`hosts` は引き続き明示的な選択リストで、自動同期しない。SSH 設定には wildcard や実接続先ではない Host 宣言もあるため、利用者が追加を選ぶ形にする。
- `choose from list` のプロンプトにファイル名を出し、ボタンを「転送」「キャンセル」にする。一覧の末尾に「Host を追加…」を置く。
- ヘルパーをバックグラウンドで起動し、stdout を一時ファイルへ出す。`progress total steps` と `progress description` でスピナーを出し、`kill -0` で終了を待つ。Stop は AppleScript のエラー -128 になるので、ヘルパーへ TERM を送り、終了を待ってからキャンセルを表示する。
- 成功後にだけクリップボードへ設定する。設定に失敗したら、パスを表示して「コピー」を再試行できるようにする。転送は再実行しない。
- 失敗の表示は CATEGORY ごとに文言を分ける。`CONNECT` では「Terminal で `ssh HOST` を実行して接続とホスト鍵を確認してください」と案内する。
- `CLEANUP` が `failed` または `unknown` のときは、「リモートに未完成のディレクトリが残っている可能性があります」と表示する。

## 採用しなかった案

| 案 | 採らない理由 |
| --- | --- |
| `ssh host 'cat > path'` で転送 | `scp` で足りる。依頼書は `scp` を指定している。 |
| ユーザー由来のファイル名を `scp` のリモートパスに使う | `scp` の版（SFTP／旧方式）でパス解釈が違う。固定名でアップロードして `mv` で改名する。 |
| `~/.ssh/config` を常に選択リストとして使う | `Host` パターンや条件付き設定が混在する。候補は追加操作の中で提示し、実際の選択リストは `hosts` に明示登録された別名に保つ。 |
| Python や Node のヘルパー | 外部ランタイムを避ける。bash と AppleScript だけで足りる。 |
