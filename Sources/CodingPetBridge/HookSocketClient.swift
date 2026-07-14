import Darwin
import Foundation

public enum HookSocketClient {
    @discardableResult
    public static func send(
        _ event: HookEventEnvelope,
        to path: String = HookSocketAddress.defaultPath,
        timeoutMilliseconds: Int32 = 75
    ) -> Bool {
        guard timeoutMilliseconds >= 0,
              var payload = try? HookEventCodec.encode(event) else {
            return false
        }
        payload.append(0x0A)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        guard let originalFlags = optionalResult(fcntl(descriptor, F_GETFL, 0)),
              fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0,
              connect(descriptor, to: path, timeoutMilliseconds: timeoutMilliseconds) else {
            return false
        }

        _ = fcntl(descriptor, F_SETFL, originalFlags)
        return writeAll(payload, to: descriptor)
    }

    private static func connect(
        _ descriptor: Int32,
        to path: String,
        timeoutMilliseconds: Int32
    ) -> Bool {
        guard var address = try? HookSocketAddress.make(path) else { return false }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }

        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        var pollResult: Int32
        repeat {
            pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        } while pollResult < 0 && errno == EINTR
        guard pollResult > 0 else { return false }

        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(
            descriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &errorLength
        ) == 0 else {
            return false
        }
        return socketError == 0
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func optionalResult(_ result: Int32) -> Int32? {
        result >= 0 ? result : nil
    }
}
