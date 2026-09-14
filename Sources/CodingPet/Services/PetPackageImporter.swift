import Foundation

/// Imports v2 pet packages (`pet.json` + `spritesheet.webp`) into the local pet
/// library, either from a `.codex-pet.zip` on disk or from a codex-pets.net pet
/// page. Network access happens only inside `importPet(reference:)`, which the
/// user starts explicitly.
@MainActor
struct PetPackageImporter {
    enum Error: Swift.Error, Equatable {
        case invalidReference
        case petNotFound(String)
        case serverError(Int)
        case untrustedDownloadHost
        case unexpectedResponse
        case extractionFailed
        case invalidPackage(String)

        var localizedDescription: String {
            switch self {
            case .invalidReference:
                "Enter a pet ID or a codex-pets.net pet link."
            case let .petNotFound(id):
                "No pet named “\(id)” was found on codex-pets.net."
            case let .serverError(status):
                "codex-pets.net responded with HTTP \(status)."
            case .untrustedDownloadHost:
                "The download link did not point at codex-pets.net."
            case .unexpectedResponse:
                "codex-pets.net returned an unexpected response."
            case .extractionFailed:
                "The archive could not be unpacked."
            case let .invalidPackage(reason):
                "The archive is not a valid v2 pet package: \(reason)"
            }
        }
    }

    struct Progress: Equatable, Sendable {
        enum Stage: Equatable, Sendable {
            case lookingUp
            case downloading
            case installing
        }

        let stage: Stage
        /// 0...1 while downloading with a known size; nil when indeterminate.
        let fraction: Double?

        var title: String {
            switch stage {
            case .lookingUp: "Looking up pet…"
            case .downloading:
                if let fraction {
                    "Downloading… \(Int((fraction * 100).rounded()))%"
                } else {
                    "Downloading…"
                }
            case .installing: "Installing…"
            }
        }
    }

    typealias ProgressHandler = @MainActor @Sendable (Progress) -> Void
    /// Reports bytes received so far and the expected total when known.
    typealias ByteProgressHandler = @Sendable (_ received: Int64, _ expected: Int64?) -> Void
    /// Returns the downloaded bytes and the HTTP status (200 for non-HTTP responses).
    typealias DataLoader = @Sendable (URL, ByteProgressHandler) async throws -> (data: Data, statusCode: Int)

    static let siteBaseURL = URL(string: "https://codex-pets.net")!

    let petsDirectory: URL
    let baseURL: URL
    let loader: DataLoader

    init(
        petsDirectory: URL = PetAppearanceStore.defaultLocalPetsDirectory,
        baseURL: URL = PetPackageImporter.siteBaseURL,
        loader: @escaping DataLoader = PetPackageImporter.defaultLoader
    ) {
        self.petsDirectory = petsDirectory
        self.baseURL = baseURL
        self.loader = loader
    }

    /// Accepts a bare pet ID or a codex-pets.net link such as
    /// `https://codex-pets.net/#/pets/<id>` or `/api/pets/<id>/download`.
    static func petID(fromReference reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("/") || trimmed.contains(".") else {
            return isValidPetID(trimmed) ? trimmed : nil
        }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              components.host?.lowercased() == siteBaseURL.host else {
            return nil
        }
        // Hash routes (`#/pets/<id>`) live in the fragment; API links in the path.
        let route = components.fragment ?? components.path
        let segments = route.split(separator: "?").first?
            .split(separator: "/").map(String.init) ?? []
        guard let petsIndex = segments.firstIndex(of: "pets"),
              petsIndex + 1 < segments.count else {
            return nil
        }
        let candidate = segments[petsIndex + 1].removingPercentEncoding ?? segments[petsIndex + 1]
        return isValidPetID(candidate) ? candidate : nil
    }

    static func isValidPetID(_ id: String) -> Bool {
        guard (1...64).contains(id.count), id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
    }

