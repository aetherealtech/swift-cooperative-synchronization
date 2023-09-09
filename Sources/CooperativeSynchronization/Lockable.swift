public protocol Lockable: Sendable {
    func lock() async throws
    func unlock() async
    
    func lock<R>(_ work: @Sendable () async throws -> R) async throws -> R
}
