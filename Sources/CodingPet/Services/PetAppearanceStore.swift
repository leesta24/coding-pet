import Combine
import Foundation

@MainActor
final class PetAppearanceStore: ObservableObject {
    static let storageKey = "codingPet.appearance"
    static let animationStorageKey = "codingPet.animationsEnabled"
    static let botSizeStorageKey = "codingPet.botSize"
    static let botSizeRange: ClosedRange<Double> = 96...256
    static let defaultBotSize: Double = 128

    @Published var selection: PetAppearance {
        didSet {
            defaults.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    @Published var animationsEnabled: Bool {
        didSet {
            defaults.set(animationsEnabled, forKey: Self.animationStorageKey)
        }
    }

    struct ImportFeedback: Equatable {
        enum Kind: Equatable {
            case success
            case error
        }

        let kind: Kind
        let message: String
    }

    @Published private(set) var availableAppearances: [PetAppearance]
    @Published private(set) var botSize: Double
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: PetPackageImporter.Progress?
    @Published private(set) var importFeedback: ImportFeedback?

    private let defaults: UserDefaults
    private let localPetsDirectory: URL
    private let importer: PetPackageImporter

    init(
        defaults: UserDefaults = .standard,
        localPetsDirectory: URL = PetAppearanceStore.defaultLocalPetsDirectory,
        importer: PetPackageImporter? = nil
    ) {
        self.defaults = defaults
        self.localPetsDirectory = localPetsDirectory
        self.importer = importer ?? PetPackageImporter(petsDirectory: localPetsDirectory)
        let discoveredAppearances = Self.discoverAppearances(in: localPetsDirectory)
        availableAppearances = discoveredAppearances
        let storedID = defaults.string(forKey: Self.storageKey)
        selection = discoveredAppearances.first { $0.rawValue == storedID } ?? .xiaobao
        animationsEnabled = defaults.object(forKey: Self.animationStorageKey) as? Bool ?? true
        let storedBotSize = (defaults.object(forKey: Self.botSizeStorageKey) as? NSNumber)?.doubleValue
        botSize = Self.clampedBotSize(storedBotSize ?? Self.defaultBotSize)
        if defaults.string(forKey: Self.storageKey) != selection.rawValue {
            defaults.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    func setBotSize(_ size: Double) {
        let clampedSize = Self.clampedBotSize(size)
        guard botSize != clampedSize else { return }
        botSize = clampedSize
        defaults.set(clampedSize, forKey: Self.botSizeStorageKey)
    }

    /// Rescans the local pet library. Keeps the current selection when its package
    /// still exists (matched by id, so a replaced package with a new name stays selected).
    func reloadAvailableAppearances() {
        availableAppearances = Self.discoverAppearances(in: localPetsDirectory)
        selection = availableAppearances.first { $0.rawValue == selection.rawValue } ?? .xiaobao
    }

    /// Downloads a pet from codex-pets.net by ID or page link, adds it to the library,
    /// and selects it.
    func importPet(reference: String) async {
        await runImport { progress in
            try await importer.importPet(reference: reference, onProgress: progress)
        }
    }

    /// Installs a `.codex-pet.zip` from disk, adds it to the library, and selects it.
    func importPackage(at archiveURL: URL) async {
        await runImport { progress in
            try await importer.importPackage(at: archiveURL, onProgress: progress)
        }
    }

    private func runImport(
        _ operation: (@escaping PetPackageImporter.ProgressHandler) async throws -> URL
    ) async {
        guard !isImporting else { return }
        isImporting = true
        importFeedback = nil
        defer {
            isImporting = false
            importProgress = nil
        }
        do {
            let directory = try await operation { [weak self] progress in
                self?.importProgress = progress
            }
            reloadAvailableAppearances()
            let importedID = directory.lastPathComponent
            guard let imported = availableAppearances.first(where: { $0.rawValue == importedID }) else {
                importFeedback = ImportFeedback(
                    kind: .error,
                    message: "The pet was saved but could not be loaded."
                )
                return
            }
            selection = imported
            importFeedback = ImportFeedback(
                kind: .success,
                message: "\(imported.displayName) was added to your pet library."
            )
        } catch let error as PetPackageImporter.Error {
            importFeedback = ImportFeedback(kind: .error, message: error.localizedDescription)
        } catch {
            importFeedback = ImportFeedback(
                kind: .error,
                message: "Could not import the pet: \(error.localizedDescription)"
            )
        }
    }

    private static func discoverAppearances(in localPetsDirectory: URL) -> [PetAppearance] {
        let localAppearances = PetSpriteAtlas.localAppearances(in: localPetsDirectory)
            .filter { $0.rawValue != PetAppearance.xiaobao.rawValue }
        return [PetAppearance.xiaobao] + localAppearances
    }

    private static func clampedBotSize(_ size: Double) -> Double {
        min(max(size, botSizeRange.lowerBound), botSizeRange.upperBound)
    }

    static var defaultLocalPetsDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "CodingPet/Pets", directoryHint: .isDirectory)
    }
}
