public struct TrappingScheduler<Base: Scheduler>: Scheduler {
    public struct JobConfig: JobConfigProtocol {
        public let base: Base.JobConfig
        public let errorHandler: ErrorHandler?
        
        public init() {
            self.init(
                errorHandler: nil
            )
        }
        
        public init(
            base: Base.JobConfig = .init(),
            errorHandler: ErrorHandler?
        ) {
            self.base = base
            self.errorHandler = errorHandler
        }
    }
    
    public typealias ErrorHandler = @Sendable (any Error) -> Void
    
    public let base: Base
    public let errorHandler: ErrorHandler
    
    public init(
        base: Base,
        errorHandler: @escaping ErrorHandler
    ) {
        self.base = base
        self.errorHandler = errorHandler
    }

    @discardableResult
    public func schedule(config: JobConfig = .init(), _ work: @escaping @Sendable () async throws -> Void) async -> Base.CancelHandle {
        let errorHandler = config.errorHandler ?? errorHandler
        
        return await base.schedule(config: config.base) {
            do {
                try await work()
            } catch let error as CancellationError {
                throw error
            } catch {
                errorHandler(error)
            }
        }
    }

    public func cancelAll() async {
        await base.cancelAll()
    }
}

public extension Scheduler {
    func trapping(
        errorHandler: @escaping TrappingScheduler<Self>.ErrorHandler
    ) -> TrappingScheduler<Self> {
        .init(base: self, errorHandler: errorHandler)
    }
}
