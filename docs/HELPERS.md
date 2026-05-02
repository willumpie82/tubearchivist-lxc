# TubeArchivist Helpers Documentation

## Storage Architecture

Your setup uses a **two-tier storage approach**:

```
Tier 1: Raw Archive Storage
├── /mnt/media/arr/tubearchivist/
│   ├── videos/
│   ├── cache/
│   └── download/
└── Purpose: Primary archive storage (large, untouched files)

Tier 2: Indexed/Organized Storage
└── /mnt/media/library/youtube/
    ├── Channel Name 1/
    │   ├── Video Title 1.mp4 (hardlink)
    │   ├── Video Title 1.nfo (metadata)
    │   └── ...
    ├── Channel Name 2/
    │   └── ...
    └── Purpose: Human-readable library for Jellyfin/media tools
```

## Helper Functions

### 1. **ta-helper-simple.py** - Symlink Library Manager

**Purpose**: Create organized hardlinks and NFO metadata files for Jellyfin

**Workflow**:
1. Queries Elasticsearch for all archived videos
2. Creates hardlinks in `/mnt/media/library/youtube/<channel>/<title>.mp4`
3. Generates NFO metadata files for Jellyfin metadata parsing
4. Auto-marks watched videos for deletion (optional)

**Key Features**:
- Hardlinks (not copies) - save storage space
- Channel-based organization
- Jellyfin NFO format compatibility
- Logs to `/var/log/ta-helper.log`

**Execution**:
- Systemd timer runs every 5 minutes
- Service: `ta-helper.service`
- Timer: `ta-helper.timer`

**Config**:
```bash
SOURCE_FOLDER="/mnt/media/arr/tubearchivist"    # Raw archive
TARGET_FOLDER="/mnt/media/library/youtube"      # Indexed library
ES_URL="http://localhost:9200/ta_video/_search" # Elasticsearch
```

**Use Cases**:
- ✅ Create organized library view in Jellyfin
- ✅ Automatic hardlink management
- ✅ NFO metadata generation
- ✅ Filesystem-based approach (no plugin needed)

**Commands**:
```bash
# View logs
journalctl -u ta-helper.service -f

# Disable if not using
systemctl disable ta-helper.timer

# Run manually
/opt/ta-helper/ta-helper-run.sh
```

---

### 2. **ta-helper-run.sh** - Symlink Manager Wrapper

**Purpose**: Wrapper script that activates the Python venv and runs ta-helper-simple.py

**Workflow**:
1. Activates `/app/venv/bin/activate`
2. Sets Python path
3. Runs `ta-helper-simple.py`
4. Captures output/errors

**Dependency**:
- Required by `ta-helper.service` to run ta-helper-simple.py
- Do not use independently

**File**:
```bash
#!/bin/bash
export PYTHONPATH="/app:$PYTHONPATH"
cd /opt/ta-helper
source /app/venv/bin/activate
python3 ta-helper-simple.py 2>/dev/null
```

---

### 3. **ta-jf-proxy.py** - Jellyfin API Proxy

**Purpose**: Translate human-readable names to TubeArchivist IDs for Jellyfin plugin

**Workflow**:
1. Listens on port 8081 (HTTP proxy)
2. Jellyfin plugin requests channel/video by name
3. Proxy queries Elasticsearch for internal ID
4. Returns TA API data with proper formatting
5. Handles image URL rewriting

**Key Endpoints**:
- `/api/channel/<name>/` - Get channel metadata by name
- `/api/video/<title>/` - Get video metadata by title
- `/api/image/<path>` - Serve images
- `/debug/` - Debug troubleshooting info
- `/health/` - Health check

**Execution**:
- Systemd service runs continuously
- Service: `ta-jf-proxy.service`
- Requires Flask: `apt install python3-flask`

**Use Cases**:
- ✅ Jellyfin plugin integration
- ✅ Real-time API proxy
- ✅ Name-to-ID translation
- ✅ No extra storage needed

**Commands**:
```bash
# View logs
journalctl -u ta-jf-proxy.service -f

# Test
curl http://localhost:8081/health/
curl http://localhost:8081/api/channel/MyChannel/
```

---

## Integration Modes

### Mode A: Symlink + NFO (ta-helper-simple.py + ta-helper-run.sh)

**Best for**: Separate storage, Jellyfin with library scanning

