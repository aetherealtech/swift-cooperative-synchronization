public actor CountdownLatch {
    public init(value: Int) {
        self.value = value
    }
    
    public func wait() async throws {
        if value > 0 {
            try await condition.wait() {
                value == 0
            }
        }
    }
    
    public func signal() async throws {
        let value = self.value
        self.value -= 1

        if value == 0 {
            await condition.notifyAll()
        }
    }
    
    private var value: Int
    private var condition = ConditionVariable()
}
