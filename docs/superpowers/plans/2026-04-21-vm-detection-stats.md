# VM Detection & Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `VMMenuBarApp.swift` into focused modules, add 6 new VM detectors (UTM, Parallels, VMware, VirtualBox, Tart, OrbStack), and add opt-in per-VM CPU%/memory stats with a column-aligned menu layout.

**Architecture:** Nine detectors are defined as data (`VMDetector.all`) so adding a new VM type is one struct entry with no `if/else` chain. `VMScanner` builds a single `ps | grep` from all detector patterns. `StatsProvider` fetches CPU%+RSS for all active PIDs in one additional `ps` call, cached per tick.

**Tech Stack:** Swift 5, Cocoa, `swiftc` CLI build (no Xcode project), `NSAttributedString`+`NSTextTab` for column alignment.

---

### Task 1: Scaffold new files and update build.sh

**Files:**
- Create: `VMInfo.swift`
- Create: `VMDetector.swift`
- Create: `VMScanner.swift`
- Create: `StatsProvider.swift`
- Create: `AppDelegate.swift`
- Create: `main.swift`
- Create: `Tests/verify_parsing.swift`
- Modify: `build.sh`

- [ ] **Step 1: Create empty Swift files**

```bash
touch VMInfo.swift VMDetector.swift VMScanner.swift StatsProvider.swift AppDelegate.swift main.swift
mkdir -p Tests
touch Tests/verify_parsing.swift
```

- [ ] **Step 2: Update build.sh to compile all source files**

Replace the entire `build.sh` with:

```bash
#!/bin/bash

APP_NAME="VMMenuBar"
BUNDLE_ID="com.vmmonitor.menubar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

swiftc \
    VMInfo.swift \
    VMDetector.swift \
    VMScanner.swift \
    StatsProvider.swift \
    AppDelegate.swift \
    main.swift \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -target arm64-apple-macos13.0

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed"
    exit 1
fi

cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "Build complete! App created at: $APP_DIR"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To install the app:"
echo "  cp -r $APP_DIR /Applications/"
```

- [ ] **Step 3: Commit scaffolding**

```bash
git add VMInfo.swift VMDetector.swift VMScanner.swift StatsProvider.swift AppDelegate.swift main.swift Tests/verify_parsing.swift build.sh
git commit -m "chore: scaffold module files, update build.sh for multi-file compile"
```

---

### Task 2: Implement VMInfo.swift

**Files:**
- Modify: `VMInfo.swift`

- [ ] **Step 1: Write VMInfo.swift**

```swift
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
```

- [ ] **Step 2: Verify it compiles in isolation**

```bash
swiftc VMInfo.swift -framework Foundation -target arm64-apple-macos13.0 -o /tmp/vminfo_check && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add VMInfo.swift
git commit -m "feat: add VMInfo and VMStats structs"
```

---

### Task 3: Implement VMDetector.swift

**Files:**
- Modify: `VMDetector.swift`

- [ ] **Step 1: Write VMDetector.swift**

```swift
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
```

- [ ] **Step 2: Verify it compiles together with VMInfo**

```bash
swiftc VMInfo.swift VMDetector.swift -framework Foundation -target arm64-apple-macos13.0 -o /tmp/vmdetector_check && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add VMDetector.swift
git commit -m "feat: add VMDetector registry with 9 VM type detectors"
```

---

### Task 4: Implement VMScanner.swift + verify parser

**Files:**
- Modify: `VMScanner.swift`
- Modify: `Tests/verify_parsing.swift`

- [ ] **Step 1: Write VMScanner.swift**

```swift
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
```

- [ ] **Step 2: Write Tests/verify_parsing.swift**

```swift
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
// qemu-system should appear only once even though UTM+QEMU both use it
let qemuCount = pattern.components(separatedBy: "qemu-system").count - 1
check("qemu-system appears once", "\(qemuCount)", "1")

// ── Summary ───────────────────────────────────────────────────────────────────

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) FAILED.")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 3: Run the parser tests**

```bash
swiftc VMInfo.swift VMDetector.swift VMScanner.swift Tests/verify_parsing.swift \
    -framework Foundation -target arm64-apple-macos13.0 \
    -o /tmp/test_scanner && /tmp/test_scanner
```

Expected output:
```
VMScanner.parseOutput
  PASS  count
  PASS  QEMU type
  PASS  QEMU name
  PASS  Lima type
  PASS  Lima name
  PASS  vfkit type
  PASS  vfkit name
  PASS  UTM type
  PASS  UTM name

VMScanner.buildGrepPattern
  PASS  qemu-system appears once

