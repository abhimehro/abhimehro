tell application "System Events"
    tell process "DownloadsOrganizer"
        set frontmost to true
        repeat 20 times
            if exists button "Organize 3 Files" of window 1 then exit repeat
            delay 0.5
        end repeat
        if not (exists button "Organize 3 Files" of window 1) then error "Expected organize button was not available"
        click button "Organize 3 Files" of window 1
        repeat 10 times
            if exists sheet 1 of window 1 then exit repeat
            delay 0.5
        end repeat
        if not (exists sheet 1 of window 1) then error "Organization confirmation did not appear"
        click button "Organize" of sheet 1 of window 1
        delay 2
    end tell
end tell
