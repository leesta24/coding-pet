import Darwin
import Foundation

struct CodexHookSnapshot {
    let agentPeekKeys: Set<String>
    let codingPetKeys: Set<String>
}

struct CodexHookActivationReport {
    let trustedHookCount: Int
    let removedAgentPeekStateCount: Int
}

struct CodexHookTrustManager {
    enum Error: LocalizedError {
        case codexExecutableUnavailable
        case malformedResponse(String)
        case codingPetHooksMissing(expected: Int, found: Int)
        case trustVerificationFailed

        var errorDescription: String? {
            switch self {
            case .codexExecutableUnavailable:
                "Codex CLI was not found. Install Codex CLI or set CODEX_CLI_PATH."
            case let .malformedResponse(method):
                "Codex app-server returned an unexpected response for \(method)."
            case let .codingPetHooksMissing(expected, found):
                "Codex found \(found) of \(expected) CodingPet hooks after installation."
            case .trustVerificationFailed:
                "Codex did not mark every CodingPet hook as trusted."
            }
        }
    }

    private let sessionFactory: () throws -> any CodexAppServerSessionProtocol

    init(codexExecutableURL: URL? = nil) {
        sessionFactory = {
            let executableURL = try codexExecutableURL ?? Self.resolveCodexExecutable()
            return try CodexAppServerSession(executableURL: executableURL)
        }
    }

    init(sessionFactory: @escaping () throws -> any CodexAppServerSessionProtocol) {
        self.sessionFactory = sessionFactory
    }

    func snapshot(cwd: URL) throws -> CodexHookSnapshot {
        let session = try sessionFactory()
        defer { session.close() }
        let hooks = try listHooks(session: session, cwd: cwd)
        return CodexHookSnapshot(
            agentPeekKeys: Set(hooks.filter(\.isAgentPeek).map(\.key)),
            codingPetKeys: Set(hooks.filter(\.isCodingPet).map(\.key))
        )
    }

    func activateCodingPetHooks(
        cwd: URL,
        removingAgentPeekKeys agentPeekKeys: Set<String>
    ) throws -> CodexHookActivationReport {
        let session = try sessionFactory()
        defer { session.close() }

        let hooks = try listHooks(session: session, cwd: cwd)
        let codingPetHooks = hooks.filter(\.isCodingPet)
        // SessionEnd is accepted in hooks.json but is not returned by the
        // current Codex hooks/list trust surface. The other six configured
        // Codex hook commands must all be present and explicitly trusted.
        let expectedHookCount = 6
        guard codingPetHooks.count == expectedHookCount else {
            throw Error.codingPetHooksMissing(
                expected: expectedHookCount,
                found: codingPetHooks.count
            )
        }

        var hookState = try readHookState(session: session)
        let removedAgentPeekStateCount = agentPeekKeys.reduce(into: 0) { count, key in
            if hookState[key] != nil { count += 1 }
        }
        for key in agentPeekKeys {
            hookState.removeValue(forKey: key)
        }
        for hook in codingPetHooks {
            hookState[hook.key] = ["trusted_hash": hook.currentHash]
        }
        try replaceHookState(hookState, session: session)

        let verifiedHooks = try listHooks(session: session, cwd: cwd)
        let verifiedByKey = Dictionary(uniqueKeysWithValues: verifiedHooks.map { ($0.key, $0) })
        guard codingPetHooks.allSatisfy({ verifiedByKey[$0.key]?.trustStatus == "trusted" }) else {
            throw Error.trustVerificationFailed
        }

        return CodexHookActivationReport(
            trustedHookCount: codingPetHooks.count,
            removedAgentPeekStateCount: removedAgentPeekStateCount
        )
    }

    func removeTrustedHookKeys(_ keys: Set<String>) throws {
        guard !keys.isEmpty else { return }
        let session = try sessionFactory()
        defer { session.close() }
        var hookState = try readHookState(session: session)
        for key in keys {
            hookState.removeValue(forKey: key)
        }
        try replaceHookState(hookState, session: session)
    }

    private func listHooks(
        session: any CodexAppServerSessionProtocol,
        cwd: URL
    ) throws -> [CodexHookRecord] {
        let result = try session.call(
            method: "hooks/list",
            params: ["cwds": [cwd.path]]
        )
        guard let data = result["data"] as? [[String: Any]] else {
            throw Error.malformedResponse("hooks/list")
        }
        return try data.flatMap { item -> [CodexHookRecord] in
            guard let hooks = item["hooks"] as? [[String: Any]] else {
                throw Error.malformedResponse("hooks/list")
            }
            return try hooks.map { hook in
                guard let key = hook["key"] as? String,
                      let command = hook["command"] as? String,
                      let currentHash = hook["currentHash"] as? String,
                      let trustStatus = hook["trustStatus"] as? String else {
                    throw Error.malformedResponse("hooks/list")
                }
                return CodexHookRecord(
                    key: key,
                    command: command,
                    currentHash: currentHash,
                    trustStatus: trustStatus,
                    statusMessage: hook["statusMessage"] as? String
                )
            }
        }
    }

    private func readHookState(
        session: any CodexAppServerSessionProtocol
    ) throws -> [String: Any] {
        let result = try session.call(method: "config/read", params: [:])
        guard let config = result["config"] as? [String: Any] else {
            throw Error.malformedResponse("config/read")
        }
        guard let hooks = config["hooks"] as? [String: Any] else { return [:] }
        guard let state = hooks["state"] else { return [:] }
        guard let stateObject = state as? [String: Any] else {
            throw Error.malformedResponse("config/read")
        }
        return stateObject
    }