All tests passed.
```

- [ ] **Step 4: Commit**

```bash
git add VMScanner.swift Tests/verify_parsing.swift
git commit -m "feat: add VMScanner with 9-detector ps-based VM detection"
```

---

### Task 5: Implement StatsProvider.swift + verify parser

**Files:**
- Modify: `StatsProvider.swift`
- Modify: `Tests/verify_parsing.swift`

- [ ] **Step 1: Write StatsProvider.swift**

```swift
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
```

- [ ] **Step 2: Add StatsProvider tests to Tests/verify_parsing.swift**

Append to the bottom of `Tests/verify_parsing.swift` (before the summary block — move the summary to the end):

```swift
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
```

The full `Tests/verify_parsing.swift` after the append (replace the whole file):

```swift
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
```

- [ ] **Step 3: Run all parser tests**

```bash
swiftc VMInfo.swift VMDetector.swift VMScanner.swift StatsProvider.swift Tests/verify_parsing.swift \
    -framework Foundation -target arm64-apple-macos13.0 \
    -o /tmp/test_all && /tmp/test_all
```

Expected output:
```
VMScanner.parseOutput
  PASS  count
  PASS  QEMU type
  PASS  QEMU name
  PASS  Lima type
  PASS  Lima name
  PASS  vfkit type
  PASS  vfkit name
  PASS  UTM type
  PASS  UTM name

VMScanner.buildGrepPattern
  PASS  qemu-system appears once

StatsProvider.parseStatsOutput
  PASS  stats count
  PASS  PID 1234 cpu
  PASS  PID 1234 mem
  PASS  PID 5678 cpu
  PASS  PID 5678 mem
  PASS  missing PID is nil

All tests passed.
```

- [ ] **Step 4: Commit**

```bash
git add StatsProvider.swift Tests/verify_parsing.swift
git commit -m "feat: add StatsProvider with CPU%/memory cache; add parser tests"
```

---

### Task 6: Implement AppDelegate.swift

**Files:**
- Modify: `AppDelegate.swift`

- [ ] **Step 1: Write AppDelegate.swift**

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    var statusItem: NSStatusItem!
    var timer: Timer?
    var cachedVMs: [VMInfo] = []
    var updateInterval: TimeInterval = 5.0
    let statsProvider = StatsProvider()

    var showCPU: Bool {
        get { UserDefaults.standard.bool(forKey: "showCPU") }
        set { UserDefaults.standard.set(newValue, forKey: "showCPU") }
    }

    var showMemory: Bool {
        get { UserDefaults.standard.bool(forKey: "showMemory") }
        set { UserDefaults.standard.set(newValue, forKey: "showMemory") }
    }

    // Monospaced font and paragraph style for the stats column layout.
    private let colFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let colStyle: NSParagraphStyle = {
        let s = NSMutableParagraphStyle()
        s.tabStops = [
            NSTextTab(textAlignment: .right, location: 200),
            NSTextTab(textAlignment: .right, location: 270),
        ]
        return s
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        if UserDefaults.standard.object(forKey: "updateInterval") != nil {
            updateInterval = UserDefaults.standard.double(forKey: "updateInterval")
        }
        refresh()
        startTimer()
    }

    // MARK: - Timer

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Refresh

    @objc func refresh() {
        let vms = VMScanner.getRunningVMs()
        if showCPU || showMemory {
            statsProvider.refresh(pids: vms.map { $0.pid })
            cachedVMs = vms.map { vm in
                var v = vm
                v.stats = statsProvider.cache[vm.pid]
                return v
            }
        } else {
            cachedVMs = vms
        }
        updateStatusItemImage(count: vms.count)
    }

    // MARK: - Status bar icon

    func updateStatusItemImage(count: Int) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 28, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let boxRect = NSRect(x: 4, y: 3, width: 20, height: 16)
            let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4)
            (isDarkMode
                ? NSColor.white.withAlphaComponent(0.8)
                : NSColor.black.withAlphaComponent(0.7)).setFill()
            boxPath.fill()
            let text = "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: isDarkMode ? NSColor.black : NSColor.white,
            ]
            let ts = text.size(withAttributes: attrs)
            text.draw(in: NSRect(x: boxRect.midX - ts.width / 2,
                                 y: boxRect.midY - ts.height / 2,
                                 width: ts.width, height: ts.height),
                      withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        button.image = image
        button.title = ""
    }

    // MARK: - Menu

    @objc func statusBarButtonClicked() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let vms = cachedVMs
        let statsOn = showCPU || showMemory

        // Header row
        let count = vms.count
        let headerText = count == 0
            ? "No VMs running"
            : "\(count) VM\(count == 1 ? "" : "s") RUNNING"
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !vms.isEmpty {
            if statsOn {
                menu.addItem(makeColumnHeaderItem())
            }
            for vm in vms {
                menu.addItem(statsOn ? makeStatsRow(vm: vm) : makePlainRow(vm: vm))
            }
            menu.addItem(.separator())
        }

        // Update Interval submenu
        let intervalMenu = NSMenu()
        for (label, secs) in [("1 second", 1.0), ("5 seconds", 5.0),
                               ("10 seconds", 10.0), ("30 seconds", 30.0),
                               ("1 minute", 60.0)] as [(String, TimeInterval)] {
            let item = NSMenuItem(title: label, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(secs)
            item.state = secs == updateInterval ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        // Stats submenu
        let statsMenu = NSMenu()
        let cpuItem = NSMenuItem(title: "Show CPU%", action: #selector(toggleCPU), keyEquivalent: "")
        cpuItem.target = self
        cpuItem.state = showCPU ? .on : .off
        statsMenu.addItem(cpuItem)
        let memItem = NSMenuItem(title: "Show Memory", action: #selector(toggleMemory), keyEquivalent: "")
        memItem.target = self
        memItem.state = showMemory ? .on : .off
        statsMenu.addItem(memItem)
        let statsMenuItem = NSMenuItem(title: "Stats", action: nil, keyEquivalent: "")
        statsMenuItem.submenu = statsMenu
        menu.addItem(statsMenuItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Menu item builders

    private func makePlainRow(vm: VMInfo) -> NSMenuItem {
        let item = NSMenuItem(title: vm.baseTitle, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeColumnHeaderItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        var title = "VM"
        if showCPU    { title += "\tCPU" }
        if showMemory { title += "\tMEM" }
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: colFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: colStyle,
        ])
        return item
    }

    private func makeStatsRow(vm: VMInfo) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        var title = "\(vm.name) [\(vm.type)]"
        if showCPU    { title += "\t\(vm.stats?.cpuString    ?? "—")" }
        if showMemory { title += "\t\(vm.stats?.memoryString ?? "—")" }
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: colFont,
            .paragraphStyle: colStyle,
        ])
        return item
    }

    // MARK: - Actions

    @objc func changeInterval(_ sender: NSMenuItem) {
        updateInterval = TimeInterval(sender.tag)
        UserDefaults.standard.set(updateInterval, forKey: "updateInterval")
        startTimer()
        refresh()
    }

    @objc func toggleCPU() {
        showCPU.toggle()
        refresh()
    }

    @objc func toggleMemory() {
        showMemory.toggle()
        refresh()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add AppDelegate.swift
git commit -m "feat: refactor AppDelegate to use VMScanner/StatsProvider, add stats column menu"
```

