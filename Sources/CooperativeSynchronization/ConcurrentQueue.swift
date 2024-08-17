import CollectionExtensions
import Combine
import Foundation

public actor ConcurrentQueue: Scheduler {
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
        let queue: ConcurrentQueue
        let id: UUID
        
        public func cancel() {
            Task { await queue.cancel(id: id) }
        }
    }
    
    public let maxConcurrency: Int

    public init(maxConcurrency: Int = .max) {
        self.maxConcurrency = maxConcurrency
    }

    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) -> CancelHandle {
        let job = IdentifiableJob(
            id: .init(),
            config: config,
            work: work
        )
        
        enqueued.append(job)

        if runners.count < maxConcurrency {
            addRunner()
        }

        return .init(queue: self, id: job.id)
    }

    public func cancelAll() {
        enqueued.removeAll()
        
        runners
            .lazy
            .compactMap(\.value.mode.currentTask)
            .forEach { $0.task.cancel() }
    }

    private typealias IdentifiableJob = CooperativeSynchronization.IdentifiableJob<JobConfig>
    private typealias IdentifiableTask = CooperativeSynchronization.IdentifiableTask<JobConfig>
    
    private struct Runner: Sendable {
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
        
        var mode: Mode = .idle

        init(run: @escaping @Sendable () async throws -> Void) {
            Task { try await run() }
        }
    }
    
    private var runners: [UUID: Runner] = [:]
    private var enqueued: [IdentifiableJob] = []

    private func addRunner() {
        print("ADDING RUNNER")
        let id = UUID()
        runners[id] = .init { await self.run(id: id) }
    }
    
    @Sendable
    private func run(id: UUID) async {
        while let task = nextReadyTask(for: id) {
            try? await task.task.value

            runners[id]!.mode = .idle
            
            if task.config.barrier, let next = enqueued.first, !next.config.barrier {
                let count = min(enqueued.count - 1, maxConcurrency - runners.count)
                
                for _ in 0 ..< count {
                    addRunner()
                }
            }
        }
    }
    
    private func nextReadyTask(for id: UUID) -> IdentifiableTask? {
        let currentTasks = runners
            .lazy
            .compactMap(\.value.mode.currentTask)
        
        let currentBarrierTask = currentTasks
            .first(where: \.config.barrier)
        
        guard let job = enqueued.first,
              currentBarrierTask == nil,
              !job.config.barrier || currentTasks.isEmpty else {
            runners.removeValue(forKey: id)
            return nil
        }
        
        enqueued.removeFirst()
        
        let task = job.start()
        runners[id]!.mode = .running(task)
        
        return task
    }
    
    private func cancel(id: UUID) {
        enqueued.remove(id: id)
        
        runners
            .lazy
            .compactMap(\.value.mode.currentTask)
            .filter { task in task.id == id }
            .forEach { task in task.task.cancel() }
    }
    
}
