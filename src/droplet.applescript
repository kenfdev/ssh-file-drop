-- SSH File Drop: ファイルをドロップすると SSH 接続先の /tmp へ送り、リモートの絶対パスをクリップボードに入れる。
-- 転送の処理はすべて Contents/Resources/ssh-file-drop-send が行う。ここは画面と結果の受け取りだけを担当する。

property appTitle : "SSH File Drop"
property addHostItem : "＋ Host を追加…"

on run
	activate
	display dialog "このアプリのアイコンへ、転送したいファイルを 1 つドロップしてください。" & return & return & "Host の一覧は ~/.config/ssh-file-drop/hosts に 1 行 1 つで書くか、ドロップ後の画面で追加できます。" with title appTitle buttons {"OK"} default button 1
end run

on open theItems
	try
		my handleDrop(theItems)
	on error errMsg number errNum
		if errNum is not -128 then
			activate
			display alert appTitle message "予期しないエラーが起きました。" & return & errMsg as critical
		end if
	end try
end open

on helperPath()
	return POSIX path of (path to resource "ssh-file-drop-send")
end helperPath

on runHelper(args)
	set cmd to quoted form of my helperPath()
	repeat with a in args
		set cmd to cmd & " " & quoted form of (a as text)
	end repeat
	return do shell script cmd
end runHelper

on handleDrop(theItems)
	activate
	if (count of theItems) is not 1 then
		display alert appTitle message "ファイルは一度に 1 つだけ転送できます。" & return & (count of theItems) & " 個がドロップされました。" as warning
		return
	end if
	set filePath to POSIX path of (item 1 of theItems)

	set checkResult to my runHelperTolerant({"--check-file", filePath})
	set parsed to my parseOutput(checkResult)
	if (errCategory of parsed) is not "" then
		display alert appTitle message "このファイルは転送できません。" & return & (errMessage of parsed) as warning
		return
	end if
	set fileName to okValue of parsed

	set hostName to my chooseHost(fileName)
	if hostName is missing value then return

	my transfer(hostName, filePath, fileName)
end handleDrop

-- 終了コードが 0 以外でも標準出力を受け取る。
on runHelperTolerant(args)
	set cmd to quoted form of my helperPath()
	repeat with a in args
		set cmd to cmd & " " & quoted form of (a as text)
	end repeat
	return do shell script cmd & " 2>/dev/null; true"
end runHelperTolerant

on listHosts()
	set raw to my runHelper({"--list-hosts"})
	if raw is "" then return {}
	return paragraphs of raw
end listHosts

on lastHost()
	return my runHelper({"--last-host"})
end lastHost

-- 戻り値は選ばれた Host。キャンセルなら missing value。
on chooseHost(fileName)
	set preferred to my lastHost()
	repeat
		set hosts to my listHosts()
		set choices to hosts & {addHostItem}
		set defaultItem to addHostItem
		if preferred is not "" and hosts contains preferred then
			set defaultItem to preferred
		else if (count of hosts) > 0 then
			set defaultItem to item 1 of hosts
		end if
		set promptText to "ファイル: " & fileName & return & "転送先の Host を選んでください。"
		if (count of hosts) is 0 then set promptText to promptText & return & "まだ Host が登録されていません。"
		set picked to choose from list choices with title appTitle with prompt promptText default items {defaultItem} OK button name "転送" cancel button name "キャンセル"
		if picked is false then return missing value
		set choice to item 1 of picked
		if choice is not addHostItem then return choice

		set answer to display dialog "~/.ssh/config に書いてある Host の名前を入力してください。" & return & "(例: dev-server)" default answer "" with title appTitle buttons {"キャンセル", "追加"} default button 2 cancel button 1
		set newHost to text returned of answer
		try
			my runHelper({"--add-host", newHost})
			set preferred to newHost
		on error
			display alert appTitle message "この名前は使えません。" & return & "英数字と . _ @ + - だけで、先頭は英数字か _ にしてください。" as warning
		end try
	end repeat
end chooseHost

on transfer(hostName, filePath, fileName)
	set workDir to do shell script "/usr/bin/mktemp -d /tmp/ssh-file-drop-ui.XXXXXX"
	set outFile to workDir & "/out"
	set pidFile to workDir & "/pid"
	set rcFile to workDir & "/rc"

	set launcher to "/bin/sh -c " & quoted form of ("\"$1\" \"$2\" \"$3\" >\"$4\" 2>/dev/null </dev/null & echo $! >\"$5\"; wait $!; echo $? >\"$6\"")
	set launcher to launcher & " sh " & quoted form of my helperPath() & " " & quoted form of hostName & " " & quoted form of filePath & " " & quoted form of outFile & " " & quoted form of pidFile & " " & quoted form of rcFile
	do shell script launcher & " >/dev/null 2>&1 &"

	set cancelled to false
	try
		set progress total steps to -1
		set progress description to "転送中: " & fileName
		set progress additional description to "転送先: " & hostName & "  (Stop で中止)"
		repeat until my fileExists(rcFile)
			delay 0.3
		end repeat
	on error errMsg number errNum
		if errNum is not -128 then error errMsg number errNum
		set cancelled to true
	end try

	if cancelled then
		my stopHelper(pidFile, rcFile)
	end if

	set outText to ""
	try
		set outText to read (POSIX file outFile) as «class utf8»
	end try
	do shell script "/bin/rm -f " & quoted form of outFile & " " & quoted form of pidFile & " " & quoted form of rcFile & "; /bin/rmdir " & quoted form of workDir & " 2>/dev/null; true"

	set parsed to my parseOutput(outText)
	my report(parsed, hostName, fileName, cancelled)
