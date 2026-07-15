import Foundation
import Testing
import CodingPetBridge

struct HookEventSanitizerTests {
    @Test
    func codexPromptPayloadKeepsOnlyRoutingMetadata() throws {
        let data = try fixtureData("Codex/user-prompt-submit.json")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let event = try HookEventSanitizer.sanitize(
            data,
            provider: .codex,
            timestamp: timestamp,
            parentProcessID: 42
        )

        #expect(event.protocolVersion == 1)
        #expect(event.provider == .codex)
        #expect(event.eventName == "UserPromptSubmit")
        #expect(event.eventSubtype == nil)
        #expect(event.timestamp == timestamp)
        #expect(event.parentProcessID == 42)
        #expect(event.sessionID == "codex-session-1")
        #expect(event.cwd == "/Users/example/Projects/coding-pet")

        let encoded = try HookEventCodec.encode(event)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("prompt"))
        #expect(!json.contains("transcript"))
        #expect(!json.contains("This prompt must never"))
    }

    @Test
    func claudePermissionPayloadDropsToolDetails() throws {
        let data = try fixtureData("Claude/permission-request.json")
        let event = try HookEventSanitizer.sanitize(
            data,
            provider: .claudeCode,
            timestamp: .distantPast,
            parentProcessID: nil
        )

        #expect(event.provider == .claudeCode)
        #expect(event.eventName == "PermissionRequest")
        #expect(event.sessionID == "claude-session-1")

        let encoded = try HookEventCodec.encode(event)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("tool_input"))
        #expect(!json.contains("rm -rf"))
        #expect(!json.contains("Sensitive tool request"))
    }

    @Test
    func claudeToolPayloadKeepsOnlyAllowlistedActivityAndClientMetadata() throws {
        let data = try fixtureData("Claude/pre-tool-use.json")
        let event = try HookEventSanitizer.sanitize(
            data,
            provider: .claudeCode,
            timestamp: .distantPast,
            parentProcessID: 99,
            environment: [
                "CLAUDE_CODE_ENTRYPOINT": "cli",
                "TERM_PROGRAM": "Apple_Terminal"
            ]
        )

        #expect(event.activityKind == .editing)
        #expect(event.clientSurface == .terminal)
        #expect(event.terminalApplication == .appleTerminal)

        let encoded = try HookEventCodec.encode(event)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("tool_name"))
        #expect(!json.contains("tool_input"))
        #expect(!json.contains("source.swift"))
        #expect(!json.contains("private source"))
        #expect(!json.contains("CLAUDE_CODE_ENTRYPOINT"))
        #expect(!json.contains("TERM_PROGRAM"))
    }

    @Test
    func claudeDesktopSurfaceIsRecognizedWithoutPersistingRawEnvironment() throws {
        let data = try fixtureData("Claude/user-prompt-submit.json")
        let event = try HookEventSanitizer.sanitize(
            data,
            provider: .claudeCode,
            parentProcessID: 100,
            environment: [
                "CLAUDE_CODE_ENTRYPOINT": "claude-desktop",
                "TERM_PROGRAM": "Untrusted Secret Terminal"
            ]
        )

        #expect(event.clientSurface == .desktop)
        #expect(event.terminalApplication == nil)
        #expect(!String(decoding: try HookEventCodec.encode(event), as: UTF8.self)
            .contains("Untrusted Secret Terminal"))
    }

    @Test
    func missingRoutingFieldsAreRejected() {
        let data = Data(#"{"hook_event_name":"Stop","cwd":"/tmp"}"#.utf8)

        #expect(throws: HookEventSanitizer.Error.self) {
            try HookEventSanitizer.sanitize(
                data,
                provider: .codex,
                timestamp: .now,
                parentProcessID: nil
            )
        }
    }

    private func fixtureData(_ path: String) throws -> Data {
        let resourceURL = try #require(Bundle.module.resourceURL)
        let url = resourceURL.appending(path: "Fixtures/\(path)")
        return try Data(contentsOf: url)
    }
}
