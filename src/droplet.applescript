-- SSH File Drop sends dropped files to /tmp on an SSH host and copies their remote paths to the clipboard.
-- The helper in Contents/Resources/ssh-file-drop-send handles transfers; this script handles the UI and results.

property appTitle : "SSH File Drop"
property addHostItem : "+ Add Host..."

on run
	activate
	display dialog "Drop one or more files onto this app's icon to send them." & return & return & "List hosts one per line in ~/.config/ssh-file-drop/hosts, or add them after dropping files." with title appTitle buttons {"OK"} default button 1
end run

on open theItems
	try
		my handleDrop(theItems)
	on error errMsg number errNum
		if errNum is not -128 then
			activate
			display alert appTitle message "An unexpected error occurred." & return & errMsg as critical
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

-- Capture stdout even when the helper exits with a nonzero status.
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

-- Returns the selected host, or missing value if cancelled.
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
		set picked to choose from list choices with title appTitle with prompt promptText default items {defaultItem} OK button name "Transfer" cancel button name "Cancel"
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
	set manualItem to "Enter Manually..."
	if (count of candidates) > 0 then
		set pickedCandidate to choose from list (candidates & {manualItem}) with title appTitle with prompt "Choose a host from ~/.ssh/config or enter one manually." OK button name "Add" cancel button name "Cancel"
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
		display alert appTitle message "This host name is not allowed." & return & "Use letters, digits, and . _ @ + -. The first character must be a letter, digit, or _." as warning
		return missing value
	end try
end addHost

on promptForHost()
	set answer to display dialog "Enter a host name from ~/.ssh/config." & return & "(Example: dev-server)" default answer "" with title appTitle buttons {"Cancel", "Add"} default button 2 cancel button 1
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

-- Send TERM to the helper and wait for cleanup to finish.
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
	if state is "failed" then return return & return & "An incomplete file may remain on the host. When connected, check /tmp/ssh-file-drop.*."
	if state is "unknown" then return return & return & "Remote cleanup could not be confirmed. An empty directory or incomplete file may remain under /tmp/ssh-file-drop.*."
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
		set answer to display dialog "The transfer finished, but the path could not be copied to the clipboard." & return & return & remotePath with title appTitle buttons {"Close", "Copy Again"} default button 2 cancel button 1
		-- Close raises a cancellation error and exits. Do not repeat the transfer.
	end repeat
	display dialog "Transfer complete. The path was copied to the clipboard." & return & return & remotePath & return & return & "Host: " & hostName with title appTitle buttons {"OK"} default button 1 giving up after 15
end finishSuccess
