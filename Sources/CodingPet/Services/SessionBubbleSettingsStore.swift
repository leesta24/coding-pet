import Combine
import Foundation

@MainActor
final class SessionBubbleSettingsStore: ObservableObject {
    static let runningStorageKey = "codingPet.sessionBubbles.runningEnabled"
    static let pendingStorageKey = "codingPet.sessionBubbles.pendingEnabled"
    static let readyStorageKey = "codingPet.sessionBubbles.readyEnabled"

    @Published var runningBubblesEnabled: Bool {
        didSet {
            defaults.set(runningBubblesEnabled, forKey: Self.runningStorageKey)
        }
    }

    @Published var pendingBubblesEnabled: Bool {
        didSet {
            defaults.set(pendingBubblesEnabled, forKey: Self.pendingStorageKey)
        }
    }

    @Published var readyBubblesEnabled: Bool {
        didSet {
            defaults.set(readyBubblesEnabled, forKey: Self.readyStorageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        runningBubblesEnabled = defaults.object(forKey: Self.runningStorageKey) as? Bool ?? true
        pendingBubblesEnabled = defaults.object(forKey: Self.pendingStorageKey) as? Bool ?? true
        readyBubblesEnabled = defaults.object(forKey: Self.readyStorageKey) as? Bool ?? true
    }
}
