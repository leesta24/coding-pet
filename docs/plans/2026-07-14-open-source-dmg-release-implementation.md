# CodingPet Open-Source DMG Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish CodingPet's MIT-licensed Swift source and produce a signed, notarized Apple-silicon DMG containing only the user-owned 胖墩 appearance.

**Architecture:** Keep SwiftPM as the build system, then assemble its two release executables and resource bundle into a conventional macOS `.app`. Centralized runtime path resolution supports both the packaged `Contents/Helpers`/`Contents/Resources` layout and existing SwiftPM development builds; shell release tooling signs nested code before the container, notarizes the DMG, and verifies every artifact.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing, AppKit/SwiftUI, `codesign`, `notarytool`, `hdiutil`, GitHub Actions.

---

### Task 1: Migrate 奶龙 to generic local-pet storage

**Files:**
- Modify: `Sources/CodingPet/Models/PetAppearance.swift`
- Modify: `Sources/CodingPet/Services/PetAppearanceStore.swift`
- Modify: `Sources/CodingPet/UI/PetSpriteAtlas.swift`
- Modify: `Sources/CodingPet/UI/SettingsView.swift`
- Delete: `Sources/CodingPet/Resources/Pets/nailong/pet.json`
- Delete: `Sources/CodingPet/Resources/Pets/nailong/spritesheet.webp`
- Modify: `Tests/CodingPetTests/PetAppearanceStoreTests.swift`
- Modify: `Tests/CodingPetTests/PetSpriteAtlasTests.swift`
- Modify: `Tests/CodingPetTests/PetAppearanceRenderingTests.swift`

**Step 1: Write failing local-discovery and migration tests**

Create a temporary Application Support pet directory containing a valid v2
manifest and atlas. Expect `PetAppearanceStore` to expose that manifest as a
selectable dynamic appearance while still exposing bundled `xiaobao`. When a
stored local ID is unavailable, expect the store to fall back to `xiaobao`.

**Step 2: Run the targeted tests**

Run: `swift test --filter PetAppearance`

Expected: FAIL because appearances are currently a fixed enum.

**Step 3: Implement generic local-pet discovery**

Replace the fixed appearance enum with an ID-backed value. Discover and
validate local manifests below
`~/Library/Application Support/CodingPet/Pets`, merge them after the bundled
`xiaobao` appearance, and render them with the existing v2 atlas path. The
gallery shows only successfully loaded packages.

**Step 4: Migrate and verify this Mac's private package**

Copy the current `nailong` package to the Application Support directory,
compare file hashes, then remove it from `Sources`. Do not add the private
directory or its contents to Git.

**Step 5: Run the targeted tests again**

Run: `swift test --filter PetAppearance && swift test --filter PetSpriteAtlas`

Expected: PASS and the resource tree contains no `nailong` path.

### Task 2: Add bundle-aware runtime path resolution

**Files:**
- Create: `Sources/CodingPet/Services/AppBundlePaths.swift`
- Modify: `Sources/CodingPet/CodingPetMain.swift`
- Modify: `Sources/CodingPet/UI/BotWindowController.swift`
- Modify: `Sources/CodingPet/UI/SettingsWindowController.swift`
- Modify: `Sources/CodingPet/UI/PetSpriteAtlas.swift`
- Create: `Tests/CodingPetTests/AppBundlePathsTests.swift`
- Modify: `Tests/CodingPetTests/PetSpriteAtlasTests.swift`

**Step 1: Write failing pure path tests**

Assert that an executable at
`/Applications/CodingPet.app/Contents/MacOS/CodingPet` resolves the hook to
`/Applications/CodingPet.app/Contents/Helpers/CodingPetHook`, while
`/tmp/debug/CodingPet` resolves `/tmp/debug/CodingPetHook`.

**Step 2: Run the path tests**

Run: `swift test --filter AppBundlePathsTests`

Expected: FAIL because the resolver does not exist.

**Step 3: Implement and adopt the resolver**

Centralize hook resolution and remove the three duplicated sibling-path
expressions. Add a packaged-resource lookup that loads
`CodingPet_CodingPet.bundle` through `Bundle.main.resourceURL`, falling back to
`Bundle.module` for SwiftPM execution.

**Step 4: Verify paths and resources**

Run: `swift test --filter AppBundlePathsTests && swift test --filter PetSpriteAtlasTests`

Expected: PASS.

### Task 3: Add explicit code and artwork licensing

**Files:**
- Create: `LICENSE`
- Create: `ASSET_LICENSE.md`
- Modify: `README.md`

**Step 1: Add the MIT license**

Use copyright `2026 Juyi Wu` for the source code.

**Step 2: Add the asset exception**