**Setup**:
1. Raw files stored in `/mnt/media/arr/tubearchivist/`
2. Hardlinks created in `/mnt/media/library/youtube/`
3. Jellyfin scans `/mnt/media/library/youtube/` as library
4. Reads NFO files for metadata

**Advantages**:
- ✅ Organized, human-readable structure
- ✅ Independent storage tiers (raw vs indexed)
- ✅ No plugin required
- ✅ Familiar Jellyfin library approach

**Disadvantages**:
- ❌ Requires extra storage mount
- ❌ Hardlinks only work on same filesystem
- ❌ Periodic sync (every 5 min)

---

### Mode B: Jellyfin Plugin + Proxy (ta-jf-proxy.py)

**Best for**: Direct integration, no extra storage

**Setup**:
1. Install Jellyfin TubeArchivist plugin
2. Configure plugin to proxy: `http://localhost:8081`
3. Plugin queries videos through proxy

**Advantages**:
- ✅ Real-time data
- ✅ No extra storage needed
- ✅ Direct API integration

**Disadvantages**:
- ❌ Requires Jellyfin plugin
- ❌ Proxy must be running
- ❌ More moving parts

---

### Mode C: Both (Recommended in Your Setup)

**Use**: Symlinking for filesystem library + proxy for plugin flexibility

**Both running**:
```bash
# Symlinking running
systemctl status ta-helper.timer

# Proxy running  
systemctl status ta-jf-proxy.service
```

---

## Storage Considerations

### Why Separate Storage?

**Your Architecture**:
- **Tier 1 (Raw)**: `/mnt/media/arr/tubearchivist/`
  - Primary archive storage
  - All downloaded videos
  - Full media cache
  - Large volume (hundreds of GB+)
  - Rarely accessed directly

- **Tier 2 (Indexed)**: `/mnt/media/library/youtube/`
  - Symlinks to Tier 1 files
  - Minimal storage (just inodes)
  - Organized by channel
  - Accessed via Jellyfin
  - Metadata files (.nfo)

**Benefits**:
- ✅ Organize raw archive separately from browsable library
- ✅ Hardlinks preserve space (no duplication)
- ✅ Independent scaling of both tiers
- ✅ Archive remains untouched (raw)
- ✅ Library can be rebuilt/reorganized independently

### Mount Requirements

For hardlinks to work, both mounts must be on **same filesystem**:

```bash
# Option 1: Same disk/partition
/dev/sda1 → /mnt/media
├── arr/tubearchivist/     (Tier 1)
└── library/youtube/       (Tier 2)

# Option 2: Different disks - use symlinks instead
# Or bind mount Tier 1 under Tier 2
```

---

## Monitoring & Maintenance

### Health Checks

```bash
# Symlink manager
journalctl -u ta-helper.service -f
tail -f /var/log/ta-helper.log

# Proxy
journalctl -u ta-jf-proxy.service -f
tail -f /var/log/ta-jf-proxy.log

# Check symlink count
ls /mnt/media/library/youtube/**/*.mp4 | wc -l
```

### Troubleshooting

**Symlinks not created**:
```bash
# Check if Elasticsearch is running
curl http://localhost:9200/ta_video/_search

# Run helper manually to see errors
/opt/ta-helper/ta-helper-run.sh

# Check permissions
ls -l /mnt/media/library/youtube/
```

**Proxy not responding**:
```bash
# Check if running
systemctl status ta-jf-proxy.service

# Test endpoint
curl http://localhost:8081/health/

# Check logs for errors
journalctl -u ta-jf-proxy.service -n 50
```

---

## Configuration Files

### ta-helper Environment
Location: `/opt/ta-helper/.env` (created by setup script)

### ta-helper Logs
- Location: `/var/log/ta-helper.log`
- Rotation: Via systemd journal

### ta-jf-proxy Logs
- Location: `/var/log/ta-jf-proxy.log`
- Rotation: Via systemd journal

---

## Summary

| Component | Role | Storage | Mode |
|-----------|------|---------|------|
| **ta-helper-simple.py** | Symlink + NFO generator | `/mnt/media/arr/` → `/mnt/media/library/` | Periodic |
| **ta-helper-run.sh** | ta-helper wrapper | N/A | Wrapper |
| **ta-jf-proxy.py** | Jellyfin API proxy | N/A (in-memory) | Continuous |

**Your Setup**: Both modes active for maximum flexibility. Use whichever approach works best for your Jellyfin integration!
