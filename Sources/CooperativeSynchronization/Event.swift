import AsyncExtensions
import CollectionExtensions
import Foundation

public actor Event {
    public init() {}

    public private(set) var signaled = false
    
    public func wait() async throws {
        if !signaled {
            try await conditionVariable.wait()
        }
    }

    public func signal(reset: Bool = true) async throws {
        signaled = !reset
        await conditionVariable.notifyAll()
    }

    public func reset() async throws {
        signaled = false
    }

    private let conditionVariable = ConditionVariable()
}
