import CollectionExtensions
import Combine
import Foundation
import Synchronization

fileprivate struct IdentifiableJob: Identifiable {
    let id: UUID
    let barrier: Bool
    let work: @Sendable () async -> Void
}

fileprivate struct IdentifiableTask: Identifiable {
    let id: UUID
    let barrier: Bool
    let task: Task<Void, Never>
}

public final class ConcurrentQueue: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        let barrier: Bool
        
        public init() {
            self.init(barrier: false)
        }
        
        public init(barrier: Bool) {
            self.barrier = barrier
        }
    }
    
    fileprivate struct State {
        struct Runner: Identifiable {
            enum Mode {
                case idle
                case running(IdentifiableTask)

                var isIdle: Bool {
                    if case .idle = self {
                        return true
                    }

                    return false
                }

                var currentTask: IdentifiableTask? {
                    if case let .running(currentTask) = self {
                        return currentTask
                    }

                    return nil
                }
            }

            let id = UUID()
            var mode: Mode = .idle

            init(run: @escaping @Sendable (ID) async throws -> Void) {
                task = .init { [id] in try await run(id) }
            }

            func cancel() {
                task.cancel()
            }

            private let task: Task<Void, Error>
        }

        init(maxConcurrency: Int) {
            self.maxConcurrency = maxConcurrency
        }
        
        let maxConcurrency: Int
        var runners: [Runner] = []
        var enqueued: [IdentifiableJob] = []
        
        mutating func cancelAll() {
            enqueued.removeAll()

            runners
                .compactMap(\.mode.currentTask)
                .forEach { $0.task.cancel() }
        }

        mutating func cancel(id: UUID) {
            let matchingTask = runners
                .lazy
                .compactMap(\.mode.currentTask)
                .first { $0.id == id }

            if let matchingTask {
                matchingTask.task.cancel()
            } else {
                enqueued.remove(id: id)
            }
        }
        
        mutating func nextReadyTask(id: State.Runner.ID) -> IdentifiableTask? {
            let currentTasks = runners
                .compactMap(\.mode.currentTask)

            let currentBarrierTask = currentTasks
                .first(where: \.barrier)

            guard let job = enqueued.first,
                  currentBarrierTask == nil,
                  !job.barrier || currentTasks.isEmpty else {
                runners.remove(id: id)
                return nil
            }

            enqueued.removeFirst()

            let task = IdentifiableTask(id: job.id, barrier: job.barrier, task: Task { await job.work() })
            runners[id: id]?.mode = .running(task)

            return task
        }
    }

    private let _state: Synchronization.Synchronized<State>

    private var state: State {
        get { _state.wrappedValue }
        set { _state.wrappedValue = newValue }
    }
    
    public init(maxConcurrency: Int = .max) {
        _state = .init(wrappedValue: .init(
            maxConcurrency: maxConcurrency
        ))
    }

    deinit {
        _state.write {
            state in state.cancelAll()
        }
    }
    
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> AnyCancellable {
        let id = UUID()
        
        let job = IdentifiableJob(
            id: id,
            barrier: config.barrier,
            work: work
        )

        _state.write { state in
            state.enqueued.append(job)

            if state.runners.count < state.maxConcurrency {
                print("ADDING RUNNER")

                state.runners.append(.init(run: _state.run))
            }
        }
        
        return .init { [weak _state] in
            _state?.write { state in
                state.cancel(id: id)
            }
        }
    }

    public func cancelAll() {
        _state.write {
            state in state.cancelAll()
        }
    }
}

extension Synchronization.Synchronized where T == ConcurrentQueue.State {
    @Sendable
    func run(id: ConcurrentQueue.State.Runner.ID) async throws {
        while let task = write({ state in state.nextReadyTask(id: id) }) {
            try Task.checkCancellation()

            await task.task.value

            write { state in
                state.runners[id: id]?.mode = .idle
                
                if task.barrier, let next = state.enqueued.first {
                    let count = min(next.barrier ? 1 : state.enqueued.count, state.maxConcurrency - state.runners.count)
                    
                    for _ in 0 ..< count {
                        state.runners.append(.init(run: self.run))
                    }
                }
            }
        }
    }
}
