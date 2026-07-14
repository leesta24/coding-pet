# Local Event Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Connect supported Codex CLI and Claude Code lifecycle hooks to CodingPet through a private, best-effort Unix-domain socket without forwarding conversation content.

**Architecture:** Add a small shared `CodingPetBridge` target containing the safe event envelope, payload sanitizer, codec, socket address, and client. Add a `CodingPetHook` executable that reads one bounded JSON payload from stdin, sanitizes it, sends it with a short timeout, and always exits silently. The app listens on the same per-user socket and routes events through provider-specific adapters into `SessionStore`.

**Tech Stack:** Swift 6.2, SwiftPM, Foundation, Darwin POSIX sockets, Dispatch, Swift Testing.

---

### Task 1: Define the safe bridge protocol

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CodingPetBridge/HookEventEnvelope.swift`
- Create: `Sources/CodingPetBridge/HookEventSanitizer.swift`
- Create: `Tests/CodingPetTests/HookEventSanitizerTests.swift`
- Create: `Tests/CodingPetTests/Fixtures/Codex/user-prompt-submit.json`
- Create: `Tests/CodingPetTests/Fixtures/Claude/permission-request.json`

**Step 1: Write failing fixture-driven tests**

Verify that provider, event name, session id, cwd, safe event subtype, timestamp, and parent PID survive sanitization. Encode the resulting envelope and assert that prompt text, assistant messages, transcript paths, tool input, and tool output are absent.

**Step 2: Run the focused tests**

Run: `swift test --filter HookEventSanitizerTests`

Expected: FAIL because the bridge target and sanitizer do not exist.

**Step 3: Implement the envelope and sanitizer**

The wire shape is:

```swift
public struct HookEventEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let provider: HookProvider
    public let eventName: String
    public let eventSubtype: String?
    public let timestamp: Date
    public let parentProcessID: Int32?
    public let sessionID: String
    public let cwd: String
}
```

Decode source payloads through a private minimal struct containing only `hook_event_name`, `session_id`, `cwd`, `source`, and `notification_type`. Reject missing/blank routing fields and never retain the original JSON object.

**Step 4: Run the focused tests**

Run: `swift test --filter HookEventSanitizerTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Package.swift Sources/CodingPetBridge Tests/CodingPetTests
git commit -m "feat: define safe hook event protocol"
```

### Task 2: Add the non-blocking hook helper

**Files:**
- Create: `Sources/CodingPetBridge/HookSocketAddress.swift`
- Create: `Sources/CodingPetBridge/HookSocketClient.swift`
- Create: `Sources/CodingPetHook/CodingPetHookMain.swift`
- Create: `Tests/CodingPetTests/HookSocketClientTests.swift`

**Step 1: Write failing socket-client tests**

Cover successful delivery to a temporary Unix socket and fast success when no listener exists. Measure the unavailable-listener path with a generous test ceiling while keeping the production timeout at 100 ms or less.

**Step 2: Run the focused tests**

Run: `swift test --filter HookSocketClientTests`

Expected: FAIL because the socket client does not exist.

**Step 3: Implement the client and executable**

Use a non-blocking `AF_UNIX` stream socket, `poll` for a bounded connect, `SO_NOSIGPIPE`, and a newline-terminated JSON payload. `CodingPetHook` reads at most 64 KiB from stdin, accepts `--provider codex|claude-code`, sanitizes the event, attempts delivery, produces no stdout/stderr, and returns status 0 for every outcome.

**Step 4: Run tests and manual failure-path timing**

Run:

```bash
swift test --filter HookSocketClientTests
time printf '{"hook_event_name":"Stop","session_id":"demo","cwd":"/tmp"}' | swift run CodingPetHook --provider codex
```

Expected: tests pass; helper exits successfully and quickly with no output when CodingPet is closed.

**Step 5: Commit**

```bash
git add Package.swift Sources/CodingPetBridge Sources/CodingPetHook Tests/CodingPetTests
git commit -m "feat: add best-effort hook helper"
```

### Task 3: Normalize provider events into sessions

**Files:**
- Create: `Sources/CodingPet/Services/AgentSessionEventAdapter.swift`
- Create: `Sources/CodingPet/Services/CodexEventAdapter.swift`
- Create: `Sources/CodingPet/Services/ClaudeCodeEventAdapter.swift`
- Create: `Sources/CodingPet/Services/SessionEventRouter.swift`
- Modify: `Sources/CodingPet/Services/SessionStore.swift`
- Create: `Tests/CodingPetTests/ProviderEventAdapterTests.swift`
- Add fixtures under: `Tests/CodingPetTests/Fixtures/Codex/`
- Add fixtures under: `Tests/CodingPetTests/Fixtures/Claude/`

**Step 1: Write failing provider mapping tests**

For each provider, cover `SessionStart -> running`, `UserPromptSubmit -> running`, `PermissionRequest -> needsInput`, and `Stop -> ready`. Cover Claude `Notification` subtypes `permission_prompt` and `idle_prompt` as `needsInput`, plus `StopFailure -> blocked`. Verify unknown events are ignored.

**Step 2: Run the focused tests**

Run: `swift test --filter ProviderEventAdapterTests`

Expected: FAIL because adapters do not exist.

**Step 3: Implement adapters and router**

Keep event switches provider-specific even where mappings currently match. Generate summaries from local constants only. Derive `projectName` from the last cwd component, update `updatedAt` from the envelope, and store the captured parent PID as a best-effort terminal target.

**Step 4: Connect the router to SessionStore**

Add `apply(_ event: HookEventEnvelope)` and preserve the existing session when an adapter ignores an event.

**Step 5: Run tests**

Run: `swift test --filter ProviderEventAdapterTests`

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodingPet Tests/CodingPetTests
git commit -m "feat: normalize provider hook events"
```

