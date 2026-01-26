property parallelJobs : "12"

on open theseItems
	try
		set pathList to {}
		repeat with thisItem in theseItems
			set end of pathList to quoted form of POSIX path of thisItem
		end repeat

		if (count of pathList) is 0 then return

		set AppleScript's text item delimiters to " "
		set pathString to pathList as text
		set AppleScript's text item delimiters to ""

		set myPath to POSIX path of (path to me)
		set scriptPath to myPath & "Contents/Resources/Scripts/convert.sh"
		set progressApp to myPath & "Contents/Resources/ADMProgress"
		set wrapperScript to myPath & "Contents/Resources/Scripts/run_with_progress.sh"

		do shell script quoted form of wrapperScript & " " & quoted form of scriptPath & " " & quoted form of progressApp & " " & parallelJobs & " " & pathString

	on error
	end try
end open

on run
end run