State that `Sources/CodingPet/Resources/Pets/xiaobao/**` is not licensed under
MIT and is copyright Juyi Wu, all rights reserved, with permission for official
CodingPet release artifacts only.

**Step 3: Link both documents from the README**

Clearly distinguish open-source code from bundled character artwork and add a
non-affiliation notice for OpenAI and Anthropic.

**Step 4: Verify repository licensing references**

Run: `rg -n "MIT|ASSET_LICENSE|OpenAI|Anthropic|nailong|奶龙" README.md LICENSE ASSET_LICENSE.md Sources Tests HANDOFF.md docs`

Expected: licensing and notices are present; no production/documentation claim
still advertises 奶龙.

### Task 4: Assemble a conventional unsigned app bundle

**Files:**
- Create: `Packaging/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `Tests/Packaging/build-app-tests.sh`
- Modify: `.gitignore`

**Step 1: Write the bundle-layout smoke test**

The test invokes `scripts/build-app.sh` into a temporary output directory and
asserts the Info.plist, main executable, helper, and nested resource bundle all
exist. It also asserts the bundle contains no 奶龙 asset.

**Step 2: Run the smoke test**

Run: `bash Tests/Packaging/build-app-tests.sh`

Expected: FAIL because the packaging script does not exist.

**Step 3: Add Info.plist and assembly script**

Use bundle identifier `com.juyiwu.codingpet`, deployment target 14.0,
`LSUIElement=true`, and architecture `arm64`. Build both SwiftPM products in
release mode, copy the products into the standard layout, copy the SwiftPM
resource bundle under `Contents/Resources`, normalize permissions, and write a
version supplied by `CODINGPET_VERSION` (default `0.1.0`).

**Step 4: Run the smoke test**

Run: `bash Tests/Packaging/build-app-tests.sh`

Expected: PASS and print the absolute `.app` path.

### Task 5: Add Developer ID signing, DMG, and notarization tooling

**Files:**
- Create: `scripts/release-dmg.sh`
- Create: `Packaging/README.md`

**Step 1: Add strict preflight and dry-run modes**

Require `DEVELOPER_ID_APPLICATION` for signing. Accept either
`NOTARYTOOL_PROFILE` or the App Store Connect key variables. A
`--skip-notarization` option may create a locally signed test DMG but must label
the result as not notarized.

**Step 2: Implement nested signing and verification**

Sign `Contents/Helpers/CodingPetHook`, then the `.app`, both with hardened
runtime and timestamps. Verify using `codesign --verify --deep --strict` and
`spctl --assess --type execute`.

**Step 3: Create and notarize the DMG**

Stage the app beside an `Applications` symlink, create a compressed DMG, submit
with `notarytool --wait`, staple, then run `stapler validate` and Gatekeeper
assessment against the DMG.

**Step 4: Document credential setup without secrets**

Document `xcrun notarytool store-credentials` and environment-variable inputs.
Never print or persist certificate or API-key secrets.

### Task 6: Add GitHub CI and tagged release automation

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`

**Step 1: Add CI**

On pushes and pull requests, run `swift test` and the unsigned bundle-layout
smoke test on an Apple-silicon macOS runner.

**Step 2: Add the tag workflow**

For `v*` tags, import the Developer ID certificate into an ephemeral keychain,
materialize the App Store Connect key, run the release script, attach the DMG
and checksum to a GitHub Release, and delete the keychain/key in an `always()`
cleanup step.

**Step 3: Validate workflow syntax and secret names**

Run a local YAML parse if available, then review every `${{ secrets.* }}` name
against `Packaging/README.md`.

Expected: no credential value is present in the repository.

### Task 7: Final verification and documentation

**Files:**
- Modify: `README.md`
- Modify: `HANDOFF.md`

**Step 1: Run the complete test suite**

Run: `swift test`

Expected: all suites pass.

**Step 2: Build and inspect the unsigned application**

Run: `scripts/build-app.sh`

Expected: `dist/CodingPet.app` exists with only 胖墩 assets and its helper is
executable.

**Step 3: Launch the bundle and exercise hook status**

Run: `open dist/CodingPet.app`

Expected: the pet appears, Settings opens, and Integrations finds the helper at
`Contents/Helpers/CodingPetHook` without changing configuration until the user
presses Install.

**Step 4: Produce a signed local candidate**

Run: `DEVELOPER_ID_APPLICATION="Developer ID Application: juyi wu (8B749N476M)" scripts/release-dmg.sh --skip-notarization`

Expected: strict signature and local Gatekeeper checks pass. Full notarization
is run only after a notary profile or App Store Connect API key is configured.

**Step 5: Update release instructions and handoff**

Document installation, Gatekeeper verification, hook behavior, privacy,
release prerequisites, and the remaining notarization credential step.
