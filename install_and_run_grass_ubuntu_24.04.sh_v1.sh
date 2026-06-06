#!/usr/bin/env bash
# install_and_run_grass_ubuntu_24.04.sh
# Purpose: Bootstrap an Ubuntu 24.04 LTS VPS to run the "Grass" service.
# Usage:
# 1) Edit the variables in the CONFIG section below (DOCKER_IMAGE or GRASS_BINARY_URL, GRASS_EXEC/ExecStart if needed).
# 2) Run as root: sudo bash install_and_run_grass_ubuntu_24.04.sh
#
# NOTES:
# - This is a safe template. Do NOT run without replacing placeholders and reviewing the start command.
# - If you choose Docker (USE_DOCKER=true) the script will install Docker and create a systemd unit that runs the image.
# - If you choose binary, provide GRASS_BINARY_URL which should point to a signed release tar.gz/zip that contains the executable.

set -euo pipefail

# ------------------ CONFIGURE BEFORE RUNNING ------------------
GRASS_USER="grassd"
GRASS_HOME="/opt/grass"
GRASS_CONFIG="/etc/grass/config.yaml"   # edit to match the real config path if different
SERVICE_NAME="grass"

# Choose one of the two: set USE_DOCKER=true to run via Docker, or leave false and set GRASS_BINARY_URL
USE_DOCKER=false
DOCKER_IMAGE="grass-foundation/grass:latest"  # replace with official image if docs specify

# If not using Docker, set this to a release tarball URL (tar.gz or zip) that contains the grass executable
GRASS_BINARY_URL=""  # REQUIRED if USE_DOCKER=false. Provide a signed release tarball URL (tar.gz or zip).
# Example (uncomment and set):
# GRASS_BINARY_URL="https://github.com/grass-foundation/grass/releases/download/vX.Y/grass-linux-amd64.tar.gz"
# Security: if the project publishes checksum files (SHA256SUMS) and signatures (.asc), download and verify them
# before running this script. Example verification (manual steps):
# curl -fsSL -o SHA256SUMS https://.../SHA256SUMS
# curl -fsSL -o SHA256SUMS.asc https://.../SHA256SUMS.asc
# gpg --verify SHA256SUMS.asc SHA256SUMS
# sha256sum -c SHA256SUMS
# Do NOT run this script with an unsigned/unverified binary unless you trust the source.
GRASS_EXEC="/usr/local/bin/grass"  # where the executable will be installed

# Ports (adjust according to the Grass docs)
# Example placeholder: 3000
GRASS_PORTS=(3000)

# --------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo"
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release software-properties-common tar unzip jq ufw

# Create system user and directories
if ! id -u "$GRASS_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$GRASS_HOME" --shell /usr/sbin/nologin "$GRASS_USER"
fi
mkdir -p "$GRASS_HOME"
chown -R "$GRASS_USER":"$GRASS_USER" "$GRASS_HOME"
mkdir -p "$(dirname "$GRASS_CONFIG")"
chown -R "$GRASS_USER":"$GRASS_USER" "$(dirname "$GRASS_CONFIG")"

# Helper: enable and start a systemd service file path
enable_start_service() {
  local svc_path="$1"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME".service || true
}

if [ "$USE_DOCKER" = true ]; then
  # Install Docker (official repository recommended)
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker engine..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io
    # Add grass user to docker group so it can run containers if needed
    usermod -aG docker "$GRASS_USER" || true
  fi

  # Create systemd service that runs the container (simple wrapper)
  cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Grass (Docker)
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10s
User=root
# Build ExecStart with all required flags and port mappings in a single line.
# The command substitution below expands at script runtime to add "-p X:X" for each port in GRASS_PORTS.
ExecStart=/usr/bin/docker run --name ${SERVICE_NAME} --rm --restart unless-stopped -v ${GRASS_HOME}:/var/lib/grass -v $(dirname ${GRASS_CONFIG}):/etc/grass:ro -e TZ=UTC$(for p in "${GRASS_PORTS[@]}"; do printf " -p %s:%s" "$p" "$p"; done) ${DOCKER_IMAGE}
ExecStop=/usr/bin/docker stop ${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  enable_start_service "/etc/systemd/system/${SERVICE_NAME}.service"
  echo "Docker-based service created: systemctl status ${SERVICE_NAME}" 
  exit 0
fi

# Non-Docker path: download and install binary
if [ -z "$GRASS_BINARY_URL" ]; then
  echo "ERROR: GRASS_BINARY_URL is empty and USE_DOCKER=false. Set one and re-run."
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading Grass binary from: $GRASS_BINARY_URL"
if ! curl -fsSL "$GRASS_BINARY_URL" -o "$tmpdir/grass_release"; then
  echo "Download failed. Check the URL. Exiting."
  exit 1
fi

# Try to extract based on file type
file "$tmpdir/grass_release" | grep -q 'gzip compressed' && {
  tar -xzf "$tmpdir/grass_release" -C "$tmpdir"
} || file "$tmpdir/grass_release" | grep -q 'Zip archive' && {
  unzip -q "$tmpdir/grass_release" -d "$tmpdir"
} || {
  # If it's already an executable binary
  chmod +x "$tmpdir/grass_release"
  mv "$tmpdir/grass_release" "$tmpdir/grass_executable"
}

# Attempt to find an executable named 'grass' or starting with 'grass'
exec_candidate=$(find "$tmpdir" -type f -perm /111 -iname 'grass*' | head -n1 || true)
if [ -z "$exec_candidate" ]; then
  echo "No executable found in the archive. Listing contents:" 
  ls -la "$tmpdir"
  echo "You must extract manually and set GRASS_EXEC to the real path. Exiting."
  exit 1
fi

install -m 0755 "$exec_candidate" "$GRASS_EXEC"
chown "$GRASS_USER":"$GRASS_USER" "$GRASS_EXEC"

# Create simple systemd unit. IMPORTANT: adjust ExecStart if the real command differs (e.g. 'grass start' or 'grass run')
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

enable_start_service "/etc/systemd/system/${SERVICE_NAME}.service"

# Firewall: enable UFW and open SSH + required Grass ports
ufw --force enable
ufw allow OpenSSH
for p in "${GRASS_PORTS[@]}"; do
  ufw allow ${p}/tcp
done

# Final messages
cat <<EOF
Installation finished.
 - Service: systemctl status ${SERVICE_NAME}
 - Logs: journalctl -u ${SERVICE_NAME} -f
 - Config file (edit as needed): ${GRASS_CONFIG}
 - Executable: ${GRASS_EXEC}

IMPORTANT:
 - Verify ExecStart in /etc/systemd/system/${SERVICE_NAME}.service matches the real start command from the Grass docs.
 - If the service fails to start, run: journalctl -u ${SERVICE_NAME} --no-pager -n 200
 - If running a node that needs keys or wallet file, place them securely in ${GRASS_CONFIG} or ${GRASS_HOME} and ensure permissions are owned by ${GRASS_USER}.

If you provide the DOCKER_IMAGE or GRASS_BINARY_URL and the exact start command from the docs, I will update the script and the systemd unit to match precisely.
EOF
