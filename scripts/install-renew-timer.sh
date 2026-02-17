#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
STACK_DIR="${STACK_DIR:-$ROOT_DIR}"
RUN_USER="${RUN_USER:-${SUDO_USER:-$USER}}"
RENEW_TIMER_ONCALENDAR="${RENEW_TIMER_ONCALENDAR:-*-*-* 03:17:00}"
RENEW_TIMER_RANDOMIZED_DELAY="${RENEW_TIMER_RANDOMIZED_DELAY:-45m}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is not available; skipping timer installation." >&2
  exit 0
fi

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Cannot read env file: $ENV_FILE" >&2
  exit 1
fi

service_name="adguard-renew"
service_path="/etc/systemd/system/${service_name}.service"
timer_path="/etc/systemd/system/${service_name}.timer"

echo "Installing ${service_name}.service and ${service_name}.timer"
cat > "$service_path" <<SERVICE
[Unit]
Description=Renew Let's Encrypt certs for AdGuard stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=${STACK_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/bin/bash ${STACK_DIR}/scripts/renew-letsencrypt.sh
User=${RUN_USER}
SERVICE

cat > "$timer_path" <<TIMER
[Unit]
Description=Daily Let's Encrypt renewal for AdGuard stack

[Timer]
OnCalendar=${RENEW_TIMER_ONCALENDAR}
RandomizedDelaySec=${RENEW_TIMER_RANDOMIZED_DELAY}
Persistent=true

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now "${service_name}.timer"

echo "Timer installed. Next runs:"
systemctl list-timers --all | grep "${service_name}" || true
