import Dispatch
import Foundation
import Testing
@testable import CodingPet

@Suite(.serialized)
struct CodexAppServerInputWriterTests {
    @Test
    func brokenPipeReturnsAnErrorInsteadOfTerminatingTheProcess() throws {
        let pipe = Pipe()
        let writer = try CodexAppServerInputWriter(
            fileHandle: pipe.fileHandleForWriting
        )
        try pipe.fileHandleForReading.close()

        #expect(throws: (any Swift.Error).self) {
            try writer.write(Data("request\n".utf8))
        }
        writer.close()
    }

    @Test
    func closeIsIdempotentAndRejectsLaterWrites() throws {
        let pipe = Pipe()
        let writer = try CodexAppServerInputWriter(
            fileHandle: pipe.fileHandleForWriting
        )

        writer.close()
        writer.close()

        #expect(throws: CodexAppServerInputWriter.Error.self) {
            try writer.write(Data("request\n".utf8))
        }
        try pipe.fileHandleForReading.close()
    }

    @Test
    func racingWriteAndCloseDoesNotCrash() throws {
        let queue = DispatchQueue(
            label: "com.codingpet.tests.app-server-writer",
            attributes: .concurrent
        )

        for _ in 0..<200 {
            let pipe = Pipe()
            let writer = try CodexAppServerInputWriter(
                fileHandle: pipe.fileHandleForWriting
            )
            let group = DispatchGroup()

            group.enter()
            queue.async {
                try? writer.write(Data("request\n".utf8))
                group.leave()
            }
            group.enter()
            queue.async {
                writer.close()
                group.leave()
            }

            #expect(group.wait(timeout: .now() + 1) == .success)
            writer.close()
            try pipe.fileHandleForReading.close()
        }
    }
}
