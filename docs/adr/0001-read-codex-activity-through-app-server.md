# ADR-0001: Read Codex activity messages through app-server

## Status

Accepted

## Context

Running bubbles currently show only a generic `Working` label. The user wants
the latest agent-authored progress message, similar to the Codex App, without
weakening CodingPet's local-only privacy boundary or making transcript files a
provider integration contract.

Codex's documented app-server exposes structured threads, turns, and
`agentMessage` items through JSON-RPC. Claude Code hooks do not expose an
equivalent structured running-message API.

## Decision

On Codex `PreToolUse` and `PostToolUse` events, asynchronously call the local
app-server's `thread/read` method with `includeTurns: true`. Extract only the
last `agentMessage` item from the current turn, normalize whitespace, cap it at
240 characters, and keep it only in the in-memory `AgentSession.summary`.

The update is accepted only while the matching session is still running and
its lifecycle event timestamp is unchanged. App-server failure leaves the
existing `Working` summary in place. Claude Code keeps its provider lifecycle
summary; CodingPet does not parse Claude transcript files as a fallback.

## Consequences

### Positive

- Running bubbles show useful current progress with no cloud service.
- The event bridge and persisted snapshots remain metadata-only.
- Tool-boundary reads avoid continuous full-history polling.
- Stale asynchronous reads cannot overwrite a later input or stopped state.

### Negative

- `thread/read(includeTurns: true)` temporarily materializes the current local
  thread response in process memory.
- Message freshness follows Codex tool events rather than every streamed token.
- Claude Code cannot yet show equivalent agent-authored progress text.

### Neutral

- The existing app-server process is reused until a read fails, then recreated.

## Alternatives Considered

**Put assistant output in hook payloads or snapshots**

Rejected because it would broaden the bridge and persistence privacy boundary.

**Parse Codex or Claude transcript files**

Rejected because transcripts are not a supported primary integration contract.

**Poll every active thread continuously**

Rejected because `thread/read` returns turn history and continuous polling is
unnecessarily expensive.

## References

- Codex app-server manual: structured threads, turns, items, and streamed agent events.
- `docs/plans/2026-07-14-running-activity-bubble-design.md`
