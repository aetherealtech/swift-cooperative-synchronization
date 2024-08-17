public protocol Lockable: Sendable {
    func lock() async
    func unlock() async
    
    func lock<R>(_ work: @Sendable () async throws -> R) async rethrows -> R
}
