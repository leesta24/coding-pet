# CodingPet handoff

Updated: 2026-07-14

Repository: the current Git working tree

## One-sentence definition

CodingPet is a native macOS desktop pet that watches Codex and Claude Code sessions, visibly asks for attention when a session is waiting, and returns the user to the exact Codex App task or originating terminal to respond.

## Intended user experience

The bot floats above normal windows and can be dragged around the desktop. Its appearance reflects the highest-priority state across all known sessions. Clicking it opens a compact session panel. Clicking a Codex session opens the matching Codex App task; other providers activate their originating terminal when known. CodingPet does not render an approval form or send a reply itself.

The five normalized states are:

1. `needsInput`: a session is waiting for approval, an answer, or another user decision.
2. `blocked`: a session failed or encountered a system error.
3. `ready`: a session completed and has unread activity.
4. `running`: at least one session is actively working.
5. `idle`: there are no active sessions.

The live panel projection is intentionally narrower: `running`, explicit
`needsInput`, and Codex App tasks with a real local unread marker are visible.
Ordinary completed, read, merely started, ended, or failed turns are inactive
and removed from the local session cache.

## Decisions already made

- Product name: `CodingPet`; repository folder: `coding-pet`.
- Platform: macOS 14+ and Apple silicon only.
- Providers in MVP: Codex CLI and Claude Code CLI.
- UI stack: SwiftUI hosted in AppKit `NSPanel` windows.
- Interaction boundary: notify and navigate only; approvals and replies stay in the CLI.
- Integration direction: lifecycle hooks send best-effort events to a local Unix socket.
- Privacy: local-only, with no account, telemetry, prompt upload, or code upload.
- Artwork: original transparent sprite sheets; Codex Pet is a behavioral reference only.

## What exists now

- SwiftPM executable product and test target named `CodingPet`.
- Transparent, always-on-top bot window.
- A tightly fitted, clickable session-bubble overlay follows the bot without
  taking keyboard focus. Full bubbles navigate directly to their session;
  compact count bubbles open the session list. Every full bubble can be closed
  independently through a hover-only control without ending or removing its
  session. A dismissed Running bubble ignores later Running activity and
  reappears only when that session escalates to Input or unread Ready. More than two eligible sessions use
  a two-row vertical scroll viewport without a persistent scrollbar instead of
  being truncated. Running, Pending input, and Ready conversation bubbles can
  be enabled independently;
  disabled Pending or Ready bubbles collapse into a compact attention count,
  while disabled Running bubbles disappear completely.
- Refined 64pt conversation bubbles use a restrained solid surface, subtle
  border/shadow, semantic state rail, green Ready indicator, red Input marker,
  and blue animated Running arc. Codex tool events enrich the two-line activity
  summary from the current
  turn's latest structured app-server `agentMessage`; the text is capped and
  kept in memory only. Input bubbles retain a distinct red dot indicator.
- Click-to-open, session-first panel with only a settings control in its chrome.
  Its native single-surface list adapts to one through four rows, eliminating
  empty space for short lists while retaining four visible rows before scrolling.
  Opening this panel temporarily hides the conversation-bubble overlay so the
  two floating surfaces never cover or visually compete with each other.
- A hook-gated, text-only Codex usage summary reads the local app-server's
  primary and secondary rate-limit windows when the session panel opens. It renders two
  restrained remaining percentages only while the Codex hook is
  installed; missing, damaged, or unavailable integrations leave no placeholder.
- Bot drag/click gating based on screen-space pointer movement: releasing after
  repositioning the bot does not toggle the session panel, while clicks and
  small pointer jitter still do.
- One user-owned bundled companion appearance, 胖墩, plus generic discovery
  of private Codex-compatible v2 packages below
  `~/Library/Application Support/CodingPet/Pets`. Private packages stay outside
  the repository and release artifacts; selection remains locally persisted.
