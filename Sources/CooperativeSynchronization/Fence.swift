import AsyncExtensions
import CollectionExtensions
import Foundation

public actor Fence {
    public init() {}

    public private(set) var signaled = false
    
    public func wait() async throws {
        if !signaled {
            try Task.checkCancellation()

            let id = UUID()
            waiters[id] = .init()
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        let waiter = waiters[id]!
                        
                        switch waiter.mode {
                            case .waiting:
                                waiters[id]!.continuation = cont
                                
                            case .signalled:
                                cont.resume()
                                waiters.removeValue(forKey: id)
                                
                            case .cancelled:
                                cont.resume(throwing: CancellationError())
                                waiters.removeValue(forKey: id)
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

    public func signal(reset: Bool = true) {
        signaled = !reset
        
        for (id, waiter) in waiters {
            if let continuation = waiter.continuation {
                continuation.resume()
                waiters.removeValue(forKey: id)
            } else if case .waiting = waiter.mode {
                waiters[id]!.mode = .signalled
            }
        }
    }

    public func reset() {
        signaled = false
    }
    
    private struct WaiterState {
        enum Mode {
            case waiting
            case signalled
            case cancelled
        }
        
        var continuation: CheckedContinuation<Void, any Error>?
        var mode = Mode.waiting
    }

    private var waiters: [UUID: WaiterState] = [:]
            
    private func cancel(id: UUID) {
        if let waiter = waiters[id] {
            if let continuation = waiter.continuation {
                continuation.resume(throwing: CancellationError())
                waiters.removeValue(forKey: id)
            } else if case .waiting = waiter.mode {
                waiters[id]!.mode = .cancelled
            }
        }
    }
}
