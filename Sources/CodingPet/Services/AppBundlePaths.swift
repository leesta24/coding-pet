import Foundation

enum AppBundlePaths {
    static let petResourceBundleName = "CodingPet_CodingPet"

    static func hookExecutableURL(for executableURL: URL) -> URL {
        let executableDirectory = executableURL.deletingLastPathComponent()
        let contentsDirectory = executableDirectory.deletingLastPathComponent()
        let appBundleURL = contentsDirectory.deletingLastPathComponent()

        if executableDirectory.lastPathComponent == "MacOS",
           contentsDirectory.lastPathComponent == "Contents",
           appBundleURL.pathExtension == "app" {
            return contentsDirectory
                .appending(path: "Helpers", directoryHint: .isDirectory)
                .appending(path: "CodingPetHook")
        }

        return executableDirectory.appending(path: "CodingPetHook")
    }

    static var hookExecutableURL: URL {
        guard let executableURL = Bundle.main.executableURL else {
            return URL(filePath: "/usr/local/bin/CodingPetHook")
        }
        return hookExecutableURL(for: executableURL)
    }

    static func petResourceBundleURL(in appBundleURL: URL) -> URL {
        appBundleURL
            .appending(path: "Contents/Resources", directoryHint: .isDirectory)
            .appending(path: "\(petResourceBundleName).bundle", directoryHint: .isDirectory)
    }

    static var packagedPetResourceBundle: Bundle? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return Bundle(url: petResourceBundleURL(in: Bundle.main.bundleURL))
    }
}
