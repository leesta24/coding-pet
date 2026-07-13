# CodingPet handoff

Updated: 2026-07-13

Repository: `/Users/juyiwu/Dev/coding-pet`

## One-sentence definition

CodingPet is a native macOS desktop pet that watches Codex CLI and Claude Code CLI sessions, visibly asks for attention when a session is waiting, and takes the user back to the correct terminal to respond.

## Intended user experience

The bot floats above normal windows and can be dragged around the desktop. Its appearance reflects the highest-priority state across all known sessions. Clicking it opens a compact session panel. Clicking a session activates its originating terminal; CodingPet does not render an approval form or send a reply itself.

The five normalized states are:

1. `needsInput`: a session is waiting for approval, an answer, or another user decision.
2. `blocked`: a session failed or encountered a system error.
3. `ready`: a session completed and has unread activity.
4. `running`: at least one session is actively working.
5. `idle`: there are no active sessions.

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
- Click-to-open session panel.
- `AgentSession`, `SessionStore`, and normalized provider/status models.
- Bot state reducer with the priority listed above.
- Terminal navigation boundary with process, bundle-ID, and working-directory fallbacks.
- `--demo` mode with Codex and Claude Code sample sessions.
- Unit tests for state reduction.

The current bot face is an original vector placeholder, not the production sprite renderer.

## What is not implemented

- Codex or Claude Code hook installation.
- Local Unix-domain-socket event receiver.
- Provider event adapters and fixture payloads.
- Session expiry, persistence, or crash recovery.
- Parent-process, TTY, terminal-window, and tab resolution.
- Precise return to an existing Terminal/iTerm/Ghostty tab.
- Production sprite sheets and animation playback.
- Settings, launch-at-login, signing, notarization, and updates.

## Next milestone: local event bridge

Build one vertical slice before expanding the UI:

1. Add a small `CodingPetHook` executable that reads one hook JSON object from stdin, attaches only safe routing metadata such as provider, event name, timestamp, parent PID, session ID, and working directory, and sends it to a local Unix socket.
2. The helper must use a short timeout, exit successfully when CodingPet is not running, and never write to stdout in a way that changes agent behavior.
3. Add an in-app socket listener and provider adapters that normalize events into `AgentSession` updates.
4. Start with session start, user prompt submission, permission/input waiting, and turn stop events.
5. Add fixture-driven tests before installing any real hooks.
6. Implement reversible installers that back up and merge `~/.codex/hooks.json` or the active Codex hook layer and `~/.claude/settings.json`. Never replace an existing hooks object wholesale.

Codex exposes lifecycle events including `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, and `Stop`. Claude Code exposes corresponding lifecycle hooks plus notification events. Verify payloads against the installed CLI versions and current official documentation before committing adapters:

- Codex: <https://learn.chatgpt.com/codex/hooks>
- Claude Code: <https://code.claude.com/docs/en/hooks>

## Acceptance criteria for that milestone

- Starting either supported CLI creates or updates one session in the panel.
- Submitting a prompt changes that session to `running`.
- A permission or input request changes it to `needsInput` and raises the bot badge.
- A completed turn changes it to `ready`.
- With CodingPet closed, both CLIs behave normally and the helper exits quickly.
- Existing user hook configuration survives install and uninstall byte-for-byte apart from CodingPet's own entries.
- No prompt body, assistant response, code, diff, or tool output is sent over the event bridge.
- `swift test` passes.

## Explicit non-goals for MVP

- Inline approval, denial, or text replies.
- Token usage, billing, and rate-limit dashboards.
- Local development server management or arbitrary shell actions.
- Codex or Claude desktop apps.
- Windows, Linux, Intel Macs, tmux, or remote sessions.
- Providers other than Codex CLI and Claude Code CLI.

