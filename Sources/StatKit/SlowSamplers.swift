import Foundation
import IOKit.ps

final class BatterySampler {
    func sample() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard
                let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                d[kIOPSIsPresentKey] as? Bool ?? true,
                let current = d[kIOPSCurrentCapacityKey] as? Int,
                let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let charged = d[kIOPSIsChargedKey] as? Bool ?? false
            let state: BatteryReading.State =
                charging ? .charging : charged ? .charged : onAC ? .onACNotCharging : .discharging
            // Negative values mean the system is still estimating.
            let minutes = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int
            let remaining = minutes.flatMap { $0 >= 0 && state != .charged && state != .onACNotCharging ? $0 : nil }
            return BatteryReading(
                level: Double(current) / Double(max), state: state, minutesRemaining: remaining)
        }
        return nil
    }
}

final class StorageSampler {
    private let root = URL(fileURLWithPath: "/")

    func sample() -> StorageReading? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let v = try? root.resourceValues(forKeys: keys),
            let total = v.volumeTotalCapacity,
            let available = v.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return StorageReading(
            name: v.volumeLocalizedName ?? "Disk", total: UInt64(total), available: UInt64(available))
    }
}
