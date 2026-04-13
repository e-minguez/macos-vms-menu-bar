import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var cachedVMs: [VMInfo] = []
    var updateInterval: TimeInterval = 5.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        // Load saved interval
        if UserDefaults.standard.object(forKey: "updateInterval") != nil {
            updateInterval = UserDefaults.standard.double(forKey: "updateInterval")
        }

        updateVMCount()
        startTimer()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateVMCount()
        }
    }

    @objc func statusBarButtonClicked() {
        let menu = NSMenu()
        let vms = cachedVMs

        if vms.isEmpty {
            let item = NSMenuItem(title: "No VMs running", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for vm in vms {
                let item = NSMenuItem(title: vm.description, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Update interval submenu
        let intervalMenu = NSMenu()
        let intervals: [(String, TimeInterval)] = [
            ("1 second", 1.0),
            ("5 seconds", 5.0),
            ("10 seconds", 10.0),
            ("30 seconds", 30.0),
            ("1 minute", 60.0)
        ]

        for (label, interval) in intervals {
            let item = NSMenuItem(title: label, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(interval)
            item.state = (interval == updateInterval) ? .on : .off
            intervalMenu.addItem(item)
        }

        let intervalItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(updateVMCount), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func changeInterval(_ sender: NSMenuItem) {
        updateInterval = TimeInterval(sender.tag)
        UserDefaults.standard.set(updateInterval, forKey: "updateInterval")
        startTimer()
        updateVMCount()
    }

    @objc func updateVMCount() {
        let vms = getRunningVMs()
        cachedVMs = vms
        updateStatusItemImage(count: vms.count)
    }

    func updateStatusItemImage(count: Int) {
        guard let button = statusItem.button else { return }

        // Create custom image with number in a box
        let size = NSSize(width: 28, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            // Determine if we're in dark mode
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Box dimensions
            let boxRect = NSRect(x: 4, y: 3, width: 20, height: 16)
            let cornerRadius: CGFloat = 4

            // Draw box
            let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: cornerRadius, yRadius: cornerRadius)

            if isDarkMode {
                // Dark mode: white/light gray box with dark text
                NSColor.white.withAlphaComponent(0.8).setFill()
            } else {
                // Light mode: dark box with light text
                NSColor.black.withAlphaComponent(0.7).setFill()
            }
            boxPath.fill()

            // Draw number
            let text = "\(count)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: isDarkMode ? NSColor.black : NSColor.white
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: boxRect.midX - textSize.width / 2,
                y: boxRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)

            return true
        }

        image.isTemplate = false
        button.image = image
        button.title = ""
    }

    func getRunningVMs() -> [VMInfo] {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "ps axo pid,command | grep -E 'qemu-system|limactl hostagent|/vfkit ' | grep -v grep"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return parseVMOutput(output)
        } catch {
            return []
        }
    }

    func parseVMOutput(_ output: String) -> [VMInfo] {
        var vms: [VMInfo] = []
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }

            let pid = String(trimmed[..<firstSpace])
            let command = String(trimmed[trimmed.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)

            let (vmType, vmName) = identifyVM(command: command)

            vms.append(VMInfo(
                pid: pid,
                name: vmName,
                type: vmType
            ))
        }

        return vms
    }

    func identifyVM(command: String) -> (type: String, name: String) {
        let cmdLower = command.lowercased()

        if cmdLower.contains("qemu-system") {
            let name = extractQEMUName(from: command)
            return ("QEMU", name)
        } else if cmdLower.contains("limactl hostagent") {
            let name = extractLimaName(from: command)
            return ("Lima/VZ", name)
        } else if cmdLower.contains("vfkit") {
            return ("vfkit/VZ", "vfkit")
        }

        return ("VM", "Unknown")
    }

    func extractQEMUName(from command: String) -> String {
        if let nameRange = command.range(of: "-name\\s+([^\\s,]+)", options: .regularExpression) {
            let nameMatch = String(command[nameRange])
            let parts = nameMatch.split(separator: " ")
            if parts.count > 1 {
                return String(parts[1]).components(separatedBy: ",").first ?? String(parts[1])
            }
        }
        return "QEMU VM"
    }

    func extractLimaName(from command: String) -> String {
        let parts = command.split(separator: " ").filter { !$0.contains("=") && !$0.hasPrefix("-") }

        if let last = parts.last, last.count < 20 {
            let instanceId = String(last)
            return instanceId == "0" ? "Lima" : "Lima: \(instanceId)"
        }

        return "Lima"
    }
}

struct VMInfo {
    let pid: String
    let name: String
    let type: String

    var description: String {
        return "\(name) [\(type)] (PID: \(pid))"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
