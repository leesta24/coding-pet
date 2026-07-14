import Foundation
import Testing
@testable import CodingPet

@MainActor
struct PetAppearanceStoreTests {
    @Test
    func defaultsToXiaobaoAndPersistsLocalSelection() throws {
        let suiteName = "PetAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let localPetsDirectory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-local-pets-\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: localPetsDirectory)
        }
        try installLocalPet(
            id: "private-pet",
            displayName: "Private Pet",
            in: localPetsDirectory
        )

        let store = PetAppearanceStore(
            defaults: defaults,
            localPetsDirectory: localPetsDirectory
        )
        #expect(store.selection == .xiaobao)
        #expect(store.availableAppearances.map(\.rawValue) == ["xiaobao", "private-pet"])

        store.selection = try #require(
            store.availableAppearances.first { $0.rawValue == "private-pet" }
        )

        let restoredStore = PetAppearanceStore(
            defaults: defaults,
            localPetsDirectory: localPetsDirectory
        )
        #expect(restoredStore.selection.rawValue == "private-pet")
        #expect(restoredStore.selection.displayName == "Private Pet")
    }

    @Test
    func removedPersistedAppearanceFallsBackToXiaobao() {
        let suiteName = "PetAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("robot", forKey: PetAppearanceStore.storageKey)

        let store = PetAppearanceStore(defaults: defaults)

        #expect(store.selection == .xiaobao)
        #expect(defaults.string(forKey: PetAppearanceStore.storageKey) == "xiaobao")
    }

    @Test
    func unavailableLocalSelectionFallsBackToXiaobao() {
        let suiteName = "PetAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("private-pet", forKey: PetAppearanceStore.storageKey)

        let store = PetAppearanceStore(defaults: defaults)

        #expect(store.selection == .xiaobao)
        #expect(defaults.string(forKey: PetAppearanceStore.storageKey) == "xiaobao")
    }

    @Test
    func animationsDefaultToEnabledAndPersistWhenDisabled() {
        let suiteName = "PetAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PetAppearanceStore(defaults: defaults)
        #expect(store.animationsEnabled)

        store.animationsEnabled = false

        let restoredStore = PetAppearanceStore(defaults: defaults)
        #expect(!restoredStore.animationsEnabled)
    }

    @Test
    func botSizeDefaultsPersistsAndClampsInvalidStoredValues() {
        let suiteName = "PetAppearanceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PetAppearanceStore(defaults: defaults)
        #expect(store.botSize == PetAppearanceStore.defaultBotSize)

        store.setBotSize(112)
        #expect(PetAppearanceStore(defaults: defaults).botSize == 112)

        defaults.set(500, forKey: PetAppearanceStore.botSizeStorageKey)
        #expect(PetAppearanceStore(defaults: defaults).botSize == 160)

        defaults.set(12, forKey: PetAppearanceStore.botSizeStorageKey)
        #expect(PetAppearanceStore(defaults: defaults).botSize == 64)
    }

    private func installLocalPet(
        id: String,
        displayName: String,
        in root: URL
    ) throws {
        let source = try #require(PetSpriteAtlas.bundledPackageURL(resourceID: "xiaobao"))
        let destination = root.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        let manifestURL = destination.appending(path: "pet.json")
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        manifest["id"] = id
        manifest["displayName"] = displayName
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
            .write(to: manifestURL, options: .atomic)
    }
}
