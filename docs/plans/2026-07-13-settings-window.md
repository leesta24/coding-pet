# CodingPet Settings Window Implementation Plan

> **For Codex:** Implement this plan task-by-task in the current shared workspace. Preserve the existing uncommitted event-bridge and UI work; do not commit without user approval.

**Goal:** Remove the rectangular session-panel shadow artifact and move companion configuration into a dedicated macOS settings window that also manages supported CLI integrations and explains local privacy behavior.

**Architecture:** `BotWindowController` owns one reusable `SettingsWindowController` and passes an open-settings callback into the compact session panel. `SettingsView` uses a native sidebar selection for Appearance, Integrations, and About. Existing `PetAppearanceStore` expands to persist animation preference, while `HookInstallationCoordinator` exposes read-only provider status plus the existing safe install/uninstall operations.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Combine, Swift Testing, UserDefaults.

---

### Task 1: Regression tests for settings state

**Files:**
- Modify: `Tests/CodingPetTests/PetAppearanceStoreTests.swift`
- Modify: `Tests/CodingPetTests/HookConfigurationInstallerTests.swift`

1. Add a test that animation defaults to enabled and persists when disabled.
2. Add installer status tests for not-installed and installed configurations.
3. Run focused tests and confirm they fail against the current APIs.
4. Add the minimal persistence and status APIs.
5. Run focused tests and confirm they pass.

### Task 2: Fix session panel chrome and simplify content

**Files:**
- Modify: `Sources/CodingPet/UI/SessionPanelController.swift`
- Modify: `Sources/CodingPet/UI/SessionPanelView.swift`
- Modify: `Tests/CodingPetTests/SessionPanelControllerTests.swift`

1. Disable the AppKit rectangular window shadow and keep only the rounded SwiftUI shadow.
2. Remove the in-panel appearance selector.
3. Add a settings gear beside the status badge and route it through a callback.
4. Reduce panel height to fit the session-only content.
5. Preserve click-outside dismissal and session navigation.

### Task 3: Dedicated settings window

**Files:**
- Create: `Sources/CodingPet/UI/SettingsWindowController.swift`
- Create: `Sources/CodingPet/UI/SettingsView.swift`
- Modify: `Sources/CodingPet/UI/BotWindowController.swift`

1. Create a normal titled, closable settings window that can become key.
2. Add a sidebar with Appearance, Integrations, and About destinations.
3. Appearance: show large live previews for bundled and validated local pets plus a status-animation toggle.
4. Integrations: show Codex CLI and Claude Code installation status and a single safe install/uninstall action with success/error feedback.
5. About: show version, local-only storage, no telemetry/account behavior, and config paths.
6. Reuse the same `PetAppearanceStore` instance so changes update the floating pet immediately.

### Task 4: Verification

**Files:**
- Modify: `Tests/CodingPetTests/PetAppearanceRenderingTests.swift`
- Modify: `HANDOFF.md`
- Modify: `README.md`

1. Extend visual rendering coverage to include the Appearance settings page.
2. Run `swift test` and require zero failures.
3. Inspect rendered settings and panel previews for clipping, contrast, selected, hover, empty, success, and error states.
4. Restart the detached demo process.
5. Verify the session panel has no rectangular frame, the gear opens settings, appearance changes apply immediately, and clicking outside still dismisses only the session panel.
