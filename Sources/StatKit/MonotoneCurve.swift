/// Tangents for a monotone cubic Hermite curve through evenly spaced
/// points (Fritsch–Carlson). Each segment stays within the range of its two
/// endpoints, so a smoothed graph never shows a peak or dip that wasn't
/// sampled, which ordinary splines do.
///
/// Slopes are per index step; a Bézier segment from i to i+1 uses control
/// points at y[i] + m[i]/3 and y[i+1] - m[i+1]/3.
public func monotoneTangents(_ y: [Double]) -> [Double] {
    let n = y.count
    guard n > 1 else { return Array(repeating: 0, count: n) }
    let d = (0..<n - 1).map { y[$0 + 1] - y[$0] }
    var m = [Double](repeating: 0, count: n)
    m[0] = d[0]
    m[n - 1] = d[n - 2]
    for k in 1..<n - 1 {
        // A local extremum or a flat neighbour gets a flat tangent.
        m[k] = d[k - 1] * d[k] <= 0 ? 0 : (d[k - 1] + d[k]) / 2
    }
    for k in 0..<n - 1 {
        if d[k] == 0 {
            m[k] = 0
            m[k + 1] = 0
            continue
        }
        let a = m[k] / d[k], b = m[k + 1] / d[k]
        let s = a * a + b * b
        if s > 9 {
            let t = 3 / s.squareRoot()
            m[k] = t * a * d[k]
            m[k + 1] = t * b * d[k]
        }
    }
    return m
}
