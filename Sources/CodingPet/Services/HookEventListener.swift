import Darwin
@preconcurrency import Dispatch
import Foundation
import OSLog
import CodingPetBridge

final class HookEventListener: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (HookEventEnvelope) -> Void

    static let maximumMessageSize = 16_384

    private let descriptor: Int32
    private let path: String
    private let socketDevice: dev_t
    private let socketInode: ino_t
    private let source: any DispatchSourceRead
    private let handler: Handler
    private let lock = NSLock()
    private var stopped = false
    private let logger = Logger(subsystem: "CodingPet", category: "HookEventListener")

    init(
        path: String = HookSocketAddress.defaultPath,
        handler: @escaping Handler
    ) throws {
        self.path = path
        self.handler = handler

        try Self.removeStaleSocket(at: path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Self.posixError() }

        do {
            var address = try HookSocketAddress.make(path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard bindResult == 0 else { throw Self.posixError() }
            guard chmod(path, S_IRUSR | S_IWUSR) == 0 else { throw Self.posixError() }
            guard listen(descriptor, 16) == 0 else { throw Self.posixError() }

            let flags = fcntl(descriptor, F_GETFL, 0)
            guard flags >= 0,
                  fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw Self.posixError()
            }

            var info = stat()
            guard lstat(path, &info) == 0 else { throw Self.posixError() }
            socketDevice = info.st_dev
            socketInode = info.st_ino
        } catch {
            Darwin.close(descriptor)
            unlink(path)
            throw error
        }

        self.descriptor = descriptor
        let queue = DispatchQueue(label: "com.codingpet.hook-listener", qos: .utility)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptAvailableClients()
        }
        source.resume()
    }

    deinit {
        stop()
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()

        source.cancel()
        Darwin.close(descriptor)
        removeSocketIfOwned()
    }

    static func decodeMessage(_ data: Data) -> HookEventEnvelope? {
        guard data.count <= maximumMessageSize,
              data.last == 0x0A,
              data.dropLast().lastIndex(of: 0x0A) == nil,
              let event = try? HookEventCodec.decode(data.dropLast()),
              event.protocolVersion == HookEventEnvelope.currentProtocolVersion else {
            return nil
        }
        return event
    }

    private func acceptAvailableClients() {
        while true {
            let client = accept(descriptor, nil, nil)
            if client >= 0 {
                receiveMessage(from: client)
                Darwin.close(client)
            } else if errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    private func receiveMessage(from client: Int32) {
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        _ = setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var message = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while message.count <= Self.maximumMessageSize {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(client, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                message.append(buffer, count: count)
                if message.contains(0x0A) { break }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                return
            }
        }

        guard let event = Self.decodeMessage(message) else {
            logger.error("Discarded malformed or oversized hook event")
            return
        }
        Task { @MainActor [handler] in
            handler(event)
        }
    }

    private static func removeStaleSocket(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return }
            throw posixError()
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw POSIXError(.EADDRINUSE)
        }

        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw posixError() }
        defer { Darwin.close(probe) }
        var address = try HookSocketAddress.make(path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 {
            throw POSIXError(.EADDRINUSE)
        }
        guard errno == ECONNREFUSED || errno == ENOENT else {
            throw posixError()
        }
        guard unlink(path) == 0 else { throw posixError() }
    }

    private func removeSocketIfOwned() {
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_dev == socketDevice,
              info.st_ino == socketInode else {
            return
        }
        unlink(path)
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
