public protocol Lockable {
    func lock() async throws
    func unlock() async
    
    func lock<R>(_ work: () async throws -> R) async throws -> R
}
