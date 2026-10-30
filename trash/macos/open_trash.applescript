-- Opens the Trash in a window of the Finder, and prints "opened".
tell application "Finder"
	activate
	open trash
end tell
return "opened"
