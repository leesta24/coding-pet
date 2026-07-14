import Combine
import Foundation

@MainActor
final class PetAppearanceStore: ObservableObject {
    static let storageKey = "codingPet.appearance"
    static let animationStorageKey = "codingPet.animationsEnabled"
    static let botSizeStorageKey = "codingPet.botSize"
    static let botSizeRange: ClosedRange<Double> = 64...160
    static let defaultBotSize: Double = 84

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

    @Published private(set) var availableAppearances: [PetAppearance]
    @Published private(set) var botSize: Double

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        localPetsDirectory: URL = PetAppearanceStore.defaultLocalPetsDirectory
    ) {
        self.defaults = defaults
        let localAppearances = PetSpriteAtlas.localAppearances(in: localPetsDirectory)
            .filter { $0.rawValue != PetAppearance.xiaobao.rawValue }
        let discoveredAppearances = [PetAppearance.xiaobao] + localAppearances
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
