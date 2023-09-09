public actor Semaphore: Sendable {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        try await condition.wait() {
            value > 0
        }
        
        value -= 1
    }
    
    public func signal() async throws {
        value += 1
        
        await condition.notifyOne()
    }
    
    private var value: Int
    private var condition = ConditionVariable()
}

public extension Semaphore {
    func acquire<R>(_ work: @Sendable () async throws -> R) async throws -> R {
        try await wait()

        let result = await Result { try await work() }
        
        try await signal()
        
        return try result.get()
    }
}
