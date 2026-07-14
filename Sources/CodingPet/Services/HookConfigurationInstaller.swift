import CryptoKit
import Foundation

enum HookConfigurationProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claudeCode
}

enum HookInstallationStatus: String, Equatable, Sendable {
    case notInstalled
    case installed
    case needsRepair
}

struct HookConfigurationInstaller {
    enum Error: Swift.Error {
        case invalidJSON
        case invalidRootObject
        case invalidHooksObject
        case invalidHookEvent(String)
        case missingBackup
        case unsupportedMetadata

        var localizedDescription: String {
            switch self {
            case .invalidJSON: "The provider configuration is not valid JSON."
            case .invalidRootObject: "The provider configuration must contain a JSON object."
            case .invalidHooksObject: "The hooks setting is not a JSON object."
            case let .invalidHookEvent(event): "The \(event) hook setting has an unsupported format."
            case .missingBackup: "The CodingPet hook backup is missing; the configuration was left unchanged."
            case .unsupportedMetadata: "The CodingPet hook installation metadata is not supported."
            }
        }
    }

    static let ownershipMarker = "CodingPet session observer"
    static let agentPeekBridgeName = "AgentPeekBridge"
    static let agentPeekHookArgument = "--bridge-hook-event"

    let provider: HookConfigurationProvider
    let configURL: URL
    let hookExecutableURL: URL

    var backupURL: URL {
        sidecarURL(suffix: "backup")
    }

    var metadataURL: URL {
        sidecarURL(suffix: "install.json")
    }

    func installationStatus() -> HookInstallationStatus {
        let fileManager = FileManager.default
        let hasMetadata = fileManager.fileExists(atPath: metadataURL.path)
        let hasBackup = fileManager.fileExists(atPath: backupURL.path)
        let hasConfig = fileManager.fileExists(atPath: configURL.path)

        guard hasMetadata || hasBackup else {
            guard hasConfig,
                  let data = try? Data(contentsOf: configURL),
                  let root = try? Self.parseRoot(data) else {
                return .notInstalled
            }
            return ownedHandlerCount(in: root) == 0 ? .notInstalled : .needsRepair
        }

        guard hasMetadata, hasBackup, hasConfig,
              let data = try? Data(contentsOf: configURL),
              let root = try? Self.parseRoot(data),
              ownedHandlerCount(in: root) == eventDefinitions.count else {
            return .needsRepair
        }
        return .installed
    }

    func validateInstall(removingAgentPeekHandlers: Bool = false) throws {
        let fileManager = FileManager.default
        let currentData = fileManager.fileExists(atPath: configURL.path)
            ? try Data(contentsOf: configURL)
            : Data("{}".utf8)
        var root = try Self.parseRoot(currentData)
        try Self.removeOwnedHandlers(from: &root)
        if removingAgentPeekHandlers {
            _ = try Self.removeAgentPeekHandlers(from: &root)
        }
        try addOwnedHandlers(to: &root)
        _ = try Self.serialize(root)

        if try loadMetadataIfPresent() != nil,
           !fileManager.fileExists(atPath: backupURL.path) {
            throw Error.missingBackup
        }
    }

