import Foundation

struct IdentifiableContinuation<T, E: Error>: Identifiable {
    let id: UUID
    let continuation: CheckedContinuation<T, E>
    
    func resume(returning value: T) {
        continuation.resume(returning: value)
    }
    
    func resume(throwing error: E) {
        continuation.resume(throwing: error)
    }
    
    func resume(with result: Result<T, E>) {
        continuation.resume(with: result)
    }
}

extension IdentifiableContinuation where T == Void {
    func resume() {
        continuation.resume()
    }
}

extension Collection where Element: Identifiable {
    subscript(id id: Element.ID) -> Element? {
        first { $0.id == id }
    }
}

extension RangeReplaceableCollection where Self: MutableCollection, Element: Identifiable {
    subscript(id id: Element.ID) -> Element? {
        get { first { $0.id == id } }
        set {
            guard let newValue else {
                removeAll { $0.id == id }
                return
            }
            
            guard newValue.id == id else {
                fatalError("Attempted to insert an identifiable value with a different id")
            }
            
            if let index = firstIndex(where: { $0.id == id }) {
                self[index] = newValue
            } else {
                append(newValue)
            }
        }
    }
}

extension RangeReplaceableCollection where Element: Identifiable {
    mutating func safelyRemoveFirst() -> Element? {
        isEmpty ? nil : removeFirst()
    }
    
    @discardableResult
    mutating func remove(id: Element.ID) -> Element? {
        removeFirst { $0.id == id }
    }
}
