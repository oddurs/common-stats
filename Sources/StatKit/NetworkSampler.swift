import Darwin
import SystemConfiguration

/// Measures the primary interface: the one the default route uses. Summing
/// every interface would count VPN traffic twice (tunnel and carrier).
final class NetworkSampler {
    private let store = SCDynamicStoreCreate(nil, "StatBar" as CFString, nil, nil)
    private var meter = RateMeter<String>()
    private var primary: String?
    private var primaryCheckedAt: UInt64 = 0

    func sample(now: UInt64) -> RateReading? {
        // configd lookups are IPC; the route rarely changes, so recheck every few seconds.
        if primary == nil || now &- primaryCheckedAt > 3_000_000_000 {
            let found = primaryInterface()
            primary = found
            primaryCheckedAt = now
        }
        guard let primary, let counters = Self.counters(for: primary) else { return nil }
        // Keyed by interface, so switching from Wi-Fi to Ethernet restarts the baseline.
        guard let (down, up) = meter.update([primary: counters], nanoseconds: now) else { return nil }
        return RateReading(inbound: down, outbound: up, source: primary)
    }

    private func primaryInterface() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                let name = dict["PrimaryInterface"] as? String
            {
                return name
            }
        }
        return nil
    }

    /// 64-bit byte counters. getifaddrs only exposes 32-bit ones, which wrap
    /// every 4 GB.
    static func counters(for interface: String) -> (inbound: UInt64, outbound: UInt64)? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> (UInt64, UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(header.ifm_type) == RTM_IFINFO2, header.ifm_index == index {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                }
                guard header.ifm_msglen > 0 else { break }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}
