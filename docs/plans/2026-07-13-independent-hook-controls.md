# Independent Hook Controls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users install, repair, and uninstall Codex CLI and Claude Code hooks independently from the Integrations settings page.

**Architecture:** Keep the existing reversible per-provider `HookConfigurationInstaller` as the source of truth. Add provider-specific coordinator methods so Claude operations never require Codex trust access, while Codex operations continue to activate and remove exact trusted hashes. Bind each settings row to its own operation and status.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation, Swift Testing.

---

### Task 1: Add provider-specific coordinator operations

**Files:**
- Modify: `Sources/CodingPet/Services/HookInstallationCoordinator.swift`
- Test: `Tests/CodingPetTests/HookConfigurationInstallerTests.swift`

**Step 1: Write failing provider-isolation tests**

Add tests proving that a Claude-only install/uninstall changes only `~/.claude/settings.json` and does not require a valid Codex configuration or Codex app-server. Cover Codex isolation through an injectable trust manager or focused coordinator test.

**Step 2: Run the focused tests**

Run `swift test --filter HookConfigurationInstallerTests` and confirm the new provider-specific API is missing.

**Step 3: Implement the minimal API**

Add `install(_ provider:)` and `uninstall(_ provider:)`. Keep the existing all-provider methods for CLI compatibility. Codex-specific operations must retain exact-hash trust activation and cleanup; Claude-specific operations must not instantiate or contact Codex app-server.

**Step 4: Re-run focused tests**

Run `swift test --filter HookConfigurationInstallerTests` and require a pass.

### Task 2: Expose independent store actions

**Files:**
- Modify: `Sources/CodingPet/Services/IntegrationSettingsStore.swift`

**Step 1: Replace aggregate UI actions**

Change `installOrRepair()` and `uninstall()` into provider-parameterized actions. Refresh all statuses after every operation and generate provider-specific success/error feedback.

**Step 2: Preserve status semantics**

Keep `.notInstalled`, `.installed`, and `.needsRepair` independent for each provider.

### Task 3: Put install/uninstall controls on each row

**Files:**
- Modify: `Sources/CodingPet/UI/SettingsView.swift`
- Test: `Tests/CodingPetTests/PetAppearanceRenderingTests.swift`

**Step 1: Update the provider cards**

Render a trailing action for each provider. Show `Install` for `.notInstalled`, `Repair` for `.needsRepair`, and `Uninstall` for `.installed`. Keep the status pill and Refresh control; remove the aggregate install/uninstall button.

**Step 2: Verify layout**

Render the settings preview and inspect that both rows retain readable names, config paths, status, and actions without clipping.

### Task 4: Update documentation and verify

**Files:**
- Modify: `HANDOFF.md`
- Modify: `README.md`

**Step 1: Document independent controls**

State that Codex and Claude hooks can be installed and removed independently.

**Step 2: Run the full suite**

Run `swift test` and require all tests to pass.

**Step 3: Interactive smoke test**

Run `swift run CodingPet --demo`, open Integrations, and verify each row changes only its own configuration and status.