### Task 4: Add the app-side socket listener

**Files:**
- Create: `Sources/CodingPet/Services/HookEventListener.swift`
- Modify: `Sources/CodingPet/CodingPetMain.swift`
- Create: `Tests/CodingPetTests/HookEventListenerTests.swift`

**Step 1: Write a failing end-to-end listener test**

Start the listener at a unique temporary path, send one encoded envelope through `HookSocketClient`, and wait for the callback. Also verify malformed and oversized messages do not call the handler.

**Step 2: Run the focused tests**

Run: `swift test --filter HookEventListenerTests`

Expected: FAIL because the listener does not exist.

**Step 3: Implement the listener**

Bind an `AF_UNIX` socket with mode `0600`, remove only the socket path owned by this listener, accept on a private queue, cap each message at 16 KiB, decode exactly one newline-delimited envelope, and dispatch valid events to the main actor. Closing the listener cancels reads, closes descriptors, and removes the socket.

**Step 4: Start it with the app**

Retain the listener in `AppDelegate`; on valid events call `sessionStore.apply(event)`. Listener startup failure must not prevent the UI from launching.

**Step 5: Run tests**

Run: `swift test --filter HookEventListenerTests`

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodingPet Tests/CodingPetTests
git commit -m "feat: receive local hook events"
```

### Task 5: Verify and document the vertical slice

**Files:**
- Modify: `README.md`
- Modify: `HANDOFF.md`

**Step 1: Run formatting/build diagnostics**

Run: `swift build && swift test`

Expected: build succeeds and all tests pass.

**Step 2: Exercise the bridge without editing user configuration**

Launch `swift run CodingPet`, then pipe sanitized sample events into `swift run CodingPetHook --provider codex` and `--provider claude-code`. Confirm the session panel changes through running, needs-input, and ready states.

**Step 3: Update documentation**

Document the new executable, socket path behavior, supported events, privacy contract, and that automatic hook installation remains the next task. Do not claim precise terminal-tab restoration yet.

**Step 4: Run the full suite again**

Run: `swift test`

Expected: PASS.

**Step 5: Commit**

```bash
git add README.md HANDOFF.md
git commit -m "docs: record local event bridge status"
```

### Task 6: Add reversible hook configuration installers

**Files:**
- Create: `Sources/CodingPet/Services/HookConfigurationInstaller.swift`
- Create: `Sources/CodingPet/Services/HookInstallationCoordinator.swift`
- Create: `Tests/CodingPetTests/HookConfigurationInstallerTests.swift`
- Modify: `README.md`
- Modify: `HANDOFF.md`

**Step 1: Write failing configuration preservation tests**

Use temporary directories only. Cover an existing Codex hooks object, an
existing Claude settings object, a missing config file, idempotent reinstall,
invalid JSON, exact uninstall restoration when the installed file is unchanged,
and semantic preservation when a user edits unrelated settings after install.

**Step 2: Run the focused tests**

Run: `swift test --filter HookConfigurationInstallerTests`

Expected: FAIL because the installer does not exist.

**Step 3: Implement structural merging and ownership markers**

Append matcher groups without replacing existing hooks. Mark every owned
command handler with the official `statusMessage` field, remove only handlers
with that exact marker during reinstall/uninstall, and drop a matcher group only
when no handlers remain. Use shell quoting for Codex command strings and Claude
Code's exec-form `command` plus `args`.

**Step 4: Implement backup and uninstall behavior**

On first install, save the original bytes and metadata next to the config with
mode `0600`. Store a digest of the installed result. If uninstall sees the exact
installed digest, restore the original bytes byte-for-byte (or remove a file that
did not originally exist). If unrelated edits occurred later, structurally
remove only CodingPet handlers and retain the user's current values.

**Step 5: Run focused and full tests**

Run: `swift test --filter HookConfigurationInstallerTests && swift test`

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodingPet/Services Tests/CodingPetTests README.md HANDOFF.md
git commit -m "feat: add reversible hook configuration installers"
```
