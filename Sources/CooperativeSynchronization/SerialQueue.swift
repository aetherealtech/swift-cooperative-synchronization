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

    fileprivate final class State: @unchecked Sendable {
        var current: IdentifiableTask?
        var enqueued: [IdentifiableJob] = []
        
        let lock = Synchronization.Lock()
        let condition = ConditionVariable()
        
        @Sendable
        func run() async throws {
            while true {
                try Task.checkCancellation()
                
                let task = try await startNextJob()
                
                await task.task.value
            }
        }
        
        private func startNextJob() async throws -> IdentifiableTask {
            lock.lock()
            defer { lock.unlock() }
            
            let job = try await {
                if let job = enqueued.safelyRemoveFirst() {
                    return job
                } else {
                    try await condition.wait(lock: lock) {
                        !enqueued.isEmpty
                    }
                    
                    return enqueued.removeFirst()
                }
            }()

            let task = IdentifiableTask(id: job.id, task: Task { await job.work() })
            current = task
            
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
        let id = UUID()
        
        schedule(id: id, work)

        return .init { [weak self] in self?.cancel(id: id) }
    }

    public func cancelAll() {
        state.lock.lock {
            state.current?.task.cancel()
            state.enqueued.removeAll()
        }
    }
    
    func schedule(id: UUID, _ work: @escaping @Sendable () async -> Void) {
        let job = IdentifiableJob(id: id, work: work)

        state.lock.lock {
            state.enqueued.append(job)
        }
        
        Task {
            await state.condition.notifyOne()
        }
    }

    func cancel(id: UUID) {
        state.lock.lock {
            if state.current?.id == id {
                state.current?.task.cancel()
            } else {
                state.enqueued.remove(id: id)
            }
        }
    }
}
