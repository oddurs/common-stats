import Darwin

final class MemorySampler {
    private let total: UInt64 = sysctlValue("hw.memsize") ?? 0
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = pageSize
        // Activity Monitor: App Memory is anonymous memory less what the
        // owner has marked purgeable.
        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (anonymous > purgeable ? anonymous - purgeable : 0) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        let level: Int32 = sysctlValue("kern.memorystatus_vm_pressure_level") ?? 1
        let pressure: MemoryReading.Pressure =
            switch level {
            case 4: .critical
            case 2: .warning
            default: .normal
            }

        return MemoryReading(
            total: total,
            app: app,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swapUsed,
            pressure: pressure)
    }
}

func sysctlValue<T: FixedWidthInteger>(_ name: String) -> T? {
    var value: T = 0
    var size = MemoryLayout<T>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
}
