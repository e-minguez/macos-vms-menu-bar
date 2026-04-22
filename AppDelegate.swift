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
