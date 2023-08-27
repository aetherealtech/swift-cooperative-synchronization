// Unfortunately this can't be a propertyWrapper because the accessors are async
@dynamicMemberLookup
public struct Isolated<Value> {
    public init(_ value: Value) {
        _value = value
    }
    
    public var value: Value {
        get async throws { try await lock.read { _value } }
    }
    
    public mutating func set(_ newValue: Value) async throws {
        try await lock.write { _value = newValue }
    }
    
    let lock = ReadWriteLock()
    private var _value: Value
}

public extension Isolated {
    func read<R>(_ work: (Value) async throws -> R) async throws -> R {
        try await lock.read {
            try await work(_value)
        }
    }
    
    mutating func write<R>(_ work: (inout Value) async throws -> R) async throws -> R {
        try await lock.write {
            try await work(&_value)
        }
    }

    mutating func getAndSet(_ work: (inout Value) async throws -> Void) async throws -> Value {
        try await lock.write {
            let value = _value
            try await work(&_value)
            return value
        }
    }
    
    mutating func swap(_ otherValue: inout Value) async throws {
        otherValue = try await getAndSet { value in
            value = otherValue
        }
    }
    
    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
        get async throws { try await read { value in value[keyPath: keyPath] } }
    }
    
    mutating func set<Member>(member keyPath: WritableKeyPath<Value, Member>, to newValue: Member) async throws {
        try await write { value in value[keyPath: keyPath] = newValue }
    }
}