---

### Task 7: Add main.swift, build, and smoke test

**Files:**
- Modify: `main.swift`
- Delete: `VMMenuBarApp.swift`

- [ ] **Step 1: Write main.swift**

```swift
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Build**

```bash
chmod +x build.sh && ./build.sh
```

Expected output:
```
Building VMMenuBar...
Build complete! App created at: build/VMMenuBar.app
```

If compilation fails, read the error carefully — it will point to a specific file and line. Fix the issue before proceeding.

- [ ] **Step 3: Launch the app**

```bash
open build/VMMenuBar.app
```

Expected: app icon appears in menu bar showing a number in a box.

- [ ] **Step 4: Smoke test — no stats (default)**

1. Click the menu bar icon
2. Verify the header shows "N VMs RUNNING" or "No VMs running"
3. Each VM entry shows `name [type] #pid` format
4. "Update Interval" submenu is present with a checkmark on the active interval
5. "Stats" submenu is present with both "Show CPU%" and "Show Memory" unchecked

- [ ] **Step 5: Smoke test — enable stats**

1. Open menu → Stats → Show CPU% (checkmark appears)
2. Open menu → Stats → Show Memory (checkmark appears)
3. VM list now shows column header row "VM  CPU  MEM"
4. Each VM row shows name, CPU%, and memory right-aligned in columns
5. Open menu → Stats → Show CPU% again (unchecks it, column disappears)

- [ ] **Step 6: Delete VMMenuBarApp.swift**

```bash
rm VMMenuBarApp.swift
git add -A
git commit -m "feat: add main.swift; remove VMMenuBarApp.swift now that logic is split"
```

---

### Task 8: Run full parser test suite one final time

- [ ] **Step 1: Run all tests**

```bash
swiftc VMInfo.swift VMDetector.swift VMScanner.swift StatsProvider.swift Tests/verify_parsing.swift \
    -framework Foundation -target arm64-apple-macos13.0 \
    -o /tmp/test_final && /tmp/test_final
```

Expected output:
```
VMScanner.parseOutput
  PASS  count
  PASS  QEMU type
  PASS  QEMU name
  PASS  Lima type
  PASS  Lima name
  PASS  vfkit type
  PASS  vfkit name
  PASS  UTM type
  PASS  UTM name

VMScanner.buildGrepPattern
  PASS  qemu-system appears once

StatsProvider.parseStatsOutput
  PASS  stats count
  PASS  PID 1234 cpu
  PASS  PID 1234 mem
  PASS  PID 5678 cpu
  PASS  PID 5678 mem
  PASS  missing PID is nil

All tests passed.
```

- [ ] **Step 2: Final commit**

```bash
git add -A
git commit -m "chore: verify all parser tests pass on final build"
```
