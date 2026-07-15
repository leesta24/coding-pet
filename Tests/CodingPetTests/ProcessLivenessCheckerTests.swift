import Darwin
import Testing
@testable import CodingPet

struct ProcessLivenessCheckerTests {
    @Test
    func currentProcessIsAliveAndInvalidProcessIsNot() {
        #expect(ProcessLivenessChecker.isAlive(getpid()))
        #expect(!ProcessLivenessChecker.isAlive(Int32.max))
    }
}
