#!/usr/bin/env bash
# Completes Nightscout setup after the initial install.
# Run via: gcloud compute ssh ... --command="bash /tmp/complete-setup.sh"
set -euo pipefail

NS_DIR="/opt/nightscout"
DOMAIN="ns-sf.joshnliz.com"

echo "=== [1/5] Add 2GB swap (needed for webpack on e2-micro) ==="
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo "Swap added."
else
  echo "Swap already present."
fi
free -h

echo "=== [2/5] Re-run npm ci with swap available ==="
cd "$NS_DIR"
npm ci --omit=optional

echo "=== [3/5] Write .env ==="
# Env vars passed in via environment
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

echo "=== [4/5] Configure nginx ==="
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
sudo nginx -t && sudo systemctl reload nginx
echo "nginx configured."

echo "=== [5/5] Start Nightscout via PM2 ==="
sudo mkdir -p /var/log/nightscout
sudo chown "$USER:$USER" /var/log/nightscout
cd "$NS_DIR"
pm2 delete nightscout 2>/dev/null || true
pm2 start lib/server/server.js --name nightscout
pm2 startup systemd -u "$USER" --hp "$HOME" | tail -1 | sudo bash || true
pm2 save

echo ""
echo "=== Setup complete! ==="
pm2 status
echo ""
echo "Nightscout should be live at https://$DOMAIN"
echo "Check logs: pm2 logs nightscout --lines 20"
