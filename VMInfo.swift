import Foundation

struct VMStats {
    let cpu: Double   // percent, e.g. 8.2
    let memoryMB: Int // resident set size in MB

    var cpuString: String {
        String(format: "%.1f%%", cpu)
    }

    var memoryString: String {
        memoryMB >= 1024
            ? String(format: "%.1f GB", Double(memoryMB) / 1024.0)
            : "\(memoryMB) MB"
    }
}

struct VMInfo {
    let pid: String
    let name: String
    let type: String
    var stats: VMStats? = nil

    /// Plain title used when stats are disabled.
    var baseTitle: String {
        "\(name) [\(type)] #\(pid)"
    }
}
