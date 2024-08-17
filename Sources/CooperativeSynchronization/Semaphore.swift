import Foundation

//public actor Semaphore: Sendable {
//    public init(value: Int) {
//        self.value = value
//    }
//    
//    public func wait() async throws {
//        try await condition.wait() {
//            value > 0
//        }
//        
//        value -= 1
//    }
//    
//    public func signal() async throws {
//        value += 1
//        
//        await condition.notifyOne()
//    }
//    
//    private var value: Int
//    private var condition = ConditionVariable()
//}

public actor Semaphore {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        if value == 0 {
            try Task.checkCancellation()

            let waiter = WaiterState()
            waiters.append(waiter)
            let id = waiter.id
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        let waiterIndex = waiters.firstIndex { waiter in waiter.id == id }!
                        
                        switch waiter.mode {
                            case .waiting:
                                waiters[waiterIndex].continuation = cont
                                
                            case .signalled:
                                cont.resume()
                                waiters.remove(at: waiterIndex)
                                
                            case .cancelled:
                                cont.resume(throwing: CancellationError())
                                waiters.remove(at: waiterIndex)
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
        
        value -= 1
    }

    public func signal() {
        value += 1
        
        if let waiter = waiters.first {
            if let continuation = waiter.continuation {
                continuation.resume()
                waiters.removeFirst()
            } else if case .waiting = waiter.mode {
                waiters[0].mode = .signalled
            }
        }
    }

    private struct WaiterState {
        enum Mode {
            case waiting
            case signalled
            case cancelled
        }
        
        let id = UUID()
        var continuation: CheckedContinuation<Void, any Error>?
        var mode = Mode.waiting
    }
    
    private var value: Int
    private var waiters: [WaiterState] = []
            
    private func cancel(id: UUID) {
        if let waiterIndex = waiters.firstIndex(where: { waiter in waiter.id == id }) {
            if let continuation = waiters[waiterIndex].continuation {
                continuation.resume(throwing: CancellationError())
                waiters.remove(at: waiterIndex)
            } else if case .waiting = waiters[waiterIndex].mode {
                waiters[waiterIndex].mode = .cancelled
            }
        }
    }
}


public extension Semaphore {
    func acquire<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await wait()
        defer { signal() }
        
        return try await work()
    }
}
