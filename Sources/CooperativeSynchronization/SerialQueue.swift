import Combine
import Foundation
import Synchronization

fileprivate struct IdentifiableJob: Identifiable {
    let id: UUID
    let work: @Sendable () async -> Void
}

fileprivate struct IdentifiableTask: Identifiable {
    let id: UUID
    let task: Task<Void, Never>
}

public final class SerialQueue: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        public init() {}
    }

    fileprivate struct State {
        enum Mode {
            case idle
            case waiting(CheckedContinuation<IdentifiableTask, Error>)
            case running(IdentifiableTask)
        }

        var mode: Mode = .idle
        var enqueued: [IdentifiableJob] = []

        mutating func cancelAll() {
            enqueued.removeAll()

            switch mode {
                case let .waiting(continuation):
                    continuation.resume(throwing: CancellationError())
                case let .running(task):
                    task.task.cancel()
                default:
                    break
            }
        }

        mutating func schedule(id: UUID, _ work: @escaping @Sendable () async -> Void) {
            switch mode {
                case let .waiting(continuation):
                    let task = IdentifiableTask(id: id, task: Task { await work() })
                    mode = .running(task)
                    continuation.resume(returning: task)
                default:
                    let job = IdentifiableJob(id: id, work: work)
                    enqueued.append(job)
            }
        }

        mutating func cancel(id: UUID) {
            if case let .running(currentTask) = mode, currentTask.id == id {
                currentTask.task.cancel()
            } else {
                enqueued.remove(id: id)
            }
        }
    }

    @Synchronization.Synchronized
    private var state: State = .init()

    private let runner: Task<Void, Error>

    public init() {
        runner = Task(operation: _state.run)
    }

    deinit {
        runner.cancel()

        _state.write { state in
            state.cancelAll()
        }
    }
    
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> AnyCancellable {
        let id = UUID()
        
        _state.write { state in
            state.schedule(id: id, work)
        }

        return .init { [weak _state] in _state?.write { state in state.cancel(id: id) } }
    }

    public func cancelAll() {
        _state.write { state in
            state.cancelAll()
        }
    }
}

extension Synchronization.Synchronized where T == SerialQueue.State {
    @Sendable
    func run() async throws {
        while true {
            try Task.checkCancellation()
            
            let task = try await withCheckedThrowingContinuation { continuation in
                write { state in
                    guard let job = state.enqueued.safelyRemoveFirst() else {
                        state.mode = .waiting(continuation)
                        return
                    }
                    
                    let task = IdentifiableTask(id: job.id, task: Task { await job.work() })
                    state.mode = .running(task)
                }
                
                continuation.resume(returning: task)
            }
            
            await task.task.value
            
            write { state in
                state.mode = .idle
            }
        }
    }
}
