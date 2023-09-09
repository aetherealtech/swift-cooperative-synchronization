import AsyncExtensions
import Foundation
import Synchronization

public struct TimedOut: Error {}

public actor ConditionVariable {
    public init() {
        
    }
    
    deinit {
        if !waiters.isEmpty {
            fatalError("ConditionVariable was released with waiters")
        }
    }
    
    public func wait() async throws {
        try Task.checkCancellation()
                
        @Synchronization.Synchronized
        var state: WaiterState = .init()
        
        try await withTaskCancellationHandler(
            operation: { [_state] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    _state.write { state in
                        if state.cancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            state.continuation = continuation
                            waiters.append(continuation)
                        }
                    }
                }
            },
            onCancel: { [_state] in
                _state.write { state in
                    state.cancelled = true
                    state.continuation?.resume(throwing: CancellationError())
                }
            }
        )
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

    private var waiters: [CheckedContinuation<Void, Error>] = []
}

public extension ConditionVariable {
    nonisolated
    func wait(
        @_inheritActorContext _ condition: @Sendable () throws -> Bool
    ) async throws {
        while try !condition() {
            try await wait()
        }
    }
}
