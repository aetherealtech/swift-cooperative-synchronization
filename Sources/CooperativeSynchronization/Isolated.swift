// Unfortunately this can't be a propertyWrapper because the accessors are async
@dynamicMemberLookup
public actor Isolated<Value> {
    public init(_ value: Value) {
        self.value = value
    }
    
    public var value: Value
}

public extension Isolated {
    func read<R>(_ work: (Value) throws -> R) rethrows -> R {
        try work(value)
    }
    
    func write<R>(_ work: (inout Value) throws -> R) rethrows -> R {
        try work(&value)
    }

    func getAndSet(_ work: (inout Value) throws -> Void) rethrows -> Value {
        let value = self.value
        try work(&self.value)
        return value
    }
    
    func swap(_ otherValue: inout Value) {
        otherValue = getAndSet { value in
            value = otherValue
        }
    }
    
    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
        value[keyPath: keyPath]
    }
    
    subscript<Member>(dynamicMember keyPath: WritableKeyPath<Value, Member>) -> Member {
        get { value[keyPath: keyPath] }
        set { value[keyPath: keyPath] = newValue }
    }
}
