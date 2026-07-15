#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/codingpet-build-test.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

test -f "$repo_root/scripts/render-dmg-background.swift"
test -f "$repo_root/scripts/layout-dmg.applescript"
grep -q 'format UDRW' "$repo_root/scripts/release-dmg.sh"
grep -q 'hdiutil convert' "$repo_root/scripts/release-dmg.sh"
grep -q 'volume_name="CodingPet \$version"' "$repo_root/scripts/release-dmg.sh"
grep -q 'layout_volume_name=' "$repo_root/scripts/release-dmg.sh"
grep -q 'diskutil renameVolume' "$repo_root/scripts/release-dmg.sh"
grep -q 'background picture' "$repo_root/scripts/layout-dmg.applescript"

CODINGPET_DIST_DIR="$temporary_directory" \
CODINGPET_VERSION="0.1.0" \
CODINGPET_BUILD_NUMBER="1" \
    "$repo_root/scripts/build-app.sh"

app="$temporary_directory/CodingPet.app"
main_executable="$app/Contents/MacOS/CodingPet"
hook_executable="$app/Contents/Helpers/CodingPetHook"
resource_bundle="$app/Contents/Resources/CodingPet_CodingPet.bundle"
app_icon="$app/Contents/Resources/AppIcon.icns"

test -f "$app/Contents/Info.plist"
test -x "$main_executable"
test -x "$hook_executable"
test -d "$resource_bundle"
test -f "$app_icon"
test -f "$resource_bundle/Pets/xiaobao/pet.json"
test -f "$resource_bundle/Pets/xiaobao/spritesheet.webp"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = \
    "com.juyiwu.codingpet"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist")" = \
    "AppIcon"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = \
    "0.1.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = \
    "1"

if find "$app" -iname '*nailong*' -o -iname '*奶龙*' | grep -q .; then
    echo "Unexpected private pet asset in application bundle" >&2
    exit 1
fi

file "$main_executable" | grep -q 'arm64'
file "$hook_executable" | grep -q 'arm64'

echo "CodingPet app bundle smoke test passed: $app"
