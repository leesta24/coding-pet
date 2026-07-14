# CodingPet

CodingPet is a macOS floating companion for Codex CLI and Claude Code CLI sessions. It makes session state visible without keeping every terminal in front of you.

For a zero-context development handoff, read `HANDOFF.md` and `AGENTS.md` first.

The first milestone is intentionally small:

- show an always-on-top floating bot;
- let the bot be repositioned without treating a drag release as a click;
- aggregate active CLI sessions;
- call attention when a session needs user input;
- show sessions in a compact panel;
- return the user to the originating terminal.

The official build includes the user-owned, Codex-compatible v2 胖墩 pet.
CodingPet also discovers private v2 pet packages from
`~/Library/Application Support/CodingPet/Pets/`; local packages never enter the
repository or release artifacts. Open the session panel and choose the gear
button to switch between available pets in the dedicated Appearance settings
page. Each pet has a large image card in the pet library; the selection is
stored locally and restored on the next launch. The
same page includes a 64–160pt Bot size slider that updates the floating pet
immediately and persists the chosen size.

Settings also reports Codex CLI and Claude Code hook installation status,
provides independent reversible install/repair/uninstall actions for each provider, controls status animation, and
has independent Running, Pending input, and Ready bubble switches. Turning
Pending input or Ready bubbles off folds that state into a compact attention
count; turning Running bubbles off hides those notifications completely. Click a full bubble to open its exact
session, or close that bubble without stopping/removing the session. A closed
Running bubble stays quiet across later messages and tool activity, then
reappears if the session needs input or gains an unread Ready marker. The close
control appears only while hovering that card. Three or more eligible bubbles stay in a two-row vertical scroll
viewport without a persistent scrollbar instead of being discarded. Click a
compact count to choose from the
session panel. The interactive bubble window shrinks to its visible content and
remains non-activating, so it does not cover the nearby editor with a large
transparent click target.
Settings also documents CodingPet's local-only privacy boundary.

The panel lists sessions that are actively working, explicitly waiting for
input, or marked unread by Codex App. Opening a CLI alone does not create a row,
and a completed/stopped turn loses its running state immediately. It appears as
Ready only while its ID is in Codex App's local unread index; ordinary read or
idle tasks remain hidden. A later prompt recreates its running row. The native
single-surface panel adapts its height to one through four sessions, then
scrolls without reserving blank space for missing rows. While the panel is open,
the conversation-bubble overlay is hidden and returns when the panel closes.
When the Codex hook is installed, the header also reads the local Codex
app-server and shows a quiet, text-only summary of the current rate-limit
windows. If the hook is missing, damaged, or the local request fails, the
usage summary is omitted without reserving space.

## Requirements

- macOS 14 or later
- Apple silicon
- Xcode 26 or a compatible Swift 6.2 toolchain

## Run

```sh
swift run CodingPet
```

Launch with sample sessions while developing the UI:

```sh
swift run CodingPet --demo
```

Run tests:

```sh
swift test
```

Build a conventional Apple-silicon application bundle:

```sh
scripts/build-app.sh
open dist/CodingPet.app
```

Release maintainers can create a Developer ID signed DMG locally and submit it
for notarization with `scripts/release-dmg.sh`. Credential setup and artifact
verification are documented in [Packaging/README.md](Packaging/README.md).

Build the best-effort lifecycle hook helper:

```sh
swift build --product CodingPetHook
```

`CodingPetHook` accepts `--provider codex` or `--provider claude-code`, reads
one provider hook JSON object from stdin, strips it down to routing metadata,
and attempts to deliver it to the running app. It is intentionally silent and
returns success when the app or socket is unavailable. Do not point provider
configuration at `swift run`, because SwiftPM build output and startup work do
not belong in a CLI lifecycle hook.

For a SwiftPM development build, install or uninstall the lifecycle hooks with:

```sh
swift build
.build/debug/CodingPet --install-hooks
.build/debug/CodingPet --uninstall-hooks
```

Installation merges CodingPet matcher groups into `~/.codex/hooks.json` and
`~/.claude/settings.json`, creates `0600` sidecar backups, and is idempotent.
It then uses the local `codex app-server` `hooks/list` response to read each
installed CodingPet hook's exact current hash and records those hashes through
`config/batchWrite`, so the hooks are active without a separate `/hooks` step.
The installer also removes AgentPeek bridge hooks and their Codex trust entries
without touching unrelated hooks; CodingPet's backups are sanitized so an
uninstall cannot restore AgentPeek later. Set `CODEX_CLI_PATH` if `codex` is not
in a standard installation location or the app's `PATH`.

Uninstall restores the original bytes when no unrelated edits occurred; when
the user changed other settings after installation, it removes only handlers
owned by CodingPet. It also removes CodingPet's saved Codex trust entries.

You can open `Package.swift` directly in Xcode.

## Current structure

- `Models`: normalized agent session and bot state
- `CodingPetBridge`: safe hook envelope, sanitizer, codec, and bounded socket client
- `CodingPetHook`: silent stdin-to-socket helper executable
- `Services`: session store, provider adapters, socket listener, and terminal navigation boundary
- `UI`: transparent floating bot panel and session panel

胖墩 and validated private pet packages share the production
Codex-compatible v2 WebP atlas path. Their idle, running, waiting, review, and
failed rows map directly to CodingPet states. Idle poses stay still for several
seconds and only play an occasional brief gesture.

## License

CodingPet source code is available under the [MIT License](LICENSE). The
bundled 胖墩 artwork is not covered by MIT; see
[ASSET_LICENSE.md](ASSET_LICENSE.md) before redistributing a fork or build.

CodingPet is an independent project and is not affiliated with, endorsed by,
or sponsored by OpenAI or Anthropic. Codex and Claude are trademarks of their
respective owners.

## Next milestone

Publish the first signed and notarized GitHub Release, validate lifecycle
delivery against a real Claude Code session, and improve terminal-process
ancestry resolution. The standard `.app` now packages its helper under
`Contents/Helpers`, and CI/tag workflows cover tests, Developer ID signing,
notarization, DMG verification, and release upload. A real Codex CLI `0.142.5`
smoke run completed both the `SessionStart` and `UserPromptSubmit` hooks.

## Event bridge privacy

The bridge sends only a protocol version, provider, event name, safe event
subtype, timestamp, parent PID, session ID, and working directory. Prompt text,
assistant responses, transcript paths, tool input, tool output, code, and diffs
are discarded before socket delivery. The per-user Unix socket is created in
the macOS temporary directory with mode `0600` and accepts messages up to 16 KiB.
For Codex sessions, the app separately resolves the optional user-facing
`thread.name` from the local `codex app-server` using the session ID. It does
not request turns or use the thread preview; missing names fall back to the
project directory name. On startup and every 15 seconds, CodingPet also asks
the app-server for non-archived thread IDs and removes archived or deleted
Codex sessions from its local metadata snapshots. If the app-server is
unavailable or returns malformed data, existing sessions are retained.

For running Codex sessions, `PreToolUse` and `PostToolUse` also trigger a local
app-server `thread/read` call. CodingPet extracts only the current turn's latest
structured `agentMessage`, truncates it for the two-line activity bubble, and
keeps it in memory only. It is never added to the hook envelope or snapshot
store. CodingPet does not parse Codex or Claude transcript files; Claude Code
continues to show lifecycle summaries until it exposes an equivalent local API.

For Codex Ready state, CodingPet reads only the typed local unread-thread ID
field from `~/.codex/.codex-global-state.json`, then resolves matching name,
working directory, and update time through `thread/read(includeTurns:false)`.
The file is size-bounded and malformed or missing state fails closed. CodingPet
does not write Codex App state.