    @discardableResult
    func install(removingAgentPeekHandlers: Bool = false) throws -> Int {
        try validateInstall(removingAgentPeekHandlers: removingAgentPeekHandlers)
        let fileManager = FileManager.default
        let originalExisted = fileManager.fileExists(atPath: configURL.path)
        let currentData = originalExisted ? try Data(contentsOf: configURL) : Data("{}".utf8)
        var root = try Self.parseRoot(currentData)
        try Self.removeOwnedHandlers(from: &root)
        let removedAgentPeekHandlerCount = removingAgentPeekHandlers
            ? try Self.removeAgentPeekHandlers(from: &root)
            : 0
        try addOwnedHandlers(to: &root)
        let installedData = try Self.serialize(root)

        let existingMetadata = try loadMetadataIfPresent()
        let metadata: InstallationMetadata
        if let existingMetadata {
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw Error.missingBackup
            }
            if removingAgentPeekHandlers, existingMetadata.originalExisted {
                try sanitizeAgentPeekHandlersInBackup()
            }
            metadata = InstallationMetadata(
                version: existingMetadata.version,
                originalExisted: existingMetadata.originalExisted,
                originalPermissions: existingMetadata.originalPermissions,
                installedDigest: Self.digest(installedData)
            )
        } else {
            let permissions = Self.permissions(at: writableConfigURL)
            try fileManager.createDirectory(
                at: writableConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let backupData = originalExisted && removingAgentPeekHandlers
                ? try Self.removingAgentPeekHandlers(from: currentData)
                : (originalExisted ? currentData : Data())
            try Self.writeSecure(
                backupData,
                to: backupURL,
                permissions: 0o600
            )
            metadata = InstallationMetadata(
                version: 1,
                originalExisted: originalExisted,
                originalPermissions: permissions,
                installedDigest: Self.digest(installedData)
            )
        }

        try Self.writeSecure(
            try Self.metadataEncoder.encode(metadata),
            to: metadataURL,
            permissions: 0o600
        )
        try Self.writeSecure(
            installedData,
            to: writableConfigURL,
            permissions: metadata.originalPermissions ?? 0o600
        )
        return removedAgentPeekHandlerCount
    }

    func uninstall() throws {
        let fileManager = FileManager.default
        guard let metadata = try loadMetadataIfPresent() else {
            return
        }
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw Error.missingBackup
        }

        if fileManager.fileExists(atPath: configURL.path) {
            let currentData = try Data(contentsOf: configURL)
            if Self.digest(currentData) == metadata.installedDigest {
                if metadata.originalExisted {
                    try Self.writeSecure(
                        Data(contentsOf: backupURL),
                        to: writableConfigURL,
                        permissions: metadata.originalPermissions ?? 0o600
                    )
                } else {
                    try fileManager.removeItem(at: writableConfigURL)
                }
            } else {
                var root = try Self.parseRoot(currentData)
                try Self.removeOwnedHandlers(from: &root)
                try Self.writeSecure(
                    try Self.serialize(root),
                    to: writableConfigURL,
                    permissions: Self.permissions(at: writableConfigURL) ?? 0o600
                )
            }
        }

