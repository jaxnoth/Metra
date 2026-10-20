tell application "Terminal"
	activate
	do script "~/prove-metra; echo DONE_EXIT:$?; sleep 5"
end tell
