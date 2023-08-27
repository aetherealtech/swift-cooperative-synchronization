//import CollectionExtensions
//import Foundation
//
///**
// AsyncSerialQueue is like a DispatchQueue (configured to be serial), but it works entirely with async functionality.  You can enqueue an async job and optionally await the job to be completed.  The queue will execute jobs enqueued to it serially, ensuring that no more than one job is running at a time.
// */
//public final class TaskPool {
//    public init(size: Int) async {
//        await state.write { state in
//            state.tasks = (0 ..< size)
//                .map { _ in Task { try await run() } }
//        }
//    }
//
//    deinit {
//        Task { await state.write { state in
//            state.tasks.forEach { task in
//                task.cancel()
//            }
//        } }
//    }
//    
//    public func enqueue(
//        _ work: @escaping () async -> Void
//    ) async {
//        await enqueue(
//            at: Date(),
//            work
//        )
//    }
//    
//    public func enqueue(
//        at date: Date,
//        _ work: @escaping () async -> Void
//    ) async {
//        await state.write { state in
//            state.enqueued.append(.init(work: work, readyAt: date))
//            state.enqueued.sort(by: \.readyAt)
//        }
//        
//        await hasMore.notifyOne()
//    }
//    
//    public func enqueue(
//        in timeInterval: TimeInterval,
//        _ work: @escaping () async -> Void
//    ) async {
//        await enqueue(
//            at: Date().addingTimeInterval(timeInterval),
//            work
//        )
//    }
//
//    public func enqueueAndWait<R>(_ work: @escaping () async -> R) async -> R {
//        await withCheckedContinuation { resultContinuation in
//            Task {
//                await enqueue {
//                    let result = await work()
//                    resultContinuation.resume(returning: result)
//                }
//            }
//        }
//    }
//
//    public func enqueueAndWait<R>(_ work: @escaping () async throws -> R) async throws -> R {
//        try await withCheckedThrowingContinuation { resultContinuation in
//            Task {
//                await enqueue {
//                    let result = await Result { try await work() }
//                    resultContinuation.resume(with: result)
//                }
//            }
//        }
//    }
//
//    public func cancelAll() async {
//        await state.write { state in
//            state.enqueued.removeAll()
//            
//            let size = state.tasks.count
//            
//            state.tasks.forEach { task in
//                task.cancel()
//            }
//            
//            state.tasks = (0 ..< size)
//                .map { _ in Task { try await run() } }
//        }
//    }
//    
//    private struct Job {
//        let work: () async -> Void
//        let readyAt: Date
//        
//        init(
//            work: @escaping () async -> Void,
//            readyAt: Date = Date()
//        ) {
//            self.work = work
//            self.readyAt = readyAt
//        }
//    }
//    
//    private struct State {
//        var enqueued: [Job]
//        var tasks: [Task<Void, Error>]
//    }
//    
//    private let hasMore = ConditionVariable()
//    private var state: Isolated<State> = .init(.init(enqueued: [], tasks: []))
//    
//    private func run() async throws {
//        while true {
//            let nextJob = await state.write { state -> (Job, Bool)? in
//                if let next = state.enqueued.first {
//                    if next.readyAt <= Date() {
//                        state.enqueued.removeFirst()
//                        return (next, true)
//                    } else {
//                        return (next, false)
//                    }
//                } else {
//                    return nil
//                }
//            }
//            
//            if let (next, ready) = nextJob {
//                if ready {
//                    await next.work()
//                } else {
//                    try? await hasMore.wait(lock: state.lock.exclusive, until: next.readyAt)
//                }
//            } else {
//                await hasMore.wait(lock: state.lock.exclusive)
//            }
//
//            await state.lock.exclusiveUnlock()
//        }
//    }
//}
