public actor SerialExecutor {
    public func perform<R>(_ action: @escaping () -> R) -> R {
        action()
    }
}
