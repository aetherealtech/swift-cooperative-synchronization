import Foundation

public actor ReadWriteLock {
    public init(maxReaders: Int = .max) {
        self.maxReaders = maxReaders
    }
    
    public func lock() async {
        await lock(
            ready: readers < maxReaders && !writing,
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
    
    public func exclusiveLock() async {
        await lock(
            ready: readers == 0 && !writing,
            acquire: { writing = true },
            waiterType: .writer
        )
    }

    private struct Waiter {
        enum WaiterType {
            case reader
            case writer
        }
        
        let type: WaiterType
        let continuation: CheckedContinuation<Void, Never>
    }
    
    private let maxReaders: Int
    
    private var readers = 0
    private var writing = false

    private var waiters: [Waiter] = [] {
        didSet {
            print("WAITERS: \(waiters)")
        }
    }
    
    private func lock(
        ready: Bool,
        acquire: () -> Void,
        waiterType: Waiter.WaiterType
    ) async {
        if !ready || !waiters.lazy.filter({ $0.type == waiterType }).isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(Waiter(
                    type: waiterType,
                    continuation: continuation
                ))
            }
        } else {
            acquire()
        }
    }
    
    private func notify() {
        while let waiter = waiters.first {
            let ready = { switch waiter.type {
                case .writer:
                    guard !writing && readers == 0 else { return false }
                    writing = true
                    return true
                    
                case .reader:
                    guard !writing && readers < maxReaders else { return false }
                    readers += 1
                    return true
            } }()
            
            guard ready else { break }
            
            waiters.removeFirst()
            waiter.continuation.resume()
        }
    }
}

public extension ReadWriteLock {
    func read<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await lock()
        defer { unlock() }
        
        return try await work()
    }
    
    func write<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        await exclusiveLock()
        defer { unlock() }
        
        return try await work()
    }
}

public struct SharedLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async { await lock.lock() }
    public func unlock() async { await lock.unlock() }
    
    public func lock<R: Sendable>(_ work: @Sendable () async throws -> R) async rethrows -> R {
        try await lock.read(work)
    }
}

public struct ExclusiveLock: Lockable {
    let lock: ReadWriteLock
    
    public func lock() async { await lock.exclusiveLock() }
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
