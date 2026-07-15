on run arguments
    if (count of arguments) is not 1 then error "Expected the mounted DMG path"
    set mountPath to item 1 of arguments
    set diskFolder to POSIX file mountPath as alias
    set backgroundFile to POSIX file (mountPath & "/.background/dmg-background.png") as alias

    tell application "Finder"
        open diskFolder
        activate
        delay 1
        set diskWindow to container window of diskFolder
        set current view of diskWindow to icon view
        set toolbar visible of diskWindow to false
        set statusbar visible of diskWindow to false
        set pathbar visible of diskWindow to false
        set bounds of diskWindow to {120, 120, 780, 540}

        set iconOptions to the icon view options of diskWindow
        set arrangement of iconOptions to not arranged
        set icon size of iconOptions to 96
        set text size of iconOptions to 13
        set shows item info of iconOptions to false
        set shows icon preview of iconOptions to true
        set background picture of iconOptions to backgroundFile

        set position of item "CodingPet.app" of diskFolder to {170, 225}
        set position of item "Applications" of diskFolder to {490, 225}

        update diskFolder without registering applications
        delay 1
        close diskWindow
    end tell
end run
