import CollectionExtensions
import Combine
import Foundation

public actor SerialQueue: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        public init() {}
    }
    
    public struct CancelHandle: Cancellable, Sendable {
        let queue: SerialQueue
        let id: UUID

        public func cancel() {
            Task { await queue.cancel(id: id) }
        }
    }

    init() {
        Task(operation: run)
    }

    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) async -> CancelHandle {
        let job = IdentifiableJob(id: .init(), work: work)
        
        if let continuation {
            continuation.resume(returning: job)
            self.continuation = nil
        } else {
            enqueued.append(job)
        }
        
        return .init(queue: self, id: job.id)
    }

    public func cancelAll() {
        enqueued.removeAll()
        current?.task.cancel()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private typealias IdentifiableJob = CooperativeSynchronization.IdentifiableJob<JobConfig>
    private typealias IdentifiableTask = CooperativeSynchronization.IdentifiableTask<JobConfig>
            
    private var current: IdentifiableTask?
    private var enqueued: [IdentifiableJob] = []
    
    private var continuation: CheckedContinuation<IdentifiableJob, any Error>?
    
    @Sendable
    private nonisolated func run() async throws {
        while true {
            let task = try await startNextJob()
            
            try? await task.task.value
        }
    }

    private func cancel(id: UUID) {
        enqueued.remove(id: id)
        
        if current?.id == id {
            current?.task.cancel()
        }
    }
    
    private func startNextJob() async throws -> IdentifiableTask {
        let job = try await {
            if let job = enqueued.safelyRemoveFirst() {
                return job
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                }
            }
        }()
        
        let task = job.start()
        current = task
        
        return task
    }
}
