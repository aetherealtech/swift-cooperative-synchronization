import Foundation

public actor Lock: Lockable {
    public func lock() async throws {
        if locked {
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
        }
        
        locked = true
    }
    
    public func unlock() {
        locked = false
        waiters.safelyRemoveFirst()?.resume()
    }
    
    private func cancel(id: UUID) {
        if let continuation = waiters.remove(id: id) {
            continuation.resume(throwing: CancellationError())
        }
    }
    
    private var locked = false
    private var waiters: [IdentifiableContinuation<Void, Error>] = []
}

public extension Lock {
    func lock<R>(_ work: () async throws -> R) async throws -> R {
        try await lock()
        defer { unlock() }
        
        return try await work()
    }
}
