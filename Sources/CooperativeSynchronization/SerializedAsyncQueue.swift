import CollectionExtensions
import Combine
import Foundation

/**
 A queue to which items can be added, and then asynchronously consumed, which is serialized to disk.  This allows recovery of queued items across app sessions.
 Unlike AsyncQueue, SerializedAsyncQueue is not an AsyncSequence, and thus cannot be for awaited... over.  This is because it is only safe to remove an item from the serialized copy of the queue after an item is successfully processed.  A special API is provided to allow asynchronous processing that ensures an item is only removed once processing of that item completes successfully.  That way, if the app is terminated in the middle of processing an item, then that item will still exist as the first item in the queue on a new app session.
 */

public actor SerializedAsyncQueue<Element: Codable, Decoder: TopLevelDecoder, Encoder: TopLevelEncoder> where Decoder.Input == Data, Encoder.Output == Data {
    public var currentElements: [Element] {
        loadQueue
            .map(\.element)
    }

    public init(
        url: URL,
        decoder: Decoder,
        encoder: Encoder,
        onDecodeError: @escaping (Error) -> Void,
        onEncodeError: @escaping (Error) -> Void
    ) {
        self.url = url
        self.decoder = decoder
        self.encoder = encoder
        
        self.onDecodeError = onDecodeError
        self.onEncodeError = onEncodeError
    }

    public func process(_ handler: @escaping (Element) async -> Void) async {
        while true {
            let value = await withCheckedContinuation { incomingContinuation in
                let values = loadQueue
                print("---- Queue count processing: \(values.count) -----")

                guard let value = values.first else {
                    continuation = (incomingContinuation, handler)
                    return
                }

                currentTask = Task { await handler(value.element) }

                incomingContinuation.resume(returning: value)
            }

            _ = await currentTask?.value

            var values = loadQueue
            print("---- Queue count after processing: \(values.count) -----")
            values.removeAll(of: value)
            saveQueue(values)
            currentTask = nil
        }
    }

    public func append(element: Element) {
        print("---- appending to Queue -----")
        var values = loadQueue
        let queuedElement = QueuedElement(element: element)
        values.append(queuedElement)
        print("---- Queue count: \(values.count) -----")
        saveQueue(values)

        if let (continuation, handler) = continuation {
            currentTask = Task { await handler(element) }
            continuation.resume(returning: queuedElement)
            self.continuation = nil
        }
    }

    public func clearQueue() {
        saveQueue([])
        currentTask?.cancel()
        currentTask = nil
    }
    
    private struct QueuedElement: Codable, Equatable {
        let id: UUID
        let element: Element

        init(element: Element) {
            id = .init()
            self.element = element
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private let url: URL
    private let decoder: Decoder
    private let encoder: Encoder
    
    private let onDecodeError: (Error) -> Void
    private let onEncodeError: (Error) -> Void

    private var continuation: (CheckedContinuation<QueuedElement, Never>, (Element) async -> Void)?
    private var currentTask: Task<Void, Never>?

    private var loadQueue: [QueuedElement] {
        do {
            return try decoder.decode([QueuedElement].self, from: try .init(contentsOf: url))
        } catch {
            onDecodeError(error)
            return []
        }
    }

    private func saveQueue(_ elements: [QueuedElement]) {
        do {
            try encoder.encode(elements).write(to: url)
        } catch {
            onEncodeError(error)
        }
    }
}
