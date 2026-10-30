-- Empties the Trash after the confirmation of Finder, Empty Trash, and prints what it did: "empty"
-- when the Trash held nothing, "cancelled" when the user chose Cancel, and "emptied".
-- The words of the confirmation come from the Finder in the language of the user, with the English
-- text of en.lproj/LocalizableMerged.strings in the Finder of macOS 27.0.1 when the Finder no longer
-- has the key.

on finderString(stringKey, englishText)
	set finderBundle to POSIX file "/System/Library/CoreServices/Finder.app" as alias
	set localizedText to localized string stringKey from table "LocalizableMerged" in bundle finderBundle
	if localizedText is stringKey then return englishText
	return localizedText
end finderString

on run
	tell application "Finder" to set itemCount to count of items of trash
	if itemCount is 0 then return "empty"
	set messageText to my finderString("A15", "Are you sure you want to permanently erase the items in the Trash?")
	set informativeText to my finderString("A16", "You can’t undo this action.")
	set emptyLabel to my finderString("AL10", "Empty Trash")
	set cancelLabel to my finderString("AL1", "Cancel")
	-- The alert shows in the Finder, so that it carries the icon of the Finder, and its timeout keeps
	-- it open for up to a day, where the default of AppleScript is two minutes.
	try
		tell application "Finder"
			activate
			with timeout of 86400 seconds
				display alert messageText message informativeText buttons {cancelLabel, emptyLabel} default button emptyLabel cancel button cancelLabel
			end timeout
		end tell
	on error number -128
		return "cancelled"
	end try
	-- The user has confirmed already, so the warning of the Finder is off for this erase alone, and
	-- the setting of the user comes back also when the erase fails.
	tell application "Finder"
		set warnsBeforeEmptying to warns before emptying of trash
		set warns before emptying of trash to false
		try
			with timeout of 3600 seconds
				empty trash
			end timeout
		on error errorMessage number errorNumber
			set warns before emptying of trash to warnsBeforeEmptying
			error errorMessage number errorNumber
		end try
		set warns before emptying of trash to warnsBeforeEmptying
	end tell
	return "emptied"
end run
