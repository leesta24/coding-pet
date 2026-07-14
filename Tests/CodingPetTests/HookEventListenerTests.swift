import Foundation
import Testing
import CodingPetBridge
@testable import CodingPet

struct HookEventListenerTests {
    @Test
    @MainActor
    func receivesAnEventFromTheSocketClient() async throws {
        let path = "/tmp/codingpet-listener-\(UUID().uuidString.prefix(8)).sock"
        let expected = HookEventEnvelope(
            provider: .codex,
            eventName: "Stop",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            parentProcessID: 99,
            sessionID: "listener-session",
            cwd: "/tmp/project"
        )

        try await confirmation("listener callback") { confirmation in
            let listener = try HookEventListener(path: path) { event in
                #expect(event == expected)
                confirmation.confirm()
            }
            #expect(HookSocketClient.send(expected, to: path, timeoutMilliseconds: 100))
            try await Task.sleep(for: .milliseconds(100))
            withExtendedLifetime(listener) {}
        }
    }

    @Test
    func rejectsMalformedAndOversizedMessages() throws {
        #expect(HookEventListener.decodeMessage(Data("not-json\n".utf8)) == nil)
        #expect(HookEventListener.decodeMessage(Data(repeating: 0x41, count: 16_385)) == nil)

        let unsupported = HookEventEnvelope(
            protocolVersion: 999,
            provider: .codex,
            eventName: "Stop",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "unsupported",
            cwd: "/tmp"
        )
        var data = try HookEventCodec.encode(unsupported)
        data.append(0x0A)
        #expect(HookEventListener.decodeMessage(data) == nil)
    }
}
