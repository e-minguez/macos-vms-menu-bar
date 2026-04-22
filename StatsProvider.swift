import Foundation

class StatsProvider {

    /// Cache keyed by PID string. Updated on each `refresh(pids:)` call.
    private(set) var cache: [String: VMStats] = [:]

    /// Fetches CPU% and RSS for the given PIDs in a single `ps` call.
    /// Results are stored in `cache`. Clears cache if `pids` is empty.
    func refresh(pids: [String]) {
        guard !pids.isEmpty else { cache = [:]; return }

        let pidList = pids.joined(separator: ",")
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "ps -o pid=,pcpu=,rss= -p \(pidList) 2>/dev/null"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            cache = parseStatsOutput(String(data: data, encoding: .utf8) ?? "")
        } catch {
            cache = [:]
        }
    }

    /// Parses the output of `ps -o pid=,pcpu=,rss=` into a PID→VMStats map.
    func parseStatsOutput(_ output: String) -> [String: VMStats] {
        var result: [String: VMStats] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 3,
                  let cpu = Double(parts[1]),
                  let rssKB = Int(parts[2]) else { continue }
            result[parts[0]] = VMStats(cpu: cpu, memoryMB: rssKB / 1024)
        }
        return result
    }
}
