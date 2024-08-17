public protocol Lockable: Sendable {
    func lock() async -> Task<Void, Never>
    func unlock() async
    
    func lock<R>(_ work: @Sendable () async throws -> R) async rethrows -> R
}
