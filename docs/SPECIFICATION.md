# Proxmox LXC Update Script - Specification

## Project Overview
A Python script that automatically discovers running Proxmox LXC containers and executes the `update` command in each container using intelligent script detection and silent mode handling.

## Dynamic Update Script Detection ✨ NEW
The script now detects the update script type per container by reading `/usr/bin/update` and applies the appropriate update strategy:

### Detected Script Types

**1. Community-Scripts** (Community-Scripts/ProxmoxVE)
- Detection: Checks for `PHS_SILENT`, `msg_menu`, or `build.func`
- Execution: `PHS_SILENT=1 update` (silent mode)
- Benefit: Fully automated, no prompts

**2. tteck's Scripts** (tteck/Proxmox)
- Detection: Checks for `tteck/Proxmox` or `github.com/tteck` in script
- Execution: `update` (runs as-is, may auto-run or need handling)
- Example: `bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/ct/uptimekuma.sh)"`

**3. Community-Scripts Variants**
- Detection: Checks for `community-scripts.org` or `community-scripts/ProxmoxVE`
- Execution: `PHS_SILENT=1 update` (attempts silent mode)

**4. Generic/Unknown**
- Detection: Unrecognized script type
- Execution: `update` (runs with defaults)

## How It Works

1. **Container Discovery**: Scans running LXC containers via `pct list`
2. **Script Detection**: Reads `/usr/bin/update` from each container
3. **Type Classification**: Analyzes script content to determine type
4. **Smart Execution**: Applies type-specific update command
5. **Reporting**: Shows script types detected and individual container results

## Script Features
- ✅ Dynamically detects update script type per container
- ✅ Applies appropriate silent/automated method for each type
- ✅ Handles Community-Scripts with PHS_SILENT=1
- ✅ Handles tteck and other script variants
- ✅ Per-container error reporting with meaningful messages
- ✅ Summary report showing script types found
- ✅ Verbose mode for debugging: `sudo python3 proxmox_lxc_update.py -v`
- ✅ Requires root privileges (checks EUID)

## Usage

### Basic (Silent)
```bash
sudo python3 proxmox_lxc_update.py
```

### Verbose (with script detection output)
```bash
sudo python3 proxmox_lxc_update.py -v
```
or
```bash
sudo python3 proxmox_lxc_update.py --verbose
```

## Example Output
```
Found 2 running container(s): 104, 109

Processing container 104...
  → Script type: community-scripts
  ✓ Updated 104 (community-scripts: success)

Processing container 109...
  → Script type: tteck
  ✓ Updated 109 (tteck: success)

============================================================
SUMMARY
============================================================

Script Types Detected:
  community-scripts: 1
  tteck: 1

Updated: 2/2
  ✓ 104 (community-scripts)
  ✓ 109 (tteck)

✓ All containers updated successfully!
```

## Key Discovery
Community-Scripts uses `update` as an interactive script:
```bash
update = bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/gitea.sh)"
```

This presented a menu with 3 options requiring user input. The `PHS_SILENT=1` environment variable bypasses the interactive menu.

## SSH Remote Setup
For editing files directly in VS Code instead of nano:

1. SSH key already copied to Proxmox:
   ```bash
   ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.101
   ```

2. SSH config at `~/.ssh/config`:
   ```
   Host proxmox
       HostName 192.168.1.101
       User root
       IdentityFile ~/.ssh/id_rsa
   ```

3. Connect in VS Code:
   - `Cmd+Shift+P` → Remote-SSH: Connect to Host → proxmox
   - `Cmd+K Cmd+O` → `/opt/proxmox-scripts/`

## Script Location
- **Local**: `/Users/willemoldemans/Documents/PROJECTEN/proxmox-scripts/proxmox_lxc_update.py`
- **Remote**: `/opt/proxmox-scripts/proxmox_lxc_update.py`

## Test Command
```bash
sudo python3 /opt/proxmox-scripts/proxmox_lxc_update.py
```

## Container Details
- **Gitea Container**: VMID 104
- This is where we discovered the interactive update prompt issue
