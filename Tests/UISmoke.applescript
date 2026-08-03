on buttonReport()
    tell application "System Events"
        tell process "Kakikomi"
            set report to ""
            set elements to entire contents of window 1
            repeat with elementItem in elements
                try
                    if role of elementItem is "AXButton" then
                        set elementName to ""
                        set elementDescription to ""
                        set elementIdentifier to ""
                        try
                            set elementName to name of elementItem as text
                        end try
                        try
                            set elementDescription to description of elementItem as text
                        end try
                        try
                            set elementIdentifier to value of attribute "AXIdentifier" of elementItem as text
                        end try
                        set report to report & elementName & "|" & elementDescription & "|" & elementIdentifier & "=" & (enabled of elementItem as text) & linefeed
                    end if
                end try
            end repeat
            return report
        end tell
    end tell
end buttonReport

on run argv
    tell application "Kakikomi" to activate
    delay 0.5
    if (count of argv) > 0 and item 1 of argv is "paste" then
        set the clipboard to (read POSIX file "/tmp/KakikomiVisualTest.png" as «class PNGf»)
        tell application "System Events" to keystroke "v" using command down
        delay 1
    end if
    if (count of argv) > 0 and item 1 of argv is "save" then
        tell application "System Events"
            tell process "Kakikomi"
                set elements to entire contents of window 1
                repeat with elementItem in elements
                    try
                        if value of attribute "AXIdentifier" of elementItem is "picturesSaveButton" then
                            perform action "AXPress" of elementItem
                            exit repeat
                        end if
                    end try
                end repeat
            end tell
        end tell
        delay 1
    end if
    return buttonReport()
end run