    private func replaceHookState(
        _ state: [String: Any],
        session: any CodexAppServerSessionProtocol
    ) throws {
        _ = try session.call(
            method: "config/batchWrite",
            params: [
                "edits": [[
                    "keyPath": "hooks.state",
                    "value": state,
                    "mergeStrategy": "replace"
                ]],
                "reloadUserConfig": true
            ]
        )
    }

    static func resolveCodexExecutable() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configuredPath = environment["CODEX_CLI_PATH"], !configuredPath.isEmpty {
            candidates.append(configuredPath)
        }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        candidates += (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" }

        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        throw Error.codexExecutableUnavailable
    }
}

private struct CodexHookRecord {
    let key: String
    let command: String
    let currentHash: String
    let trustStatus: String
    let statusMessage: String?

    var isAgentPeek: Bool {
        command.contains(HookConfigurationInstaller.agentPeekBridgeName)
            && command.contains(HookConfigurationInstaller.agentPeekHookArgument)
    }

    var isCodingPet: Bool {
        statusMessage == HookConfigurationInstaller.ownershipMarker
    }
}

protocol CodexAppServerSessionProtocol: AnyObject {
    func call(method: String, params: [String: Any]) throws -> [String: Any]
    func close()
}

final class CodexAppServerSession: CodexAppServerSessionProtocol {
    enum Error: LocalizedError {
        case timedOut(String)
        case streamClosed
        case invalidResponse
        case server(code: Int?, message: String)

        var errorDescription: String? {
            switch self {
            case let .timedOut(method):
                "Codex app-server timed out while calling \(method)."
            case .streamClosed:
                "Codex app-server closed its response stream."
            case .invalidResponse:
                "Codex app-server returned invalid JSON."
            case let .server(code, message):
                code.map { "Codex app-server error \($0): \(message)" } ?? message
            }
        }
    }

    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let inputWriter: CodexAppServerInputWriter
    private let responses = CodexAppServerResponseBuffer()
    private let timeout: TimeInterval
    private var nextRequestID = 1
    private var isClosed = false

    init(executableURL: URL, timeout: TimeInterval = 5) throws {
        self.timeout = timeout
        inputWriter = try CodexAppServerInputWriter(
            fileHandle: inputPipe.fileHandleForWriting
        )
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [responses] handle in
            let data = handle.availableData
            data.isEmpty ? responses.markClosed() : responses.append(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            _ = try call(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "coding-pet",
                        "title": "CodingPet",
                        "version": "0.1.0"
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            )
            try send(["method": "initialized", "params": [:]])
        } catch {
            close()
            throw error
        }
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        let requestID = nextRequestID
        nextRequestID += 1
        try send(["id": requestID, "method": method, "params": params])
        guard let response = try responses.wait(for: requestID, timeout: timeout) else {
            throw Error.timedOut(method)
        }
        if let error = response["error"] as? [String: Any] {
            throw Error.server(
                code: (error["code"] as? NSNumber)?.intValue,
                message: error["message"] as? String ?? "Codex app-server request failed."
            )
        }
        guard let result = response["result"] as? [String: Any] else {
            throw Error.invalidResponse
        }
        return result
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        inputWriter.close()
        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        close()
    }

    private func send(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw Error.invalidResponse
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputWriter.write(data)
    }
}

/// Serializes app-server stdin writes with close and avoids Foundation's
/// `FileHandle.write` crash when the child process has already closed its end
/// of the pipe. `F_SETNOSIGPIPE` converts that lifecycle boundary into EPIPE,
/// which the existing reconnect and fail-closed paths can handle normally.
final class CodexAppServerInputWriter: @unchecked Sendable {
    enum Error: Swift.Error {
        case closed
    }

    private let fileHandle: FileHandle
    private let descriptor: Int32
    private let lock = NSLock()
    private var isClosed = false

    init(fileHandle: FileHandle) throws {
        self.fileHandle = fileHandle
        descriptor = fileHandle.fileDescriptor
        guard fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw Self.posixError()
        }
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            guard !isClosed else { throw Error.closed }
            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                var written = 0
                while written < bytes.count {
                    let result = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: written),
                        bytes.count - written
                    )
                    if result > 0 {
                        written += result
                    } else if result == -1, errno == EINTR {
                        continue
                    } else {
                        throw Self.posixError()
                    }
                }
            }
        }
    }

    func close() {
        lock.withLock {
            guard !isClosed else { return }
            isClosed = true
            try? fileHandle.close()
        }
    }

    deinit {
        close()
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private final class CodexAppServerResponseBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private var bufferedData = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var isClosed = false

    func append(_ data: Data) {
        condition.lock()
        bufferedData.append(data)
        while let newlineIndex = bufferedData.firstIndex(of: 0x0A) {
            let line = bufferedData[..<newlineIndex]
            bufferedData.removeSubrange(...newlineIndex)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let response = object as? [String: Any],
                  let requestID = (response["id"] as? NSNumber)?.intValue else {
                continue
            }
            responses[requestID] = response
        }
        condition.broadcast()
        condition.unlock()
    }

    func markClosed() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(for requestID: Int, timeout: TimeInterval) throws -> [String: Any]? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while responses[requestID] == nil, !isClosed {
            guard condition.wait(until: deadline) else { break }
        }
        if let response = responses.removeValue(forKey: requestID) {
            return response
        }
        if isClosed {
            throw CodexAppServerSession.Error.streamClosed
        }
        return nil
    }
}
