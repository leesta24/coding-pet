# CodingPet Open-Source DMG Release Design

Date: 2026-07-14

## Distribution boundary

CodingPet will be distributed directly from GitHub as an Apple-silicon macOS
application for macOS 14 or later. The Swift source is released under the MIT
License. The 胖墩 character artwork remains copyright Juyi Wu and is licensed
only for use in official CodingPet distributions unless a separate asset
license is granted later. 奶龙 is not owned by the project and must be removed
from source control, tests, documentation, resource bundles, and release
artifacts before the first public release.

This keeps the code genuinely reusable without accidentally granting third
parties rights to redistribute a character asset that is outside the MIT code
license. The repository must identify the asset exception next to the MIT
license and in the README.

The app also discovers Codex-compatible v2 pet packages from
`~/Library/Application Support/CodingPet/Pets/<pet-id>/`. These local packages
are never copied into builds or release artifacts. Before the bundled 奶龙
files are removed from the working tree, the developer copy is migrated to this
directory and byte-verified so it remains selectable on this Mac. Public code
implements only generic local-pet discovery and contains no built-in 奶龙
catalog entry.

## Application bundle

The release bundle uses the standard direct-distribution layout:

```text
CodingPet.app/
  Contents/
    Info.plist
    MacOS/CodingPet
    Helpers/CodingPetHook
    Resources/CodingPet_CodingPet.bundle
```

The app resolves `CodingPetHook` from `Contents/Helpers` when running from an
application bundle and keeps the existing sibling-executable fallback for
SwiftPM development builds. The pet resource loader resolves the nested bundle
from `Contents/Resources` in a packaged app and falls back to `Bundle.module`
for `swift run` and tests.

The app remains an accessory application (`LSUIElement`) so it does not add a
Dock icon. It is signed with the hardened runtime but is not App Sandbox
enabled: CodingPet needs narrowly scoped access to the user's Codex and Claude
hook configuration and local app-server state, which is incompatible with the
current direct filesystem integration.

## Release pipeline

A deterministic build script produces an unsigned `.app` locally so bundle
layout and tests can be verified without credentials. A release script signs
the helper first, signs the containing app with the available Developer ID
Application certificate, verifies the signature, creates a DMG with an
Applications shortcut, submits it with `notarytool`, staples the ticket, and
runs Gatekeeper verification.

GitHub Actions runs tests for every change. A tag workflow may build and attach
a signed, notarized DMG once the repository has signing and App Store Connect
secrets configured. Signing secrets are never committed. Local release uses a
notarytool keychain profile or App Store Connect API-key environment variables.

## Failure behavior and verification

Packaging must fail before modifying a release directory when a required
binary, resource bundle, signing identity, or notarization credential is
missing. It must never modify user hook configuration. Verification includes
`swift test`, a release SwiftPM build, bundle-layout assertions, helper path and
resource-loading tests, strict code-signature validation, Gatekeeper
assessment, notarization ticket validation, and a manual launch from the built
application bundle.
