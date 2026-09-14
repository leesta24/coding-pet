import Darwin
import Foundation
import CodingPetBridge

@main
enum CodingPetHookMain {
    private static let maximumInputSize = 65_536
    private static let maximumStatusLineInputSize = 262_144
    static let statusLineArgument = "--statusline"

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == statusLineArgument {
            runStatusLine(passthroughCommand: passthroughCommand(in: arguments))
            return
        }
        if arguments.first == reportClaudeUsageArgument, arguments.count == 3 {
            reportClaudeUsage(
                sessionID: arguments[1],
                cwd: arguments[2],
                environment: ProcessInfo.processInfo.environment
            )
            return
        }

        guard let provider = providerArgument(),
              let input = readInput(limit: maximumInputSize),
              let event = try? HookEventSanitizer.sanitize(
                  input,
                  provider: provider,
                  parentProcessID: getppid(),
                  environment: ProcessInfo.processInfo.environment
              ) else {
            return
        }

        // Persist the already-sanitized routing envelope first so sessions can
        // be recovered when CodingPet is relaunched. Both operations are best
        // effort and never affect the agent command's exit status.
        HookEventSnapshotStore().persist(event)
        HookSocketClient.send(event)
        spawnClaudeUsageReportIfDue(after: event, environment: ProcessInfo.processInfo.environment)
    }

    static let reportClaudeUsageArgument = "--report-claude-usage"

    /// Claude Desktop hands its sessions an OAuth token through the environment,
    /// which hook processes inherit. The network lookup runs in a detached copy
    /// of this executable so the hook itself still exits immediately; the token
    /// travels only through the inherited environment, never on the command line.
    private static func spawnClaudeUsageReportIfDue(
        after event: HookEventEnvelope,
        environment: [String: String]
    ) {
        guard event.provider == .claudeCode,
              event.eventName == "Stop" || event.eventName == "SessionStart",
              let token = environment[ClaudeUsageEndpoint.tokenEnvironmentKey],
              !token.isEmpty,
              FileManager.default.fileExists(atPath: HookSocketAddress.defaultPath),
              ClaudeUsageEndpoint.claimAttempt(),
              let executableURL = Bundle.main.executableURL else {
            return
        }
        let reporter = Process()
        reporter.executableURL = executableURL
        reporter.arguments = [reportClaudeUsageArgument, event.sessionID, event.cwd]
        reporter.standardInput = FileHandle.nullDevice
        reporter.standardOutput = FileHandle.nullDevice
        reporter.standardError = FileHandle.nullDevice
        try? reporter.run()
    }

    private static func reportClaudeUsage(
        sessionID: String,
        cwd: String,
        environment: [String: String]
    ) {
        guard let token = environment[ClaudeUsageEndpoint.tokenEnvironmentKey],
              !token.isEmpty else {
            return
        }

        let completion = DispatchSemaphore(value: 0)
        var body: Data?
        let task = URLSession.shared.dataTask(
            with: ClaudeUsageEndpoint.request(token: token)
        ) { data, response, _ in
            if let status = (response as? HTTPURLResponse)?.statusCode,
               (200..<300).contains(status) {
                body = data
            }
            completion.signal()
        }
        task.resume()
        guard completion.wait(timeout: .now() + 9) == .success,
              let body,
              let limits = ClaudeUsageEndpoint.rateLimits(from: body) else {
            return
        }

        HookSocketClient.send(HookEventEnvelope(
            provider: .claudeCode,
            eventName: StatusLinePayloadParser.eventName,
            timestamp: .now,
            parentProcessID: nil,
            sessionID: sessionID,
            cwd: cwd,
            rateLimits: limits
        ))
    }

    /// Status line mode: forward Claude Code's usage windows to CodingPet, then
    /// hand the untouched JSON to the user's original status line command so
    /// their status bar keeps rendering exactly as before.
    private static func runStatusLine(passthroughCommand: String?) {
        let input = readInput(limit: maximumStatusLineInputSize) ?? Data()
        if let event = StatusLinePayloadParser.envelope(from: input) {
            HookSocketClient.send(event)
        }
        guard let passthroughCommand else { return }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", passthroughCommand]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            Darwin.exit(1)
        }
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        Darwin.exit(process.terminationStatus)
    }

    /// Everything after `--` is the original status line command.
    private static func passthroughCommand(in arguments: [String]) -> String? {
        guard let separator = arguments.firstIndex(of: "--") else { return nil }
        let command = arguments[arguments.index(after: separator)...].joined(separator: " ")
        return command.isEmpty ? nil : command
    }

    private static func readInput(limit: Int) -> Data? {
        var input = Data()
        do {
            while input.count <= limit {
                let remaining = limit + 1 - input.count
                guard let chunk = try FileHandle.standardInput.read(
                    upToCount: min(8_192, remaining)
                ) else {
                    break
                }
                if chunk.isEmpty { break }
                input.append(chunk)
            }
        } catch {
            return nil
        }
        return input.count <= limit ? input : nil
    }

    private static func providerArgument() -> HookProvider? {
        let arguments = CommandLine.arguments.dropFirst()
        guard let flagIndex = arguments.firstIndex(of: "--provider") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex != arguments.endIndex else { return nil }
        return HookProvider(rawValue: arguments[valueIndex])
    }
}
