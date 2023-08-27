import AsyncExtensions
import Foundation

public struct TimedOut: Error {}

public actor ConditionVariable {
    public init() {
        
    }
    
    deinit {
        if !waiters.isEmpty {
            fatalError("ConditionVariable was released with waiters")
        }
    }
    
    public func wait(
        lock: some Lockable
    ) async throws {
        await lock.unlock()
        
        do {
            let id = UUID()
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        waiters.append(.init(
                            id: id,
                            continuation: continuation
                        ))
                    }
                },
                onCancel: {
                    Task {
                        await cancel(id: id)
                    }
                }
            )
            
            try await lock.lock()
        } catch {
            try await lock.lock()
            throw error
        }
    }
    
    public func notifyOne() {
        waiters.safelyRemoveFirst()?.resume()
    }
    
    public func notifyAll() {
        for waiter in waiters {
            waiter.resume()
        }
        
        waiters.removeAll()
    }

    private var waiters: [IdentifiableContinuation<Void, Error>] = []
    
    private func cancel(id: UUID) {
        if let continuation = waiters.remove(id: id) {
            continuation.resume(throwing: CancellationError())
        }
    }
}

public extension ConditionVariable {
    func wait(
        lock: some Lockable,
        _ condition: () throws -> Bool
    ) async throws {
        while try !condition() {
            try await wait(lock: lock)
        }
    }
}
