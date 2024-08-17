public final class ScopedScheduler<Base: Scheduler>: Scheduler {
    public typealias JobConfig = Base.JobConfig
        
    public let scheduler: Base
    
    public init(scheduler: Base) {
        self.scheduler = scheduler
    }
    
    deinit {
        Task { await cancelAll() }
    }

    @discardableResult
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) async -> Base.CancelHandle {
        await scheduler.schedule(config: config, work)
    }

    public func cancelAll() async {
        await scheduler.cancelAll()
    }
}

public extension Scheduler {
    var scoped: ScopedScheduler<Self> {
        .init(scheduler: self)
    }
}