- Appearance also persists an adjustable 64–160pt floating bot size. Resizing
  updates the AppKit panel around its current center and re-anchors the session
  bubble overlay immediately.
- A manifest-validating v2 atlas renderer with exact frame durations and state
  mapping for idle, running, waiting for input, review/ready, and failed. Idle
  animation holds its neutral frame for seven seconds before a brief gesture.
- Click-outside dismissal for the non-activating session panel.
- Dedicated Appearance, Session Bubbles, Integrations, and About & Privacy
  settings pages. The
  Appearance page presents every bundled pet as a large image in a two-column
  library, with the current selection called out by a state-colored outline.
- In-app Codex CLI and Claude Code hook status plus independent, safe
  install/repair/uninstall actions for each provider.
- `AgentSession`, `SessionStore`, and normalized provider/status models.
- Bot state reducer with the priority listed above.
- Session navigation that opens Codex sessions through the validated
  `codex://threads/<thread-id>` deep link, then falls back to process,
  bundle-ID, and working-directory navigation.
- `--demo` mode with Codex and Claude Code sample sessions.
- Unit tests for state reduction.
- Shared `CodingPetBridge` target with a versioned, metadata-only event envelope.
- `CodingPetHook` executable with bounded stdin reads and short, non-blocking Unix-socket delivery.
- Metadata-only per-session event snapshots written by `CodingPetHook`, allowing
  the app to recover known running/attention states after a restart without
  reading provider transcripts or logs.
- Startup and 15-second Codex reconciliation through the local app-server's
  non-archived `thread/list` catalog. Archived/deleted Codex tasks and terminal
  `SessionEnd` snapshots are removed locally; an unavailable or malformed
  catalog preserves existing sessions instead of deleting them.
- Three-second Codex terminal-turn reconciliation through structured
  `thread/read` lifecycle metadata. A completed, interrupted, or failed turn
  clears stale running state when Codex App cancellation did not emit a Stop
  hook; message and tool content are not inspected or retained.
- Read-only three-second Ready reconciliation through Codex App's versioned
  local unread-thread index in `~/.codex/.codex-global-state.json`. Unread IDs
  are enriched with narrow app-server metadata; malformed or unavailable state
  fails closed, and ordinary idle tasks remain hidden.
- Per-user in-app Unix-domain-socket listener with `0600` permissions and bounded messages.
- Provider-specific Codex and Claude Code adapters wired into `SessionStore`.
- Fixture-driven privacy, event-normalization, socket-client, and listener tests.
- Reversible, idempotent Codex and Claude Code JSON hook installers with `0600` backups.
- One-click Codex activation through local `hooks/list` exact hashes and `config/batchWrite`.
- Targeted AgentPeek hook/trust cleanup, including sanitized CodingPet backups.
- Development CLI management through `CodingPet --install-hooks` and `--uninstall-hooks`.
- A conventional Apple-silicon `CodingPet.app` build packages the non-blocking
  helper under `Contents/Helpers` and the SwiftPM pet bundle under
  `Contents/Resources`. Developer ID signing, DMG creation, notarization,
  stapling, checksums, and tag-triggered GitHub Release automation are scripted;
  the local signed candidate has passed strict code-signature validation.
- MIT-licensed source code with a separate all-rights-reserved notice for the
  bundled 胖墩 artwork. Private local pet packages stay outside release artifacts.
- 114 tests across 23 suites covering the bridge, snapshot recovery and Codex
  archive reconciliation, sprite
  atlas resources and state mapping, Codex
  session-name resolution and deep-link navigation, active-session projection,
  floating-window focus/placement policy, installers, cleanup, and trust writes.
- Bot and session panels explicitly cannot become key/main windows, preserving terminal and editor keyboard focus.
- Bot startup placement follows the display containing the mouse pointer, with main-screen fallback.
- The visible list/count/bot state includes `running`, explicit `needsInput`,
  and exact unread `ready` sessions. `SessionStart`, `Stop`, `SessionEnd`, and
  `StopFailure` remove hook-owned active state; an unread Codex App task can
  then reappear as Ready. Older inactive events cannot delete newer state.
