# CodingPet

[![CI](https://github.com/leesta24/coding-pet/actions/workflows/ci.yml/badge.svg)](https://github.com/leesta24/coding-pet/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-arm64-black)
[![MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)

CodingPet is a native macOS floating companion for Codex and Claude Code. It
keeps active agent sessions visible, tells you when a task needs attention, and
returns you to the right session without taking keyboard focus away from your
editor or terminal.

## What it does

- **Watch multiple sessions** — show running tasks, explicit input requests,
  completed Codex tasks with unread activity, and completed Claude turns until
  you acknowledge them.
- **Stay out of the way** — a transparent always-on-top pet and compact bubbles
  remain visible across Spaces without becoming the key window.
- **Jump back to work** — open an exact Codex App task when its thread ID is
  available, with terminal and working-directory fallbacks for CLI sessions.
- **Show useful progress** — display the latest structured Codex activity
  message while a task is running, without parsing transcript files.
- **Customize the companion** — choose a pet, resize it, control animations,
  and independently enable Running, Pending input, and Ready bubbles.
- **Keep everything local** — no account, cloud service, analytics, telemetry,
  prompt upload, code upload, or remote session storage.

## Codex and Claude Code support

| Capability | Codex | Claude Code |
| --- | --- | --- |
| Non-blocking lifecycle hooks | Yes | Yes |
| Running and pending-input state | Yes | Yes |
| Session display name | Codex local app-server | Claude local activity metadata |
| Reversible per-provider hook install | Yes | Yes |
| Completed attention state | Codex App unread state | Stop hook + Claude Desktop unread state |
| Latest agent activity message | Codex local app-server | Not currently exposed |
| Navigation | Exact Codex App task, then fallbacks | Direct navigation unavailable; shows a local notice |
| Usage window summary | Codex local app-server | Not currently exposed |

CodingPet observes and navigates. Permission approvals and user replies always
remain inside Codex or Claude Code.

## Pet library

The official source tree includes the user-owned **胖墩** appearance.
CodingPet also discovers private Codex-compatible v2 packages from:

```text
~/Library/Application Support/CodingPet/Pets/<pet-id>/
├── pet.json
└── spritesheet.webp
```

A valid package uses a transparent `1536x2288` atlas: 8 columns, 11 rows, and
`192x208` cells. Private packages stay outside this repository and are never
copied into application or DMG builds.

### Create a new pet with Codex

The repository includes an installable Codex skill that guides creation of an
original or user-owned v2 appearance and installs it into the local pet
library:

```sh
mkdir -p ~/.codex/skills
cp -R skills/create-coding-pet-appearance ~/.codex/skills/
```

Then ask Codex:

```text
$create-coding-pet-appearance Create a new CodingPet from character art I own.
```

### Migrate a custom pet from Codex

Only customized pets that you created, commissioned, or otherwise have the
right to reuse may be migrated. Built-in Codex pets and application assets are
explicitly excluded.

```sh
mkdir -p ~/.codex/skills
cp -R skills/migrate-codex-custom-pet ~/.codex/skills/
```

Then provide the exact custom pet ID or directory:

```text
$migrate-codex-custom-pet Migrate my user-created pet from ~/.codex/pets/my-pet.
```

Restart CodingPet after adding or removing a local package so the Appearance
gallery refreshes.

## Requirements

- macOS 14 or later
- Apple silicon
- Xcode 26 or a compatible Swift 6.2 toolchain
- Codex CLI and/or Claude Code CLI

## Build and run

Run directly with SwiftPM:

```sh
swift run CodingPet
```

Launch with sample sessions while developing the interface:

```sh
swift run CodingPet --demo
```

Build a conventional local application bundle:

```sh
scripts/build-app.sh
open dist/CodingPet.app
```

Public DMG releases are intentionally deferred while the current interaction
and session-lifecycle fixes are completed.

## Connect providers

Open the pet, choose **Settings → Integrations**, then install Codex CLI and
Claude Code independently. CodingPet:

- merges its handlers instead of replacing existing configuration;
- creates permission-restricted backups;
- activates its own Codex hook hashes through the local Codex app-server;
- removes only CodingPet-owned handlers during uninstall;
- exits hooks quickly and successfully when the app or local socket is absent;
- never approves, denies, or modifies a tool request.

Development builds can also manage both providers from the command line:

```sh
swift build
.build/debug/CodingPet --install-hooks
.build/debug/CodingPet --uninstall-hooks
```

## Development

Run the complete test suite:

```sh
swift test
```

The current suite covers provider payload normalization, hook privacy,
configuration merging and restoration, session lifecycle reconciliation,
Codex navigation, local pet discovery, floating-window behavior, and SwiftUI
rendering.

Main source areas:

- `Sources/CodingPet`: native AppKit/SwiftUI application
- `Sources/CodingPetBridge`: bounded, metadata-only local hook protocol
- `Sources/CodingPetHook`: best-effort CLI lifecycle helper
- `Sources/CodingPet/Resources/Pets`: officially bundled appearances
- `skills`: optional Codex workflows for creating and migrating private pets
- `Tests`: unit, integration, rendering, and packaging smoke tests

## Privacy

Hook events contain only provider, event name, safe event subtype, timestamp,
parent PID, session ID, and working directory. Prompt text, assistant replies,
tool input, tool output, code, diffs, and transcript paths are removed before
delivery. The Unix socket is per-user, permission restricted, local only, and
message-size bounded.

Codex-specific task names, unread IDs, activity messages, and usage windows are
read from local Codex interfaces and remain on the Mac. Claude Desktop titles
are matched exactly from `cliSessionId` to the bounded metadata index in
`~/Library/Application Support/Claude/claude-code-sessions`. Claude read state
also uses only bounded session metadata plus focused-session events extracted
from the tail of Claude Desktop's local `main.log`; prompts and responses are
never inspected. CodingPet then falls back to explicit Claude Code `--name` or
`/rename` values, ignores directory-derived process names, and otherwise uses
`Untitled session`. CodingPet does not parse Codex or Claude transcript files.

## License

The source code is available under the [MIT License](LICENSE). The bundled
胖墩 character artwork is not covered by MIT; see
[ASSET_LICENSE.md](ASSET_LICENSE.md) before redistributing a fork or build.

CodingPet is an independent project and is not affiliated with, endorsed by,
or sponsored by OpenAI or Anthropic. Codex and Claude are trademarks of their
respective owners.
