#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="notify-hub-vr-forwarder"
INSTALL_BIN="/usr/local/bin/${SERVICE_NAME}"
CONFIG_DIR="/etc/${SERVICE_NAME}"
CONFIG_PATH="${CONFIG_DIR}/config.json"
STATE_DIR="/var/lib/${SERVICE_NAME}"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

echo "Building ${SERVICE_NAME}..."
go build -o "/tmp/${SERVICE_NAME}" "${REPO_ROOT}/cmd/notify-forwarder"

echo "Installing binary to ${INSTALL_BIN}..."
sudo install -m 0755 "/tmp/${SERVICE_NAME}" "${INSTALL_BIN}"

echo "Creating config and state directories..."
sudo install -d -m 0755 "${CONFIG_DIR}"
sudo install -d -m 0755 -o "${RUN_USER}" -g "${RUN_GROUP}" "${STATE_DIR}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  if [[ -f "${REPO_ROOT}/cmd/notify-forwarder/config.json" ]]; then
    echo "Installing local config to ${CONFIG_PATH}..."
    sudo install -m 0644 "${REPO_ROOT}/cmd/notify-forwarder/config.json" "${CONFIG_PATH}"
  else
    echo "Installing example config to ${CONFIG_PATH}..."
    sudo install -m 0644 "${REPO_ROOT}/cmd/notify-forwarder/config.example.json" "${CONFIG_PATH}"
  fi
else
  echo "Keeping existing config at ${CONFIG_PATH}"
fi

UNIT_TMP="$(mktemp)"
cat > "${UNIT_TMP}" <<UNIT
[Unit]
Description=Notify Hub VR Raspberry Pi forwarder
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
ExecStart=${INSTALL_BIN} --config ${CONFIG_PATH}
Restart=on-failure
RestartSec=5
WorkingDirectory=${STATE_DIR}
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=true
ReadWritePaths=${STATE_DIR}

[Install]
WantedBy=multi-user.target
UNIT

echo "Installing systemd unit to ${UNIT_PATH}..."
sudo install -m 0644 "${UNIT_TMP}" "${UNIT_PATH}"
rm -f "${UNIT_TMP}"

echo "Reloading systemd..."
sudo systemctl daemon-reload

cat <<NEXT_STEPS

Installed ${SERVICE_NAME}.

Next steps:
1. Edit the config:
   sudo nano ${CONFIG_PATH}

2. Check the service file:
   systemctl cat ${SERVICE_NAME}

3. Start it now and enable it on boot:
   sudo systemctl enable --now ${SERVICE_NAME}

4. Watch logs:
   journalctl -u ${SERVICE_NAME} -f

NEXT_STEPS
