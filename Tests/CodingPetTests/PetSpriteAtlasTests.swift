import AppKit
import Testing
@testable import CodingPet

@MainActor
struct PetSpriteAtlasTests {
    @Test(arguments: [
        ("xiaobao", "胖墩")
    ])
    func bundledPetsAreValidV2Atlases(resourceID: String, displayName: String) throws {
        let atlas = try PetSpriteAtlas(resourceID: resourceID)

        #expect(atlas.manifest.id == resourceID)
        #expect(atlas.manifest.displayName == displayName)
        #expect(atlas.manifest.spriteVersionNumber == 2)
        #expect(atlas.pixelWidth == 1_536)
        #expect(atlas.pixelHeight == 2_288)
        #expect(atlas.frame(row: 0, column: 0) != nil)
        #expect(atlas.frame(row: 10, column: 7) != nil)
        #expect(atlas.frame(row: 11, column: 0) == nil)
    }

    @Test
    func bundledAppearanceHasAnAtlas() {
        #expect(PetSpriteAtlas.available(for: .xiaobao) != nil)
    }

    @Test
    func loadsLegacyNineRowV1PackagesWithoutAVersionField() throws {
        let package = try makePackage(id: "legacy", rows: 9, manifestExtra: "")
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }

        let atlas = try PetSpriteAtlas(packageDirectory: package)

        #expect(atlas.manifest.spriteVersionNumber == 1)
        #expect(atlas.rowCount == 9)
        #expect(atlas.frame(row: 8, column: 7) != nil)
        #expect(atlas.frame(row: 9, column: 0) == nil)
    }

    @Test
    func rejectsSheetsWithUnsupportedRowCounts() throws {
        let package = try makePackage(id: "odd", rows: 10, manifestExtra: #""spriteVersionNumber": 2,"#)
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }

        #expect(throws: PetSpriteAtlas.Error.self) {
            try PetSpriteAtlas(packageDirectory: package)
        }
    }

    /// Writes a package with a blank PNG sheet of the given row count.
    private func makePackage(id: String, rows: Int, manifestExtra: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-atlas-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let package = root.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("""
        {"id": "\(id)", "displayName": "\(id)", \(manifestExtra) "spritesheetPath": "spritesheet.png"}
        """.utf8).write(to: package.appending(path: "pet.json"))

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: PetSpriteAtlas.columns * PetSpriteAtlas.cellWidth,
            pixelsHigh: rows * PetSpriteAtlas.cellHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: package.appending(path: "spritesheet.png"))
        return package
    }

    @Test(arguments: [
        (BotState.idle, 0, 6),
        (BotState.blocked, 5, 8),
        (BotState.needsInput, 6, 6),
        (BotState.running, 7, 6),
        (BotState.ready, 8, 6)
    ])
    func mapsCodingPetStatesToCodexAnimationRows(
        state: BotState,
        expectedRow: Int,
        expectedFrameCount: Int
    ) {
        let animation = PetSpriteAnimation.animation(for: state)

        #expect(animation.row == expectedRow)
        #expect(animation.frameDurations.count == expectedFrameCount)
        #expect(animation.frameIndex(elapsed: 0) == 0)
        #expect(animation.frameIndex(elapsed: animation.totalDuration) == 0)
    }

    @Test
    func idleDwellsBeforePlayingItsBriefMotion() {
        let animation = PetSpriteAnimation.animation(for: .idle)

        #expect(animation.frameIndex(elapsed: 6.99) == 0)
        #expect(animation.frameIndex(elapsed: 7.01) == 1)
        #expect(animation.totalDuration > 7.7)
    }
}
