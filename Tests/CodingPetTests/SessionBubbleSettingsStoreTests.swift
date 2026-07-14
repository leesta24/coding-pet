import Foundation
import Testing
@testable import CodingPet

@MainActor
struct SessionBubbleSettingsStoreTests {
    @Test
    func bubblePreferencesDefaultToEnabledAndPersistIndependently() {
        let suiteName = "SessionBubbleSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionBubbleSettingsStore(defaults: defaults)
        #expect(store.runningBubblesEnabled)
        #expect(store.pendingBubblesEnabled)
        #expect(store.readyBubblesEnabled)

        store.runningBubblesEnabled = false

        let restored = SessionBubbleSettingsStore(defaults: defaults)
        #expect(!restored.runningBubblesEnabled)
        #expect(restored.pendingBubblesEnabled)
        #expect(restored.readyBubblesEnabled)

        restored.pendingBubblesEnabled = false

        let restoredAgain = SessionBubbleSettingsStore(defaults: defaults)
        #expect(!restoredAgain.runningBubblesEnabled)
        #expect(!restoredAgain.pendingBubblesEnabled)
        #expect(restoredAgain.readyBubblesEnabled)

        restoredAgain.readyBubblesEnabled = false

        let finalRestored = SessionBubbleSettingsStore(defaults: defaults)
        #expect(!finalRestored.runningBubblesEnabled)
        #expect(!finalRestored.pendingBubblesEnabled)
        #expect(!finalRestored.readyBubblesEnabled)
    }
}
