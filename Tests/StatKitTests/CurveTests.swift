import Testing

@testable import StatKit

struct MonotoneCurveTests {
    /// Samples the cubic Bézier for segment k at many points.
    func segment(_ y: [Double], _ m: [Double], _ k: Int) -> [Double] {
        let p0 = y[k], p1 = y[k] + m[k] / 3, p2 = y[k + 1] - m[k + 1] / 3, p3 = y[k + 1]
        return (0...50).map { i in
            let t = Double(i) / 50, u = 1 - t
            return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
        }
    }

    @Test(arguments: [
        [0, 0, 1, 0, 0],  // a lone spike: a spline would ring below zero beside it
        [0.1, 0.9, 0.1, 0.9, 0.1],
        [0, 0.2, 0.2, 0.2, 1],  // a plateau then a jump
        [1, 1, 1, 1],
        [0, 0.01, 0.5, 0.51, 1],
    ])
    func neverOvershootsTheSamples(y: [Double]) {
        let m = monotoneTangents(y)
        for k in 0..<y.count - 1 {
            let lo = min(y[k], y[k + 1]) - 1e-9, hi = max(y[k], y[k + 1]) + 1e-9
            #expect(segment(y, m, k).allSatisfy { $0 >= lo && $0 <= hi }, "segment \(k) of \(y)")
        }
    }

    @Test func degenerateInputs() {
        #expect(monotoneTangents([]) == [])
        #expect(monotoneTangents([0.5]) == [0])
        #expect(monotoneTangents([0, 1]) == [1, 1])
    }
}
