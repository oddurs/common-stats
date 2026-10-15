/// Fixed-capacity history, oldest first. Appending never allocates once full.
public struct History: Sendable {
    public let capacity: Int
    private var storage: [Double]
    private var start = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = []
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var last: Double? { storage.isEmpty ? nil : self[count - 1] }

    public mutating func append(_ value: Double) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[start] = value
            start = (start + 1) % capacity
        }
    }

    public subscript(i: Int) -> Double { storage[(start + i) % storage.count] }

    /// The newest `n` values, oldest first.
    public func suffix(_ n: Int) -> [Double] {
        let n = min(n, count)
        return (count - n..<count).map { self[$0] }
    }

    public func max(last n: Int) -> Double {
        let n = Swift.min(n, count)
        var m = 0.0
        for i in count - n..<count { m = Swift.max(m, self[i]) }
        return m
    }
}