end transfer

on fileExists(p)
	return (do shell script "/bin/test -e " & quoted form of p & " && echo y || echo n") is "y"
end fileExists

-- ヘルパーへ TERM を送り、後始末が終わるまで待つ。
on stopHelper(pidFile, rcFile)
	try
		set helperPid to do shell script "/bin/cat " & quoted form of pidFile
		if helperPid is not "" then do shell script "/bin/kill -TERM " & helperPid & " 2>/dev/null; true"
	end try
	repeat 60 times
		if my fileExists(rcFile) then exit repeat
		delay 0.5
	end repeat
end stopHelper

on parseOutput(outText)
	set okVal to ""
	set errCat to ""
	set errMsg to ""
	set cleanup to ""
	set savedDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to tab
	repeat with ln in paragraphs of outText
		set parts to text items of (ln as text)
		if (count of parts) >= 2 then
			set tag to item 1 of parts
			if tag is "OK" then
				set okVal to (items 2 thru -1 of parts) as text
			else if tag is "ERR" and (count of parts) >= 3 then
				set errCat to item 2 of parts
				set errMsg to (items 3 thru -1 of parts) as text
			else if tag is "CLEANUP" then
				set cleanup to item 2 of parts
			end if
		end if
	end repeat
	set AppleScript's text item delimiters to savedDelims
	return {okValue:okVal, errCategory:errCat, errMessage:errMsg, cleanupState:cleanup}
end parseOutput

on cleanupNote(state)
	if state is "failed" then return return & return & "リモートに未完成のファイルが残っている可能性があります。接続できるときに /tmp/ssh-file-drop.* を確認してください。"
	if state is "unknown" then return return & return & "リモートの後始末を確認できませんでした。/tmp/ssh-file-drop.* に空のディレクトリや未完成のファイルが残っている可能性があります。"
	return ""
end cleanupNote

on report(parsed, hostName, fileName, cancelled)
	activate
	set okVal to okValue of parsed
	if okVal is not "" then
		my finishSuccess(okVal, hostName)
		return
	end if

	set cat to errCategory of parsed
	set noteText to my cleanupNote(cleanupState of parsed)
	if cancelled or cat is "CANCELLED" then
		display alert appTitle message "転送を中止しました。クリップボードは変更していません。" & noteText as informational
		return
	end if

	set detail to errMessage of parsed
	if cat is "" then
		set body to "ヘルパーが結果を返しませんでした。クリップボードは変更していません。"
	else if cat is "CONNECT" then
		set body to "接続できませんでした。" & return & return & "Terminal で次を実行し、接続とホスト鍵の確認ができるか試してください。" & return & "ssh " & hostName & return & return & "Terminal では成功するのにこのアプリで失敗する場合は、SSH エージェントがアプリから見えていない可能性があります。~/.ssh/config の IdentityAgent や AddKeysToAgent を確認してください。" & return & return & "詳細: " & detail
	else if cat is "REMOTE_SETUP" then
		set body to "転送先に作業用ディレクトリを作れませんでした。空き容量と権限を確認してください。" & return & return & "詳細: " & detail
	else if cat is "UPLOAD" then
		set body to "アップロードに失敗しました。通信が切れたか、転送先の容量が足りない可能性があります。" & return & return & "詳細: " & detail
	else if cat is "VERIFY" then
		set body to "転送内容を確認できませんでした。パスは出していません。" & return & return & "詳細: " & detail
	else if cat is "FINALIZE" then
		set body to "ファイルの確定に失敗しました。パスは出していません。" & return & return & "詳細: " & detail
	else
		set body to detail
	end if
	display alert appTitle message body & noteText as critical
end report

on finishSuccess(remotePath, hostName)
	set copied to false
	repeat
		try
			set the clipboard to remotePath
			if (the clipboard as text) is remotePath then
				set copied to true
				exit repeat
			end if
		end try
		set answer to display dialog "転送は完了しましたが、クリップボードにコピーできませんでした。" & return & return & remotePath with title appTitle buttons {"閉じる", "もう一度コピー"} default button 2 cancel button 1
		-- 「閉じる」は取り消しエラーになり、そのまま終了する。転送は再実行しない。
	end repeat
	display dialog "転送しました。パスをクリップボードにコピーしました。" & return & return & remotePath & return & return & "転送先: " & hostName with title appTitle buttons {"OK"} default button 1 giving up after 15
end finishSuccess
