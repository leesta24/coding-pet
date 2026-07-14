#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_directory="${CODINGPET_DIST_DIR:-$repo_root/dist}"
version="${CODINGPET_VERSION:-0.1.0}"
build_number="${CODINGPET_BUILD_NUMBER:-1}"
identity="${DEVELOPER_ID_APPLICATION:-}"
skip_notarization=false

usage() {
    cat <<'EOF'
Usage: scripts/release-dmg.sh [--skip-notarization]

Required:
  DEVELOPER_ID_APPLICATION  Full Developer ID Application identity name

Notarization (choose one):
  NOTARYTOOL_PROFILE
or:
  ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
EOF
}

while (($#)); do
    case "$1" in
        --skip-notarization)
            skip_notarization=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -z "$identity" ]]; then
    echo "DEVELOPER_ID_APPLICATION is required" >&2
    exit 2
fi
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$identity\""; then
    echo "Developer ID identity is not available in the current keychain" >&2
    exit 2
fi

notary_mode=""
if [[ "$skip_notarization" == false ]]; then
    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
        notary_mode="profile"
    elif [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
        test -f "$ASC_KEY_PATH" || { echo "ASC_KEY_PATH does not exist" >&2; exit 2; }
        notary_mode="api-key"
    else
        echo "Notarization credentials are required; use --skip-notarization only for local testing" >&2
        exit 2
    fi
fi

CODINGPET_DIST_DIR="$dist_directory" \
CODINGPET_VERSION="$version" \
CODINGPET_BUILD_NUMBER="$build_number" \
    "$repo_root/scripts/build-app.sh"

app="$dist_directory/CodingPet.app"
hook="$app/Contents/Helpers/CodingPetHook"

/usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$hook"
/usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/codingpet-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
/usr/bin/ditto "$app" "$staging_directory/CodingPet.app"
/bin/ln -s /Applications "$staging_directory/Applications"

if [[ "$skip_notarization" == true ]]; then
    dmg="$dist_directory/CodingPet-$version-arm64-UNNOTARIZED.dmg"
else
    dmg="$dist_directory/CodingPet-$version-arm64.dmg"
fi
rm -f "$dmg" "$dmg.sha256"

/usr/bin/hdiutil create \
    -volname "CodingPet" \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$dmg" >/dev/null
/usr/bin/codesign --force --timestamp --sign "$identity" "$dmg"
/usr/bin/codesign --verify --verbose=2 "$dmg"

if [[ "$skip_notarization" == false ]]; then
    if [[ "$notary_mode" == "profile" ]]; then
        /usr/bin/xcrun notarytool submit "$dmg" \
            --keychain-profile "$NOTARYTOOL_PROFILE" \
            --wait
    else
        /usr/bin/xcrun notarytool submit "$dmg" \
            --key "$ASC_KEY_PATH" \
            --key-id "$ASC_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait
    fi
    /usr/bin/xcrun stapler staple "$dmg"
    /usr/bin/xcrun stapler validate "$dmg"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
    /usr/sbin/spctl --assess --type open \
        --context context:primary-signature \
        --verbose=2 \
        "$dmg"
else
    echo "Warning: local candidate is signed but not notarized; Gatekeeper acceptance is not expected." >&2
fi

(cd "$dist_directory" && /usr/bin/shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")

echo "$dmg"
echo "$dmg.sha256"
