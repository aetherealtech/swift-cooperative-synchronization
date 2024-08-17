import Foundation

public actor CountdownLatch {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        if value > 0 {
            try Task.checkCancellation()

            let id = UUID()
            waiters[id] = .init()
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        let waiter = waiters[id]!
                        
                        if waiter.cancelled {
                            cont.resume(throwing: CancellationError())
                            waiters.removeValue(forKey: id)
                        } else if value == 0 {
                            cont.resume()
                            waiters.removeValue(forKey: id)
                        } else {
                            waiters[id]!.continuation = cont
                        }
                    }
                },
                onCancel: {
                    Task {
                        await cancel(id: id)
                    }
                }
            )
        }
    }
    
    public func signal() {
        guard value > 0 else {
            return
        }
        
        value -= 1

        if value == 0 {
            for (id, waiter) in waiters {
                if let continuation = waiter.continuation {
                    continuation.resume()
                    waiters.removeValue(forKey: id)
                }
            }
        }
    }
    
    private struct WaiterState {
        var continuation: CheckedContinuation<Void, any Error>?
        var cancelled = false
    }

    private var value: Int
    private var waiters: [UUID: WaiterState] = [:]
            
    private func cancel(id: UUID) {
        if let waiter = waiters[id] {
            if let continuation = waiter.continuation {
                continuation.resume(throwing: CancellationError())
                waiters.removeValue(forKey: id)
            } else {
                waiters[id]!.cancelled = true
            }
        }
    }
}
