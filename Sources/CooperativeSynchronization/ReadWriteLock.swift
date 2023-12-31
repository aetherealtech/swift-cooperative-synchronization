import Foundation
import Synchronization

fileprivate protocol Waiter {
    var continuation: CheckedContinuation<Void, Error> { get }
    
    init(
        continuation: CheckedContinuation<Void, Error>
    )
}

struct WaiterState {
    var continuation: CheckedContinuation<Void, Error>?
    var cancelled = false
}

public actor ReadWriteLock {
    public init(maxReaders: Int = .max) {
        self.maxReaders = maxReaders
    }
    
    public func lock() async throws {
        try await lock(
            ready: readers < maxReaders && !writing,
            acquire: { readers += 1 },
            waiterType: Reader.self
        )
    }
    
    public func unlock() {
        if writing {
            writing = false
        } else {
            readers -= 1
        }
        
        notify()
    }
    
    public func exclusiveLock() async throws {
        try await lock(
            ready: readers == 0 && !writing,
            acquire: { writing = true },
            waiterType: Writer.self
        )
    }

    private struct Reader: Waiter {
        let continuation: CheckedContinuation<Void, Error>
    }
    
    private struct Writer: Waiter {
        let continuation: CheckedContinuation<Void, Error>
    }
    
    private let maxReaders: Int
    
    private var readers = 0
    private var writing = false

    private var waiters: [any Waiter] = []
    
    private func lock<W: Waiter>(
        ready: Bool,
        acquire: () -> Void,
        waiterType: W.Type
    ) async throws {
        if !ready || !waiters.of(type: Writer.self).isEmpty {
            @Synchronization.Synchronized
            var state: WaiterState = .init()
            
            try await withTaskCancellationHandler(
                operation: { [_state] in
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        _state.write { state in
                            if _state.cancelled {
                                continuation.resume(throwing: CancellationError())
                            } else {
                                state.continuation = continuation
                                waiters.append(W.init(
                                    continuation: continuation
                                ))
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
        } else {
            acquire()
        }
    }
    
    private func notify() {
        while let waiter = waiters.first {
            if waiter is Writer {
                guard !writing && readers == 0 else { break }
                writing = true
            } else {
                guard !writing && readers < maxReaders else { break }
                readers += 1
            }
            
            waiters.removeFirst()
            waiter.continuation.resume()
        }
    }
}

public extension ReadWriteLock {
    func read<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await lock()
        defer { unlock() }
        
        return try await work()
    }
    
    func write<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await exclusiveLock()
        defer { unlock() }
        
        return try await work()
    }
}

public struct SharedLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async throws { try await lock.lock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await lock.read(work)
    }
}

public struct ExclusiveLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async throws { try await lock.exclusiveLock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async throws -> R {
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
