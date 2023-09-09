import CollectionExtensions
import Combine
import Foundation
import Synchronization

public final class SerialQueue: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        public init() {}
    }
    
    fileprivate typealias IdentifiableJob = CooperativeSynchronization.IdentifiableJob<JobConfig>
    fileprivate typealias IdentifiableTask = CooperativeSynchronization.IdentifiableTask<JobConfig>

    fileprivate final class State: Sendable {
        private struct State {
            var current: IdentifiableTask?
            var enqueued: [IdentifiableJob] = []
        }
        
        private let _state: Synchronization.Synchronized<State> = .init(wrappedValue: .init())
        
        private var state: State {
            get { _state.wrappedValue }
            set { _state.wrappedValue = newValue}
        }
        
        let condition = AnyConditionVariable<Synchronization.SharedLock>()
        
        @Sendable
        func run() async throws {
            while true {
                try Task.checkCancellation()
                
                let task = try await startNextJob()
                
                await task.task.value
            }
        }
        
        fileprivate func schedule(job: IdentifiableJob) {
            _state.write { state in
                state.enqueued.append(job)
            }
            
            condition.notifyOne()
        }
        
        func cancel(id: UUID) {
            _state.write { state in
                state.enqueued.remove(id: id)
                
                if state.current?.id == id {
                    state.current?.task.cancel()
                }
            }
        }
        
        func cancelAll() {
            _state.write { state in
                state.current?.task.cancel()
                state.enqueued.removeAll()
            }
        }
        
        private func startNextJob() async throws -> IdentifiableTask {
            let job = {
                if let job = _state.write({ state in state.enqueued.safelyRemoveFirst() }) {
                    return job
                } else {
                    _state.wait(condition) { state in
                        !state.enqueued.isEmpty
                    }
                    
                    return _state.write { state in state.enqueued.removeFirst() }
                }
            }()

            let task = job.start()
            _state.write { state in state.current = task }
            
            return task
        }
    }

    private let state = State()
    private let runner: Task<Void, Error>

    public init() {
        runner = Task(operation: state.run)
    }

    deinit {
        cancelAll()
    }
    
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async -> Void) -> AnyCancellable {
        let job = IdentifiableJob(id: .init(), work: work)
        
        state.schedule(job: job)

        return .init { [weak state, id = job.id] in
            state?.cancel(id: id)
        }
    }

    public func cancelAll() {
        state.cancelAll()
    }
}
