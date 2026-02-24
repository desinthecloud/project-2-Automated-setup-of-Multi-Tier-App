#!/usr/bin/env bash
set -euo pipefail

TOMCAT_VER="9.0.96"
TOMCAT_USER="tomcat"
APP_REPO="https://github.com/devopshydclub/vprofile-project.git"
APP_BRANCH="local-setup"

echo "[tomcat.sh] Installing packages..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openjdk-11-jdk git unzip curl ufw

echo "[tomcat.sh] Create tomcat user..."
id -u "${TOMCAT_USER}" &>/dev/null || sudo useradd -m -U -d /opt/tomcat -s /bin/false "${TOMCAT_USER}"

echo "[tomcat.sh] Download + install Tomcat ${TOMCAT_VER}..."
cd /tmp
curl -fsSL "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz" -o tomcat.tgz
sudo mkdir -p /opt/tomcat
sudo tar -xzf tomcat.tgz -C /opt/tomcat --strip-components=1

echo "[tomcat.sh] Permissions..."
sudo chown -R ${TOMCAT_USER}:${TOMCAT_USER} /opt/tomcat
sudo chmod +x /opt/tomcat/bin/*.sh

echo "[tomcat.sh] Create systemd service..."
sudo tee /etc/systemd/system/tomcat.service >/dev/null <<'SERVICE'
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.security.egd=file:/dev/./urandom"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE

echo "[tomcat.sh] Enable + start Tomcat..."
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat

echo "[tomcat.sh] Pull app repo..."
cd /tmp
rm -rf vprofile-project || true
git clone -b "${APP_BRANCH}" "${APP_REPO}"

echo "[tomcat.sh] Deploy app (WAR)..."
# Many vprofile repos keep a prebuilt WAR in the repo OR build output.
# We’ll handle both safely.
WAR_CANDIDATE=""
if ls /tmp/vprofile-project/target/*.war >/dev/null 2>&1; then
  WAR_CANDIDATE=$(ls /tmp/vprofile-project/target/*.war | head -n 1)
elif ls /tmp/vprofile-project/*.war >/dev/null 2>&1; then
  WAR_CANDIDATE=$(ls /tmp/vprofile-project/*.war | head -n 1)
elif ls /tmp/vprofile-project/src/main/webapp >/dev/null 2>&1; then
  # If no WAR exists, we’ll deploy as ROOT using the webapp folder (fallback).
  WAR_CANDIDATE=""
fi

sudo rm -rf /opt/tomcat/webapps/ROOT /opt/tomcat/webapps/ROOT.war || true

if [[ -n "${WAR_CANDIDATE}" ]]; then
  echo "[tomcat.sh] Found WAR: ${WAR_CANDIDATE}"
  sudo cp "${WAR_CANDIDATE}" /opt/tomcat/webapps/ROOT.war
else
  echo "[tomcat.sh] No WAR found in repo. Fallback: deploy raw webapp folder."
  sudo cp -r /tmp/vprofile-project/src/main/webapp /opt/tomcat/webapps/ROOT
fi

sudo chown -R ${TOMCAT_USER}:${TOMCAT_USER} /opt/tomcat/webapps

echo "[tomcat.sh] Open firewall for Tomcat (8080/tcp)..."
sudo ufw allow OpenSSH >/dev/null || true
sudo ufw allow 8080/tcp >/dev/null || true
sudo ufw --force enable >/dev/null || true

echo "[tomcat.sh] Restart Tomcat..."
sudo systemctl restart tomcat

echo "[tomcat.sh] Done ✅  (Tomcat: http://<app01-private-ip>:8080)"

