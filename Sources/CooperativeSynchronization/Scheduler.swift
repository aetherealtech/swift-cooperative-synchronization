import AsyncExtensions
import Combine
import Foundation
import Synchronization

public protocol JobConfigProtocol {
    init()
}

public protocol Scheduler: Sendable {
    associatedtype JobConfig: JobConfigProtocol
    associatedtype CancelHandle: Cancellable & Sendable
    
    @discardableResult
    func schedule(config: JobConfig, _ work: @escaping @Sendable () async -> Void) -> CancelHandle
        
    func cancelAll()
}

public extension Scheduler {
    @discardableResult
    func schedule(_ work: @escaping @Sendable () async -> Void) -> CancelHandle {
        schedule(config: .init(), work)
    }
}

private struct ScheduleWaitState<R, Failure: Error> {
    var continuation: CheckedContinuation<R, Failure>?
    var task: AnyCancellable?
    var cancelled = false
}

private struct TaskState<Success, Failure: Error> {
    enum Mode {
        case scheduled
        case running
        case cancelled
        case finished(Result<Success, Failure>)
    }
    
    var mode: Mode = .scheduled
    var continuation: CheckedContinuation<Success, Failure>?
    
    var isRunning: Bool {
        switch mode {
            case .running: return true
            default: return false
        }
    }
    
    var isCancelled: Bool {
        switch mode {
            case .cancelled: return true
            default: return false
        }
    }
    
    var result: Result<Success, Failure>? {
        switch mode {
            case let .finished(result): return result
            default: return nil
        }
    }
}

public extension Scheduler {
    func schedule<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> Result<R, Error> = .failure(CancellationError()),
        _ work: @escaping @Sendable () async throws -> R
    ) -> Task<R, Error> {
        .init(operation: scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        ))
    }
    
    func schedule<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> R,
        _ work: @escaping @Sendable () async -> R
    ) -> Task<R, Never> {
        .init(operation: scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        ))
    }
    
    func schedule(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        schedule(
            config: config,
            resultIfCancelled: (),
            work
        )
    }

    func schedule<R>(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> R?
    ) -> Task<R?, Never> {
        schedule(
            config: config,
            resultIfCancelled: nil, work
        )
    }

    func scheduleAndWait<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> R,
        _ work: @escaping @Sendable () async -> R
    ) async -> R {
        await scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        )()
    }

    func scheduleAndWait<R>(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> R?
    ) async -> R? {
        await scheduleAndWait(
            config: config,
            resultIfCancelled: nil,
            work
        )
    }

    func scheduleAndWait(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) async {
        await scheduleAndWait(
            config: config,
            resultIfCancelled: (),
            work
        )
    }

    func scheduleAndWait<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> Result<R, Error> = .failure(CancellationError()),
        _ work: @escaping @Sendable () async throws -> R
    ) async throws -> R {
        try await scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        )()
    }
    
    private func scheduleInternal<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> Result<R, Error> = .failure(CancellationError()),
        _ work: @escaping @Sendable () async throws -> R
    ) -> @Sendable () async throws -> R {
        @Synchronization.Synchronized
        var taskState: TaskState<R, Error> = .init()
        
        let cancelHandle = schedule { [_taskState] in
            guard _taskState.write({ taskState in
                let cancelled = taskState.isCancelled
                taskState.mode = .running
                return !cancelled
            }) else {
                return
            }
            
            let result: Result<R, Error> = Task.isCancelled ? resultIfCancelled() : await Result { try await work() }
            
            _taskState.write { taskState in
                if let continuation = taskState.continuation {
                    continuation.resume(with: result)
                    taskState.continuation = nil
                }
                
                taskState.mode = .finished(result)
            }
        }
                
        return { [_taskState] in
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        _taskState.write { taskState in
                            if Task.isCancelled && !taskState.isRunning {
                                cancelHandle.cancel()
                                taskState.mode = .cancelled
                                continuation.resume(with: resultIfCancelled())
                            } else if let result = taskState.result {
                                continuation.resume(with: result)
                            } else {
                                taskState.mode = .scheduled
                                taskState.continuation = continuation
                            }
                        }
                    }
                },
                onCancel: {
                    _taskState.write { taskState in
                        cancelHandle.cancel()
                        
                        if let continuation = taskState.continuation {
                            continuation.resume(with: resultIfCancelled())
                            taskState.continuation = nil
                        }
                        
                        taskState.mode = .cancelled
                    }
                }
            )
        }
    }
    
    func scheduleInternal<R>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> R,
        _ work: @escaping @Sendable () async -> R
    ) -> @Sendable () async -> R {
        @Synchronization.Synchronized
        var taskState: TaskState<R, Never> = .init()
        
        let cancelHandle = schedule { [_taskState] in
            guard _taskState.write({ taskState in
                let cancelled = taskState.isCancelled
                taskState.mode = .running
                return !cancelled
            }) else {
                return
            }
            
            let result = Task.isCancelled ? resultIfCancelled() : await work()
            
            _taskState.write { taskState in
                if let continuation = taskState.continuation {
                    continuation.resume(returning: result)
                    taskState.continuation = nil
                }
                
                taskState.mode = .finished(.success(result))
            }
        }
                
        return { [_taskState] in
            await withTaskCancellationHandler(
                operation: {
                    await withCheckedContinuation { continuation in
                        _taskState.write { taskState in
                            if Task.isCancelled && !taskState.isRunning {
                                cancelHandle.cancel()
                                taskState.mode = .cancelled
                                continuation.resume(returning: resultIfCancelled())
                            } else if let result = taskState.result {
                                continuation.resume(with: result)
                            } else {
                                taskState.mode = .scheduled
                                taskState.continuation = continuation
                            }
                        }
                    }
                },
                onCancel: {
                    _taskState.write { taskState in
                        cancelHandle.cancel()

                        if let continuation = taskState.continuation {
                            continuation.resume(returning: resultIfCancelled())
                            taskState.continuation = nil
                        }
                        
                        taskState.mode = .cancelled
                    }
                }
            )
        }
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
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        .init(priority: config.priority ?? defaultPriority, operation: work)
    }

    public func cancelAll() {}
}
