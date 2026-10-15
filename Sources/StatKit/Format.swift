import Foundation

/// Compact formatters for a 9–12 pt menu bar. Each keeps to at most three
/// significant digits so a fixed-width cell never clips.
public enum Format {
    // Every formatter rejects NaN and infinity first: Int(_:) traps on them,
    // and a menu bar extra that crashes is worse than one that shows a dash.

    public static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return missing }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// Decimal units, as Finder and Activity Monitor report storage and traffic.
    public static func bytes(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        bytes(value, base: 1000, locale: locale)
    }

    /// Binary units labelled GB, as Apple reports RAM: 24 GiB reads "24 GB", not "26 GB".
    public static func memory(_ value: UInt64, locale: Locale = .autoupdatingCurrent) -> String {
        bytes(Double(value), base: 1024, locale: locale)
    }

    /// "." or "," as the user's region writes it.
    public static func decimalSeparator(_ locale: Locale = .autoupdatingCurrent) -> String {
        locale.decimalSeparator ?? "."
    }

    private static func bytes(_ value: Double, base: Double, locale: Locale) -> String {
        guard value.isFinite else { return missing }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(value, 0)
        var unit = 0
        // Round before choosing the unit so 999.7 KB becomes 1.0 MB, not "1000 KB".
        while unit < units.count - 1, v.rounded(toPlaces: v < 10 ? 1 : 0) >= 1000 {
            v /= base
            unit += 1
        }
        if unit == 0 { return "\(Int(v.rounded())) B" }
        return v < 10 && v.rounded(toPlaces: 1) < 10
            ? String(format: "%.1f", v).replacingOccurrences(of: ".", with: decimalSeparator(locale)) + " "
                + units[unit]
            : "\(Int(v.rounded())) \(units[unit])"
    }

    public static func rate(_ bytesPerSecond: Double, locale: Locale = .autoupdatingCurrent) -> String {
        bytesPerSecond.isFinite ? bytes(bytesPerSecond, locale: locale) + "/s" : missing
    }

    public static func duration(minutes: Int) -> String {
        guard minutes >= 0 else { return missing }
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return missing }
        let minutes = Int(seconds) / 60
        let (d, h, m) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

extension Double {
    fileprivate func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
