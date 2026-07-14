import Foundation

struct CodexUsageSnapshot: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let label: String
        let remainingPercent: Int
        let resetsAt: Date?
    }

    let windows: [Window]
}

protocol CodexUsageReading: Sendable {
    func snapshot() async -> CodexUsageSnapshot?
}

actor CodexUsageReader: CodexUsageReading {
    typealias SessionFactory = @Sendable () throws -> any CodexAppServerSessionProtocol

    private let sessionFactory: SessionFactory
    private var session: (any CodexAppServerSessionProtocol)?

    init(codexExecutableURL: URL? = nil) {
        sessionFactory = {
            let executableURL = try codexExecutableURL
                ?? CodexHookTrustManager.resolveCodexExecutable()
            return try CodexAppServerSession(executableURL: executableURL)
        }
    }

    init(sessionFactory: @escaping SessionFactory) {
        self.sessionFactory = sessionFactory
    }

    func snapshot() async -> CodexUsageSnapshot? {
        do {
            let result = try activeSession().call(
                method: "account/rateLimits/read",
                params: [:]
            )
            return Self.parseSnapshot(from: result)
        } catch {
            resetSession()
            return nil
        }
    }

    static func parseSnapshot(from result: [String: Any]) -> CodexUsageSnapshot? {
        let bucket: [String: Any]?
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codexBucket = buckets["codex"] as? [String: Any] {
            bucket = codexBucket
        } else {
            bucket = result["rateLimits"] as? [String: Any]
        }

        guard let bucket else { return nil }
        let windows = [
            parseWindow(bucket["primary"], fallbackLabel: "Primary"),
            parseWindow(bucket["secondary"], fallbackLabel: "Secondary")
        ].compactMap { $0 }
        return windows.isEmpty ? nil : CodexUsageSnapshot(windows: windows)
    }

    private static func parseWindow(
        _ value: Any?,
        fallbackLabel: String
    ) -> CodexUsageSnapshot.Window? {
        guard let object = value as? [String: Any],
              let usedPercent = (object["usedPercent"] as? NSNumber)?.intValue else {
            return nil
        }
        let duration = (object["windowDurationMins"] as? NSNumber)?.intValue
        let resetTimestamp = (object["resetsAt"] as? NSNumber)?.doubleValue
        return CodexUsageSnapshot.Window(
            label: windowLabel(durationMinutes: duration, fallback: fallbackLabel),
            remainingPercent: 100 - min(max(usedPercent, 0), 100),
            resetsAt: resetTimestamp.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func windowLabel(durationMinutes: Int?, fallback: String) -> String {
        guard let durationMinutes, durationMinutes > 0 else { return fallback }
        if durationMinutes == 10_080 { return "Week" }
        if durationMinutes.isMultiple(of: 1_440) {
            return "\(durationMinutes / 1_440)d"
        }
        if durationMinutes.isMultiple(of: 60) {
            return "\(durationMinutes / 60)h"
        }
        return "\(durationMinutes)m"
    }

    private func activeSession() throws -> any CodexAppServerSessionProtocol {
        if let session { return session }
        let newSession = try sessionFactory()
        session = newSession
        return newSession
    }

    private func resetSession() {
        session?.close()
        session = nil
    }
}

@MainActor
final class CodexUsageStore: ObservableObject {
    typealias HookStatusProvider = @MainActor () -> HookInstallationStatus

    @Published private(set) var snapshot: CodexUsageSnapshot?

    private let statusProvider: HookStatusProvider
    private let reader: any CodexUsageReading
    private var refreshTask: Task<Void, Never>?

    init(
        statusProvider: @escaping HookStatusProvider,
        reader: any CodexUsageReading = CodexUsageReader(),
        initialSnapshot: CodexUsageSnapshot? = nil
    ) {
        self.statusProvider = statusProvider
        self.reader = reader
        snapshot = initialSnapshot
    }

    func refresh() {
        refreshTask?.cancel()
        guard statusProvider() == .installed else {
            snapshot = nil
            return
        }

        refreshTask = Task { [weak self, reader] in
            let latest = await reader.snapshot()
            guard !Task.isCancelled else { return }
            self?.snapshot = latest
        }
    }
}
