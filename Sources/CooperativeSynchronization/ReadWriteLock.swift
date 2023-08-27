import Foundation

fileprivate protocol Waiter: Identifiable where ID == UUID {
    var continuation: CheckedContinuation<Void, Error> { get }
}

extension RangeReplaceableCollection where Element == any Waiter {
    mutating func remove(id: UUID) -> Element? {
        removeFirst { $0.id == id }
    }
}

public actor ReadWriteLock {
    public init(maxReaders: Int = .max) {
        self.maxReaders = maxReaders
    }
    
    public func lock() async throws {
        if readers == maxReaders || writing {
            let id = UUID()
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        waiters.append(Reader(
                            id: id,
                            continuation: continuation
                        ))
                    }
                },
                onCancel: {
                    Task { await cancel(id: id) }
                }
            )
        }
        
        readers += 1
    }
    
    public func unlock() {
        readers -= 1
        notify()
    }
    
    public func exclusiveLock() async throws {
        if readers > 0 || writing {
            let id = UUID()
            
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        waiters.append(Writer(
                            id: id,
                            continuation: continuation
                        ))
                    }
                },
                onCancel: {
                    Task { await cancel(id: id) }
                }
            )
        }
        
        writing = true
    }
    
    public func exclusiveUnlock() {
        writing = false
        notify()
    }
    
    private struct Reader: Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    
    private struct Writer: Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    
    private let maxReaders: Int
    
    private var readers = 0
    private var writing = false

    private var waiters: [any Waiter] = []
    
    private func notify() {
        while !waiters.isEmpty, !writing && readers < maxReaders {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume()
        }
    }
    
    private func cancel(id: UUID) {
        if let continuation = waiters.remove(id: id) {
            continuation.continuation.resume(throwing: CancellationError())
        }
    }
}

public extension ReadWriteLock {
    func read<R>(_ work: () async throws -> R) async throws -> R {
        try await lock()
        defer { unlock() }
        
        return try await work()
    }
    
    func write<R>(_ work: () async throws -> R) async throws -> R {
        try await exclusiveLock()
        defer { exclusiveUnlock() }
        
        return try await work()
    }
}

public struct SharedLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async throws { try await lock.lock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R>(_ work: () async throws -> R) async throws -> R {
        try await lock.read(work)
    }
}

public struct ExclusiveLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async throws { try await lock.exclusiveLock() }
    public func unlock() async { await lock.exclusiveUnlock() }
    
    public func lock<R>(_ work: () async throws -> R) async throws -> R {
        try await lock.write(work)
    }
}

public extension ReadWriteLock {
    var shared: some Lockable {
        SharedLock(lock: self)
    }
    
    var exclusive: some Lockable {
        ExclusiveLock(lock: self)
    }
}
