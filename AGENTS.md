# VM Detection Agents

This document explains how the VM Menu Bar app detects and identifies virtual machines running on macOS.

## Architecture

The app uses a **process-based detection** approach that scans running processes to identify VM hypervisors and their instances.

### Core Components

1. **Update Timer**: Periodically triggers VM detection (configurable: 1s-60s)
2. **VM Scanner**: Executes process listing and filtering
3. **VM Identifiers**: Pattern matchers for different VM types
4. **Display Manager**: Updates menu bar icon with VM count
5. **Cache**: Stores VM list for instant menu display

## Detection Agents

Each "agent" is a detection pattern that identifies a specific type of VM hypervisor.

### Current Agents

#### 1. QEMU Agent
**Pattern**: `qemu-system`

**Detects**: 
- QEMU virtual machines
- Common process names: `qemu-system-aarch64`, `qemu-system-x86_64`

**Name Extraction**:
- Looks for `-name <vm-name>` parameter in command line
- Falls back to "QEMU VM" if not found

**Example Process**:
```
qemu-system-aarch64 -name myvm -m 4096 -smp 4 ...
```
**Identified as**: "myvm [QEMU]"

---

#### 2. Lima Agent
**Pattern**: `limactl hostagent`

**Detects**:
- Lima VMs (used by Rancher Desktop, Colima, etc.)
- Uses Apple's Virtualization.framework (VZ)

**Name Extraction**:
- Extracts instance ID from command line arguments
- Instance "0" is shown as "Lima"
- Other instances shown as "Lima: <instance-id>"

**Example Process**:
```
/path/to/limactl hostagent --pidfile /path/lima/0/ha.pid ... 0
```
**Identified as**: "Lima [Lima/VZ]"

---

#### 3. vfkit Agent
**Pattern**: `vfkit`

**Detects**:
- vfkit-based VMs (modern Lima backend)
- Uses Apple's Virtualization.framework (VZ)

**Name Extraction**:
- Currently shows as "vfkit"
- Can be extended to parse VM-specific arguments

**Example Process**:
```
vfkit --cpus 4 --memory 4096 ...
```
**Identified as**: "vfkit [vfkit/VZ]"

---

## How Detection Works

### 1. Process Listing
```bash
ps axo pid,command | grep -E 'qemu-system|limactl hostagent|vfkit' | grep -v grep
```

This single command:
- Lists all processes with PID and full command line
- Filters for known VM patterns
- Excludes the grep process itself

### 2. Output Parsing
Each line is parsed to extract:
- **PID**: Process identifier
- **Command**: Full command line with arguments

### 3. VM Identification
The `identifyVM()` function:
1. Converts command to lowercase for case-insensitive matching
2. Checks each agent pattern in order
3. Returns VM type and extracted name
4. Falls back to "Unknown" if no pattern matches

### 4. Caching
Results are cached in `cachedVMs` array:
- Menu displays instantly from cache
- Cache is updated on each timer tick
- No duplicate scanning when clicking menu

## Adding a New Detection Agent

To add support for a new VM type:

### Step 1: Add Pattern to grep
Edit `getRunningVMs()`:
```swift
task.arguments = ["-c", "ps axo pid,command | grep -E 'qemu-system|limactl hostagent|vfkit|YOUR_PATTERN' | grep -v grep"]
```

### Step 2: Add Identifier Logic
Edit `identifyVM()`:
```swift
func identifyVM(command: String) -> (type: String, name: String) {
    let cmdLower = command.lowercased()

    // ... existing patterns ...

    // Add your new pattern
    else if cmdLower.contains("your_vm_process") {
        let name = extractYourVMName(from: command)
        return ("YourVM", name)
    }

    return ("VM", "Unknown")
}
```

### Step 3: Add Name Extractor
Create a function to extract the VM name:
```swift
func extractYourVMName(from command: String) -> String {
    // Parse command line to find VM name
    // Example: look for specific flags or arguments
    if let nameRange = command.range(of: "--vm-name=([^\\s]+)", options: .regularExpression) {
        // Extract and return name
    }
    return "YourVM Instance"
}
```

### Step 4: Test
1. Start your VM
2. Verify it appears in: `ps aux | grep your_vm_process`
3. Rebuild the app: `./build.sh`
4. Launch and verify detection

## Performance Considerations

### Why This Approach?

**Single Command**: One `ps | grep` is much faster than:
- Iterating all processes with syscalls
- Calling `vmmap` on each process
- Spawning multiple processes

**Benchmarks**:
- Previous approach (syscall per process): ~0.8% CPU constant
- Current approach (single ps): 0.0% idle, brief spike on update

### Update Interval Trade-offs

| Interval | CPU Impact | Detection Lag | Use Case |
|----------|------------|---------------|----------|
| 1 second | Minimal (~0.1% avg) | Instant | Development/testing |
| 5 seconds | Negligible | Acceptable | General use (default) |
| 10 seconds | None | Slight delay | Battery saving |
| 30+ seconds | None | Noticeable | Minimal overhead |

## Future Enhancements

### Potential New Agents

1. **UTM Agent**: Detect UTM.app VMs
2. **Parallels Agent**: Detect Parallels Desktop VMs
3. **VMware Agent**: Detect VMware Fusion VMs
4. **VirtualBox Agent**: Detect VirtualBox VMs
5. **Tart Agent**: Detect Tart VMs (Cirrus Labs)
6. **OrbStack Agent**: Detect OrbStack containers/VMs

### Advanced Features

1. **Resource Monitoring**: Add CPU/memory stats per VM
2. **Control Actions**: Start/stop VMs from menu
3. **Notifications**: Alert on VM state changes
4. **VM Grouping**: Group by VM type or project
5. **Custom Icons**: Different icons per VM type

## Troubleshooting

### VM Not Detected

1. **Check if process is running**:
   ```bash
   ps aux | grep -i <your-vm>
   ```

2. **Verify process name matches pattern**:
   - Check the command line output
   - Ensure pattern in grep matches

3. **Add debug logging**:
   ```swift
   print("Command: \(command)")
   print("Identified: \(vmType), \(vmName)")
   ```

### Multiple Instances of Same VM

- Each running VM instance should appear separately
- Check PID to distinguish instances
- Ensure name extraction handles multiple instances

### Performance Issues

- Increase update interval
- Reduce grep pattern complexity
- Check system process count: `ps aux | wc -l`

## Technical Details

### Why Not Use Virtualization.framework API?

The app could theoretically use native Virtualization.framework APIs, but:
- **Requires entitlements**: Needs special app permissions
- **Only works for VZ-based VMs**: Misses QEMU, etc.
- **More complex**: Process scanning is simpler and generic
- **Performance**: Current approach is already optimal

### Process Filtering Strategy

The grep pattern uses:
- **Extended regex (-E)**: Allows multiple patterns with `|`
- **Full command line**: Captures all arguments for parsing
- **Double grep**: First finds VMs, second excludes grep itself

This is more efficient than:
- Multiple separate grep calls
- Post-processing in Swift
- Regular expression in Swift (slower)
