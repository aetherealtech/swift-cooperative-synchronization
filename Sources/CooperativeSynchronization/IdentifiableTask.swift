import Foundation

struct IdentifiableJob<Config: JobConfigProtocol>: Identifiable {
    let id: UUID
    let config: Config
    let work: @Sendable () async -> Void
    
    init(
        id: UUID,
        config: Config = .init(),
        work: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.config = config
        self.work = work
    }
    
    func start() -> IdentifiableTask<Config> {
        .init(
            id: id,
            config: config,
            task: .init(operation: work)
        )
    }
}

struct IdentifiableTask<Config: JobConfigProtocol>: Identifiable {
    let id: UUID
    let config: Config
    let task: Task<Void, Never>
}
