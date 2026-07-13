# CodingPet repository guidance

## Start here

Read these files before changing code:

1. `HANDOFF.md` for current status and the next milestone.
2. `docs/plans/2026-07-13-coding-pet-design.md` for the validated MVP design.
3. `README.md` for build and run commands.

## Product definition

CodingPet is a native macOS floating companion for Codex CLI and Claude Code CLI sessions. It shows a small always-on-top bot, summarizes active sessions in a panel, alerts the user when a session needs attention, and returns the user to the originating terminal.

The CLI remains the place where users approve permissions and type replies. CodingPet observes and navigates; it does not control the agent.

## MVP constraints

- Support macOS 14+ on Apple silicon.
- Support Codex CLI and Claude Code CLI only.
- Use Swift, SwiftUI, and AppKit.
- Keep all session data local. Do not add accounts, telemetry, or cloud storage.
- Agent hooks must be non-blocking and must never approve, deny, or modify a tool request.
- Hook installation must merge with user configuration, create a backup, and be reversible.
- Do not parse transcript files as the primary integration contract.
- Do not copy or extract Codex Pet assets or proprietary code. Use original artwork and a clean-room implementation of publicly visible interaction patterns.

## Engineering rules

- Keep provider-specific event handling behind adapters and normalize into `AgentSession`.
- Preserve the state priority: `needsInput`, `blocked`, `ready`, `running`, `idle`.
- An unavailable app, socket, or helper must not delay Codex or Claude Code.
- Prefer small testable milestones. Add fixtures for every provider payload introduced.
- Run `swift test` before handing off changes.

## Commands

```sh
swift run CodingPet --demo
swift test
```

## Current priority

Implement the local hook event bridge described in `HANDOFF.md`. Do not expand into token accounting, inline approvals, local server management, or additional agent providers yet.

