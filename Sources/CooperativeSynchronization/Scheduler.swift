import AsyncExtensions
import Combine
import Foundation
import Synchronization

public protocol JobConfigProtocol {
    init()
}

public protocol Scheduler: Sendable {
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

private struct ScheduleWaitState<R, Failure: Error> {
    var continuation: CheckedContinuation<R, Failure>?
    var task: AnyCancellable?
    var cancelled = false
}

public extension Scheduler {
    func scheduleAndWait<R>(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> R,
        resultIfCancelled: @autoclosure @Sendable () -> R
    ) async -> R {
        @Synchronization.Synchronized
        var state: ScheduleWaitState<R, Never> = .init()
        
        return await withTaskCancellationHandler(
            operation: { [_state] in
                if _state.cancelled {
                    return resultIfCancelled()
                }

                return await withCheckedContinuation { resultContinuation in
                    _state.write { state in
                        state.continuation = resultContinuation
                        state.task = schedule(config: config) {
                            guard let continuation = _state.write({ state in
                                let continuation = state.continuation
                                state.continuation = nil
                                return continuation
                            }) else {
                                return
                            }

                            let result = await work()
                            continuation.resume(returning: result)
                        }
                    }
                }
            },
            onCancel: { [_state] in
                _state.write { state in
                    state.cancelled = true
                    state.task?.cancel()
                    if let continuation = state.continuation {
                        continuation.resume(returning: resultIfCancelled())
                    }
                    
                    state.continuation = nil
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
        var state: ScheduleWaitState<R, Error> = .init()
        
        return try await withTaskCancellationHandler(
            operation: { [_state] in
                if _state.cancelled {
                    throw CancellationError()
                }

                return try await withCheckedThrowingContinuation { resultContinuation in
                    _state.write { state in
                        state.continuation = resultContinuation
                        state.task = schedule(config: config) {
                            guard let continuation = _state.write({ state in
                                let continuation = state.continuation
                                state.continuation = nil
                                return continuation
                            }) else {
                                return
                            }

                            let result = await Result { try await work() }
                            continuation.resume(with: result)
                        }
                    }
                }
            },
            onCancel: { [_state] in
                _state.write { state in
                    state.cancelled = true
                    state.task?.cancel()
                    if let continuation = state.continuation {
                        continuation.resume(throwing: CancellationError())
                    }
                    
                    state.continuation = nil
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
