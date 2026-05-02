#!/bin/bash
# Upgrade TubeArchivist in LXC container
# Usage: ./upgrade_tubearchivist.sh <container-id> [--skip-backup] [--skip-restart]

set -e

CONTAINER_ID="${1:-122}"
SKIP_BACKUP="${2:-}"
SKIP_RESTART="${3:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/ta-backup-${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TubeArchivist Upgrade Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Verify container exists
echo -e "${BLUE}Step 1: Verifying container ${CONTAINER_ID}...${NC}"
if ! pct status "${CONTAINER_ID}" >/dev/null 2>&1; then
    echo -e "${RED}✗ Container ${CONTAINER_ID} not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Container found${NC}"
echo ""

# Check if TubeArchivist is fully installed
echo -e "${BLUE}Step 2: Checking TubeArchivist installation...${NC}"
if ! pct exec "${CONTAINER_ID}" -- test -d /app 2>/dev/null; then
    echo -e "${RED}✗ TubeArchivist application directory (/app) not found${NC}"
    echo "It appears TubeArchivist is not fully installed on this container."
    echo ""
    echo "Please run the setup script first:"
    echo "  pct push ${CONTAINER_ID} ./tubearchivist_setup_ubuntu.sh /tmp/"
    echo "  pct push ${CONTAINER_ID} ./helpers/ /tmp/helpers/"
    echo "  pct exec ${CONTAINER_ID} -- bash /tmp/tubearchivist_setup_ubuntu.sh --media-path /mnt/media"
    echo ""
    exit 1
fi
if ! pct exec "${CONTAINER_ID}" -- test -d /app/venv 2>/dev/null; then
    echo -e "${RED}✗ Python virtual environment (/app/venv) not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ TubeArchivist installation verified${NC}"
echo ""

# Backup current state
if [[ "${SKIP_BACKUP}" != "--skip-backup" ]]; then
    echo -e "${BLUE}Step 3: Backing up current configuration...${NC}"
    
    # Create backup directory
    pct exec "${CONTAINER_ID}" -- mkdir -p "${BACKUP_DIR}"
    
    # Backup key directories
    echo "  - Backing up TubeArchivist config..."
    pct exec "${CONTAINER_ID}" -- tar -czf "${BACKUP_DIR}/tubearchivist-config.tar.gz" \
        /opt/tubearchivist 2>/dev/null || true
    
    echo "  - Backing up environment files..."
    pct exec "${CONTAINER_ID}" -- tar -czf "${BACKUP_DIR}/env-backup.tar.gz" \
        /etc/systemd/system/tubearchivist.service.d/ \
        /etc/systemd/system/ta-helper.service.d/ \
        /etc/systemd/system/ta-jf-proxy.service.d/ 2>/dev/null || true
    
    echo "  - Backing up database..."
    pct exec "${CONTAINER_ID}" -- tar -czf "${BACKUP_DIR}/elasticsearch-data.tar.gz" \
        /var/lib/elasticsearch 2>/dev/null || true
    
    echo -e "${GREEN}✓ Backups created in ${BACKUP_DIR}${NC}"
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping backup (--skip-backup flag)${NC}"
    echo ""
fi

# Stop services
echo -e "${BLUE}Step 4: Stopping services...${NC}"
pct exec "${CONTAINER_ID}" -- systemctl stop tubearchivist ta-helper ta-jf-proxy
echo -e "${GREEN}✓ Services stopped${NC}"
echo ""

# Update system packages
echo -e "${BLUE}Step 5: Updating system packages...${NC}"
pct exec "${CONTAINER_ID}" -- apt-get update
pct exec "${CONTAINER_ID}" -- apt-get upgrade -y
echo -e "${GREEN}✓ System packages updated${NC}"
echo ""

# Upgrade Python packages
echo -e "${BLUE}Step 6: Upgrading Python packages...${NC}"
pct exec "${CONTAINER_ID}" -- /app/venv/bin/pip install --upgrade pip setuptools wheel
pct exec "${CONTAINER_ID}" -- /app/venv/bin/pip install --upgrade -r /app/requirements.txt
echo -e "${GREEN}✓ Python packages upgraded${NC}"
echo ""

# Pull latest TubeArchivist code
echo -e "${BLUE}Step 7: Checking for code updates...${NC}"
if pct exec "${CONTAINER_ID}" -- test -d /app/.git 2>/dev/null; then
    echo "  Git repository detected, pulling latest code..."
    pct exec "${CONTAINER_ID}" -- bash -c 'cd /app && git fetch origin && git pull origin master'
    echo -e "${GREEN}✓ Latest code pulled${NC}"
