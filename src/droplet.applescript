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

on candidatePath()
	return POSIX path of (path to resource "ssh-file-drop-host-candidates")
end candidatePath

on runCandidateExtractor()
	return do shell script quoted form of my candidatePath()
end runCandidateExtractor

on runHelper(args)
	set cmd to quoted form of my helperPath()
	repeat with a in args
		set cmd to cmd & " " & quoted form of (a as text)
	end repeat
	return do shell script cmd
end runHelper

on handleDrop(theItems)
	activate
	if (count of theItems) is 0 then return
	set filePaths to {}
	set fileNames to {}
	repeat with droppedItem in theItems
		set filePath to POSIX path of droppedItem
		set checkResult to my runHelperTolerant({"--check-file", filePath})
		set parsed to my parseOutput(checkResult)
		if (errCategory of parsed) is not "" then
			display alert appTitle message "This item cannot be sent:" & return & filePath & return & (errMessage of parsed) as warning
			return
		end if
		set end of filePaths to filePath
		set end of fileNames to okValue of parsed
	end repeat

	set hostName to my chooseHost(fileNames)
	if hostName is missing value then return

	set sentPaths to {}
	set totalFiles to count of filePaths
	repeat with fileIndex from 1 to totalFiles
		set transferResult to my transfer(hostName, item fileIndex of filePaths, item fileIndex of fileNames, fileIndex, totalFiles)
		set parsed to transferParsed of transferResult
		set wasCancelled to transferCancelled of transferResult
		if (okValue of parsed) is not "" then
			set end of sentPaths to okValue of parsed
		else
			my reportFailure(parsed, hostName, item fileIndex of fileNames, wasCancelled, sentPaths)
			return
		end if
	end repeat
	my finishSuccess(my joinLines(sentPaths), hostName)
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
on chooseHost(fileNames)
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
		set promptText to "Files: " & my joinLines(fileNames) & return & "Choose a host for this drop."
		if (count of hosts) is 0 then set promptText to promptText & return & "No hosts are registered yet."
		set picked to choose from list choices with title appTitle with prompt promptText default items {defaultItem} OK button name "転送" cancel button name "キャンセル"
		if picked is false then return missing value
		set choice to item 1 of picked
		if choice is not addHostItem then return choice

		set newHost to my addHost()
		if newHost is missing value then return missing value
		set preferred to newHost
	end repeat
end chooseHost

on addHost()
	set candidates to {}
	try
		set rawCandidates to my runCandidateExtractor()
		if rawCandidates is not "" then set candidates to paragraphs of rawCandidates
	end try
	set manualItem to "手入力…"
	if (count of candidates) > 0 then
		set pickedCandidate to choose from list (candidates & {manualItem}) with title appTitle with prompt "~/.ssh/config の Host 候補を選ぶか、手入力してください。" OK button name "追加" cancel button name "キャンセル"
		if pickedCandidate is false then return missing value
		set newHost to item 1 of pickedCandidate
		if newHost is manualItem then set newHost to my promptForHost()
	else
		set newHost to my promptForHost()
	end if
	if newHost is missing value then return missing value
	try
		my runHelper({"--add-host", newHost})
		return newHost
	on error
		display alert appTitle message "この名前は使えません。" & return & "英数字と . _ @ + - だけで、先頭は英数字か _ にしてください。" as warning
		return missing value
	end try
end addHost

on promptForHost()
	set answer to display dialog "~/.ssh/config に書いてある Host の名前を入力してください。" & return & "(例: dev-server)" default answer "" with title appTitle buttons {"キャンセル", "追加"} default button 2 cancel button 1
	return text returned of answer
end promptForHost

on transfer(hostName, filePath, fileName, fileIndex, totalFiles)
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
		set progress description to "Sending " & fileIndex & " of " & totalFiles & ": " & fileName
		set progress additional description to "Host: " & hostName & "  (Stop to cancel)"
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
	return {transferParsed:parsed, transferCancelled:cancelled}
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

on reportFailure(parsed, hostName, fileName, cancelled, sentPaths)
	activate
	set cat to errCategory of parsed
	set noteText to my cleanupNote(cleanupState of parsed)
	set copyResult to my copyPartial(sentPaths)
	set copiedCount to copiedCount of copyResult
	set clipboardNote to copyNote of copyResult
	set detail to errMessage of parsed
	if cat is "" then
		set body to "The helper did not return a result."
	else if cat is "CONNECT" then
		set body to "Could not connect. In Terminal, run ssh " & hostName & " to check the connection and host key." & return & return & "If that works but this app fails, the app may not see your SSH agent. Check IdentityAgent or AddKeysToAgent in ~/.ssh/config." & return & return & "Details: " & detail
	else if cat is "REMOTE_SETUP" then
		set body to "Could not create a work directory on the host. Check free space and permissions." & return & return & "Details: " & detail
	else if cat is "UPLOAD" then
		set body to "Upload failed. The connection may have dropped or the host may be out of space." & return & return & "Details: " & detail
	else if cat is "VERIFY" then
		set body to "Transfer verification failed. No path was returned." & return & return & "Details: " & detail
	else if cat is "FINALIZE" then
		set body to "Could not finalize the file. No path was returned." & return & return & "Details: " & detail
	else if cat is "CANCELLED" or cancelled then
		set body to "Transfer was cancelled."
	else
		set body to detail
	end if
	set body to "File: " & fileName & return & body & return & return & copiedCount & " path(s) copied to the clipboard." & clipboardNote
	display alert appTitle message body & noteText as critical
end reportFailure

on copyPartial(sentPaths)
	if (count of sentPaths) is 0 then return {copiedCount:0, copyNote:" The clipboard was left unchanged."}
	try
		set joinedPaths to my joinLines(sentPaths)
		set the clipboard to joinedPaths
		if (the clipboard as text) is joinedPaths then return {copiedCount:(count of sentPaths), copyNote:""}
	on error
	end try
	return {copiedCount:0, copyNote:" The clipboard could not be updated; no paths were copied."}
end copyPartial

on joinLines(theLines)
	set savedDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set joined to theLines as text
	set AppleScript's text item delimiters to savedDelims
	return joined
end joinLines

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
