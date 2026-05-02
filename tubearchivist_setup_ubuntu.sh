#!/bin/bash
# TubeArchivist Native Installation Script for Ubuntu 24.04
# Simplified - Uses native Python 3.12 (no compilation needed)
# Much faster than source building

set -e

# Script directory for external files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup logging
LOG_FILE="/var/log/tubearchivist-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1
echo "=== TubeArchivist Setup Started at $(date) ===" >> "$LOG_FILE"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
MEDIA_PATH="/mnt/media"


print_status() {
  echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
  echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --media-path)
      MEDIA_PATH="$2"
      shift 2
      ;;
    --help)
      head -n 12 "$0"
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root"
  exit 1
fi

print_status "Starting TubeArchivist native setup (Ubuntu 24.04)..."
print_status "Media storage path: $MEDIA_PATH"
print_status "Using Python 3.12 (native)"

# ========== Update system ==========
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y
print_success "System updated"

# ========== Install dependencies ==========
print_status "Installing dependencies..."
apt-get install -y \
  curl wget git \
  python3.12 python3.12-venv python3.12-dev \
  python3-pip \
  build-essential libssl-dev libffi-dev \
  libldap2-dev libsasl2-dev \
  redis-server \
  default-jre-headless \
  nginx \
  atomicparsley \
  ffmpeg

print_success "Dependencies installed"

# ========== Install Node.js (for frontend build) ==========
print_status "Installing Node.js..."
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
  print_success "Node.js installed"
else
  print_success "Node.js already installed"
fi

# ========== Install Elasticsearch ==========
print_status "Installing Elasticsearch..."
if [ ! -d /opt/elasticsearch ]; then
  cd /opt
  ES_VERSION="8.11.0"
  ES_FILE="elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz"
  
  if [ ! -f "$ES_FILE" ]; then
    print_status "Downloading Elasticsearch $ES_VERSION..."
    wget -q "https://artifacts.elastic.co/downloads/elasticsearch/$ES_FILE"
  fi
  
  tar -xzf "$ES_FILE"
  rm "$ES_FILE"
  mv elasticsearch-${ES_VERSION} elasticsearch
  
  useradd -r -s /bin/false elasticsearch 2>/dev/null || true
  chown -R elasticsearch:elasticsearch /opt/elasticsearch
  
  cat > /etc/systemd/system/elasticsearch.service << 'ESEOF'
[Unit]
Description=Elasticsearch
After=network.target

[Service]
Type=simple
User=elasticsearch
Group=elasticsearch
ExecStart=/opt/elasticsearch/bin/elasticsearch
WorkingDirectory=/opt/elasticsearch
Environment="ES_JAVA_OPTS=-Xms1g -Xmx2g"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
ESEOF

  systemctl daemon-reload
  print_success "Elasticsearch installed"
else
  print_success "Elasticsearch already installed"
fi

# ========== Create directories ==========
print_status "Creating application directories..."
mkdir -p /app /cache /opt/yt_plugins/bgutil

# Only chmod local directories - DO NOT touch the network mount
chmod -R 755 /app /cache /opt/yt_plugins

# Verify YouTube folder exists on mount (don't chmod it - other services might use /mnt/media)
if [ -d "$MEDIA_PATH/Youtube" ]; then
  print_status "YouTube folder found at $MEDIA_PATH/Youtube"
elif [ -d "$MEDIA_PATH/youtube" ]; then
  print_status "YouTube folder found at $MEDIA_PATH/youtube"
elif [ -d "$MEDIA_PATH" ]; then
  print_warning "No Youtube folder found in $MEDIA_PATH - TubeArchivist will create it on first run"
else
  print_error "Media path $MEDIA_PATH not mounted!"
  exit 1
fi

print_success "Application directories created"

# ========== Clone TubeArchivist repository ==========
print_status "Cloning TubeArchivist repository..."
if [ ! -d /opt/tubearchivist/app ]; then
  mkdir -p /opt/tubearchivist
  git clone https://github.com/bbilly1/tubearchivist.git /opt/tubearchivist/app
  print_success "Repository cloned"
else
  print_status "Repository already exists, updating..."
  cd /opt/tubearchivist/app
  git pull
  print_success "Repository updated"
fi

