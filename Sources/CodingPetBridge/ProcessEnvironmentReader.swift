import Darwin
import Foundation

/// Reads environment variables of same-user processes through
/// `KERN_PROCARGS2`, the mechanism behind `ps eww`. Claude Code does not pass
/// its OAuth token down to hook commands, but the Claude process that spawned
/// the hook still carries it, so the hook walks up its ancestry.
public enum ProcessEnvironmentReader {
    public static func value(
        of key: String,
        inAncestorsOf processID: pid_t,
        maximumDepth: Int = 5
    ) -> String? {
        var current = processID
        for _ in 0...maximumDepth {
            guard current > 1 else { return nil }
            if let value = environment(of: current)?[key], !value.isEmpty {
                return value
            }
            guard let parent = parentProcessID(of: current), parent != current else {
                return nil
            }
            current = parent
        }
        return nil
    }

    public static func parentProcessID(of processID: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0,
              size > 0 else {
            return nil
        }
        return info.kp_eproc.e_ppid
    }

    public static func environment(of processID: pid_t) -> [String: String]? {
        // KERN_PROCARGS2 does not support a size probe; allocate KERN_ARGMAX.
        var argumentMaximum: Int32 = 0
        var argumentMaximumSize = MemoryLayout<Int32>.size
        var argumentMaximumName: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argumentMaximumName, 2, &argumentMaximum, &argumentMaximumSize, nil, 0) == 0,
              argumentMaximum > 0 else {
            return nil
        }
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, processID]
        var size = Int(argumentMaximum)
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&name, u_int(name.count), &buffer, &size, nil, 0) == 0, size > 4 else {
            return nil
        }
        return parseEnvironment(from: buffer[..<size])
    }

    /// Layout: Int32 argc, executable path, NUL padding, argc argv strings,
    /// then `KEY=VALUE` strings until an empty string.
    static func parseEnvironment(from bytes: ArraySlice<UInt8>) -> [String: String]? {
        guard bytes.count > 4 else { return nil }
        let argc = bytes[bytes.startIndex..<bytes.startIndex + 4].withUnsafeBytes {
            Int($0.loadUnaligned(as: Int32.self))
        }
        var index = bytes.startIndex + 4
        let end = bytes.endIndex

        func nextString() -> String? {
            guard index < end else { return nil }
            let start = index
            while index < end, bytes[index] != 0 { index += 1 }
            let string = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return string
        }

        _ = nextString()
        while index < end, bytes[index] == 0 { index += 1 }
        for _ in 0..<max(argc, 0) {
            guard nextString() != nil else { return nil }
        }

        var environment: [String: String] = [:]
        while let entry = nextString(), !entry.isEmpty {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return environment
    }
}
