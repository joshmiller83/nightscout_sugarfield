#!/usr/bin/env bash
# Run this script once on the GCP VM to install and configure Nightscout.
# Cloudflare handles HTTPS — no certbot needed.
# Usage: bash setup-vm.sh
set -euo pipefail

DOMAIN="ns-sf.joshnliz.com"
NS_DIR="/opt/nightscout"

echo "=== [1/7] System update ==="
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y git curl nginx

echo "=== [2/7] Install Node.js 22.x ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "=== [3/7] Install PM2 ==="
sudo npm install -g pm2

echo "=== [4/7] Clone Nightscout ==="
sudo mkdir -p "$NS_DIR"
sudo chown "$USER:$USER" "$NS_DIR"
git clone https://github.com/nightscout/cgm-remote-monitor.git "$NS_DIR"
cd "$NS_DIR"
npm ci --omit=optional

echo "=== [5/7] Create log directory ==="
sudo mkdir -p /var/log/nightscout
sudo chown "$USER:$USER" /var/log/nightscout

echo "=== [6/7] Write .env file ==="
echo "Enter your Nightscout environment variables (input is hidden for secrets):"
read -rp  "MONGODB_URI: " MONGODB_URI
read -rsp "API_SECRET (12+ chars, letters+numbers only): " API_SECRET; echo

cat > "$NS_DIR/.env" << ENVEOF
MONGODB_URI=${MONGODB_URI}
API_SECRET=${API_SECRET}
DISPLAY_UNITS=mg/dl
PORT=1337
BASE_URL=https://${DOMAIN}
CUSTOM_TITLE=ns-sf
ENABLE=careportal rawbg iob cob cage sage
AUTH_DEFAULT_ROLES=readable
ALARM_TYPES=simple
ENVEOF
chmod 600 "$NS_DIR/.env"
echo ".env written."

echo "=== [7/7] nginx + PM2 ==="
sudo bash -c 'cat > /etc/nginx/sites-available/nightscout' << 'NGXEOF'
server {
    listen 80;
    server_name ns-sf.joshnliz.com;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 198.41.128.0/17;
    real_ip_header CF-Connecting-IP;
    location / {
        proxy_pass         http://127.0.0.1:1337;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_read_timeout 300s;
    }
}
NGXEOF

sudo ln -sf /etc/nginx/sites-available/nightscout /etc/nginx/sites-enabled/nightscout
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx

cd "$NS_DIR"
pm2 start lib/server/server.js --name nightscout
pm2 startup systemd -u "$USER" --hp "$HOME"
pm2 save

echo ""
echo "=== Done! ==="
echo "Nightscout should be live at https://$DOMAIN"
echo "(Enable Cloudflare proxy / orange cloud, set SSL mode to Flexible)"
echo "Check logs with: pm2 logs nightscout"
