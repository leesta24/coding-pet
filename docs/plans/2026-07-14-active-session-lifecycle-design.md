# Active session lifecycle design

## Goal

Show only sessions that are actively working or explicitly waiting for user
input. A CLI session that merely exists, has completed a turn, or has stopped
must not remain in the panel, badge count, bubbles, or restored snapshot state.

## Lifecycle contract

- `UserPromptSubmit`, `PreToolUse`, and `PostToolUse` create or update a
  `running` session.
- `PermissionRequest` and supported Claude input notifications create or update
  a `needsInput` session.
- `SessionStart`, `Stop`, `SessionEnd`, and `StopFailure` are inactive
  boundaries. They remove the matching in-memory session and its metadata-only
  snapshot.
- Codex App cancellation can end a turn without delivering one of those hook
  boundaries. Every three seconds, CodingPet therefore reads only the latest
  turn's structured `status` and `completedAt` fields from the local app-server.
  A terminal turn (`completed`, `interrupted`, or `failed`) removes the session
  only when its completion time is not older than the last active hook event.
- A later active event for the same provider/session ID recreates the session.
- Timestamp ordering remains authoritative: an older inactive event must not
  delete a newer active state.

The app-server check is a secondary stale-state repair path, not the primary
integration contract. It does not inspect or retain turn items, prompts,
assistant messages, tool input, or tool output.

## Why remove instead of hide

Filtering `ready` only in SwiftUI would leave stale snapshots that reappear on
restart and would keep aggregate state/count logic inconsistent. A timeout
would also be both delayed and inaccurate. Removing on the provider lifecycle
boundary gives the same result in the store, persisted recovery state, session
panel, bot state, and bubbles.

## Compatibility

The existing `ready` and `blocked` enum cases remain for artwork compatibility
and isolated previews, but neither is part of the active-session projection.
No hook is allowed to approve, reject, or alter a provider request.

## Verification

- Fixture tests prove inactive lifecycle payloads do not normalize into visible
  sessions.
- Store tests prove Stop removes an active session and a future prompt can
  recreate it.
- Snapshot tests prove inactive events clear persisted state without allowing
  an older event to delete a newer active snapshot.
- Startup reconciliation tests remove legacy inactive snapshots for both
  providers, including when Codex catalog lookup is unavailable.
- Turn reconciliation tests prove manual interruption is recognized and an
  older completed turn cannot remove newer hook activity.
