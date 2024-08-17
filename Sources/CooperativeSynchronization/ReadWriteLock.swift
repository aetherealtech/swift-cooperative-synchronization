import Foundation

public actor ReadWriteLock {
    public init(maxReaders: Int = .max) {
        self.maxReaders = maxReaders
    }
    
    public func lock() -> Task<Void, Never> {
        lock(
            ready: readers < maxReaders && !writing && waiters.lazy.filter { $0.type == .writer }.isEmpty,
            acquire: { readers += 1 },
            waiterType: .reader
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
    
    public func exclusiveLock() -> Task<Void, Never> {
        lock(
            ready: readers == 0 && !writing && waiters.isEmpty,
            acquire: { writing = true },
            waiterType: .writer
        )
    }

    private struct Waiter {
        enum WaiterType {
            case reader
            case writer
        }
        
        let id = UUID()
        let type: WaiterType
        var continuation: CheckedContinuation<Void, Never>?
        var notified = false
    }
    
    private let maxReaders: Int
    
    private var readers = 0
    private var writing = false

    private var waiters: [Waiter] = []
    
    private func lock(
        ready: Bool,
        acquire: () -> Void,
        waiterType: Waiter.WaiterType
    ) -> Task<Void, Never> {
        if !ready {
            let waiter = Waiter(type: waiterType)
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
            acquire()
            
            return .init {}
        }
    }
    
    private func notify() {
        while let waiter = waiters.first {
            let ready = { switch waiter.type {
                case .writer:
                    guard readers == 0 && !writing else { return false }
                    writing = true
                    return true
                    
                case .reader:
                    guard readers < maxReaders && !writing else { return false }
                    readers += 1
                    return true
            } }()
            
            guard ready else { break }
            
            if let continuation = waiter.continuation {
                continuation.resume()
                waiters.removeFirst()
            } else {
                waiters[0].notified = true
            }
        }
    }
}

public extension ReadWriteLock {
    func scheduleRead<R: Sendable>(_ work: @escaping @Sendable () async -> R) -> Task<R, Never> {
        let locked = lock()
        
        return .init {
            defer { unlock() }
            
            await locked.value
            
            return await work()
        }
    }
    
    func scheduleRead<R: Sendable>(_ work: @escaping @Sendable () async throws -> R) -> Task<R, any Error> {
        let locked = lock()
        
        return .init {
            defer { unlock() }
            
            await locked.value
            
            return try await work()
        }
    }
    
    func scheduleWrite<R: Sendable>(_ work: @escaping @Sendable () async -> R) -> Task<R, Never> {
        let locked = exclusiveLock()
        
        return .init {
            defer { unlock() }
            
            await locked.value
            
            return await work()
        }
    }
    
    func scheduleWrite<R: Sendable>(_ work: @escaping @Sendable () async throws -> R) -> Task<R, any Error> {
        let locked = exclusiveLock()
        
        return .init {
            defer { unlock() }
            
            await locked.value
            
            return try await work()
        }
    }

    func read<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await lock().value
        defer { unlock() }
        
        return try await work()
    }
    
    func write<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await exclusiveLock().value
        defer { unlock() }
        
        return try await work()
    }
}

public struct SharedLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async -> Task<Void, Never> { await lock.lock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        try await lock.read(work)
    }
}

public struct ExclusiveLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async -> Task<Void, Never> { await lock.exclusiveLock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
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
