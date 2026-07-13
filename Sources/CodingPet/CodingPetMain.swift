import AppKit

@main
enum CodingPetMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionStore: SessionStore
    private var botWindowController: BotWindowController?

    override init() {
        if CommandLine.arguments.contains("--demo") {
            sessionStore = SessionStore(sessions: .demo)
        } else {
            sessionStore = SessionStore()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        botWindowController = BotWindowController(store: sessionStore)
        botWindowController?.show()
    }
}
