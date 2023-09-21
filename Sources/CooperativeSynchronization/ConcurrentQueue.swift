import CollectionExtensions
import Combine
import Foundation
import Synchronization

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
    
    public struct CancelHandle: Cancellable, Sendable {
        fileprivate weak var state: State?
        let id: UUID
        
        public func cancel() {
            state?.cancel(id: id)
        }
    }
    
    fileprivate typealias IdentifiableJob = CooperativeSynchronization.IdentifiableJob<JobConfig>
    fileprivate typealias IdentifiableTask = CooperativeSynchronization.IdentifiableTask<JobConfig>
    
    fileprivate final class State: Sendable {
        final class Runner: Hashable, Sendable {
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

            let _mode: Synchronization.Synchronized<Mode> = .init(wrappedValue: .idle)
            
            var mode: Mode {
                get { _mode.wrappedValue }
                set { _mode.wrappedValue = newValue }
            }

            init(run: @escaping @Sendable (Runner) async throws -> Void) {
                Task { try await run(self) }
            }

            static func == (lhs: Runner, rhs: Runner) -> Bool {
                lhs === rhs
            }
            
            func hash(into hasher: inout Hasher) {
                ObjectIdentifier(self).hash(into: &hasher)
            }
        }
        
        struct State {
            var runners: Set<Runner> = []
            var enqueued: [IdentifiableJob] = []
        }

        init(maxConcurrency: Int) {
            self.maxConcurrency = maxConcurrency
        }
        
        let maxConcurrency: Int
        let _state: Synchronization.Synchronized<State> = .init(wrappedValue: .init())
        
        func schedule(job: IdentifiableJob) {
            _state.write { [maxConcurrency] state in
                state.enqueued.append(job)

                if state.runners.count < maxConcurrency {
                    print("ADDING RUNNER")
                    state.runners.insert(.init(run: run))
                }
            }
        }
        
        func cancelAll() {
            _state.write { state in
                state.enqueued.removeAll()
                
                state.runners
                    .compactMap(\.mode.currentTask)
                    .forEach { $0.task.cancel() }
            }
        }

        func cancel(id: UUID) {
            _state.write { state in
                state.enqueued.remove(id: id)
                
                state.runners
                    .lazy
                    .compactMap(\.mode.currentTask)
                    .filter { task in task.id == id }
                    .forEach { task in task.task.cancel() }
            }
        }
        
        @Sendable
        private func run(runner: Runner) async {
            while let task = nextReadyTask(for: runner) {
                await task.task.value

                _state.write { [maxConcurrency] state in
                    runner.mode = .idle
                    
                    if task.config.barrier, let next = state.enqueued.first {
                        let count = min(next.config.barrier ? 1 : state.enqueued.count, maxConcurrency - state.runners.count)
                        
                        for _ in 0 ..< count {
                            state.runners.insert(.init(run: run))
                        }
                    }
                }
            }
        }
        
        private func nextReadyTask(for runner: Runner) -> IdentifiableTask? {
            _state.write { state in
                let currentTasks = state.runners
                    .compactMap(\.mode.currentTask)
                
                let currentBarrierTask = currentTasks
                    .first(where: \.config.barrier)
                
                guard let job = state.enqueued.first,
                      currentBarrierTask == nil,
                      !job.config.barrier || currentTasks.isEmpty else {
                    state.runners.remove(runner)
                    return nil
                }
                
                state.enqueued.removeFirst()
                
                let task = job.start()
                runner.mode = .running(task)
                
                return task
            }
        }
    }

    private let state: State

    public init(maxConcurrency: Int = .max) {
        state = .init(
            maxConcurrency: maxConcurrency
        )
    }

    deinit {
        state.cancelAll()
    }
    
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> CancelHandle {
        let job = IdentifiableJob(
            id: .init(),
            config: config,
            work: work
        )
        
        state.schedule(job: job)

        return .init(state: state, id: job.id)
    }

    public func cancelAll() {
        state.cancelAll()
    }
}
