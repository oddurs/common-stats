import Darwin

/// Cumulative scheduler ticks for one logical core.
struct CoreTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Usage between two tick snapshots. Nil if the core count changed, which
/// makes the snapshots incomparable.
func cpuUsage(from old: [CoreTicks], to new: [CoreTicks]) -> (user: Double, system: Double, cores: [Double])? {
    guard old.count == new.count, !new.isEmpty else { return nil }
    var user: UInt64 = 0, system: UInt64 = 0, total: UInt64 = 0
    var cores: [Double] = []
    cores.reserveCapacity(new.count)
    for (a, b) in zip(old, new) {
        // The kernel's counters are 32-bit and wrap; wrapping subtraction
        // still yields the true delta across one wrap.
        let du = UInt64(b.user &- a.user), ds = UInt64(b.system &- a.system)
        let dn = UInt64(b.nice &- a.nice), di = UInt64(b.idle &- a.idle)
        let coreTotal = du + ds + dn + di
        user += du + dn
        system += ds
        total += coreTotal
        cores.append(coreTotal == 0 ? 0 : Double(du + ds + dn) / Double(coreTotal))
    }
    guard total > 0 else { return (0, 0, cores) }
    return (Double(user) / Double(total), Double(system) / Double(total), cores)
}

final class CPUSampler {
    private var previous: [CoreTicks] = []

    func sample() -> CPUReading? {
        let current = Self.readTicks()
        defer { previous = current }
        guard let usage = cpuUsage(from: previous, to: current) else { return nil }
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        return CPUReading(
            user: usage.user, system: usage.system, cores: usage.cores,
            loadAverage: (load[0], load[1], load[2]))
    }

    private static func readTicks() -> [CoreTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            let base = core * states
            // Ticks are unsigned 32-bit values stored in signed slots.
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return CoreTicks(
                user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }
}
