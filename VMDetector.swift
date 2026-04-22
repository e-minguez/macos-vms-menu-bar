import Foundation

struct VMDetector {
    /// Pattern used to build the combined grep (may contain `|` for OR).
    let grepPattern: String
    /// VM type label shown in the menu, e.g. "QEMU", "Lima/VZ".
    let type: String
    /// Returns true if this detector owns the given command string.
    /// Checked in order — first match wins.
    let canHandle: (String) -> Bool
    /// Extracts the human-readable VM name from the full command string.
    let extractName: (String) -> String

    // MARK: - Registry (order matters: UTM before QEMU)

    static let all: [VMDetector] = [

        VMDetector(
            grepPattern: "qemu-system",
            type: "UTM",
            canHandle: { $0.lowercased().contains("qemu-system") && $0.contains("UTM.app") },
            extractName: { extractQEMUStyleName(from: $0, fallback: "UTM VM") }
        ),

        VMDetector(
            grepPattern: "qemu-system",
            type: "QEMU",
            canHandle: { $0.lowercased().contains("qemu-system") && !$0.contains("UTM.app") },
            extractName: { extractQEMUStyleName(from: $0, fallback: "QEMU VM") }
        ),

        VMDetector(
            grepPattern: "limactl hostagent",
            type: "Lima/VZ",
            canHandle: { $0.contains("limactl hostagent") },
            extractName: { command in
                let parts = command.split(separator: " ")
                    .filter { !$0.contains("=") && !$0.hasPrefix("-") }
                if let last = parts.last, last.count < 20 {
                    let id = String(last)
                    return id == "0" ? "Lima" : "Lima: \(id)"
                }
                return "Lima"
            }
        ),

        VMDetector(
            grepPattern: "/vfkit ",
            type: "vfkit/VZ",
            canHandle: { $0.contains("/vfkit ") },
            extractName: { command in
                if let range = command.range(of: "--label\\s+(\\S+)", options: .regularExpression) {
                    let match = String(command[range])
                    return match.split(separator: " ").last.map(String.init) ?? "vfkit"
                }
                return "vfkit"
            }
        ),

        VMDetector(
            grepPattern: "prl_vm_app",
            type: "Parallels",
            canHandle: { $0.contains("prl_vm_app") },
            extractName: { command in
                if let range = command.range(of: "--config\\s+(\\S+)", options: .regularExpression) {
                    let match = String(command[range])
                    let path = match.split(separator: " ").last.map(String.init) ?? ""
                    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                }
                return "Parallels VM"
            }
        ),

        VMDetector(
            grepPattern: "vmware-vmx",
            type: "VMware",
            canHandle: { $0.contains("vmware-vmx") },
            extractName: { command in
                let parts = command.split(separator: " ")
                if let vmx = parts.first(where: { $0.hasSuffix(".vmx") }) {
                    return URL(fileURLWithPath: String(vmx)).deletingPathExtension().lastPathComponent
                }
                return "VMware VM"
            }
        ),

        VMDetector(
            grepPattern: "VBoxHeadless|VirtualBoxVM",
            type: "VirtualBox",
            canHandle: { $0.contains("VBoxHeadless") || $0.contains("VirtualBoxVM") },
            extractName: { command in
                if let range = command.range(of: "--startvm\\s+(\\S+)", options: .regularExpression) {
                    let match = String(command[range])
                    return match.split(separator: " ").last.map(String.init) ?? "VirtualBox VM"
                }
                return "VirtualBox VM"
            }
        ),

        VMDetector(
            grepPattern: "tart run|tart: ",
            type: "Tart",
            canHandle: { $0.contains("tart run") || $0.contains("tart: ") },
            extractName: { command in
                let parts = command.split(separator: " ")
                if let runIdx = parts.firstIndex(of: "run"), runIdx + 1 < parts.count {
                    return String(parts[runIdx + 1])
                }
                return "Tart VM"
            }
        ),

        VMDetector(
            grepPattern: "com.orbstack",
            type: "OrbStack",
            canHandle: { $0.contains("com.orbstack") },
            extractName: { command in
                let parts = command.split(separator: " ").filter { !$0.hasPrefix("-") }
                if let last = parts.last, !last.contains("/"), last != "com.orbstack" {
                    return String(last)
                }
                return "OrbStack VM"
            }
        ),
    ]
}

// MARK: - Shared helpers

/// Extracts the value of the `-name` flag from a QEMU command string.
func extractQEMUStyleName(from command: String, fallback: String) -> String {
    if let range = command.range(of: "-name\\s+([^\\s,]+)", options: .regularExpression) {
        let match = String(command[range])
        let parts = match.split(separator: " ")
        if parts.count > 1 {
            return String(parts[1]).components(separatedBy: ",").first ?? String(parts[1])
        }
    }
    return fallback
}
