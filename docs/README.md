# TubeArchivist Proxmox Deployment Scripts

Modern, production-ready scripts for deploying TubeArchivist on Proxmox VE with LXC containers.

## 📁 Folder Structure

```
proxmox-scripts/
├── README.md                        (this file)
├── create_ubuntu_lxc.sh            (create LXC container on Proxmox)
├── tubearchivist_setup_ubuntu.sh   (configure & deploy TubeArchivist in container)
├── check_proxmox_setup.sh          (verify Proxmox installation)
├── proxmox_lxc_update.py           (Proxmox LXC utilities)
│
├── helpers/                        (helper scripts - copied to container)
│   ├── ta-helper-simple.py        (hardlink organizer + NFO generator)
│   ├── ta-helper-run.sh           (helper runner wrapper)
│   └── ta-jf-proxy.py             (Jellyfin metadata proxy)
│
├── tubearchivist_nginx.conf       (nginx reference config)
└── docs/                          (documentation)
    ├── TUBEARCHIVIST_SETUP.md
    ├── TUBEARCHIVIST_CONFIG.md
    ├── SPECIFICATION.md
    └── (history files)
```

## 🚀 Quick Start

### Step 1: Create LXC Container
Run on Proxmox host:
```bash
./create_ubuntu_lxc.sh 122 tubearchivist local 192.168.1.186/24
```

**Parameters:**
- `122` - Container ID (CTID)
- `tubearchivist` - Hostname
- `local` - Proxmox storage pool
- `192.168.1.186/24` - IP address and CIDR

**Output shows next steps**

### Step 2: Deploy TubeArchivist
From Proxmox host:
```bash
# Copy scripts to container
pct push 122 ./tubearchivist_setup_ubuntu.sh /tmp/
pct push 122 ./helpers/ /tmp/helpers/

# Run setup
pct exec 122 -- bash /tmp/tubearchivist_setup_ubuntu.sh --media-path /mnt/media
```

**Setup will:**
- Install all dependencies (Python, Redis, Elasticsearch, Nginx)
- Build frontend
- Configure services
- Start all components automatically

## 🛠️ Helper Scripts (in `helpers/` folder)

### `ta-helper-simple.py`
Organizes TubeArchivist downloads with human-readable folder structure.

**Features:**
- Creates hardlinks (zero extra disk usage)
- Generates NFO metadata files (for Jellyfin)
- Marks videos as watched (prevents re-downloading)
- Queries Elasticsearch for metadata

**Runs every 5 minutes via systemd timer**

### `ta-jf-proxy.py`
Translation layer between Jellyfin plugin and TubeArchivist API.

**Features:**
- Converts human-readable names to TA IDs
- Serves images directly to Jellyfin
- Provides metadata in Jellyfin-compatible format
- Debug logging to `/var/log/ta-jf-proxy.log`

### `ta-helper-run.sh`
Wrapper script for ta-helper (handles environment setup).

## 📋 Services Started

All services run automatically on container startup:

| Service | Port | Purpose |
|---------|------|---------|
| Redis | 6379 | Cache/queue backend |
| Elasticsearch | 9200 | Search/metadata storage |
| TubeArchivist Backend | 8080 | Django API (internal only) |
| ta-jf-proxy | 8081 | Jellyfin metadata proxy |
| Nginx | 80 | Reverse proxy + frontend |

## 🔗 Access Points

- **TubeArchivist UI:** `http://container-ip:80` or `http://container-ip`
- **Jellyfin Proxy:** `http://container-ip:8081`
- **API Direct:** `http://container-ip:8080/api` (internal, use proxy for Jellyfin)

## ⚙️ Configuration

### Environment Variables (set in systemd services)

```bash
TA_USERNAME=admin
TA_PASSWORD=changeme
TA_HOST=localhost container-ip
ELASTIC_PASSWORD=changeme
```

### Media Storage

Default paths:
- Raw downloads: `/youtube` → `/mnt/media/arr/tubearchivist`
- Organized library: `/mnt/media/library/youtube`
- Cache: `/cache/`

Mount media via CIFS:
```bash
mount -t cifs //nas-ip/media /mnt/media -o username=user,password=pass
```

## 🐛 Troubleshooting

### Check Service Status
```bash
pct exec 122 -- systemctl status tubearchivist
pct exec 122 -- journalctl -u tubearchivist -n 50
```

### View Logs
```bash
# TubeArchivist
pct exec 122 -- tail -f /var/log/tubearchivist.log

# Helper
pct exec 122 -- tail -f /var/log/ta-helper.log

# Jellyfin Proxy
pct exec 122 -- tail -f /var/log/ta-jf-proxy.log
```

### Common Issues

**Elasticsearch not starting:**
```bash
pct exec 122 -- systemctl status elasticsearch
pct exec 122 -- journalctl -u elasticsearch -n 20
```

**Memory issues:**
- Increase container RAM or reduce worker concurrency
- Default: 8GB RAM, 4 CPU cores

**Permission denied errors:**
- Mount media as read-only to LXC container

## 📚 Documentation

- `TUBEARCHIVIST_SETUP.md` - Installation details
- `TUBEARCHIVIST_CONFIG.md` - Configuration reference  
- `SPECIFICATION.md` - Architecture & design
- `DEPLOYMENT_COMPLETE.md` - Past deployment history
- `FIXES_APPLIED.md` - Issue resolutions

## 🗑️ Deprecated Files

The following experimental approaches have been removed:

- ~~`tubearchivist_setup.sh`~~ - Old setup script
- ~~`tubearchivist_setup_improved.sh`~~ - Experimental variant
- ~~`tubearchivist_docker_setup.sh`~~ - Docker experiment (abandoned)
- ~~`create_tubearchivist_docker_lxc.sh`~~ - Docker LXC experiment
- ~~`create_tubearchivist_lxc.sh`~~ - Original LXC creator (replaced by `create_ubuntu_lxc.sh`)

## 📝 License & Notes

These scripts are provided as-is for TubeArchivist deployment on Proxmox VE.

**Tested on:**
- Proxmox VE 8.x
- Ubuntu 24.04 LTS
- TubeArchivist latest
- Jellyfin latest

---

**Created:** April 2026  
**Last Updated:** April 15, 2026
