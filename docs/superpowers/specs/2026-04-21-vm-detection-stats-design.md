# VM Detection & Stats — Design Spec
**Date:** 2026-04-21

## Goals

1. Expand VM detection to cover all major macOS hypervisors while keeping the `ps`-based approach.
2. Add opt-in per-VM stats (CPU%, memory) to the menu display.
3. Refactor the monolithic `VMMenuBarApp.swift` into focused modules for maintainability.

---

## File Structure

```
VMInfo.swift          — VMInfo struct + description helpers
VMDetector.swift      — VMDetector struct + all detector definitions
VMScanner.swift       — ps execution, output parsing, detector dispatch
StatsProvider.swift   — per-PID CPU%/memory fetch + cache
AppDelegate.swift     — timer, menu building, UserDefaults, status bar icon
main.swift            — 4-line app entry point
build.sh              — updated to compile all 6 files
```

Each file has one responsibility. Adding a new VM type means adding one `VMDetector` entry in `VMDetector.swift` only.

---

## VMDetector

```swift
struct VMDetector {
    let type: String
    let grepPattern: String
    let extractName: (String) -> String
}
```

`VMScanner` builds the grep command by joining all `grepPattern` values with `|` — one `ps` call covers all detectors.

### Detector Registry

| Type | grep pattern | Name extraction |
|------|-------------|-----------------|
| UTM | `qemu-system` (path contains `UTM.app`) | `-name` arg; checked **before** plain QEMU |
| QEMU | `qemu-system` | `-name` arg, fallback "QEMU VM" |
| Lima/VZ | `limactl hostagent` | instance ID from args; `0` → "Lima", else "Lima: \<id\>" |
| vfkit | `/vfkit ` | `--label` arg, fallback "vfkit" |
| Parallels | `prl_vm_app` | `.pvm` basename from `--config` arg |
| VMware Fusion | `vmware-vmx` | `.vmx` basename from path arg |
| VirtualBox | `VBoxHeadless\|VirtualBoxVM` | `--startvm` arg |
| Tart | `tart run\|tart: ` | VM name from args |
| OrbStack | `com.orbstack` | instance name from args |

**UTM/QEMU ordering:** UTM runs QEMU processes. `VMScanner.identifyVM()` checks for `UTM.app` in the command path before falling through to the plain QEMU detector.

---

## StatsProvider

Runs one `ps` call per refresh tick covering all known PIDs:

```bash
ps -o pid,pcpu,rss -p <pid1>,<pid2>,...
```

- `pcpu` → CPU percentage (e.g. `8.2`)
- `rss` → resident memory in KB → converted to MB/GB for display
- Results cached in a `[String: VMStats]` dictionary keyed by PID
- Cache cleared and refreshed on each `AppDelegate` timer tick alongside VM detection

```swift
struct VMStats {
    let cpu: Double    // percent
    let memoryMB: Int
}
```

If a PID is not found (VM exited between detection and stats fetch), the entry is omitted silently.

---

## VMInfo

```swift
struct VMInfo {
    let pid: String
    let name: String
    let type: String
    var stats: VMStats?   // nil when stats fetching is disabled
}
```

`description(showCPU:showMemory:)` computes the menu item title. When no stats are enabled, falls back to `"\(name) [\(type)] #\(pid)"`.

---

## Menu Layout

### No stats (default)

```
2 VMs RUNNING
─────────────────────────────
myvm [QEMU] #1234
Lima: default [VZ] #5678
─────────────────────────────
Update Interval  ▶
Stats            ▶
Refresh Now      ⌘R
─────────────────────────────
Quit             ⌘Q
```

### Stats enabled (CPU and/or Memory)

Column header row (disabled menu item, only shown when at least one stat is enabled) + right-aligned stat columns per VM row:

```
2 VMs RUNNING
─────────────────────────────
VM                    CPU    MEM
myvm [QEMU]          8.2%  1.2 GB
Lima: default [VZ]   0.3%  512 MB
─────────────────────────────
Update Interval  ▶
Stats            ▶
Refresh Now      ⌘R
─────────────────────────────
Quit             ⌘Q
```

Alignment is achieved via `NSAttributedString` with `NSTextTab` tab stops on menu items that use a custom `NSMenuItem` view, or approximated with a monospace font and fixed-width padding if attributed strings on `NSMenuItem` prove fragile.

### Stats submenu

```
Stats
  ✓ Show CPU%       (toggle, UserDefaults: showCPU,    default: false)
    Show Memory     (toggle, UserDefaults: showMemory, default: false)
```

Toggling either stat immediately triggers a menu rebuild and a fresh stats fetch.

---

## UserDefaults Keys

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `updateInterval` | Double | 5.0 | Refresh timer interval (existing) |
| `showCPU` | Bool | false | Show CPU% column |
| `showMemory` | Bool | false | Show Memory column |

---

## Build Script

`build.sh` updated to compile all Swift files:

```bash
swiftc VMInfo.swift VMDetector.swift VMScanner.swift \
        StatsProvider.swift AppDelegate.swift main.swift \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -target arm64-apple-macos13.0
```

---

## Out of Scope

- Start/stop VM controls from the menu
- Notifications on VM state changes
- VM grouping by type
- Custom per-type icons
- x86_64 build target (arm64 only, matching current `build.sh`)
