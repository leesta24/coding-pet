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
