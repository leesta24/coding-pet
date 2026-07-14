import Foundation

/// A metadata-only last-event cache used to bridge short periods where the UI
/// process is not running. The stored envelope never contains prompts, model
/// responses, tool arguments, or tool output.
public struct HookEventSnapshotStore: Sendable {
    public static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodingPet/SessionEvents", directoryHint: .isDirectory)
    }

    private let directoryURL: URL

    public init(directoryURL: URL = Self.defaultDirectoryURL) {
        self.directoryURL = directoryURL
    }

    @discardableResult
    public func persist(_ event: HookEventEnvelope) -> Bool {
        guard event.protocolVersion == HookEventEnvelope.currentProtocolVersion else {
            return false
        }
        if event.clearsActiveSession {
            return removeSnapshot(unlessNewerThan: event)
        }
        guard let data = try? HookEventCodec.encode(event) else { return false }

        do {
            try ensureDirectory()
            let url = snapshotURL(provider: event.provider, sessionID: event.sessionID)
            if let data = try? Data(contentsOf: url),
               let existing = try? HookEventCodec.decode(data),
               existing.timestamp > event.timestamp {
                return true
            }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: UInt16(0o600))],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }

    public func snapshots() -> [HookEventEnvelope] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  size <= 16_384,
                  let data = try? Data(contentsOf: url),
                  let event = try? HookEventCodec.decode(data),
                  event.protocolVersion == HookEventEnvelope.currentProtocolVersion else {
                return nil
            }
            return event
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    @discardableResult
    public func remove(provider: HookProvider, sessionID: String) -> Bool {
        let url = snapshotURL(provider: provider, sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private func removeSnapshot(unlessNewerThan event: HookEventEnvelope) -> Bool {
        let url = snapshotURL(provider: event.provider, sessionID: event.sessionID)
        if let data = try? Data(contentsOf: url),
           let existing = try? HookEventCodec.decode(data),
           existing.timestamp > event.timestamp {
            return true
        }
        return remove(provider: event.provider, sessionID: event.sessionID)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: directoryURL.path
        )
    }

    private func snapshotURL(provider: HookProvider, sessionID: String) -> URL {
        let routingKey = "\(provider.rawValue):\(sessionID)"
        let encodedKey = Data(routingKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appending(path: "\(encodedKey).json")
    }
}
