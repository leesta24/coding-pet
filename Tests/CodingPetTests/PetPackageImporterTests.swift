import Foundation
import Testing
@testable import CodingPet

@MainActor
struct PetPackageImporterTests {
    @Test
    func parsesPetIDsAndSiteLinks() {
        let cases: [(String, String?)] = [
            ("yuumi", "yuumi"),
            ("  Perlica_Endfield-2  ", "Perlica_Endfield-2"),
            ("https://codex-pets.net/#/pets/yuumi", "yuumi"),
            ("codex-pets.net/#/pets/yuumi?tab=notes", "yuumi"),
            ("https://codex-pets.net/api/pets/yuumi/download?v=1789279767982", "yuumi"),
            ("https://codex-pets.net/#/collections", nil),
            ("https://evil.example/#/pets/yuumi", nil),
            ("../escape", nil),
            ("", nil),
            ("has space", nil)
        ]
        for (reference, expected) in cases {
            #expect(PetPackageImporter.petID(fromReference: reference) == expected, "\(reference)")
        }
    }

    @Test
    func importsPetFromSiteAndInstallsPackage() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let archive = try makeArchive(id: "test-pet", displayName: "Test Pet", in: sandbox.root)
        let requests = RequestLog()
        let importer = PetPackageImporter(
            petsDirectory: sandbox.pets,
            loader: { url, _ in
                await requests.record(url)
                switch url.path {
                case "/api/pets/test-pet":
                    return (Data(#"{"pet":{"id":"test-pet","downloadUrl":"/api/pets/test-pet/download?v=7"}}"#.utf8), 200)
                case "/api/pets/test-pet/download":
                    return (try Data(contentsOf: archive), 200)
                default:
                    return (Data(), 404)
                }
            }
        )

        var stages: [PetPackageImporter.Progress.Stage] = []
        let installed = try await importer.importPet(
            reference: "https://codex-pets.net/#/pets/test-pet",
            onProgress: { stages.append($0.stage) }
        )

        #expect(stages == [.lookingUp, .downloading, .installing])
        #expect(installed == sandbox.pets.appending(path: "test-pet", directoryHint: .isDirectory))
        let atlas = try PetSpriteAtlas(packageDirectory: installed)
        #expect(atlas.manifest.displayName == "Test Pet")
        let visited = await requests.urls.map(\.absoluteString)
        #expect(visited == [
            "https://codex-pets.net/api/pets/test-pet",
            "https://codex-pets.net/api/pets/test-pet/download?v=7"
        ])
    }

    @Test
    func rejectsDownloadLinksOnOtherHostsWithoutFetchingThem() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let requests = RequestLog()
        let importer = PetPackageImporter(
            petsDirectory: sandbox.pets,
            loader: { url, _ in
                await requests.record(url)
                return (Data(#"{"downloadUrl":"https://evil.example/pet.zip"}"#.utf8), 200)
            }
        )

        await #expect(throws: PetPackageImporter.Error.untrustedDownloadHost) {
            try await importer.importPet(reference: "yuumi")
        }
        #expect(await requests.urls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: sandbox.pets.path))
    }

    @Test
    func reportsMissingPets() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let importer = PetPackageImporter(petsDirectory: sandbox.pets, loader: { _, _ in (Data(), 404) })

        await #expect(throws: PetPackageImporter.Error.petNotFound("nobody")) {
            try await importer.importPet(reference: "nobody")
        }
    }

    @Test
    func reportsResponsesWithoutADownloadLink() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let importer = PetPackageImporter(petsDirectory: sandbox.pets, loader: { _, _ in (Data("<html>".utf8), 200) })

        await #expect(throws: PetPackageImporter.Error.unexpectedResponse) {
            try await importer.importPet(reference: "yuumi")
        }
    }

    @Test
    func rejectsArchivesThatAreNotValidPackages() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let source = sandbox.root.appending(path: "bad-src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"id":"bad","displayName":"Bad","description":"","spriteVersionNumber":1,"spritesheetPath":"spritesheet.webp"}"#.utf8)
            .write(to: source.appending(path: "pet.json"))
        let archive = sandbox.root.appending(path: "bad.codex-pet.zip")
        try zip(directory: source, to: archive)
        let importer = PetPackageImporter(petsDirectory: sandbox.pets, loader: { _, _ in (Data(), 500) })

        await #expect(throws: PetPackageImporter.Error.self) {
            try await importer.importPackage(at: archive)
        }
        #expect(!FileManager.default.fileExists(atPath: sandbox.pets.appending(path: "bad").path))
    }

    @Test
    func localArchiveImportReplacesAnExistingPackage() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let importer = PetPackageImporter(petsDirectory: sandbox.pets, loader: { _, _ in (Data(), 500) })

        let first = try makeArchive(id: "swap", displayName: "First", in: sandbox.root, archiveName: "first.zip")
        let second = try makeArchive(id: "swap", displayName: "Second", in: sandbox.root, archiveName: "second.zip")
        _ = try await importer.importPackage(at: first)
        let installed = try await importer.importPackage(at: second)

        #expect(try PetSpriteAtlas(packageDirectory: installed).manifest.displayName == "Second")
        #expect(PetSpriteAtlas.localAppearances(in: sandbox.pets).map(\.rawValue) == ["swap"])
    }

    @Test
    func storeImportAddsSelectsAndReportsThePet() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let suiteName = "PetPackageImporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let archive = try makeArchive(id: "store-pet", displayName: "Store Pet", in: sandbox.root)
        let store = PetAppearanceStore(
            defaults: defaults,
            localPetsDirectory: sandbox.pets,
            importer: PetPackageImporter(
                petsDirectory: sandbox.pets,
                loader: { url, _ in
                    url.path.hasSuffix("/download")
                        ? (try Data(contentsOf: archive), 200)
                        : (Data(#"{"downloadUrl":"/api/pets/store-pet/download"}"#.utf8), 200)
                }
            )
        )
        #expect(store.availableAppearances.map(\.rawValue) == ["xiaobao"])

        await store.importPet(reference: "store-pet")

        #expect(store.availableAppearances.map(\.rawValue) == ["xiaobao", "store-pet"])
        #expect(store.selection.rawValue == "store-pet")
        #expect(store.importFeedback == .init(kind: .success, message: "Store Pet was added to your pet library."))
        #expect(!store.isImporting)
        #expect(defaults.string(forKey: PetAppearanceStore.storageKey) == "store-pet")

        await store.importPet(reference: "bad id!")
        #expect(store.importFeedback?.kind == .error)
        #expect(store.selection.rawValue == "store-pet")
    }

    // MARK: - Helpers

    private actor RequestLog {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    private struct Sandbox {
        let root: URL
        var pets: URL { root.appending(path: "Pets", directoryHint: .isDirectory) }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-importer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Sandbox(root: root)
    }

    /// Builds a `.codex-pet.zip` from the bundled 胖墩 package with a rewritten manifest.
    private func makeArchive(
        id: String,
        displayName: String,
        in root: URL,
        archiveName: String? = nil
    ) throws -> URL {
        let source = try #require(PetSpriteAtlas.bundledPackageURL(resourceID: "xiaobao"))
        let staging = root.appending(path: "src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: source, to: staging)
        let manifestURL = staging.appending(path: "pet.json")
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        manifest["id"] = id
        manifest["displayName"] = displayName
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let archive = root.appending(path: archiveName ?? "\(id).codex-pet.zip")
        try zip(directory: staging, to: archive)
        return archive
    }

    private func zip(directory: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", directory.path, archive.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
