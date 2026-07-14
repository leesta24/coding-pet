import Foundation
import Testing
@testable import CodingPet

@Suite
struct CodexUsageReaderTests {
    @Test
    func readsCodexRateLimitWindowsFromTheLocalAppServer() async throws {
        let fake = FakeCodexUsageSession(result: [
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": [
                        "usedPercent": 28,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000
                    ],
                    "secondary": [
                        "usedPercent": 39,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_100_000
                    ]
                ]
            ]
        ])
        let reader = CodexUsageReader(sessionFactory: { fake })

        let snapshot = try #require(await reader.snapshot())

        #expect(fake.methods == ["account/rateLimits/read"])
        #expect(snapshot.windows.map(\.label) == ["5h", "Week"])
        #expect(snapshot.windows.map(\.remainingPercent) == [72, 61])
    }

    @Test @MainActor
    func storeReadsOnlyWhenTheCodexHookIsInstalled() async {
        let expected = CodexUsageSnapshot(windows: [
            .init(label: "5h", remainingPercent: 72, resetsAt: nil)
        ])
        let reader = FakeUsageReader(snapshot: expected)
        let hookStatus = HookStatusBox(value: .notInstalled)
        let store = CodexUsageStore(
            statusProvider: { hookStatus.value },
            reader: reader
        )

        store.refresh()
        await Task.yield()
        #expect(await reader.readCount == 0)
        #expect(store.snapshot == nil)

        hookStatus.value = .installed
        store.refresh()
        for _ in 0..<20 where store.snapshot == nil {
            await Task.yield()
        }
        #expect(await reader.readCount == 1)
        #expect(store.snapshot == expected)

        hookStatus.value = .needsRepair
        store.refresh()
        #expect(store.snapshot == nil)
    }
}

@MainActor
private final class HookStatusBox {
    var value: HookInstallationStatus

    init(value: HookInstallationStatus) {
        self.value = value
    }
}

private final class FakeCodexUsageSession: CodexAppServerSessionProtocol, @unchecked Sendable {
    private let result: [String: Any]
    private(set) var methods: [String] = []

    init(result: [String: Any]) {
        self.result = result
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        methods.append(method)
        return result
    }

    func close() {}
}

private actor FakeUsageReader: CodexUsageReading {
    let snapshotValue: CodexUsageSnapshot?
    private(set) var readCount = 0

    init(snapshot: CodexUsageSnapshot?) {
        snapshotValue = snapshot
    }

    func snapshot() async -> CodexUsageSnapshot? {
        readCount += 1
        return snapshotValue
    }
}
