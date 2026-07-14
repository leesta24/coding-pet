import Foundation
import Testing
@testable import CodingPet

struct CodexHookTrustManagerTests {
    @Test
    func activationTrustsExactHashesAndRemovesOnlyAgentPeekState() throws {
        let untrustedHooks = codingPetHooks(trustStatus: "untrusted")
        let trustedHooks = codingPetHooks(trustStatus: "trusted")
        let fake = FakeCodexAppServerSession(responses: [
            hooksListResponse(untrustedHooks),
            [
                "config": [
                    "hooks": [
                        "state": [
                            "agentpeek:one": ["trusted_hash": "sha256:old-1"],
                            "agentpeek:two": ["trusted_hash": "sha256:old-2"],
                            "unrelated:key": ["enabled": false, "trusted_hash": "sha256:keep"]
                        ]
                    ]
                ]
            ],
            ["status": "ok"],
            hooksListResponse(trustedHooks)
        ])
        let manager = CodexHookTrustManager(sessionFactory: { fake })

        let report = try manager.activateCodingPetHooks(
            cwd: URL(fileURLWithPath: "/tmp/project"),
            removingAgentPeekKeys: ["agentpeek:one", "agentpeek:two"]
        )

        #expect(report.trustedHookCount == 6)
        #expect(report.removedAgentPeekStateCount == 2)
        #expect(fake.methods == ["hooks/list", "config/read", "config/batchWrite", "hooks/list"])
        let batchParams = try #require(fake.params[2])
        let edits = try #require(batchParams["edits"] as? [[String: Any]])
        let state = try #require(edits.first?["value"] as? [String: Any])
        #expect(state["agentpeek:one"] == nil)
        #expect(state["agentpeek:two"] == nil)
        #expect((state["unrelated:key"] as? [String: Any])?["enabled"] as? Bool == false)
        for index in 0..<6 {
            let value = state["codingpet:\(index)"] as? [String: Any]
            #expect(value?["trusted_hash"] as? String == "sha256:new-\(index)")
        }
    }

    @Test
    func snapshotFindsAgentPeekAndCodingPetWithoutMatchingUnrelatedHooks() throws {
        let hooks = codingPetHooks(trustStatus: "untrusted") + [
            hook(
                key: "agentpeek:key",
                command: "'/Applications/AgentPeekBridge' --bridge-hook-event codex",
                hash: "sha256:agentpeek",
                status: "trusted"
            ),
            hook(
                key: "other:key",
                command: "/tmp/not-agentpeek",
                hash: "sha256:other",
                status: "trusted"
            )
        ]
        let fake = FakeCodexAppServerSession(responses: [hooksListResponse(hooks)])
        let manager = CodexHookTrustManager(sessionFactory: { fake })

        let snapshot = try manager.snapshot(cwd: URL(fileURLWithPath: "/tmp/project"))

        #expect(snapshot.agentPeekKeys == ["agentpeek:key"])
        #expect(snapshot.codingPetKeys == Set((0..<6).map { "codingpet:\($0)" }))
    }

    private func codingPetHooks(trustStatus: String) -> [[String: Any]] {
        (0..<6).map { index in
            hook(
                key: "codingpet:\(index)",
                command: "'/tmp/CodingPetHook' --provider codex",
                hash: "sha256:new-\(index)",
                status: trustStatus,
                statusMessage: HookConfigurationInstaller.ownershipMarker
            )
        }
    }

    private func hook(
        key: String,
        command: String,
        hash: String,
        status: String,
        statusMessage: String? = nil
    ) -> [String: Any] {
        var value: [String: Any] = [
            "key": key,
            "command": command,
            "currentHash": hash,
            "trustStatus": status
        ]
        if let statusMessage { value["statusMessage"] = statusMessage }
        return value
    }

    private func hooksListResponse(_ hooks: [[String: Any]]) -> [String: Any] {
        ["data": [["hooks": hooks]]]
    }
}

private final class FakeCodexAppServerSession: CodexAppServerSessionProtocol {
    enum Error: Swift.Error {
        case missingResponse
    }

    private var responses: [[String: Any]]
    private(set) var methods: [String] = []
    private(set) var params: [[String: Any]?] = []

    init(responses: [[String: Any]]) {
        self.responses = responses
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        methods.append(method)
        self.params.append(params)
        guard !responses.isEmpty else { throw Error.missingResponse }
        return responses.removeFirst()
    }

    func close() {}
}
