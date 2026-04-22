import Foundation

enum VMScanner {

    /// Runs `ps` filtered by all known VM patterns and returns detected VMs.
    static func getRunningVMs() -> [VMInfo] {
        let pattern = buildGrepPattern()
        let output = runPS(grepPattern: pattern)
        return parseOutput(output)
    }

    /// Joins all unique detector grep patterns with `|` for a single grep call.
    static func buildGrepPattern() -> String {
        // Deduplicate: UTM and QEMU share "qemu-system"
        var seen = Set<String>()
        return VMDetector.all
            .map { $0.grepPattern }
            .filter { seen.insert($0).inserted }
            .joined(separator: "|")
    }

    /// Executes `ps axo pid,command | grep -E '<pattern>' | grep -v grep`.
    static func runPS(grepPattern: String) -> String {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "ps axo pid,command | grep -E '\(grepPattern)' | grep -v grep"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// Parses raw `ps` output into VMInfo values using the detector registry.
    static func parseOutput(_ output: String) -> [VMInfo] {
        output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> VMInfo? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let spaceIdx = trimmed.firstIndex(of: " ") else { return nil }
                let pid = String(trimmed[..<spaceIdx])
                let command = String(trimmed[trimmed.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                guard let detector = VMDetector.all.first(where: { $0.canHandle(command) }) else {
                    return nil
                }
                return VMInfo(pid: pid, name: detector.extractName(command), type: detector.type)
            }
    }
}
