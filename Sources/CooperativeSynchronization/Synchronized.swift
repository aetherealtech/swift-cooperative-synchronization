// Unfortunately this can't be a propertyWrapper because the accessors are async
@dynamicMemberLookup
public final class Synchronized<Value: Sendable>: @unchecked Sendable {
    public init(_ value: Value) {
        _value = value
    }
    
    public var value: Value {
        get async throws { try await lock.read { _value } }
    }
    
    public func set(_ newValue: Value) async throws {
        try await lock.write { _value = newValue }
    }
    
    let lock = ReadWriteLock()
    private var _value: Value
}

public extension Synchronized {
    func read<R: Sendable>(_ work: @Sendable (Value) async throws -> R) async throws -> R {
        try await lock.read {
            try await work(_value)
        }
    }
    
    func write<R: Sendable>(_ work: @Sendable (inout Value) async throws -> R) async throws -> R {
        try await lock.write {
            try await work(&_value)
        }
    }

    func getAndSet(_ work: @Sendable (inout Value) async throws -> Void) async throws -> Value {
        try await lock.write {
            let value = _value
            try await work(&_value)
            return value
        }
    }
    
    func swap(_ otherValue: inout Value) async throws {
        otherValue = try await getAndSet { [otherValue] value in
            value = otherValue
        }
    }
    
    subscript<Member: Sendable>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
        get async throws { try await read { value in value[keyPath: keyPath] } }
    }
    
    func set<Member: Sendable>(member keyPath: WritableKeyPath<Value, Member>, to newValue: Member) async throws {
        try await write { value in value[keyPath: keyPath] = newValue }
    }
}

extension KeyPath: @unchecked Sendable {}
