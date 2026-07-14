#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_directory="${CODINGPET_DIST_DIR:-$repo_root/dist}"
version="${CODINGPET_VERSION:-0.1.0}"
build_number="${CODINGPET_BUILD_NUMBER:-1}"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z]+)*$ ]]; then
    echo "Invalid CODINGPET_VERSION: $version" >&2
    exit 2
fi
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "CODINGPET_BUILD_NUMBER must be an integer" >&2
    exit 2
fi

cd "$repo_root"
swift build -c release --arch arm64 --product CodingPet
swift build -c release --arch arm64 --product CodingPetHook
bin_directory="$(swift build -c release --arch arm64 --show-bin-path)"

main_executable="$bin_directory/CodingPet"
hook_executable="$bin_directory/CodingPetHook"
resource_bundle="$bin_directory/CodingPet_CodingPet.bundle"

test -x "$main_executable" || { echo "Missing CodingPet release executable" >&2; exit 1; }
test -x "$hook_executable" || { echo "Missing CodingPetHook release executable" >&2; exit 1; }
test -d "$resource_bundle" || { echo "Missing CodingPet resource bundle" >&2; exit 1; }
/usr/bin/lipo "$main_executable" -verify_arch arm64
/usr/bin/lipo "$hook_executable" -verify_arch arm64

if find "$resource_bundle" -iname '*nailong*' -o -iname '*奶龙*' | grep -q .; then
    echo "Private pet asset found in SwiftPM release resources" >&2
    exit 1
fi

mkdir -p "$dist_directory"
staging_directory="$(mktemp -d "$dist_directory/.codingpet-app.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

app="$staging_directory/CodingPet.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Helpers" "$contents/Resources/Licenses"

install -m 755 "$main_executable" "$contents/MacOS/CodingPet"
install -m 755 "$hook_executable" "$contents/Helpers/CodingPetHook"
/usr/bin/ditto "$resource_bundle" "$contents/Resources/CodingPet_CodingPet.bundle"
install -m 644 "$repo_root/Packaging/Info.plist" "$contents/Info.plist"
install -m 644 "$repo_root/LICENSE" "$contents/Resources/Licenses/LICENSE"
install -m 644 "$repo_root/ASSET_LICENSE.md" "$contents/Resources/Licenses/ASSET_LICENSE.md"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents/Info.plist"
/usr/bin/plutil -lint "$contents/Info.plist" >/dev/null

final_app="$dist_directory/CodingPet.app"
rm -rf "$final_app"
mv "$app" "$final_app"

echo "$final_app"
