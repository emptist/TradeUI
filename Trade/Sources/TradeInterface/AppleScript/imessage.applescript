on run {targetPhoneNumber, targetMessageToSend}
    if targetMessageToSend contains "*" then
        set targetMessageToSend to my replaceText(targetMessageToSend, "*", ASCII character 10)
    end if

    tell application "Messages"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to buddy targetPhoneNumber of targetService
        set targetMessage to targetMessageToSend
        send targetMessage to targetBuddy
    end tell
end run

on replaceText(theText, oldString, newString)
    set {tempTID, AppleScript's text item delimiters} to {AppleScript's text item delimiters, oldString}
    set newText to text items of theText
    set AppleScript's text item delimiters to newString
    set newText to newText as text
    set AppleScript's text item delimiters to tempTID
    return newText
end replaceText