else
    echo -e "${YELLOW}⊘ TubeArchivist not installed from git${NC}"
    echo "  Code is pre-built (Docker distribution). Skipping code update."
    echo "  To upgrade code: Deploy new container with latest image or manually pull from GitHub."
fi
echo ""

# Rebuild frontend
echo -e "${BLUE}Step 8: Checking frontend build...${NC}"
if pct exec "${CONTAINER_ID}" -- test -f /app/frontend/package.json 2>/dev/null; then
    echo "  Frontend source detected, rebuilding..."
    pct exec "${CONTAINER_ID}" -- bash -c 'cd /app/frontend && npm install && npm run build'
    echo -e "${GREEN}✓ Frontend rebuilt${NC}"
else
    echo -e "${YELLOW}⊘ Frontend not built from source${NC}"
    echo "  Using pre-built static files. Skipping frontend rebuild."
fi
echo ""

# Run database migrations
echo -e "${BLUE}Step 9: Running database migrations...${NC}"
pct exec "${CONTAINER_ID}" -- bash -c 'cd /app && /app/venv/bin/python manage.py migrate --noinput'
echo -e "${GREEN}✓ Migrations completed${NC}"
echo ""

# Restart services (or just show commands if --skip-restart)
if [[ "${SKIP_RESTART}" != "--skip-restart" ]]; then
    echo -e "${BLUE}Step 10: Restarting services...${NC}"
    
    # Restart systemd services
    pct exec "${CONTAINER_ID}" -- systemctl daemon-reload
    pct exec "${CONTAINER_ID}" -- systemctl restart ta-helper
    pct exec "${CONTAINER_ID}" -- systemctl restart ta-jf-proxy
    pct exec "${CONTAINER_ID}" -- systemctl restart tubearchivist
    
    echo -e "${GREEN}✓ Services restarted${NC}"
    echo ""
    
    # Wait for services to stabilize
    echo -e "${BLUE}Step 10: Waiting for services to stabilize...${NC}"
    sleep 5
    
    # Health check
    echo -e "${BLUE}Step 11: Performing health checks...${NC}"
    
    # Check TubeArchivist is responding
    if pct exec "${CONTAINER_ID}" -- curl -s http://localhost:8080/api/ping >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ TubeArchivist API responding${NC}"
    else
        echo -e "${YELLOW}  ⚠ TubeArchivist API not responding (may still be starting)${NC}"
    fi
    
    # Check Elasticsearch
    if pct exec "${CONTAINER_ID}" -- curl -s http://localhost:9200 >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Elasticsearch responding${NC}"
    else
        echo -e "${RED}  ✗ Elasticsearch not responding${NC}"
    fi
    
    # Check Redis
    if pct exec "${CONTAINER_ID}" -- redis-cli ping >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Redis responding${NC}"
    else
        echo -e "${RED}  ✗ Redis not responding${NC}"
    fi
    
    echo ""
else
    echo -e "${YELLOW}⊘ Skipping restart (--skip-restart flag)${NC}"
    echo ""
    echo -e "${YELLOW}To restart services manually, run:${NC}"
    echo "  pct exec ${CONTAINER_ID} -- systemctl restart tubearchivist ta-helper ta-jf-proxy"
    echo ""
fi

# Show upgrade summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Upgrade completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Upgrade Summary:"
echo "  Container ID: ${CONTAINER_ID}"
echo "  Timestamp: ${TIMESTAMP}"
if [[ "${SKIP_BACKUP}" != "--skip-backup" ]]; then
    echo "  Backup Location: ${BACKUP_DIR}"
fi
echo ""

echo "Access TubeArchivist:"
pct exec "${CONTAINER_ID}" -- hostname -I | xargs -I {} echo "  http://{}"
echo ""

echo "Useful commands:"
echo "  View logs:"
echo "    pct exec ${CONTAINER_ID} -- journalctl -u tubearchivist -n 50"
echo "    pct exec ${CONTAINER_ID} -- tail -f /var/log/ta-helper.log"
echo "    pct exec ${CONTAINER_ID} -- tail -f /var/log/ta-jf-proxy.log"
echo ""
echo "  Backup location: ${BACKUP_DIR}"
if [[ "${SKIP_BACKUP}" != "--skip-backup" ]]; then
    echo "  To restore from backup:"
    echo "    pct exec ${CONTAINER_ID} -- tar -xzf ${BACKUP_DIR}/tubearchivist-config.tar.gz -C /"
fi
echo ""
