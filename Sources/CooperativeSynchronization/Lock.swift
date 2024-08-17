import Foundation

public actor Lock: Lockable {
    public func lock() -> Task<Void, Never> {
        if locked {
            let waiter = Waiter()
            waiters.append(waiter)
            let id = waiter.id
            
            return .init {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let waiterIndex = waiters.firstIndex { $0.id == id }!
                    
                    if waiters[waiterIndex].notified {
                        continuation.resume()
                        waiters.remove(at: waiterIndex)
                    } else {
                        waiters[waiterIndex].continuation = continuation
                    }
                }
            }
        } else {
            locked = true
            
            return .init {}
        }
    }
    
    public func unlock() {
        if let waiter = waiters.first {
            if let continuation = waiter.continuation {
                continuation.resume()
                waiters.removeFirst()
            } else {
                waiters[0].notified = true
            }
        } else {
            locked = false
        }
    }
    
    private struct Waiter {
        let id = UUID()
        var continuation: CheckedContinuation<Void, Never>?
        var notified = false
    }

    private var locked = false
    private var waiters: [Waiter] = []
}

public extension Lock {
    func scheduleLock<R: Sendable>(_ work: @escaping @Sendable () async -> R) -> Task<R, Never> {
        let locked = lock()
        
        return .init {
            await locked.value
            defer { unlock() }
            
            return await work()
        }
    }
    
    func scheduleLock<R: Sendable>(_ work: @escaping @Sendable () async throws -> R) -> Task<R, any Error> {
        let locked = lock()
        
        return .init {
            await locked.value
            defer { unlock() }
            
            return try await work()
        }
    }
    
    func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await lock().value
        defer { unlock() }
        
        return try await work()
    }
}
