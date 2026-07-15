import Darwin
import Foundation
import CodingPetBridge

@main
enum CodingPetHookMain {
    private static let maximumInputSize = 65_536

    static func main() {
        guard let provider = providerArgument(),
              let input = readInput(),
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

    private static func readInput() -> Data? {
        var input = Data()
        do {
            while input.count <= maximumInputSize {
                let remaining = maximumInputSize + 1 - input.count
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
        return input.count <= maximumInputSize ? input : nil
    }

    private static func providerArgument() -> HookProvider? {
        let arguments = CommandLine.arguments.dropFirst()
        guard let flagIndex = arguments.firstIndex(of: "--provider") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex != arguments.endIndex else { return nil }
        return HookProvider(rawValue: arguments[valueIndex])
    }
}
