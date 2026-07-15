# CodingPet release packaging

CodingPet is distributed directly as a signed and notarized Apple-silicon DMG.
The release is not App Sandbox enabled because the lifecycle-hook installer
must merge local Codex and Claude Code configuration under the user's home
directory.

## Build an application bundle

```sh
scripts/build-app.sh
open dist/CodingPet.app
```

The default version is `0.1.0` with build number `1`. Override them with
`CODINGPET_VERSION` and `CODINGPET_BUILD_NUMBER`.

## Create a local signed candidate

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
  scripts/release-dmg.sh --skip-notarization
```

The resulting filename contains `UNNOTARIZED`. It is for local verification
only and should not be attached to a public release.

## Store notarization credentials locally

Create a keychain profile without putting credentials in the repository:

```sh
xcrun notarytool store-credentials "codingpet-notary" \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Then produce the public artifact:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="codingpet-notary" \
CODINGPET_VERSION="0.1.0" \
CODINGPET_BUILD_NUMBER="1" \
  scripts/release-dmg.sh
```

The release script builds a branded Finder disk image with a fixed 660×420
window, hidden toolbar and status bar, a generated CodingPet background, and
positioned CodingPet/Applications icons. The mounted volume includes the app
version in its name so Finder cannot confuse a new installer with an older
CodingPet image that is still mounted. Layout is applied under a unique
temporary volume name before the image is renamed to its public versioned
name. The background is generated locally
from `scripts/render-dmg-background.swift`; no third-party DMG tooling is
required.

The script also accepts App Store Connect API-key inputs through
`ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`. It signs the hook before the
containing app, signs the DMG, waits for notarization, staples the ticket, runs
strict signature and Gatekeeper checks, and writes a SHA-256 checksum.

## GitHub Actions secrets

The tagged release workflow expects:

- `DEVELOPER_ID_APPLICATION`: full identity name;
- `DEVELOPER_ID_CERTIFICATE_BASE64`: Developer ID certificate and private key
  exported as a password-protected `.p12`, then base64 encoded;
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: `.p12` password;
- `ASC_KEY_BASE64`: App Store Connect `.p8` file, base64 encoded;
- `ASC_KEY_ID`: App Store Connect key ID;
- `ASC_ISSUER_ID`: App Store Connect issuer ID.

Secrets are imported into a temporary keychain and deleted after every release
job. Never commit `.p12`, `.p8`, passwords, or keychain files.