# ========== Build frontend ==========
print_status "Building frontend..."
if [ -d /opt/tubearchivist/app/frontend ]; then
  cd /opt/tubearchivist/app/frontend

  print_status "Installing frontend dependencies..."
  npm ci || npm install
  
  print_status "Building frontend distribution..."
  npm run build:deploy

  print_success "Frontend built successfully"

  # Copy dist to app
  mkdir -p /app/static
  cp -r dist/* /app/static/
else
  print_warning "Frontend source not found, skipping build"
fi

# ========== Setup Python virtual environment ==========
print_status "Creating Python 3.12 virtual environment..."
cd /opt/tubearchivist/app

python3.12 -m venv /app/venv
source /app/venv/bin/activate

print_status "Upgrading pip and build tools..."
pip install --upgrade pip setuptools wheel

# ========== Install Python dependencies ==========
print_status "Installing backend Python packages..."
if [ -f backend/requirements.txt ]; then
  # Show pip output for debugging
  if ! pip install -r backend/requirements.txt; then
    print_error "Failed to install backend requirements!"
    print_error "Check the pip output above for details"
    deactivate
    exit 1
  fi
  print_success "Backend packages installed successfully"
else
  print_error "Backend requirements.txt not found!"
  deactivate
  exit 1
fi

# Install plugin requirements (optional)
if [ -f backend/requirements.plugins.txt ]; then
  print_status "Installing plugin dependencies..."
  pip install --target /opt/yt_plugins/bgutil -r backend/requirements.plugins.txt || {
    print_warning "Plugin installation had issues, but continuing..."
  }
fi

print_success "All Python packages installed"

# ========== Setup application files ==========
print_status "Setting up application files..."
cp -r /opt/tubearchivist/app/backend/* /app/ 2>/dev/null || true
cp -r /opt/tubearchivist/app/docker_assets/* /app/ 2>/dev/null || true

if [ -f /app/run.sh ]; then
  chmod +x /app/run.sh
  print_success "run.sh is executable"
fi

# ========== Setup Nginx ==========
print_status "Configuring Nginx reverse proxy..."
cat > /etc/nginx/sites-available/tubearchivist << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /app/static;
    index index.html;

    # Serve cache files directly (images, thumbnails, etc)
    location /cache/ {
        alias /cache/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Debug-From "cache-location";
        access_log /var/log/nginx/cache-access.log;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        if ($request_method = OPTIONS) {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization, X-CSRF-Token' always;
            return 204;
        }
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/tubearchivist /etc/nginx/sites-enabled/tubearchivist
rm -f /etc/nginx/sites-enabled/default
sed -i 's/^user www-data;$/user root;/' /etc/nginx/nginx.conf
nginx -t >/dev/null 2>&1 && print_success "Nginx configured" || print_error "Nginx config error"

# ========== Optimize backend configuration ==========
print_status "Optimizing backend worker concurrency..."
sed -i 's/--concurrency 4/--concurrency 2/g' /app/run.sh 2>/dev/null || true
sed -i 's/workers=4/workers=2/g' /app/backend_start.py 2>/dev/null || true
sed -i 's/LOGLEVEL="DEBUG"/LOGLEVEL="INFO"/g' /app/run.sh 2>/dev/null || true
print_success "Backend optimized (2 workers, INFO logging)"

# ========== Get container IP ==========
CONTAINER_IP=$(ip addr show scope global 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1 || echo "localhost")

# ========== Create systemd orchestration service ==========
print_status "Creating TubeArchivist systemd service..."

cat > /etc/systemd/system/tubearchivist.service << TAEOF
[Unit]
Description=TubeArchivist Service
After=network.target redis-server.service elasticsearch.service

[Service]
Type=simple
User=root
WorkingDirectory=/app
Environment="PATH=/app/venv/bin:/usr/local/bin:/usr/bin"
Environment="PYTHONUNBUFFERED=1"
Environment="PYTHONPATH=/opt/yt_plugins"
Environment="ES_URL=http://localhost:9200"
Environment="REDIS_HOST=localhost"
Environment="REDIS_PORT=6379"
Environment="TA_USERNAME=admin"
Environment="TA_PASSWORD=changeme"
Environment="ELASTIC_PASSWORD=changeme"
Environment="TA_HOST=localhost ${CONTAINER_IP}"
Environment="DJANGO_DEBUG=0"

ExecStart=/bin/bash -c 'source /app/venv/bin/activate && /app/run.sh'

KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
TAEOF

systemctl daemon-reload
print_success "Systemd service created"

# ========== Setup download directory on NAS ==========
print_status "Setting up download directories..."
mkdir -p /mnt/media/arr/tubearchivist
mkdir -p /mnt/media/library/youtube
# Create symlink so /youtube (TubeArchivist default) points to actual downloads in arr
rm -rf /youtube
ln -sf /mnt/media/arr/tubearchivist /youtube
print_success "Downloads: /youtube → /mnt/media/arr/tubearchivist"
print_success "Symlinks: /mnt/media/library/youtube (managed by ta-helper)"

# ========== Install ta-helper for human-readable symlinks ==========
print_status "Installing ta-helper for symlink management..."
cd /opt
if [ ! -d ta-helper ]; then
  git clone https://github.com/RoninTech/ta-helper.git
  print_success "ta-helper cloned"
else
  cd ta-helper && git pull
  print_success "ta-helper updated"
fi

# Configure ta-helper
cat > /opt/ta-helper/.env << 'TAHELPEREOF'
LOGLEVEL="INFO"
TA_SERVER="http://localhost:8080"
TA_TOKEN="placeholder"
TA_CACHE="/cache"
SOURCE_FOLDER="/mnt/media/arr/tubearchivist"
TARGET_FOLDER="/mnt/media/library/youtube"
GENERATE_NFO=False
CLEANUP_DELETED_VIDEOS=True
NOTIFICATIONS_ENABLED=False
TAHELPEREOF

# Copy ta-helper script from external file
if [ -f "$SCRIPT_DIR/helpers/ta-helper-simple.py" ]; then
  cp "$SCRIPT_DIR/helpers/ta-helper-simple.py" /opt/ta-helper/ta-helper-simple.py
  print_success "ta-helper-simple.py copied"
else
  print_warning "ta-helper-simple.py not found in $SCRIPT_DIR/helpers/"
fi

chmod +x /opt/ta-helper/ta-helper-simple.py

# Create log file with proper permissions
touch /var/log/ta-helper.log
chmod 666 /var/log/ta-helper.log

# Copy ta-helper runner script from external file
if [ -f "$SCRIPT_DIR/helpers/ta-helper-run.sh" ]; then
  cp "$SCRIPT_DIR/helpers/ta-helper-run.sh" /opt/ta-helper/ta-helper-run.sh
  chmod +x /opt/ta-helper/ta-helper-run.sh
  print_success "ta-helper-run.sh copied"
else
  print_warning "ta-helper-run.sh not found in $SCRIPT_DIR/helpers/"
fi

# Create systemd timer
cat > /etc/systemd/system/ta-helper.service << 'SVCEOF'
[Unit]
Description=TubeArchivist Helper - Create human-readable symlinks
Wants=tubearchivist.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/ta-helper/ta-helper-run.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ta-helper
SVCEOF

cat > /etc/systemd/system/ta-helper.timer << 'TIMEREOF'
[Unit]
Description=Run TubeArchivist Helper every 5 minutes
Requires=ta-helper.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMEREOF

# Enable the timer
systemctl daemon-reload
systemctl enable ta-helper.timer

print_success "ta-helper configured and timer enabled (runs every 5 minutes)"
print_success "ta-helper logs available at: /var/log/ta-helper.log"
print_success "View logs: journalctl -u ta-helper.service -f"

# ========== Install ta-jf-proxy for Jellyfin integration ==========
print_status "Installing ta-jf-proxy for Jellyfin integration..."
apt install -y python3-flask

# Copy ta-jf-proxy script from external file
if [ -f "$SCRIPT_DIR/helpers/ta-jf-proxy.py" ]; then
  mkdir -p /opt/ta-helper
  cp "$SCRIPT_DIR/helpers/ta-jf-proxy.py" /opt/ta-helper/ta-jf-proxy.py
  chmod +x /opt/ta-helper/ta-jf-proxy.py
  print_success "ta-jf-proxy copied with debug logging enabled"
else
  print_warning "ta-jf-proxy.py not found in $SCRIPT_DIR/helpers/"
fi

# Create systemd service for ta-jf-proxy
cat > /etc/systemd/system/ta-jf-proxy.service << 'JFEOF'
[Unit]
Description=TubeArchivist Jellyfin Proxy - Name to ID translation + URL rewriting
After=network.target tubearchivist.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ta-helper
ExecStart=/usr/bin/python3 /opt/ta-helper/ta-jf-proxy.py
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/ta-jf-proxy.log
StandardError=append:/var/log/ta-jf-proxy.log

Environment="TA_USERNAME=admin"
Environment="TA_PASSWORD=changeme"

[Install]
WantedBy=multi-user.target
JFEOF

# Create log file
touch /var/log/ta-jf-proxy.log
chmod 666 /var/log/ta-jf-proxy.log

systemctl daemon-reload
systemctl enable ta-jf-proxy.service

print_success "ta-jf-proxy configured (debug logging to /var/log/ta-jf-proxy.log)"
print_success "View logs: tail -f /var/log/ta-jf-proxy.log"

# ========== Enable and start services ==========
print_status "Enabling services..."
systemctl enable redis-server
systemctl enable elasticsearch
systemctl enable tubearchivist
systemctl enable nginx

print_status "Starting services (in order)..."

# Start Redis first
print_status "Starting Redis..."
systemctl start redis-server
sleep 2

# Start Elasticsearch and wait
print_status "Starting Elasticsearch..."
systemctl start elasticsearch
print_status "Waiting for Elasticsearch to initialize (up to 60 seconds)..."
for i in {1..60}; do
  if curl -s http://localhost:9200/_cluster/health > /dev/null 2>&1; then
    print_success "Elasticsearch is ready"
    break
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo -n "."
  fi
  sleep 1
done

# Start TubeArchivist
print_status "Starting TubeArchivist..."
systemctl start tubearchivist
sleep 3

# Start Nginx
systemctl start nginx

# Start ta-jf-proxy
print_status "Starting ta-jf-proxy..."
systemctl start ta-jf-proxy.service
sleep 2

print_success "All services started"

# ========== Create management scripts ==========
print_status "Creating management scripts..."

cat > /usr/local/bin/ta-status << 'STATUSEOF'
#!/bin/bash
echo "=== TubeArchivist Service Status ==="
echo ""
systemctl status redis-server --no-pager 2>&1 | grep "Active:"
systemctl status elasticsearch --no-pager 2>&1 | grep "Active:"
systemctl status tubearchivist --no-pager 2>&1 | grep "Active:"
systemctl status nginx --no-pager 2>&1 | grep "Active:"
STATUSEOF

cat > /usr/local/bin/ta-logs << 'LOGSEOF'
#!/bin/bash
echo "TubeArchivist service logs (Ctrl+C to exit):"
journalctl -u tubearchivist -f
LOGSEOF

cat > /usr/local/bin/ta-restart << 'RESTARTEOF'
#!/bin/bash
echo "Restarting TubeArchivist..."
systemctl restart tubearchivist
echo "Done. Check status with: ta-status"
RESTARTEOF

chmod +x /usr/local/bin/ta-*
print_success "Management scripts created"

# ========== Print final information ==========
echo ""
echo "=========================================="
print_success "TubeArchivist Setup Complete!"
echo "=========================================="
echo ""
echo "📍 Configuration:"
echo "   Application Path: /app"
echo "   Media Storage:    $MEDIA_PATH"
echo "   Cache Path:       /cache"
echo "   Python:           $(python3.12 --version)"
echo ""
echo "🌐 Web Interface (after startup):"
echo "   URL: http://localhost:8000"
echo "   (May take 30-60 seconds to initialize on first start)"
echo ""
echo "🛠️  Services Running:"
echo "   • Redis (localhost:6379)"
echo "   • Elasticsearch (localhost:9200)"
echo "   • TubeArchivist Web (localhost:8000 via Nginx)"
echo "   • Nginx reverse proxy"
echo ""
echo "🎯 Management Commands:"
echo "   ta-status              Check service status"
echo "   ta-logs                View TubeArchivist logs (live)"
echo "   ta-restart             Restart services"
echo ""
echo "📋 Direct Service Commands:"
echo "   systemctl status tubearchivist"
echo "   systemctl stop tubearchivist"
echo "   systemctl start tubearchivist"
echo "   systemctl restart tubearchivist"
echo "   journalctl -u tubearchivist -n 100  (last 100 log lines)"
echo ""
echo "✅ Installation Tips:"
echo "   1. Wait 1-2 minutes for services to fully initialize"
echo "   2. Check status: ta-status"
echo "   3. View logs: ta-logs"
echo "   4. Django migrations run automatically on first start"
echo "   5. On first load, Elasticsearch may take time to index"
echo ""
echo "🎬 Jellyfin Integration (ta-jf-proxy):"
echo "   URL: http://192.168.1.186:8081"
echo "   "
echo "   IMPORTANT: Configure your Jellyfin plugin to use the PROXY, not direct TA:"
echo "   • Plugin Config → API URL: http://192.168.1.186:8081"
echo "   (NOT http://192.168.1.186:8000 or http://192.168.1.186)"
echo "   "
echo "   Features:"
echo "   • Auto-translates human-readable titles to TubeArchivist IDs"
echo "   • Serves images directly (channels, videos, thumbnails)"
echo "   • Returns Jellyfin-compatible metadata fields:"
echo "     - image/thumb (video thumbnails)"
echo "     - primary_image/thumb (channel thumbnails)"
echo "     - backdrop (channel banners)"
echo "     - logo (channel art)"
echo "   • Logs: tail -f /var/log/ta-jf-proxy.log"
echo ""
echo "   Troubleshooting Images Not Showing:"
echo "   1. Verify Jellyfin plugin is configured for: http://192.168.1.186:8081"
echo "   2. Manual test: curl http://192.168.1.186:8081/api/channel/Tomorrowland/"
echo "   3. Check image endpoints work: curl http://192.168.1.186:8081/api/image/channels/xxx_thumb.jpg"
echo "   4. View proxy logs: tail -50 /var/log/ta-jf-proxy.log | grep IMAGE"
echo "   5. Force Jellyfin refresh: Settings → Library → Scan All"
echo ""
