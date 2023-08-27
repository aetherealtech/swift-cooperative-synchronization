public final class CountdownLatch {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        try await lock.lock()
        
        do {
            if value > 0 {
                try await condition.wait(lock: lock) {
                    value == 0
                }
            }
            
            await lock.unlock()
        } catch {
            await lock.unlock()
            throw error
        }
    }
    
    public func signal() async throws {
        let value = try await lock.lock {
            self.value -= 1
            return self.value
        }
        
        if value == 0 {
            await condition.notifyAll()
        }
    }
    
    private var value: Int
    private var lock = Lock()
    private var condition = ConditionVariable()
}
