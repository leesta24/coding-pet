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
