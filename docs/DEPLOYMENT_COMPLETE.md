# TubeArchivist LXC Deployment - COMPLETE ✅

**Date:** April 15, 2026  
**Status:** Production Ready  
**Container:** 122 (Ubuntu 24.04, 192.168.1.186/24)

## System is Live

### Access Points
- **Web UI:** http://192.168.1.186
- **API Base:** http://192.168.1.186/api/
- **Credentials:** admin / changeme

### Test Results
```
✅ Frontend loads (HTTP 200)
✅ Login works (HTTP 204 No Content)
✅ Backend responds (uvicorn on 127.0.0.1:8080)
✅ Nginx reverse proxy routing (port 80)
✅ Redis queue (127.0.0.1:6379)
✅ Elasticsearch healthy (port 9200)
✅ Celery workers active (2 concurrent)
✅ Media mount writable (/mnt/media/Youtube)
```

## Critical Configuration

### Nginx Proxy Headers
**File:** `/etc/nginx/sites-available/tubearchivist`
```nginx
proxy_set_header Host localhost;        # NOT localhost:8080
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_pass http://127.0.0.1:8080;
```

### Django ALLOWED_HOSTS
**File:** `/etc/systemd/system/tubearchivist.service`
```ini
Environment="TA_HOST=localhost 192.168.1.186"
```

This allows requests from:
- `localhost` (internal connections)
- `192.168.1.186` (container IP for external access)

### Resource Settings
- **Celery workers:** 2 (reduced from 4 to save memory)
- **Uvicorn workers:** 2 (reduced from 4)
- **Memory usage:** ~1.8GB / 8GB (79% headroom)
- **Logging level:** INFO (reduced from DEBUG for performance)

## Files Modified Today

1. `/etc/nginx/sites-available/tubearchivist` - Host header fix
2. `/app/run.sh` - Celery concurrency reduced, logging level
3. `/app/backend_start.py` - Uvicorn workers reduced
4. `/etc/systemd/system/tubearchivist.service` - Added TA_HOST, logging

## Network Configuration

| Component | IP | Port | Status |
|-----------|----|----|--------|
| Nginx (frontend) | 0.0.0.0 | 80 | ✅ Listening |
| Backend (uvicorn) | 127.0.0.1 | 8080 | ✅ Listening |
| Redis | 127.0.0.1 | 6379 | ✅ Running |
| Elasticsearch | 0.0.0.0 | 9200 | ✅ Running |
| Container IP | 192.168.1.186 | - | ✅ DHCP |

## Operational Notes

### Starting/Stopping
```bash
# From Proxmox host
pct exec 122 -- systemctl start tubearchivist
pct exec 122 -- systemctl stop tubearchivist
pct exec 122 -- systemctl restart tubearchivist
```

### Monitoring
```bash
# View logs in real-time
pct exec 122 -- journalctl -u tubearchivist -f

# Check status
pct exec 122 -- systemctl status tubearchivist

# View memory/CPU
pct exec 122 -- ps aux --sort=-%mem | head -15
```

### Storage
```bash
# Check media mount
pct exec 122 -- ls -la /mnt/media/Youtube

# Verify writable
pct exec 122 -- touch /mnt/media/Youtube/test.txt && \
  rm /mnt/media/Youtube/test.txt && echo "✓ Writable"
```

## Troubleshooting

### If system becomes unresponsive
```bash
# Container restart
pct stop 122
sleep 3
pct start 122
```

### If login fails with 403
Check TA_HOST env var in service file includes container IP and hostname.

### If ports don't respond
```bash
# Check listening
pct exec 122 -- ss -tlnp

# Check service status
pct exec 122 -- systemctl status tubearchivist
```

### If memory is low
Reduce Celery concurrency from 2 to 1:
```bash
pct exec 122 -- sed -i 's/--concurrency 2/--concurrency 1/g' /app/run.sh
pct exec 122 -- systemctl restart tubearchivist
```

## Performance Optimizations Applied

1. ✅ Reduced worker concurrency (2 instead of 4)
2. ✅ Changed logging from DEBUG to INFO
3. ✅ Fixed Nginx Host header (removed port)
4. ✅ Added container IP to ALLOWED_HOSTS
5. ✅ Optimized Nginx buffering settings
6. ✅ Added CORS headers for browser compatibility

## Next Steps (Optional Enhancements)

- [ ] Set up SSL/TLS with Let's Encrypt
- [ ] Configure automated backups
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Implement log rotation
- [ ] Add reverse proxy (Traefik/HAProxy) if needed
- [ ] Configure fail2ban for security

## Support

For issues, check:
1. Service logs: `journalctl -u tubearchivist`
2. Nginx logs: `tail -f /var/log/nginx/error.log`
3. System resources: `free -h` and `df -h`

---

**System deployed and tested successfully.**  
**Ready for production use.**
