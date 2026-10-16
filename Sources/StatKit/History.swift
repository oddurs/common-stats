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

    /// The mean of the newest `k` values (all of them if fewer), or nil when empty.
    public func mean(last k: Int) -> Double? {
        let k = Swift.min(Swift.max(k, 1), count)
        guard k > 0 else { return nil }
        var sum = 0.0
        for i in count - k..<count { sum += self[i] }
        return sum / Double(k)
    }

    /// The newest `n` values, each replaced by the mean of itself and up to
    /// `window - 1` values before it: a trailing moving average. Early points
    /// average what history exists rather than padding with zeros.
    public func trailingMeans(last n: Int, window: Int) -> [Double] {
        let n = Swift.min(n, count), window = Swift.max(window, 1)
        guard window > 1 else { return suffix(n) }
        let first = count - n
        // Running sum over the window that ends at each output point.
        let start = Swift.max(first - (window - 1), 0)
        var sum = 0.0
        for i in start..<first { sum += self[i] }
        var out: [Double] = []
        out.reserveCapacity(n)
        for i in first..<count {
            sum += self[i]
            let drop = i - window
            if drop >= start { sum -= self[drop] }
            out.append(sum / Double(i - Swift.max(drop + 1, start) + 1))
        }
        return out
    }

    public func max(last n: Int) -> Double {
        let n = Swift.min(n, count)
        var m = 0.0
        for i in count - n..<count { m = Swift.max(m, self[i]) }
        return m
    }
}
