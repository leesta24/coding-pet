import Darwin
import Foundation
import Testing
import CodingPetBridge

struct HookSocketClientTests {
    @Test
    func sendsOneNewlineDelimitedEvent() throws {
        let path = temporarySocketPath()
        let server = try TestUnixSocket(path: path)
        defer { server.close() }
        let event = HookEventEnvelope(
            provider: .codex,
            eventName: "Stop",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            parentProcessID: 12,
            sessionID: "session-1",
            cwd: "/tmp/project"
        )

        let sent = HookSocketClient.send(event, to: path, timeoutMilliseconds: 100)

        #expect(sent)
        let received = try server.receive()
        #expect(received.last == 0x0A)
        let decoded = try HookEventCodec.decode(received.dropLast())
        #expect(decoded == event)
    }

    @Test
    func missingListenerFailsQuickly() {
        let event = HookEventEnvelope(
            provider: .claudeCode,
            eventName: "SessionStart",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "session-2",
            cwd: "/tmp/project"
        )
        let clock = ContinuousClock()
        let start = clock.now

        let sent = HookSocketClient.send(
            event,
            to: temporarySocketPath(),
            timeoutMilliseconds: 75
        )

        #expect(!sent)
        #expect(start.duration(to: clock.now) < .milliseconds(500))
    }

    private func temporarySocketPath() -> String {
        "/tmp/codingpet-test-\(UUID().uuidString.prefix(8)).sock"
    }
}

private final class TestUnixSocket {
    private let descriptor: Int32
    private let path: String

    init(path: String) throws {
        self.path = path
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

        unlink(path)
        var address = try makeUnixAddress(path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
    }

    func receive() throws -> Data {
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { throw POSIXError(.ECONNABORTED) }
        defer { Darwin.close(client) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.last == 0x0A { return data }
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    func close() {
        Darwin.close(descriptor)
        unlink(path)
    }
}

private func makeUnixAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw POSIXError(.ENAMETOOLONG)
    }

    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { destination in
            bytes.withUnsafeBufferPointer { source in
                destination.initialize(from: source.baseAddress!, count: bytes.count)
            }
        }
    }
    return address
}
