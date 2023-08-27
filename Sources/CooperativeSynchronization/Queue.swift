//public final class Queue {
//    public init(maxConcurrency: Int = 1) {
//        semaphore = .init(value: maxConcurrency)
//    }
//    
//    public func schedule<R>(_ work: () async throws -> R) async rethrows -> R {
//        try await semaphore.acquire(work)
//    }
// 
//    private var semaphore: Semaphore
//}
