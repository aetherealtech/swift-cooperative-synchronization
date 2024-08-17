import CollectionExtensions
import Combine
import Foundation

public actor BatchingQueue<S: Scheduler>: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        public enum RetryPolicy: Sendable {
            case discard
            case retry
            case abort
        }
        
        let retryPolicy: RetryPolicy
        
        public init() {
            self.retryPolicy = .discard
        }
        
        public init(
            retryPolicy: RetryPolicy = .discard
        ) {
            self.retryPolicy = retryPolicy
        }
    }
    
    public struct CancelHandle: Cancellable, Sendable {
        let queue: BatchingQueue
        let id: UUID
        
        public func cancel() {
            Task { await queue.cancel(id: id) }
        }
    }

    public init(
        scheduler: S,
        batchConfig: S.JobConfig
    ) {
        self.scheduler = scheduler
        self.batchConfig = batchConfig
    }

    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) async -> CancelHandle {
        let job = IdentifiableJob(id: .init(), work: work)
        
        await schedule(job: job)

        return .init(queue: self, id: job.id)
    }

    public func cancelAll() {
        current?.task.cancel()
        enqueued.removeAll()
    }
    
    private typealias IdentifiableJob = CooperativeSynchronization.IdentifiableJob<JobConfig>
    private typealias IdentifiableTask = CooperativeSynchronization.IdentifiableTask<JobConfig>

    private enum Mode {
        case idle
        case scheduled
        case running
    }
    
    private func schedule(job: IdentifiableJob) async {
        enqueued.append(job)
        
        if !running {
            running = true
            await scheduler.schedule(config: batchConfig, run)
        }
    }
    
    private func cancel(id: UUID) {
        enqueued.remove(id: id)
        
        if current?.id == id {
            current?.task.cancel()
        }
    }
    
    private let scheduler: S
    private let batchConfig: S.JobConfig

    private var current: IdentifiableTask?
    private var enqueued: [IdentifiableJob] = []
    private var running = false

    @Sendable
    private func run() async {
        while let task = {
            guard let job = enqueued.first else {
                running = false
                return nil as IdentifiableTask?
            }
            
            let task = job.start()
            current = task
            
            return task
        }() {
            do {
                try await task.task.value
                enqueued.remove(id: task.id)
            } catch {
                switch task.config.retryPolicy {
                    case .discard:
                        enqueued.remove(id: task.id)
                    case .retry:
                        await scheduler.schedule(config: batchConfig, run)
                        return
                    case .abort:
                        running = false
                        return
                }
            }
        }
    }
}

public extension Scheduler {
    func batching(batchConfig: JobConfig = .init()) -> BatchingQueue<Self> {
        .init(
            scheduler: self,
            batchConfig: batchConfig
        )
    }
}
