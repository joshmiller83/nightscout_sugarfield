#!/usr/bin/env bash
# Run this script once on the GCP VM to install and configure Nightscout.
# Usage: bash setup-vm.sh
set -euo pipefail

DOMAIN="ns-sf.joshnliz.com"
NS_DIR="/opt/nightscout"
CF_CREDS="/root/.secrets/cloudflare.ini"

echo "=== [1/8] System update ==="
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y git curl nginx certbot python3-certbot-dns-cloudflare

echo "=== [2/8] Install Node.js 22.x ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "=== [3/8] Install PM2 ==="
sudo npm install -g pm2

echo "=== [4/8] Clone Nightscout ==="
sudo mkdir -p "$NS_DIR"
sudo chown "$USER:$USER" "$NS_DIR"
git clone https://github.com/nightscout/cgm-remote-monitor.git "$NS_DIR"
cd "$NS_DIR"
npm ci --omit=optional

echo "=== [5/8] Create log directory ==="
sudo mkdir -p /var/log/nightscout
sudo chown "$USER:$USER" /var/log/nightscout

echo "=== [6/8] Write .env file ==="
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

echo "=== [7/8] Certbot via Cloudflare DNS ==="
echo "You need a Cloudflare API token with Zone:DNS:Edit for joshnliz.com."
echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
read -rsp "Paste your Cloudflare API token: " CF_TOKEN; echo

sudo mkdir -p "$(dirname $CF_CREDS)"
sudo bash -c "cat > $CF_CREDS << EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF"
sudo chmod 600 "$CF_CREDS"

sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CF_CREDS" \
  --dns-cloudflare-propagation-seconds 30 \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  --email mill4433.purdue@gmail.com

echo "=== [8/8] nginx + PM2 ==="
sudo bash -c 'cat > /etc/nginx/sites-available/nightscout' << 'NGXEOF'
server {
    listen 80;
    server_name ns-sf.joshnliz.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ns-sf.joshnliz.com;
    ssl_certificate     /etc/letsencrypt/live/ns-sf.joshnliz.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ns-sf.joshnliz.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;
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
        proxy_set_header   X-Forwarded-Proto $scheme;
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
echo "Nightscout is live at https://$DOMAIN"
echo "Check logs with: pm2 logs nightscout"
