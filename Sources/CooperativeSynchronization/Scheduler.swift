import AsyncExtensions
import Combine
import Foundation

public protocol JobConfigProtocol: Sendable {
    init()
}

public protocol Scheduler: Sendable {
    associatedtype JobConfig: JobConfigProtocol
    associatedtype CancelHandle: Cancellable & Sendable
    
    @discardableResult
    func schedule(config: JobConfig, _ work: @escaping @Sendable () async throws -> Void) async -> CancelHandle
        
    func cancelAll() async
}

public extension Scheduler {
    @discardableResult
    func schedule(_ work: @escaping @Sendable () async throws -> Void) async -> CancelHandle {
        await schedule(config: .init(), work)
    }
}

private struct TaskState<Success: Sendable, Failure: Error>: Sendable {
    enum Mode: Sendable {
        case scheduled
        case running
        case cancelled
        case finished(Result<Success, Failure>)
    }
    
    var mode: Mode = .scheduled
    var continuation: CheckedContinuation<Success, Failure>?
    
    var isScheduled: Bool {
        switch mode {
            case .scheduled: return true
            default: return false
        }
    }
    
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
    func schedule<R: Sendable>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> Result<R, any Error> = .failure(CancellationError()),
        _ work: @escaping @Sendable () async throws -> R
    ) async -> Task<R, any Error> {
        await .init(operation: scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        ))
    }
    
    func schedule<R: Sendable>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> R,
        _ work: @escaping @Sendable () async -> R
    ) async -> Task<R, Never> {
        await .init(operation: scheduleInternal(
            config: config,
            resultIfCancelled: resultIfCancelled(),
            work
        ))
    }
    
    func schedule(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> Void
    ) async -> Task<Void, Never> {
        await schedule(
            config: config,
            resultIfCancelled: (),
            work
        )
    }

    func schedule<R: Sendable>(
        config: JobConfig = .init(),
        _ work: @escaping @Sendable () async -> R?
    ) async -> Task<R?, Never> {
        await schedule(
            config: config,
            resultIfCancelled: nil, work
        )
    }

    func scheduleAndWait<R: Sendable>(
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

    func scheduleAndWait<R: Sendable>(
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

    func scheduleAndWait<R: Sendable>(
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
    
    private func scheduleInternal<R: Sendable>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> Result<R, any Error>,
        _ work: @escaping @Sendable () async throws -> R
    ) async -> @Sendable () async throws -> R {
        let _taskState = Isolated(TaskState<R, any Error>())
        
        let cancelHandle = await schedule { [_taskState] in
            guard await _taskState.write({ taskState in
                if taskState.isCancelled { return false }
                taskState.mode = .running
                return true
            }) else {
                return
            }
            
            let result: Result<R, any Error> = Task.isCancelled ? resultIfCancelled() : await Result { try await work() }
            
            await _taskState.write { taskState in
                if let continuation = taskState.continuation {
                    continuation.resume(with: result)
                    taskState.continuation = nil
                } else {
                    taskState.mode = .finished(result)
                }
            }
        }
                
        return { [_taskState] in
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        let cancelled = Task.isCancelled
                        
                        Task {
                            await _taskState.write { taskState in
                                switch taskState.mode {
                                    case .scheduled:
                                        if cancelled {
                                            cancelHandle.cancel()
                                            taskState.mode = .cancelled
                                            continuation.resume(with: resultIfCancelled())
                                        } else {
                                            taskState.continuation = continuation
                                        }
                                        
                                    case .running:
                                        taskState.continuation = continuation
                                        
                                    case .cancelled:
                                        continuation.resume(with: resultIfCancelled())
                                        
                                    case let .finished(result):
                                        continuation.resume(with: result)
                                }
                            }
                        }
                    }
                },
                onCancel: {
                    Task {
                        await _taskState.write { taskState in
                            cancelHandle.cancel()
                            
                            if taskState.isScheduled {
                                if let continuation = taskState.continuation {
                                    continuation.resume(with: resultIfCancelled())
                                    taskState.continuation = nil
                                } else {
                                    taskState.mode = .cancelled
                                }
                            }
                        }
                    }
                }
            )
        }
    }
    
    private func scheduleInternal<R: Sendable>(
        config: JobConfig = .init(),
        resultIfCancelled: @escaping @Sendable @autoclosure () -> R,
        _ work: @escaping @Sendable () async -> R
    ) async -> @Sendable () async -> R {
        let _taskState = Isolated(TaskState<R, Never>())
        
        let cancelHandle = await schedule { [_taskState] in
            guard await _taskState.write({ taskState in
                if taskState.isCancelled { return false }
                taskState.mode = .running
                return true
            }) else {
                return
            }
            
            let result = Task.isCancelled ? resultIfCancelled() : await work()
            
            await _taskState.write { taskState in
                if let continuation = taskState.continuation {
                    continuation.resume(returning: result)
                    taskState.continuation = nil
                } else {
                    taskState.mode = .finished(.success(result))
                }
            }
        }
                
        return { [_taskState] in
            await withTaskCancellationHandler(
                operation: {
                    await withCheckedContinuation { continuation in
                        let cancelled = Task.isCancelled
                        
                        Task {
                            await _taskState.write { taskState in
                                switch taskState.mode {
                                    case .scheduled:
                                        if cancelled {
                                            cancelHandle.cancel()
                                            taskState.mode = .cancelled
                                            continuation.resume(returning: resultIfCancelled())
                                        } else {
                                            taskState.continuation = continuation
                                        }
                                        
                                    case .running:
                                        taskState.continuation = continuation
                                        
                                    case .cancelled:
                                        continuation.resume(returning: resultIfCancelled())
                                        
                                    case let .finished(result):
                                        continuation.resume(with: result)
                                }
                            }
                        }
                    }
                },
                onCancel: {
                    Task {
                        await _taskState.write { taskState in
                            cancelHandle.cancel()
                            
                            if taskState.isScheduled {
                                if let continuation = taskState.continuation {
                                    continuation.resume(returning: resultIfCancelled())
                                    taskState.continuation = nil
                                } else {
                                    taskState.mode = .cancelled
                                }
                            }
                        }
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
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) -> Task<Void, Error> {
        .init(priority: config.priority ?? defaultPriority, operation: work)
    }

    public func cancelAll() {}
}
