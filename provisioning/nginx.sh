#!/usr/bin/env bash
set -euo pipefail

APP_IP="192.168.56.12"
APP_PORT="8090"

echo "[nginx.sh] Installing nginx..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx ufw

echo "[nginx.sh] Configure reverse proxy to ${APP_IP}:${APP_PORT} ..."
sudo tee /etc/nginx/sites-available/vprofile >/dev/null <<EOF
server {
  listen 80;
  server_name _;

  access_log /var/log/nginx/vprofile_access.log;
  error_log  /var/log/nginx/vprofile_error.log;

  location / {
    proxy_pass http://${APP_IP}:${APP_PORT};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default || true
sudo ln -sf /etc/nginx/sites-available/vprofile /etc/nginx/sites-enabled/vprofile

echo "[nginx.sh] Test + restart nginx..."
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl restart nginx

echo "[nginx.sh] Open firewall for HTTP..."
sudo ufw allow OpenSSH >/dev/null || true
sudo ufw allow 80/tcp >/dev/null || true
sudo ufw --force enable >/dev/null || true

echo "[nginx.sh] Done ✅  (Try: http://192.168.56.11/)"

