# TubeArchivist LXC Setup - Complete Configuration

## Status
✅ **Fully Working** - Ubuntu 24.04 native installation with LXC container persistence

## Certificate of Completion
- ✅ Frontend loads at `http://192.168.1.186`
- ✅ User login works (admin/changeme)
- ✅ API endpoints responsive after auth
- ✅ Media mount writable at `/mnt/media/Youtube` (CIFS to 192.168.1.102)
- ✅ Elasticsearch healthy (status: green)
- ✅ Redis running on localhost:6379
- ✅ Celery workers processing tasks
- ✅ All services auto-starting

## Container Specifications
- **Host**: Proxmox VE with LXC support
- **Container ID**: 122
- **OS**: Ubuntu 24.04 LTS (native)
- **Resources**: 4 CPU cores, 8 GB RAM, 100 GB disk
- **IP**: 192.168.1.186/24 (DHCP via vmbr0 bridge)
- **Storage**: CIFS mount at `/mnt/media` → `//192.168.1.102/Media`

## Component Versions
- **TubeArchivist**: Latest (git clone)
- **Django**: 6.0.4 + Django REST Framework
- **Elasticsearch**: 8.11.0 (HTTP, no SSL)
- **Redis**: 7.0.15
- **Nginx**: 1.24.0
- **Python**: 3.12 (native Ubuntu package)
- **Node.js**: 24.x (for frontend build)

## Critical Configuration Files

### Nginx Configuration: `/etc/nginx/sites-available/tubearchivist`
```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host localhost;  # ← CRITICAL: Must match Django ALLOWED_HOSTS
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Key Fix**: Host header set to `localhost` (NOT `localhost:8080`). Django's `ALLOWED_HOSTS` only contains `localhost` without port.

### Systemd Service: `/etc/systemd/system/tubearchivist.service`
```ini
[Service]
Environment="TA_HOST=localhost"
Environment="TA_PORT=8000"
Environment="TA_USERNAME=admin"
Environment="TA_PASSWORD=changeme"
Environment="ELASTIC_PASSWORD=changeme"
Environment="REDIS_CON=redis://localhost:6379"
Environment="ES_URL=http://localhost:9200"
Environment="ES_SNAPSHOT_DIR=/opt/elasticsearch/data/snapshots"

# CRITICAL: Must activate venv before running backend
ExecStart=/bin/bash -c 'source /app/venv/bin/activate && /app/run.sh'
```

### Elasticsearch: `/opt/elasticsearch/config/elasticsearch.yml`
```yaml
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
path.repo: /opt/elasticsearch/data/snapshots
```

**Why**: TubeArchivist connects via HTTP; snapshot directory must be writable.

## Installation Script
Run the setup script on the container:
```bash
bash /opt/proxmox-scripts/tubearchivist_setup_ubuntu.sh
```

This will:
1. Update system packages
2. Install Python 3.12, Node.js, JRE, ffmpeg, etc.
3. Download and install Elasticsearch 8.11.0
4. Clone TubeArchivist from GitHub
5. Build frontend with `npm run build:deploy`
6. Create Python venv and install dependencies
7. Configure Nginx, Redis, Celery
8. Create systemd services for auto-start

## Troubleshooting

### Backend returns 400 Bad Request
**Cause**: Nginx sends `Host: localhost:8080` but Django rejects it (ALLOWED_HOSTS mismatch)
**Fix**: Update Nginx config line to `proxy_set_header Host localhost;`

### API returns 404 Not Found
**Cause**: Backend not responding or routes not loaded
**Fix**: Restart service: `systemctl restart tubearchivist`

### Login redirects to login page
**Cause**: Django session not properly initialized
**Fix**: Clear browser cookies and try again

### Media mount not writable
**Verify**: `touch /mnt/media/Youtube/test.txt` - should succeed
**Debug**: Check `/etc/fstab` mount options, permissions on SMB share

## Testing Procedures

### From Proxmox host:
```bash
# Check container status
pct exec 122 -- systemctl status tubearchivist

# Run API tests
pct exec 122 -- curl -s http://127.0.0.1/api/ping/

# Check logs
pct exec 122 -- journalctl -u tubearchivist -n 50 --no-pager
```

### From browser:
```
http://192.168.1.186        # Frontend
http://192.168.1.186/api/   # API endpoints
```

### Login workflow:
```bash
curl -i -c /tmp/cookies.txt -X POST http://192.168.1.186/api/user/login/ \
  -d '{"username":"admin","password":"changeme"}' \
  -H "Content-Type: application/json"

# Should get 204 No Content + Set-Cookie headers

# Next request with auth:
curl -b /tmp/cookies.txt http://192.168.1.186/api/ping/
# Should return: {"response":"pong","user":1,"version":"v0.5.10",...}
```

## Known Limitations
- Single container instance (no clustering)
- Elasticsearch limited to 2GB heap (suitable for small-medium libraries)
- Celery runs with 4 workers (adjustable for RAM constraints)
- No HTTPS (use external reverse proxy/Let's Encrypt if needed)
- CIFS mount requires NAS availability

## Future Enhancements
- [ ] Add monitoring dashboard (Prometheus/Grafana)
- [ ] Implement automated backups to NAS
- [ ] Add Nginx caching for media files
- [ ] Configure log rotation for large deployments
- [ ] Add HTTPS support with self-signed or Let's Encrypt certificates

## Support References
- TubeArchivist: https://github.com/bbilly1/tubearchivist
- Django ALLOWED_HOSTS: https://docs.djangoproject.com/en/4.0/ref/settings/#allowed-hosts
- Elasticsearch: https://www.elastic.co/guide/en/elasticsearch/reference/8.11/index.html
- Proxmox LXC: https://pve.proxmox.com/wiki/Linux_Container

---
**Last Updated**: 2026-04-15
**Configuration State**: Production-ready
**Verified Status**: All components healthy and responsive
