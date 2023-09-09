import Foundation
import Synchronization

public actor Lock: Lockable {
    public func lock() async throws {
        if locked {
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
        
        locked = true
    }
    
    public func unlock() {
        locked = false
        waiters.safelyRemoveFirst()?.resume()
    }

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Error>] = []
}

public extension Lock {
    func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await lock()
        defer { unlock() }
        
        return try await work()
    }
}
