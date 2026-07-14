# Running activity bubble design

## Goal

Make running state immediately legible and replace the generic `Working` text
with the latest locally available Codex progress message.

## UI

- Replace the low-contrast outlined running circle with an 18pt blue track and
  a high-contrast rounded arc rotating once every 1.1 seconds.
- Pause the spinner when Status animations is disabled or macOS Reduce Motion
  is active; keep the visible arc as a static status mark.
- Keep the red input indicator distinct: outlined circle plus solid center dot.
- Allow running summaries to wrap to two lines. Use a minimum 68pt bubble
  height so the title and message remain readable without changing the 316pt
  width or the two-bubble limit.

## Data flow

1. A sanitized metadata-only Codex `PreToolUse` or `PostToolUse` event updates
   the session to running.
2. CodingPet asynchronously reads the thread through the local app-server.
3. It extracts only the current turn's latest structured `agentMessage`.
4. The summary updates only if the same event is still the current running
   state; otherwise the result is discarded.
5. Missing or malformed data leaves `Working` unchanged.

Messages are in-memory only, are never written into hook snapshots, and are
not sent over the CodingPet socket. Claude Code remains on lifecycle summaries
until it offers an equivalent structured local API.

## Verification

- Unit-test current-turn extraction, whitespace normalization, malformed data,
  and previous-turn exclusion.
- Unit-test lifecycle timestamp/status guards for asynchronous summary updates.
- Render running and input bubbles together to inspect spinner contrast and
  two-line wrapping.
- Run the complete Swift test suite and verify against a live Codex session.
