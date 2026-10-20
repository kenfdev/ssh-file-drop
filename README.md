# SSH File Drop

SSH File Drop は、ファイルをアプリアイコンへドロップし、選んだ SSH 接続先の `/tmp` に送る macOS アプリです。転送後、リモートの絶対パスをクリップボードにコピーします。

## 必要なものと対応範囲

- macOS の AppleScript ドロップレット機能と標準コマンドを使います。ビルドとインストールのテストは macOS 26.5 で実行しました。これより古い macOS は未確認です。
- リモート側には SSH 接続と、POSIX 系の `sh`、`mktemp`、`chmod`、`printf`、`wc`、`mv` などが必要です。リモートの `/tmp` に作成・書き込みできる必要があります。テストしたリモート OS は macOS（Darwin 25.5.0）です。Linux など他の OS は未確認です。
- macOS 標準の `/usr/bin/ssh`、`/usr/bin/scp`、`osacompile`、`codesign`、`ditto`、AppleScript 実行環境を使います。別途ランタイムのインストールは不要です。
- SSH の既存設定、鍵、エージェントを使います。アプリはパスワードや秘密鍵のパスフレーズを尋ねたり保存したりしません。

## ビルドとインストール

リポジトリのルートで実行します。

```sh
scripts/build.sh
scripts/install.sh
```

`build.sh` は `build/SSH File Drop.app` を作ります。`install.sh` はアプリをビルドし、既定で `~/Applications/SSH File Drop.app` にインストールします。既存のインストール先アプリが起動中なら終了を待ち、終了しない場合は置き換えを中止します。Dock への追加や SSH 設定の変更は行いません。

Dock に置く場合は、Finder で `~/Applications/SSH File Drop.app` を Dock へドラッグします。`build/SSH File Drop.app` ではなくインストール済みのコピーを使ってください。ビルドし直すと `build/` のアプリは置き換わります。

## SSH 接続先を登録する

1. Terminal で接続先の別名を確認します。たとえば `~/.ssh/config` に次の設定がある場合、Host 名は `dev-server` です。

   ```sshconfig
   Host dev-server
     HostName server.example.com
     User myname
     IdentityFile ~/.ssh/id_ed25519
   ```

2. 初回は Terminal で `ssh dev-server` を実行します。表示されたホスト鍵の指紋を確認し、信頼できる接続先だと確認できた場合だけ受け入れてください。接続と認証が成功したことを確認してから `exit` します。鍵を自動で信頼する設定にはしないでください。
3. アプリのファイル選択後に Host 一覧が出ます。「＋ Host を追加…」から `~/.ssh/config` の候補を選ぶか、Host 名を入力します。登録内容は `~/.config/ssh-file-drop/hosts` に 1 行 1 Host で保存されます。候補の抽出は簡易的で、Host 設定の意味を完全には解釈しません。使いたい別名が候補にない場合は手入力できます。

この一覧は SSH 接続先の選択リストです。`~/.ssh/config` を編集しただけでは一覧に自動追加されません。登録した Host 名は OpenSSH に渡され、実際の接続設定は OpenSSH が解決します。

### Terminal と Finder／Dock の違い

Terminal と Finder／Dock から起動したアプリでは環境変数や SSH エージェントへの接続状況が異なる場合があります。Terminal のシェル設定がアプリにも読み込まれるとは限りません。アプリで接続できない場合は、Terminal で `ssh dev-server` を試してください。Terminal でも失敗するなら SSH 接続、鍵、ホスト鍵を直してください。Terminal では成功するのにアプリで失敗する場合は、SSH エージェントが GUI アプリから見えない可能性があります。SSH 設定の `IdentityAgent` や `AddKeysToAgent` も確認してください。アプリは接続失敗を表示し、ホスト鍵を自動で受け入れません。

## 使い方

Finder から通常ファイルを **1 つ**、Dock または Finder 上の `SSH File Drop` アイコンへドラッグします。Host を選び、「転送」を選ぶと転送を開始します。成功すると、たとえば `/tmp/ssh-file-drop.a1B2c3D4/report.pdf` のようなパスだけをクリップボードへコピーします。自動ペーストやコマンド実行はしません。

アプリをダブルクリックすると説明ダイアログが表示されます。ダブルクリックでは転送されません。

ファイルは Host ごとに新しく作った `/tmp/ssh-file-drop.*` ディレクトリに置かれます。ディレクトリは `0700`、完成ファイルは `0600` です。同じ名前を再度送っても別ディレクトリになるため、前のファイルを上書きしません。`/tmp` の内容は OS の整理や再起動などで消えることがあります。長期保存には使わないでください。

## 送信しない入力と制限

- ディレクトリ、シンボリックリンク、複数ファイルは転送前に拒否します。通常ファイル以外、読めないファイル、改行・制御文字を含む名前、255 バイトを超える名前、予約済みの一時名も拒否します。
- 進捗表示とキャンセルに対応します。キャンセルや転送失敗では成功パスを出さず、既存のクリップボードを変更しません。切断などで後始末を確認できない場合は、未完成の作業用ディレクトリが残った可能性を表示します。
- Host 名は登録した SSH Host エイリアスです。Host 名として使えない文字は拒否します。
- コピーするのはリモートパスだけです。空白を含むパスをシェルで使う場合は、必要に応じて自分で引用してください。
- `/tmp` 内のファイルを自動削除する機能、複数ファイル転送、ディレクトリ転送、クイックアクションはありません。

## 削除

1. アプリが起動中なら終了します。
2. Finder で `~/Applications/SSH File Drop.app` をゴミ箱へ移動します。Dock に登録している場合は Dock からも取り除きます。
3. 設定も削除する場合だけ、`~/.config/ssh-file-drop/hosts` と `~/.config/ssh-file-drop/last_host` を削除します。SSH の `~/.ssh/config`、鍵、known_hosts はこのアプリの設定ではないため、削除しないでください。
4. リモートに残ったファイルが不要なら、登録済み Host に SSH 接続し、自分の `/tmp/ssh-file-drop.*` の中身を確認してから、不要な個別ディレクトリを削除します。`/tmp` 全体や、内容を確認していないディレクトリを削除しないでください。

テスト結果と未確認事項は [`docs/test-results.md`](docs/test-results.md) を参照してください。
