import Foundation

struct PetAppearance: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case bundled
        case local(URL)
    }

    static let xiaobao = PetAppearance(
        rawValue: "xiaobao",
        displayName: "胖墩",
        accessibilityName: "Pangdun child",
        source: .bundled
    )

    let rawValue: String
    let displayName: String
    let accessibilityName: String
    let source: Source

    var id: String { rawValue }

    static func local(
        id: String,
        displayName: String,
        directory: URL
    ) -> PetAppearance {
        PetAppearance(
            rawValue: id,
            displayName: displayName,
            accessibilityName: "\(displayName) pet",
            source: .local(directory)
        )
    }
}
