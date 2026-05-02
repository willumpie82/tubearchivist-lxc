# TubeArchivist LXC Setup Guide

Complete guide for setting up TubeArchivist in a Proxmox LXC container with native services (no nested Docker).

## Overview

TubeArchivist is an open-source archiver for YouTube content. This setup provides:
- **TubeArchivist**: Main application for archiving YouTube videos
- **Elasticsearch**: Search engine for archived content
- **Redis**: Cache/message broker
- **Native Services**: Running directly in LXC (no Docker within Docker)

### System Requirements

- **CPU**: 4+ cores (8+ recommended)
- **RAM**: 8GB (4GB minimum)
- **Storage**: 100GB+ (depending on video library size)
- **Network**: Access to YouTube and external APIs

---

## Quick Start

### Option 1: Create New LXC Container (Recommended)

Create and configure a complete TubeArchivist container automatically:

```bash
cd /opt/proxmox-scripts
sudo bash create_tubearchivist_lxc.sh \
  --vmid 200 \
  --hostname tubearchivist \
  --cores 4 \
  --memory 8192 \
  --disk 100 \
  --media-path /mnt/media/library/Youtube
```

**Parameters:**
- `--vmid ID`: Container ID (auto-incremented if omitted)
- `--hostname NAME`: Container hostname (default: tubearchivist)
- `--cores N`: CPU cores (default: 4)
- `--memory MB`: RAM in MB (default: 8192)
- `--disk SIZE`: Disk size in GB (default: 100)
- `--storage STORAGE`: Proxmox storage backend (default: local-lvm)
- `--ostype TYPE`: debian or ubuntu (default: debian)
- `--media-path PATH`: Storage for videos (default: /mnt/media/library/Youtube)

**What happens:**
1. Creates new LXC container with specified resources
2. Configures networking (DHCP)
3. Mounts media storage directory
4. Automatically runs installation script inside container
5. Starts all services
6. Provides access details

### Option 2: Install on Existing Container

If you already have an LXC container:

```bash
# Copy setup script to host first
scp tubearchivist_setup.sh root@<container-ip>:/tmp/

# SSH into container
ssh root@<container-ip>

# Run setup inside container
sudo bash /tmp/tubearchivist_setup.sh --media-path /mnt/media/library/Youtube
```

Or directly from Proxmox host:

```bash
pct exec <vmid> -- bash -c 'curl -o /tmp/setup.sh <script-url> && bash /tmp/setup.sh'
```

---

## What Gets Installed

### Services
- **Redis**: Cache database (port 6379)
- **Elasticsearch**: Search engine (port 9200)
- **TubeArchivist**: Main app (port 8000)

### Directories
```
/opt/tubearchivist/
  ├── venv/               # Python virtual environment
  ├── app/                # TubeArchivist application code
  ├── config.json         # Application configuration
  ├── start.sh            # Start all services
  ├── stop.sh             # Stop all services
  ├── restart.sh          # Restart TubeArchivist
  ├── status.sh           # Check service status
  └── logs.sh             # View live logs

/var/lib/tubearchivist/   # Elasticsearch data
/var/cache/tubearchivist/ # Redis cache

[MEDIA_PATH]/
  ├── videos/             # Downloaded video files
  ├── downloads/          # Temporary downloads
  └── cache/              # Application cache
```

---

## Initial Configuration

### 1. Access Web Interface

After installation, access TubeArchivist at:
```
http://<container-ip>:8000
```

### 2. First Run Setup
- Complete initial configuration wizard
- Set download preferences
- Configure YouTube channel subscriptions

### 3. Storage Configuration
- Configure download quality (recommended: 720p)
- Auto-download settings
- Retention policies

---

## Management

### View Service Status
```bash
bash /opt/tubearchivist/status.sh
```

### View Logs
```bash
bash /opt/tubearchivist/logs.sh

# Or specific service logs
journalctl -u tubearchivist -f
journalctl -u elasticsearch -f
journalctl -u redis-server -f
```

### Restart Services
```bash
bash /opt/tubearchivist/restart.sh

# Or specific service
systemctl restart tubearchivist
```

### Stop/Start
```bash
bash /opt/tubearchivist/stop.sh
bash /opt/tubearchivist/start.sh
```

---

## Advanced Configuration

### Customize JVM Heap for Elasticsearch

Edit `/etc/systemd/system/elasticsearch.service`:
```ini
Environment=ES_JAVA_OPTS=-Xms2g -Xmx4g
```

