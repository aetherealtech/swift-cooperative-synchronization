public final class Semaphore: @unchecked Sendable {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        try await lock.lock()
        
        try await condition.wait(lock: lock) {
            value > 0
        }
        
        value -= 1
        
        await lock.unlock()
    }
    
    public func signal() async throws {
        try await lock.lock { value += 1 }
        
        await condition.notifyOne()
    }
    
    private var value: Int
    private var lock = Lock()
    private var condition = ConditionVariable()
}

public extension Semaphore {
    func acquire<R>(_ work: () async throws -> R) async throws -> R {
        try await wait()
                
        let result = await Result { try await work() }
        
        try await signal()
        
        return try result.get()
    }
}