    /// Downloads the pet named by `reference` from codex-pets.net and installs it.
    /// Returns the installed package directory.
    func importPet(
        reference: String,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> URL {
        guard let id = Self.petID(fromReference: reference) else {
            throw Error.invalidReference
        }

        onProgress(Progress(stage: .lookingUp, fraction: nil))
        let metadataURL = baseURL.appending(path: "api/pets/\(id)")
        let metadata = try await loader(metadataURL) { _, _ in }
        switch metadata.statusCode {
        case 200..<300: break
        case 404: throw Error.petNotFound(id)
        default: throw Error.serverError(metadata.statusCode)
        }
        guard let downloadPath = try? JSONDecoder().decode(PetMetadata.self, from: metadata.data).resolvedDownloadURL,
              let downloadURL = URL(string: downloadPath, relativeTo: baseURL)?.absoluteURL else {
            throw Error.unexpectedResponse
        }
        guard downloadURL.host?.lowercased() == baseURL.host?.lowercased() else {
            throw Error.untrustedDownloadHost
        }

        onProgress(Progress(stage: .downloading, fraction: nil))
        let archive = try await loader(downloadURL) { received, expected in
            guard let expected, expected > 0 else { return }
            let fraction = min(Double(received) / Double(expected), 1)
            Task { @MainActor in
                onProgress(Progress(stage: .downloading, fraction: fraction))
            }
        }
        guard (200..<300).contains(archive.statusCode) else {
            throw Error.serverError(archive.statusCode)
        }

        onProgress(Progress(stage: .installing, fraction: nil))
        let stage = try Self.makeStageDirectory()
        defer { try? FileManager.default.removeItem(at: stage) }
        let archiveURL = stage.appending(path: "\(id).codex-pet.zip")
        try archive.data.write(to: archiveURL)
        return try await install(archiveURL: archiveURL, expectedID: id, stage: stage)
    }

    /// Installs a `.codex-pet.zip` already on disk. Returns the installed package directory.
    func importPackage(
        at archiveURL: URL,
        onProgress: ProgressHandler = { _ in }
    ) async throws -> URL {
        onProgress(Progress(stage: .installing, fraction: nil))
        let stage = try Self.makeStageDirectory()
        defer { try? FileManager.default.removeItem(at: stage) }
        return try await install(archiveURL: archiveURL, expectedID: nil, stage: stage)
    }

    private func install(archiveURL: URL, expectedID: String?, stage: URL) async throws -> URL {
        let fileManager = FileManager.default
        let extracted = stage.appending(path: "extracted", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        try await Self.unzip(archiveURL, into: extracted)

        guard let packageDirectory = Self.packageDirectory(in: extracted) else {
            throw Error.invalidPackage("pet.json was not found.")
        }
        let manifestData = try Data(contentsOf: packageDirectory.appending(path: "pet.json"))
        guard let manifest = try? JSONDecoder().decode(PetSpriteManifest.self, from: manifestData) else {
            throw Error.invalidPackage("pet.json could not be read.")
        }
        guard Self.isValidPetID(manifest.id) else {
            throw Error.invalidPackage("pet.json has an invalid id.")
        }
        if let expectedID, manifest.id != expectedID {
            throw Error.invalidPackage("pet.json id “\(manifest.id)” does not match “\(expectedID)”.")
        }

        // PetSpriteAtlas requires the directory name to match the manifest id.
        let validated = stage.appending(path: "validated", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: validated, withIntermediateDirectories: true)
        let candidate = validated.appending(path: manifest.id, directoryHint: .isDirectory)
        try fileManager.moveItem(at: packageDirectory, to: candidate)
        do {
            _ = try PetSpriteAtlas(packageDirectory: candidate)
        } catch let error as PetSpriteAtlas.Error {
            throw Error.invalidPackage(Self.reason(for: error))
        }

        try fileManager.createDirectory(at: petsDirectory, withIntermediateDirectories: true)
        let destination = petsDirectory.appending(path: manifest.id, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: candidate, to: destination)
        return destination
    }

    private static func reason(for error: PetSpriteAtlas.Error) -> String {
        switch error {
        case .missingManifest: "pet.json was not found."
        case .invalidManifest: "pet.json must declare spriteVersionNumber 1 or 2."
        case .missingSpritesheet: "the spritesheet image could not be loaded."
        case .invalidDimensions:
            "the spritesheet must be \(PetSpriteAtlas.columns) columns of \(PetSpriteAtlas.cellWidth)x\(PetSpriteAtlas.cellHeight) frames with \(PetSpriteAtlas.legacyRows) (v1) or \(PetSpriteAtlas.rows) (v2) rows."
        }
    }

    private static func makeStageDirectory() throws -> URL {
        let stage = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        return stage
    }

    private static func unzip(_ archiveURL: URL, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", archiveURL.path, "-d", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw Error.extractionFailed }
    }

    /// The package root is either the archive root or its single top-level folder.
    private static func packageDirectory(in extracted: URL) -> URL? {
        let fileManager = FileManager.default
        let hasManifest = { (directory: URL) in
            fileManager.fileExists(atPath: directory.appending(path: "pet.json").path)
        }
        if hasManifest(extracted) { return extracted }
        let folders = ((try? fileManager.contentsOfDirectory(
            at: extracted,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter {
            $0.lastPathComponent != "__MACOSX"
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        guard folders.count == 1, hasManifest(folders[0]) else { return nil }
        return folders[0]
    }

    private static let defaultLoader: DataLoader = { url, onBytes in
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expected = response.expectedContentLength
        let expectedLength: Int64? = expected > 0 ? expected : nil
        var data = Data()
        if let expectedLength {
            data.reserveCapacity(Int(expectedLength))
        }
        var reportedAt: Int64 = 0
        let reportStep: Int64 = 64 * 1024
        for try await byte in bytes {
            data.append(byte)
            let received = Int64(data.count)
            if received - reportedAt >= reportStep {
                reportedAt = received
                onBytes(received, expectedLength)
            }
        }
        onBytes(Int64(data.count), expectedLength)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// `/api/pets/<id>` wraps the pet in a `pet` object; list entries are flat.
    private struct PetMetadata: Decodable {
        struct Pet: Decodable {
            let downloadUrl: String?
        }

        let pet: Pet?
        let downloadUrl: String?

        var resolvedDownloadURL: String? {
            pet?.downloadUrl ?? downloadUrl
        }
    }
}
