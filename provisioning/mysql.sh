#!/usr/bin/env bash
set -euo pipefail

APP_DB="accounts"
APP_USER="admin"
APP_PASS="admin123"
REPO_URL="https://github.com/devopshydclub/vprofile-project.git"
REPO_BRANCH="local-setup"

echo "[mysql.sh] Updating + installing packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git zip unzip mariadb-server ufw

echo "[mysql.sh] Start + enable MariaDB..."
sudo systemctl enable --now mariadb

echo "[mysql.sh] Allow remote connections (bind-address=0.0.0.0)..."
CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [[ -f "$CONF" ]]; then
  sudo sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" "$CONF" || true
  grep -q "^bind-address" "$CONF" || echo "bind-address = 0.0.0.0" | sudo tee -a "$CONF" >/dev/null
fi

sudo systemctl restart mariadb

echo "[mysql.sh] Create DB + user + grants..."
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${APP_DB};
CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASS}';
GRANT ALL PRIVILEGES ON ${APP_DB}.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "[mysql.sh] Clone repo + import schema..."
cd /tmp
rm -rf vprofile-project || true
git clone -b "${REPO_BRANCH}" "${REPO_URL}"

DUMP="/tmp/vprofile-project/src/main/resources/db_backup.sql"
if [[ -f "$DUMP" ]]; then
  sudo mysql "${APP_DB}" < "$DUMP"
else
  echo "[mysql.sh] WARNING: db_backup.sql not found at expected path. Skipping import."
fi

echo "[mysql.sh] Open firewall (OpenSSH + 3306)..."
sudo ufw allow OpenSSH >/dev/null || true
sudo ufw allow 3306/tcp >/dev/null || true
sudo ufw --force enable >/dev/null || true

echo "[mysql.sh] Done ✅"

