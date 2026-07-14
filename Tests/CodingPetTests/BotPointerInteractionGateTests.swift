import AppKit
import Testing
@testable import CodingPet

struct BotPointerInteractionGateTests {
    @Test
    func normalClickAllowsPanelActivation() {
        var gate = BotPointerInteractionGate()

        gate.pointerDown(at: NSPoint(x: 100, y: 100))
        gate.pointerUp(at: NSPoint(x: 101, y: 101))

        let shouldActivate = gate.consumeActivation()
        #expect(shouldActivate)
    }

    @Test
    func draggingSuppressesOnlyTheReleaseActivation() {
        var gate = BotPointerInteractionGate()

        gate.pointerDown(at: NSPoint(x: 100, y: 100))
        gate.pointerDragged(to: NSPoint(x: 125, y: 112))
        gate.pointerUp(at: NSPoint(x: 130, y: 114))

        let firstActivation = gate.consumeActivation()
        let secondActivation = gate.consumeActivation()
        #expect(!firstActivation)
        #expect(secondActivation)
    }

    @Test
    func releaseDistanceDetectsDragEvenWithoutDraggedEvent() {
        var gate = BotPointerInteractionGate()

        gate.pointerDown(at: NSPoint(x: 10, y: 10))
        gate.pointerUp(at: NSPoint(x: 20, y: 10))

        let shouldActivate = gate.consumeActivation()
        #expect(!shouldActivate)
    }
}
