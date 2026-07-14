# Codex Ready unread reconciliation

## Goal

Show Codex App tasks with a real blue unread indicator as `ready` without
restoring ordinary completed or idle tasks to CodingPet.

## Source and boundary

Codex App stores its current local unread thread IDs under the versioned
`electron-persisted-atom-state.unread-thread-ids-by-host-v1.local` field in
`~/.codex/.codex-global-state.json`. CodingPet reads only that typed field and
uses the local app-server to resolve the matching thread's ID, name, working
directory, and update time. It does not inspect transcript files or retain
prompts, responses, tool input, or tool output.

This is a secondary read-only projection. Hooks remain authoritative for
`running` and `needsInput`. Missing, oversized, or malformed global state is
treated as unknown and does not destructively clear existing rows.

## State rules

- An unread local Codex thread with no hook-owned active row becomes `ready`.
- A running or input-waiting hook row is never overwritten by unread state.
- Terminal-turn reconciliation only examines hook-owned `running` and
  `needsInput` rows; it must not delete an unread `ready` projection.
- A ready row disappears when its ID leaves the unread set.
- Selecting a ready row acknowledges that exact thread version in CodingPet so
  the unchanged Codex unread bit does not immediately recreate it.
- A newer completion time makes the same thread visible again.
- Ready participates in the panel, pet state, attention count, and the existing
  pending/attention bubble preference. Ordinary idle threads remain hidden.

## Failure behavior

The state reader caps the file at 4 MiB and unread IDs at 10,000. Schema or I/O
failure returns unknown rather than an empty set. Thread metadata lookup also
fails closed, so no guessed Ready session is created.

## Verification

- Reader tests cover valid, empty, malformed, missing, and oversized state.
- Store tests cover add/remove, active-hook precedence, acknowledgement, and
  exclusion of Ready rows from terminal-turn cleanup.
- Bubble tests cover Ready display and compact attention counting.