        try? fileManager.removeItem(at: backupURL)
        try? fileManager.removeItem(at: metadataURL)
    }

    private func addOwnedHandlers(to root: inout [String: Any]) throws {
        var hooks: [String: Any]
        if let value = root["hooks"] {
            guard let existing = value as? [String: Any] else {
                throw Error.invalidHooksObject
            }
            hooks = existing
        } else {
            hooks = [:]
        }

        for definition in eventDefinitions {
            var groups: [[String: Any]]
            if let value = hooks[definition.name] {
                guard let existing = value as? [[String: Any]] else {
                    throw Error.invalidHookEvent(definition.name)
                }
                groups = existing
            } else {
                groups = []
            }

            var group: [String: Any] = ["hooks": [ownedHandler]]
            if let matcher = definition.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[definition.name] = groups
        }
        root["hooks"] = hooks
    }

    private func ownedHandlerCount(in root: [String: Any]) -> Int {
        guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                count += handlers.count {
                    $0["statusMessage"] as? String == Self.ownershipMarker
                }
            }
        }
    }

    private var ownedHandler: [String: Any] {
        switch provider {
        case .codex:
            [
                "type": "command",
                "command": "\(Self.shellQuote(hookExecutableURL.path)) --provider codex",
                "timeout": 1,
                "statusMessage": Self.ownershipMarker
            ]
        case .claudeCode:
            [
                "type": "command",
                "command": hookExecutableURL.path,
                "args": ["--provider", "claude-code"],
                "timeout": 1,
                "async": true,
                "statusMessage": Self.ownershipMarker
            ]
        }
    }

    private var eventDefinitions: [EventDefinition] {
        switch provider {
        case .codex:
            [
                EventDefinition(name: "SessionStart"),
                EventDefinition(name: "UserPromptSubmit"),
                EventDefinition(name: "PreToolUse"),
                EventDefinition(name: "PostToolUse"),
                EventDefinition(name: "PermissionRequest"),
                EventDefinition(name: "Stop"),
                EventDefinition(name: "SessionEnd")
            ]
        case .claudeCode:
            [
                EventDefinition(name: "SessionStart"),
                EventDefinition(name: "UserPromptSubmit"),
                EventDefinition(name: "PreToolUse"),
                EventDefinition(name: "PostToolUse"),
                EventDefinition(name: "PermissionRequest"),
                EventDefinition(
                    name: "Notification",
                    matcher: "permission_prompt|idle_prompt|elicitation_dialog"
                ),
                EventDefinition(name: "Stop"),
                EventDefinition(name: "StopFailure"),
                EventDefinition(name: "SessionEnd")
            ]
        }
    }

    private func loadMetadataIfPresent() throws -> InstallationMetadata? {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }
        let metadata = try Self.metadataDecoder.decode(
            InstallationMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.version == 1 else { throw Error.unsupportedMetadata }
        return metadata
    }

    private func sanitizeAgentPeekHandlersInBackup() throws {
        let backupData = try Data(contentsOf: backupURL)
        let sanitizedData = try Self.removingAgentPeekHandlers(from: backupData)
        guard sanitizedData != backupData else { return }
        try Self.writeSecure(sanitizedData, to: backupURL, permissions: 0o600)
    }

    private func sidecarURL(suffix: String) -> URL {
        configURL.deletingLastPathComponent()
            .appending(path: ".\(configURL.lastPathComponent).codingpet.\(suffix)")
    }

    private var writableConfigURL: URL {
        FileManager.default.fileExists(atPath: configURL.path)
            ? configURL.resolvingSymlinksInPath()
            : configURL
    }

    private static func parseRoot(_ data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw Error.invalidRootObject
        }
        return root
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else { throw Error.invalidJSON }
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    private static func removeOwnedHandlers(from root: inout [String: Any]) throws {
        _ = try removeHandlers(from: &root) {
            $0["statusMessage"] as? String == ownershipMarker
        }
    }

    private static func removeAgentPeekHandlers(from root: inout [String: Any]) throws -> Int {
        try removeHandlers(from: &root, matching: isAgentPeekHandler)
    }

    private static func removingAgentPeekHandlers(from data: Data) throws -> Data {
        var root = try parseRoot(data)
        let removedCount = try removeAgentPeekHandlers(from: &root)
        return removedCount == 0 ? data : try serialize(root)
    }

    private static func removeHandlers(
        from root: inout [String: Any],
        matching shouldRemove: ([String: Any]) -> Bool
    ) throws -> Int {
        guard let hooksValue = root["hooks"] else { return 0 }
        guard var hooks = hooksValue as? [String: Any] else {
            throw Error.invalidHooksObject
        }

        var removedCount = 0

        for eventName in Array(hooks.keys) {
            guard let groups = hooks[eventName] as? [[String: Any]] else {
                throw Error.invalidHookEvent(eventName)
            }
            var retainedGroups: [[String: Any]] = []
            for var group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    throw Error.invalidHookEvent(eventName)
                }
                let retainedHandlers = handlers.filter { handler in
                    let remove = shouldRemove(handler)
                    if remove { removedCount += 1 }
                    return !remove
                }
                guard !retainedHandlers.isEmpty else { continue }
                group["hooks"] = retainedHandlers
                retainedGroups.append(group)
            }
            if retainedGroups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = retainedGroups
            }
        }
        root["hooks"] = hooks
        return removedCount
    }

    private static func isAgentPeekHandler(_ handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String,
              command.contains(agentPeekBridgeName) else {
            return false
        }
        if command.contains(agentPeekHookArgument) {
            return true
        }
        return (handler["args"] as? [String])?.contains(agentPeekHookArgument) == true
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func permissions(at url: URL) -> UInt16? {
        guard let number = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? NSNumber else {
            return nil
        }
        return number.uint16Value
    }

    private static func writeSecure(_ data: Data, to url: URL, permissions: UInt16) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let metadataDecoder = JSONDecoder()
}

private struct EventDefinition {
    let name: String
    let matcher: String?

    init(name: String, matcher: String? = nil) {
        self.name = name
        self.matcher = matcher
    }
}

private struct InstallationMetadata: Codable {
    let version: Int
    let originalExisted: Bool
    let originalPermissions: UInt16?
    let installedDigest: String
}
