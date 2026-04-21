import Foundation

// ── Helpers ──────────────────────────────────────────────────────────────────

var failures = 0

func check(_ label: String, _ actual: String, _ expected: String) {
    if actual == expected {
        print("  PASS  \(label)")
    } else {
        print("  FAIL  \(label)")
        print("        expected: \(expected)")
        print("        actual:   \(actual)")
        failures += 1
    }
}

@main
struct TestRunner {
    static func main() {
        // ── VMScanner.parseOutput ─────────────────────────────────────────────────────

        print("VMScanner.parseOutput")

        let psOutput = """
          1234 qemu-system-aarch64 -name myvm,debug-threads=on -m 4096
          5678 /path/to/limactl hostagent --pidfile /tmp/lima/0/ha.pid 0
          9012 /usr/local/bin/vfkit --cpus 4 --memory 4096 --label devbox
         11111 /Applications/UTM.app/Contents/MacOS/qemu-system-aarch64 -name win11,debug-threads=on
        """

        let vms = VMScanner.parseOutput(psOutput)

        check("count", "\(vms.count)", "4")

        let qemu = vms.first(where: { $0.pid == "1234" })
        check("QEMU type",  qemu?.type ?? "",  "QEMU")
        check("QEMU name",  qemu?.name ?? "",  "myvm")

        let lima = vms.first(where: { $0.pid == "5678" })
        check("Lima type",  lima?.type ?? "",  "Lima/VZ")
        check("Lima name",  lima?.name ?? "",  "Lima")

        let vfkit = vms.first(where: { $0.pid == "9012" })
        check("vfkit type", vfkit?.type ?? "", "vfkit/VZ")
        check("vfkit name", vfkit?.name ?? "", "devbox")

        let utm = vms.first(where: { $0.pid == "11111" })
        check("UTM type",   utm?.type ?? "",   "UTM")
        check("UTM name",   utm?.name ?? "",   "win11")

        // ── VMScanner.buildGrepPattern ───────────────────────────────────────────────

        print("\nVMScanner.buildGrepPattern")
        let pattern = VMScanner.buildGrepPattern()
        let qemuCount = pattern.components(separatedBy: "qemu-system").count - 1
        check("qemu-system appears once", "\(qemuCount)", "1")

        // ── StatsProvider.parseStatsOutput ───────────────────────────────────────────

        print("\nStatsProvider.parseStatsOutput")

        let statsOutput = """
          1234   8.2  1258496
          5678   0.3   524288
        """

        let provider = StatsProvider()
        let statsCache = provider.parseStatsOutput(statsOutput)

        check("stats count",         "\(statsCache.count)",                   "2")
        check("PID 1234 cpu",        statsCache["1234"]?.cpuString ?? "",     "8.2%")
        check("PID 1234 mem",        statsCache["1234"]?.memoryString ?? "",  "1.2 GB")
        check("PID 5678 cpu",        statsCache["5678"]?.cpuString ?? "",     "0.3%")
        check("PID 5678 mem",        statsCache["5678"]?.memoryString ?? "",  "512 MB")
        check("missing PID is nil",  "\(statsCache["9999"] == nil)",          "true")

        // ── Summary ───────────────────────────────────────────────────────────────────

        print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }
}