Then reload and restart:
```bash
systemctl daemon-reload
systemctl restart elasticsearch
```

### Adjust Redis Memory

Edit `/etc/redis/redis.conf`:
```
maxmemory 2gb
maxmemory-policy allkeys-lru
```

Then restart:
```bash
systemctl restart redis-server
```

### Change TubeArchivist Port

Edit `/etc/systemd/system/tubearchivist.service` and update port configuration, then:
```bash
systemctl daemon-reload
systemctl restart tubearchivist
```

---

## Backup & Restore

### Backup Configuration
```bash
# Backup application data
tar -czf tubearchivist-backup.tar.gz /opt/tubearchivist/

# Backup Elasticsearch indices
# Backup Redis database
cp /var/lib/redis/dump.rdb tubearchivist-redis-backup.rdb
```

### Snapshot from Proxmox
```bash
# From Proxmox host
pct snapshot <vmid> tubearchivist-backup-$(date +%Y%m%d)
```

---

## Troubleshooting

### Elasticsearch won't start
```bash
# Check logs
journalctl -u elasticsearch -n 50

# Check disk space (Elasticsearch needs ~50% free)
df -h

# Increase JVM heap if needed
systemctl edit elasticsearch
```

### TubeArchivist shows "Connection refused"
```bash
# Check if Redis and Elasticsearch are running
systemctl status redis-server
systemctl status elasticsearch

# Restart dependent services
systemctl restart elasticsearch
sleep 10
systemctl restart tubearchivist
```

### High memory usage
- Reduce Elasticsearch heap size in systemd service
- Configure Redis maxmemory policies
- Check TubeArchivist task queue

### Container network issues
```bash
# Check network from container
pct exec <vmid> -- ping 8.8.8.8

# Test DNS
pct exec <vmid> -- nslookup youtube.com
```

---

## Updates

### Update TubeArchivist

```bash
cd /opt/tubearchivist/app
git pull origin main
source ../venv/bin/activate
pip install -r requirements.txt
systemctl restart tubearchivist
```

### Update System Packages

```bash
apt-get update
apt-get upgrade
```

### Update Elasticsearch

Not recommended without planning. Back up data first, then:
```bash
# Edit docker repository or package version
# Update and restart
```

---

## Performance Tuning

### For Large Libraries (1000+ videos)

**Elasticsearch:**
```bash
# In /etc/systemd/system/elasticsearch.service
Environment=ES_JAVA_OPTS=-Xms4g -Xmx4g
```

**Redis:**
```bash
# In /etc/redis/redis.conf
maxmemory 4gb
```

**TubeArchivist:**
- Limit concurrent downloads: 2-4 threads
- Schedule downloads off-peak
- Use lower quality for archive-only content

### Monitor Performance
```bash
# Check Elasticsearch cluster health
curl http://localhost:9200/_cluster/health

# Monitor system resources
watch -n 1 'free -h && df -h'

# Check process resources
ps aux | grep -E "(elasticsearch|redis|python)"
```

---

## Security Considerations

### Network Security
- Restrict access to ports 8000, 9200, 6379
- Use firewall rules to limit container access
- Consider VPN/reverse proxy for remote access

### Credentials
- Change default TubeArchivist credentials immediately
- Use strong, unique passwords
- Store credentials securely

### Container Security
- Regular security updates
- Limit container privileges (check Proxmox LXC config)
- Monitor disk space to prevent DoS

### Data Protection
- Regular backups of configuration and indices
- Test restore procedures
- Monitor for failed downloads/errors

---

## Integration with Proxmox Automation

### Auto-Update Script
Use `/opt/proxmox-scripts/proxmox_lxc_update.py` to automatically update containers:

```bash
# This will detect TubeArchivist and run appropriate update
sudo python3 proxmox_lxc_update.py
```

### Scheduled Updates
Add to crontab for nightly updates:
```bash
# 2 AM daily
0 2 * * * /opt/proxmox-scripts/proxmox_lxc_update.py -v >> /var/log/ta-update.log 2>&1
```

---

## Support & Resources

- **TubeArchivist GitHub**: https://github.com/bbilly1/tubearchivist
- **Documentation**: https://docs.tubearchivist.com/
- **Issues**: https://github.com/bbilly1/tubearchivist/issues
- **Community**: GitHub Discussions

---

## License

These setup scripts are provided as-is. TubeArchivist is licensed under GPLv3.

---

*Last Updated: 2026*
