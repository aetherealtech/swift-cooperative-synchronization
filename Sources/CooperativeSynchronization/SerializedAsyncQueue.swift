import CollectionExtensions
import Combine
import Foundation

/**
 A queue to which items can be added, and then asynchronously consumed, which is serialized to disk.  This allows recovery of queued items across app sessions.
 Unlike AsyncQueue, SerializedAsyncQueue is not an AsyncSequence, and thus cannot be for awaited... over.  This is because it is only safe to remove an item from the serialized copy of the queue after an item is successfully processed.  A special API is provided to allow asynchronous processing that ensures an item is only removed once processing of that item completes successfully.  That way, if the app is terminated in the middle of processing an item, then that item will still exist as the first item in the queue on a new app session.
 */

//public protocol SerializableTask: Codable, Sendable {
//    associatedtype Success
//
//
//
//    var value:
//}
//
//public protocol SerializableThrowingTask: Codable, Sendable {
//    associatedtype Success
//}

public final class SerializedAsyncQueue<
    Memento: Sendable & Identifiable,
    Scheduler: CooperativeSynchronization.Scheduler
>: @unchecked Sendable {
    public init(
        load: @escaping @Sendable () -> [Memento],
        save: @escaping @Sendable ([Memento]) -> Void,
        lock: ReadWriteLock,
        taskFactory: @escaping @Sendable (Memento) -> @Sendable () async -> Void,
        scheduler: Scheduler
    ) async {
        self.load = load
        self.save = save
        self.lock = lock
        self.taskFactory = taskFactory
        self.scheduler = scheduler
        
        await lock.read {
            let values = load()
            print("---- Queue count: \(values.count) -----")

            for value in values {
                schedule(value: value)
            }
        }
    }
    
    func append(_ value: Memento) async {
        await lock.write {
            print("---- appending to Queue -----")
            var values = load()
            values.append(value)
            print("---- Queue count: \(values.count) -----")
            save(values)
            
            schedule(value: value)
        }
    }
    
    func clearQueue() async {
        let queued = await lock.write {
            save([])
            return Array(self.queued.values)
        }
        
        for queuedTask in queued {
            await queuedTask.value.cancel()
        }
    }
    
    private func schedule(value: Memento) {
        queued[value.id] = Task { await scheduler.schedule(process(value: value)) }
    }
    
    private func process(value: Memento) -> @Sendable () async -> Void {
        let work = taskFactory(value)
        
        return {
            await work()
            
            await self.lock.write {
                var values = self.load()
                print("---- Queue count after processing: \(values.count) -----")
                values.removeAll { $0.id == value.id }
                self.save(values)
                self.queued[value.id] = nil
            }
        }
    }
    
    private let load: () -> [Memento]
    private let save: ([Memento]) -> Void
    private let lock: ReadWriteLock
    private let taskFactory: @Sendable (Memento) -> @Sendable () async -> Void
    private let scheduler: Scheduler
    
    private var queued: [Memento.ID: Task<Scheduler.CancelHandle, Never>] = [:]
}

public extension SerializedAsyncQueue {
    convenience init<
        Decoder: TopLevelDecoder & Sendable,
        Encoder: TopLevelEncoder & Sendable
    > (
        load: @escaping @Sendable () throws -> Decoder.Input,
        save: @escaping @Sendable (Encoder.Output) throws -> Void,
        lock: ReadWriteLock,
        taskFactory: @escaping @Sendable (Memento) -> @Sendable () async -> Void,
        scheduler: Scheduler,
        decoder: Decoder,
        encoder: Encoder,
        onLoadError: @escaping @Sendable (Error) -> Void,
        onSaveError: @escaping @Sendable (Error) -> Void
    ) async where Memento: Codable, Decoder.Input == Encoder.Output {
        await self.init(
            load: {
                do {
                    return try decoder.decode([Memento].self, from: try load())
                } catch {
                    onLoadError(error)
                    return []
                }
            },
            save: { queue in
                do {
                    try save(encoder.encode(queue))
                } catch {
                    onSaveError(error)
                }
            },
            lock: lock,
            taskFactory: taskFactory,
            scheduler: scheduler
        )
    }
    
    convenience init<
        Decoder: TopLevelDecoder & Sendable,
        Encoder: TopLevelEncoder & Sendable
    > (
        url: URL,
        lock: ReadWriteLock = .init(),
        taskFactory: @escaping @Sendable (Memento) -> @Sendable () async -> Void,
        scheduler: Scheduler,
        decoder: Decoder,
        encoder: Encoder,
        onLoadError: @escaping @Sendable (Error) -> Void,
        onSaveError: @escaping @Sendable (Error) -> Void
    ) async where Memento: Codable, Decoder.Input == Data, Encoder.Output == Data {
        await self.init(
            load: { try Data(contentsOf: url) },
            save: { data in try data.write(to: url) },
            lock: lock,
            taskFactory: taskFactory,
            scheduler: scheduler,
            decoder: decoder,
            encoder: encoder,
            onLoadError: onLoadError,
            onSaveError: onSaveError
        )
    }
}
