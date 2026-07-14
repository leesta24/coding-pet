import AppKit
import Foundation

struct PetSpriteManifest: Decodable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
}

struct PetSpriteAnimation: Equatable {
    let row: Int
    let frameDurations: [TimeInterval]

    var totalDuration: TimeInterval {
        frameDurations.reduce(0, +)
    }

    func frameIndex(elapsed: TimeInterval) -> Int {
        guard !frameDurations.isEmpty, totalDuration > 0 else { return 0 }
        var position = elapsed.truncatingRemainder(dividingBy: totalDuration)
        if position < 0 { position += totalDuration }
        for (index, duration) in frameDurations.enumerated() {
            if position < duration { return index }
            position -= duration
        }
        return frameDurations.count - 1
    }

    static func animation(for state: BotState) -> Self {
        switch state {
        case .idle:
            Self(row: 0, milliseconds: [7_000, 110, 110, 140, 140, 320])
        case .blocked:
            Self(row: 5, milliseconds: [140, 140, 140, 140, 140, 140, 140, 240])
        case .needsInput:
            Self(row: 6, milliseconds: [150, 150, 150, 150, 150, 260])
        case .running:
            Self(row: 7, milliseconds: [120, 120, 120, 120, 120, 220])
        case .ready:
            Self(row: 8, milliseconds: [150, 150, 150, 150, 150, 280])
        }
    }

    private init(row: Int, milliseconds: [Int]) {
        self.row = row
        frameDurations = milliseconds.map { TimeInterval($0) / 1_000 }
    }
}

@MainActor
final class PetSpriteAtlas {
    enum Error: Swift.Error {
        case missingManifest
        case invalidManifest
        case missingSpritesheet
        case invalidDimensions
    }

    static let columns = 8
    static let rows = 11
    static let cellWidth = 192
    static let cellHeight = 208

    private static var cache: [PetAppearance: PetSpriteAtlas] = [:]

    static func available(for appearance: PetAppearance) -> PetSpriteAtlas? {
        if let cached = cache[appearance] {
            return cached
        }
        let atlas: PetSpriteAtlas?
        switch appearance.source {
        case .bundled:
            atlas = try? PetSpriteAtlas(resourceID: appearance.rawValue)
        case let .local(directory):
            atlas = try? PetSpriteAtlas(packageDirectory: directory)
        }
        if let atlas {
            cache[appearance] = atlas
        }
        return atlas
    }

    static func bundledPackageURL(
        resourceID: String,
        bundle: Bundle? = nil
    ) -> URL? {
        let resolvedBundle = bundle ?? AppBundlePaths.packagedPetResourceBundle ?? .module
        return resolvedBundle.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "Pets/\(resourceID)"
        )?.deletingLastPathComponent()
    }

    static func localAppearances(in root: URL) -> [PetAppearance] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return directories.compactMap { directory in
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true,
                  let atlas = try? PetSpriteAtlas(packageDirectory: directory) else {
                return nil
            }
            let appearance = PetAppearance.local(
                id: atlas.manifest.id,
                displayName: atlas.manifest.displayName,
                directory: directory
            )
            cache[appearance] = atlas
            return appearance
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    let manifest: PetSpriteManifest
    let pixelWidth: Int
    let pixelHeight: Int

    private let sourceImage: CGImage
    private var frames: [Int: NSImage] = [:]

    convenience init(resourceID: String, bundle: Bundle? = nil) throws {
        guard let packageDirectory = Self.bundledPackageURL(
            resourceID: resourceID,
            bundle: bundle
        ) else {
            throw Error.missingManifest
        }
        try self.init(packageDirectory: packageDirectory, expectedID: resourceID)
    }

    convenience init(packageDirectory: URL) throws {
        try self.init(
            packageDirectory: packageDirectory,
            expectedID: packageDirectory.lastPathComponent
        )
    }

    private init(packageDirectory: URL, expectedID: String) throws {
        let manifestURL = packageDirectory.appending(path: "pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Error.missingManifest
        }
        guard let manifest = try? JSONDecoder().decode(
            PetSpriteManifest.self,
            from: Data(contentsOf: manifestURL)
        ), manifest.id == expectedID, manifest.spriteVersionNumber == 2 else {
            throw Error.invalidManifest
        }
        let spritesheetURL = manifestURL.deletingLastPathComponent()
            .appending(path: manifest.spritesheetPath)
        guard let image = NSImage(contentsOf: spritesheetURL),
              let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Error.missingSpritesheet
        }
        guard sourceImage.width == Self.columns * Self.cellWidth,
              sourceImage.height == Self.rows * Self.cellHeight else {
            throw Error.invalidDimensions
        }

        self.manifest = manifest
        self.sourceImage = sourceImage
        pixelWidth = sourceImage.width
        pixelHeight = sourceImage.height
    }

    func frame(row: Int, column: Int) -> NSImage? {
        guard (0..<Self.rows).contains(row),
              (0..<Self.columns).contains(column) else {
            return nil
        }
        let key = row * Self.columns + column
        if let cached = frames[key] { return cached }
        let rect = CGRect(
            x: column * Self.cellWidth,
            y: row * Self.cellHeight,
            width: Self.cellWidth,
            height: Self.cellHeight
        )
        guard let cropped = sourceImage.cropping(to: rect) else { return nil }
        let image = NSImage(
            cgImage: cropped,
            size: NSSize(width: Self.cellWidth, height: Self.cellHeight)
        )
        frames[key] = image
        return image
    }
}