- Codex rows resolve `thread.name` asynchronously through the local app-server
  by `session_id`, with project-name fallback. Running Codex bubbles also read
  the current turn's last structured `agentMessage` after tool events; no
  message content enters the hook bridge or snapshot store.
- Real Codex CLI `0.144.2` hook installation is verified against the user's
  configuration: seven events are merged, and all six events exposed by
  Codex's trust surface are active. Completed `Stop` events now clear the local
  snapshot rather than restoring a false attention state.

胖墩 and validated private packages use the same production sprite-sheet
animation path.

## What is not implemented

- General time-based expiry for stale Claude Code sessions, or Codex sessions
  that cannot be checked against the app-server and never emit `SessionEnd`.
- Parent-process, TTY, terminal-window, and tab resolution.
- Precise return to an existing Terminal/iTerm/Ghostty tab.
- An in-app import/remove UI for private pet packages; filesystem discovery is
  implemented, but users currently manage the Application Support folder.
- Agent-authored running messages for Claude Code; no transcript parsing
  fallback is used.
- Launch-at-login and automatic updates. Signing/notarization tooling exists,
  but the first public notarized artifact still requires release credentials.

## Current milestone: finish the local event bridge

The metadata-only helper-to-app vertical slice is implemented. Finish it before
expanding the UI:

1. Exercise lifecycle delivery against a real Claude Code `2.1.205` session.
   Codex CLI `0.144.2` delivery is verified; seven local event handlers are
   installed and the six returned by `hooks/list` report `trusted`.
2. Validate the packaged settings UI installer against real provider
   configurations using `Contents/Helpers/CodingPetHook`.
3. Resolve process ancestry and terminal metadata locally so navigation can reach the originating app more reliably.
4. Add session expiry after real lifecycle delivery is stable.

The adapters normalize `UserPromptSubmit`, `PreToolUse`, and `PostToolUse` as
running, and `PermissionRequest` plus supported Claude Code input notifications
as explicit input waits. `SessionStart`, `Stop`, `SessionEnd`, and `StopFailure`
clear the active session. Payload shapes were checked against the
installed versions and current official documentation:

- Codex: <https://learn.chatgpt.com/codex/hooks>
- Claude Code: <https://code.claude.com/docs/en/hooks>

## Acceptance criteria for that milestone

- Starting either supported CLI without work remains hidden.
- Submitting a prompt creates or changes that session to `running`.
- A permission or input request changes it to `needsInput` and raises the bot badge.
- A completed turn removes hook-owned running state and its snapshot; it only
  reappears as Ready when Codex App's local unread index contains the task.
- With CodingPet closed, both CLIs behave normally and the helper exits quickly.
- Existing user hook configuration survives install and uninstall byte-for-byte apart from CodingPet's own entries.
- No prompt body, assistant response, code, diff, or tool output is sent over the event bridge.
- `swift test` passes.

The full project is covered by 114 tests across 23 suites, including appearance
and session-bubble preference persistence, visual rendering, session
navigation, archived Codex task reconciliation, and floating-panel interaction
regressions.
Installer tests verify exact byte restoration, idempotence, missing files,
invalid JSON, preflight across both providers, symlink preservation, and
preservation of unrelated edits. The development installer has been run against
the user's real Codex and Claude configurations, and Codex trust activation was
verified through its local app-server.

## Explicit non-goals for MVP

- Inline approval, denial, or text replies.
- Billing, cost accounting, and detailed historical usage dashboards.
- Local development server management or arbitrary shell actions.
- Controlling Codex or Claude desktop apps beyond opening an exact supported session.
- Windows, Linux, Intel Macs, tmux, or remote sessions.
- Providers other than Codex CLI and Claude Code CLI.
