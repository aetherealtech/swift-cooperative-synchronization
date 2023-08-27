import AsyncExtensions
import Combine
import Foundation
import Synchronization

public protocol JobConfigProtocol {
    init()
}

public protocol Scheduler {
    associatedtype JobConfig: JobConfigProtocol
    
    @discardableResult
    func schedule(config: JobConfig, _ work: @escaping @Sendable () async -> Void) -> AnyCancellable
        
    func cancelAll()
}

public extension Scheduler {
    @discardableResult
    func schedule(_ work: @escaping @Sendable () async -> Void) -> AnyCancellable {
        schedule(config: .init(), work)
    }
}

public extension Scheduler {
    func scheduleAndWait<R>(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> R, resultIfCancelled: @autoclosure () -> R) async -> R {
        @Synchronization.Synchronized
        var continuation: CheckedContinuation<R, Never>? = nil
        
        var task: AnyCancellable?
        
        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { resultContinuation in
                    continuation = resultContinuation
                    
                    task = schedule(config: config) { [_continuation] in
                        let continuation = _continuation.getAndSet { continuation in
                            continuation = nil
                        }
                        
                        continuation?.resume(returning: await work())
                    }
                }
            },
            onCancel: { [task, _continuation] in
                task?.cancel()
                
                _continuation.write { continuation in
                    continuation?.resume(returning: resultIfCancelled())
                    continuation = nil
                }
            }
        )
    }
    
    func scheduleAndWait<R>(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> R?) async -> R? {
        await scheduleAndWait(config: config, work, resultIfCancelled: nil)
    }
    
    func scheduleAndWait(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) async {
        await scheduleAndWait(config: config, work, resultIfCancelled: ())
    }
    
    func scheduleAndWait<R>(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> R) async throws -> R {
        @Synchronization.Synchronized
        var continuation: CheckedContinuation<R, Error>? = nil
        
        var task: AnyCancellable?
        
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { resultContinuation in
                    continuation = resultContinuation
                    
                    task = schedule(config: config) { [_continuation] in
                        let continuation = _continuation.getAndSet { continuation in
                            continuation = nil
                        }
                        
                        let result = await Result { try await work() }
                        continuation?.resume(with: result)
                    }
                }
            },
            onCancel: { [task, _continuation] in
                task?.cancel()
                
                _continuation.write { continuation in
                    continuation?.resume(throwing: CancellationError())
                    continuation = nil
                }
            }
        )
    }
}

public struct DefaultScheduler: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        let priority: TaskPriority?
        
        public init() {
            self.init(priority: nil)
        }
 
        public init(
            priority: TaskPriority?
        ) {
            self.priority = priority
        }
    }
    
    public let defaultPriority: TaskPriority?
    
    public init(defaultPriority: TaskPriority? = nil) {
        self.defaultPriority = defaultPriority
    }

    @discardableResult
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> AnyCancellable {
        .init(Task(priority: config.priority ?? defaultPriority, operation: work))
    }

    public func cancelAll() {}
}
