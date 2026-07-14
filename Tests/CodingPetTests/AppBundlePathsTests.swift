import Foundation
import Testing
@testable import CodingPet

struct AppBundlePathsTests {
    @Test
    func resolvesHookInsidePackagedApplication() {
        let executable = URL(
            filePath: "/Applications/CodingPet.app/Contents/MacOS/CodingPet"
        )

        #expect(
            AppBundlePaths.hookExecutableURL(for: executable).path ==
                "/Applications/CodingPet.app/Contents/Helpers/CodingPetHook"
        )
    }

    @Test
    func resolvesSiblingHookForSwiftPMExecutable() {
        let executable = URL(filePath: "/tmp/codingpet-debug/CodingPet")

        #expect(
            AppBundlePaths.hookExecutableURL(for: executable).path ==
                "/tmp/codingpet-debug/CodingPetHook"
        )
    }

    @Test
    func resolvesPackagedResourceBundleURL() {
        let app = URL(filePath: "/Applications/CodingPet.app")

        #expect(
            AppBundlePaths.petResourceBundleURL(in: app).path ==
                "/Applications/CodingPet.app/Contents/Resources/CodingPet_CodingPet.bundle"
        )
    }
}
