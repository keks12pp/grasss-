#!/bin/bash
# install_grass_vps.sh
# Purpose: bootstrap a VPS to run a "Grass" node/service.
# WARNING: This is a template. You MUST replace placeholders (GRASS_BINARY_URL, GRASS_EXEC, DOCKER_IMAGE, CONFIG) with the real values from the Grass project documentation before running.
# Tested target: Ubuntu 22.04 / Debian 12 (adapt for other distros).

set -euo pipefail

# ---- CONFIGURE THESE BEFORE RUNNING ----
GRASS_BINARY_URL=""   # e.g. https://github.com/grass-foundation/grass/releases/download/vX.Y/grass-linux-amd64.tar.gz
GRASS_EXEC="/usr/local/bin/grass" # path to executable after extraction
GRASS_USER="grassd"
GRASS_HOME="/opt/grass"
GRASS_CONFIG="/etc/grass/config.yaml" # or other config path needed by the software
USE_DOCKER=false      # set true to use Docker approach (requires DOCKER_IMAGE)
DOCKER_IMAGE="grass-foundation/grass:latest"  # if using docker, replace with official image
SERVICE_NAME="grass"

# ----------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# 1) Basic system hardening and prerequisites
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg lsb-release sudo software-properties-common apt-transport-https \
  unzip tar jq ufw

# Create a dedicated user for running the daemon
if ! id -u "$GRASS_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$GRASS_HOME" --shell /bin/false "$GRASS_USER"
  mkdir -p "$GRASS_HOME"
  chown -R "$GRASS_USER":"$GRASS_USER" "$GRASS_HOME"
fi

# Create config directory
mkdir -p "$(dirname "$GRASS_CONFIG")"
chown -R "$GRASS_USER":"$GRASS_USER" "$(dirname "$GRASS_CONFIG")"

# 2) Install Docker (optional path)
if [ "$USE_DOCKER" = true ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$GRASS_USER" || true
  fi
  cat > /etc/systemd/system/${SERVICE_NAME}.service <<'EOF'
[Unit]
Description=Grass (Docker)
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10s
User=root
ExecStart=/usr/bin/docker run --rm --name grass \
  --restart unless-stopped \
  -v /opt/grass:/var/lib/grass \
  -v /etc/grass:/etc/grass:ro \
  -e TZ=UTC \
  -p 3000:3000 \ # <-- replace with real ports the app needs
  DOCKER_IMAGE_PLACEHOLDER

ExecStop=/usr/bin/docker stop grass

[Install]
WantedBy=multi-user.target
EOF
  sed -i "s|DOCKER_IMAGE_PLACEHOLDER|$DOCKER_IMAGE|" /etc/systemd/system/${SERVICE_NAME}.service
  systemctl daemon-reload
  systemctl enable --now ${SERVICE_NAME}.service || true
  echo "Docker service created as ${SERVICE_NAME}. Check: systemctl status ${SERVICE_NAME}"
  exit 0
fi

# 3) Install from binary / tarball (non-Docker path)
if [ -n "$GRASS_BINARY_URL" ]; then
  tmpdir=$(mktemp -d)
  echo "Downloading Grass binary from $GRASS_BINARY_URL"
  curl -fsSL "$GRASS_BINARY_URL" -o "$tmpdir/grass.tar.gz"
  tar -xz -C "$tmpdir" -f "$tmpdir/grass.tar.gz"
  # Attempt to find executable
  exec_candidate=$(find "$tmpdir" -maxdepth 2 -type f -perm /111 -name 'grass*' | head -n1 || true)
  if [ -z "$exec_candidate" ]; then
    echo "No executable found in the archive. Please extract manually and set GRASS_EXEC to its path. Exiting."
    ls -l "$tmpdir"
    exit 1
  fi
  install -m 0755 "$exec_candidate" "$GRASS_EXEC"
  chown "$GRASS_USER":"$GRASS_USER" "$GRASS_EXEC"
  rm -rf "$tmpdir"
else
  echo "No GRASS_BINARY_URL set and USE_DOCKER=false. Provide a binary URL or set USE_DOCKER=true. Exiting."
  exit 1
fi

# 4) Create a systemd service that runs the grass executable
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Grass node/service
After=network.target

[Service]
Type=simple
User=$GRASS_USER
Group=$GRASS_USER
WorkingDirectory=$GRASS_HOME
ExecStart=$GRASS_EXEC run --config $GRASS_CONFIG
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.service

# 5) Firewall (simple UFW) - adjust ports as needed. Do not open ports you don't need.
ufw --force enable
# Example: allow SSH and common ports. Replace 3000 with actual grass ports.
ufw allow OpenSSH
ufw allow 3000/tcp

# 6) Final messages and checks
echo "Installation complete. Check status with: systemctl status ${SERVICE_NAME}"
echo "Journal logs: journalctl -u ${SERVICE_NAME} -f"

# Print locations to edit
echo "Config file: $GRASS_CONFIG"
echo "Executable: $GRASS_EXEC"

echo "If the real start command differs, edit /etc/systemd/system/${SERVICE_NAME}.service and run: systemctl daemon-reload && systemctl restart ${SERVICE_NAME}"

# End of script