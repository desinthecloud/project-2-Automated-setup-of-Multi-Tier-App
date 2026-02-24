#!/usr/bin/env bash
set -euo pipefail

RABBIT_USER="test"
RABBIT_PASS="test"
RABBIT_PORT="5672"
MGMT_PORT="15672"

echo "[rabbitmq.sh] Installing packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y rabbitmq-server ufw

echo "[rabbitmq.sh] Enable + start rabbitmq..."
sudo systemctl enable --now rabbitmq-server

echo "[rabbitmq.sh] Enable RabbitMQ management plugin..."
sudo rabbitmq-plugins enable rabbitmq_management >/dev/null

echo "[rabbitmq.sh] Create app user (safe to re-run)..."
# Add user (ignore error if it already exists)
sudo rabbitmqctl add_user "${RABBIT_USER}" "${RABBIT_PASS}" 2>/dev/null || true
sudo rabbitmqctl set_user_tags "${RABBIT_USER}" administrator >/dev/null
sudo rabbitmqctl set_permissions -p / "${RABBIT_USER}" ".*" ".*" ".*" >/dev/null

echo "[rabbitmq.sh] Open firewall ports (SSH, 5672, 15672)..."
sudo ufw allow OpenSSH >/dev/null || true
sudo ufw allow "${RABBIT_PORT}/tcp" >/dev/null || true
sudo ufw allow "${MGMT_PORT}/tcp" >/dev/null || true
sudo ufw --force enable >/dev/null || true

echo "[rabbitmq.sh] Restart rabbitmq..."
sudo systemctl restart rabbitmq-server

echo "[rabbitmq.sh] Done ✅"
echo "[rabbitmq.sh] Mgmt UI: http://<rmq01-private-ip>:15672  (user: ${RABBIT_USER})"

