#!/usr/bin/env bash
set -euo pipefail

MEM_IP="0.0.0.0"     # we’ll listen on all interfaces on the private network
MEM_PORT="11211"

echo "[memcache.sh] Installing packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y memcached ufw

echo "[memcache.sh] Configure Memcached to listen on ${MEM_IP}:${MEM_PORT} ..."
CONF="/etc/memcached.conf"

# Ensure memcached listens on desired IP (default is 127.0.0.1)
# Ubuntu memcached.conf uses "-l 127.0.0.1" style
if grep -qE '^\s*-l\s+' "$CONF"; then
  sudo sed -i "s/^\s*-l\s\+.*/-l ${MEM_IP}/" "$CONF"
else
  echo "-l ${MEM_IP}" | sudo tee -a "$CONF" >/dev/null
fi

# Make sure port is set (usually is)
if grep -qE '^\s*-p\s+' "$CONF"; then
  sudo sed -i "s/^\s*-p\s\+.*/-p ${MEM_PORT}/" "$CONF"
else
  echo "-p ${MEM_PORT}" | sudo tee -a "$CONF" >/dev/null
fi

echo "[memcache.sh] Restart + enable memcached..."
sudo systemctl enable --now memcached
sudo systemctl restart memcached

echo "[memcache.sh] Open firewall for Memcached (${MEM_PORT}/tcp)..."
sudo ufw allow OpenSSH >/dev/null || true
sudo ufw allow "${MEM_PORT}/tcp" >/dev/null || true
sudo ufw --force enable >/dev/null || true

echo "[memcache.sh] Done ✅"

