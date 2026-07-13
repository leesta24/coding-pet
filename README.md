# AgentPet

AgentPet is a macOS floating companion for Codex CLI and Claude Code CLI sessions. It makes session state visible without keeping every terminal in front of you.

The first milestone is intentionally small:

- show an always-on-top floating bot;
- aggregate active CLI sessions;
- call attention when a session needs user input;
- show sessions in a compact panel;
- return the user to the originating terminal.

## Requirements

- macOS 14 or later
- Apple silicon
- Xcode 26 or a compatible Swift 6.2 toolchain

## Run

```sh
swift run AgentPet
```

Launch with sample sessions while developing the UI:

```sh
swift run AgentPet --demo
```

Run tests:

```sh
swift test
```

You can open `Package.swift` directly in Xcode.

## Current structure

- `Models`: normalized agent session and bot state
- `Services`: session store and terminal navigation boundary
- `UI`: transparent floating bot panel and session panel

The current bot is an original vector placeholder. Production sprite sheets will replace it without changing the session or window architecture.

## Next milestone

Add a local event bridge and non-blocking hooks for Codex and Claude Code, including reversible installation and config backups.

