import Darwin

/// Reads the process's physical footprint.
///
/// This exists because "fewest allocations" is a principle that decays without a check, and because
/// Aemi's `expectAllocations` could not be used here: the seam that reports malloc counters reaches
/// a C target that is not exposed as a product, so it does not resolve from a dependent package.
///
/// Footprint is a coarser instrument than a malloc counter, and deliberately so: it reports what the
/// process actually costs rather than how many times a function was called. A hot path that allocates
/// in a loop moves it, measurably; one that does not, does not. Where counting is unavailable the
/// value is `nil` and callers must not treat that as a pass — a measurement that could not be taken
/// is reported as missing.
public enum ProcessFootprint {
    /// The process's current physical footprint in bytes, or `nil` if the kernel would not say.
    public static func bytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Runs `body` and returns how much the footprint grew while it ran.
    ///
    /// A negative result means the footprint fell, which is possible and is not clamped: pretending a
    /// measurement went the other way would hide the real number.
    public static func growth(over body: () -> Void) -> Int? {
        // One warm-up pass, so lazily-initialised state inside the measured region is not counted as
        // growth caused by the region.
        body()
        guard let before = bytes() else { return nil }
        body()
        guard let after = bytes() else { return nil }
        return Int(after) - Int(before)
    }
}
