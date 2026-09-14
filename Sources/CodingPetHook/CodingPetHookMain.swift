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
