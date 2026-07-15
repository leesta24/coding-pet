import Foundation
import Testing
@testable import CodingPet

struct CodexSessionNameResolverTests {
    @Test
    func extractsOnlyTheExplicitThreadName() {
        let result: [String: Any] = [
            "thread": [
                "name": "  Review PR 5446  ",
                "preview": "private first prompt"
            ]
        ]

        #expect(CodexSessionNameResolver.extractName(from: result) == "Review PR 5446")
        #expect(CodexSessionNameResolver.extractName(from: [
            "thread": ["name": "   ", "preview": "do not use this"]
        ]) == nil)
        #expect(CodexSessionNameResolver.extractName(from: [
            "thread": ["preview": "do not use this"]
        ]) == nil)
    }

    @Test
    func cachesNamesUntilARefreshIsRequested() async {
        let lookup = NameLookupSequence(values: ["First title", "Renamed title"])
        let resolver = CodexSessionNameResolver { _ in
            lookup.next().map(CodexSessionNameResolver.Resolution.init(name:))
        }

        #expect(await resolver.name(for: "thread") == "First title")
        #expect(await resolver.name(for: "thread") == "First title")
        #expect(lookup.callCount == 1)
        #expect(await resolver.name(for: "thread", refresh: true) == "Renamed title")
        #expect(lookup.callCount == 2)
    }


    @Test
    func recognizesPersistedUnnamedThreads() {
        let resolution = CodexSessionNameResolver.extractResolution(from: [
            "thread": ["name": "   ", "preview": "private first prompt"]
        ])

        #expect(resolution != nil)
        #expect(resolution?.name == nil)
    }
}

private final class NameLookupSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]
    private var calls = 0

    init(values: [String]) {
        self.values = values
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func next() -> String? {
        lock.withLock {
            calls += 1
            return values.isEmpty ? nil : values.removeFirst()
        }
    }
}
