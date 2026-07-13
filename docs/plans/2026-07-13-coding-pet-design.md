# CodingPet MVP design

## Product boundary

CodingPet is a macOS-only floating companion for terminal sessions started by Codex CLI and Claude Code CLI. The bot summarizes work across sessions, calls attention when a session needs input, and opens a compact activity panel. Selecting a session returns the user to its terminal; approvals and replies remain inside the original CLI.

The MVP does not execute prompts, approve tools, manage local servers, calculate billing, or host agent processes.

## Architecture

The app uses a native SwiftUI and AppKit shell. A transparent floating `NSPanel` hosts the bot, and a second panel hosts the session list. A `SessionStore` normalizes provider-specific events into `AgentSession` records. `BotStateReducer` derives one visible state using this priority: needs input, blocked, ready, running, idle.

The integration milestone will install small, non-blocking hooks for lifecycle events exposed by Codex and Claude Code. Hooks send compact JSON events to a local Unix domain socket and immediately exit successfully. The app never returns approval decisions from these hooks. Process ancestry and terminal metadata are resolved locally so `SessionNavigator` can activate the originating terminal.

## Assets

The production companion will use original transparent sprite sheets. Each animation declares frame rectangles, frames per second, looping behavior, and a shared anchor point. The renderer will support idle, running, needs-input, ready, and blocked animations and will show a still frame when macOS Reduce Motion is enabled.

## Safety and failure behavior

Hook installation must back up existing configuration, merge rather than overwrite user hooks, and provide one-click uninstall. Event delivery is best effort: an unavailable app or socket must never delay Codex or Claude Code. Unknown events are ignored, malformed events are logged locally, and missing terminal metadata falls back to opening the working directory.

## Verification

Unit tests cover state priority and event normalization. Integration tests will use fixture hook payloads. UI verification will cover multi-display placement, Spaces, Reduce Motion, empty sessions, multiple waiting sessions, and terminal activation fallbacks.
