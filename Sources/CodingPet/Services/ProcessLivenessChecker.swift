import Darwin

enum ProcessLivenessChecker {
    static func isAlive(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        errno = 0
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
