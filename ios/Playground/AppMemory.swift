import Darwin

/// Physical footprint, the figure iOS uses to decide when to kill a process.
enum AppMemory {
    private typealias ProcPidRusage = @convention(c) (pid_t, Int32, UnsafeMutableRawPointer) -> Int32

    // The iOS SDK defines `rusage_info_v6` but does not declare `proc_pid_rusage`.
    private static let procPidRusage = dlsym(dlopen(nil, RTLD_NOW), "proc_pid_rusage")
        .map { unsafeBitCast($0, to: ProcPidRusage.self) }

    /// This app's process. It does not include WebKit's own processes, where web view pages run.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Another process, such as a web view's WebContent process. The simulator allows this; on a device
    /// the sandbox refuses and this returns nil.
    static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v6()
        guard let procPidRusage, procPidRusage(pid, RUSAGE_INFO_V6, &info) == 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// Runs `work` while sampling the footprint, and returns how far it rose above its starting value.
    static func peakGrowth(during work: () async -> Void) async -> UInt64 {
        let baseline = footprint()
        let sampler = Task.detached {
            var peak = baseline
            while !Task.isCancelled {
                peak = max(peak, footprint())
                try? await Task.sleep(for: .milliseconds(10))
            }
            return peak
        }
        await work()
        sampler.cancel()
        return max(await sampler.value, footprint()) - baseline
    }
}
