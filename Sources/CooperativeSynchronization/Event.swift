import AsyncExtensions
import CollectionExtensions
import Foundation

public final class Event {
    public init() {}

    public var signaled: Bool {
        get async throws { try await lock.lock { signaledInternal } }
    }
    
    public func wait() async throws {
        try await lock.lock()
        
        do {
            if !signaledInternal {
                try await conditionVariable.wait(lock: lock)
            }
            
            await lock.unlock()
        } catch {
            await lock.unlock()
            throw error
        }
    }

    public func signal(reset: Bool = true) async throws {
        try await lock.lock {
            signaledInternal = !reset
            await conditionVariable.notifyAll()
        }
    }

    public func reset() async throws {
        try await lock.lock {
            signaledInternal = false
        }
    }

    private let lock = Lock()
    private var signaledInternal = false
    private let conditionVariable = ConditionVariable()
}
