import Foundation

public actor Lock: Lockable {
    public func lock() async {
        if locked {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        
        locked = true
    }
    
    public func unlock() {
        locked = false
        waiters.safelyRemoveFirst()?.resume()
    }

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
}

public extension Lock {
    func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await lock()
        defer { unlock() }
        
        return try await work()
    }
}
