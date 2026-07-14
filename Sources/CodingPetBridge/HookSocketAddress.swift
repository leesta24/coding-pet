import Darwin
import Foundation

public enum HookSocketAddress {
    public static var defaultPath: String {
        FileManager.default.temporaryDirectory
            .appending(path: "codingpet-\(getuid()).sock")
            .path
    }

    public static func make(_ path: String) throws -> sockaddr_un {
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
}
