#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${PUBLIC_DOMAIN:?Set PUBLIC_DOMAIN, e.g. myadguardzi.duckdns.org}"
: "${DUCKDNS_SUBDOMAINS:?Set DUCKDNS_SUBDOMAINS}"
: "${DUCKDNS_TOKEN:?Set DUCKDNS_TOKEN}"
: "${ADGUARD_ADMIN_USER:?Set ADGUARD_ADMIN_USER, e.g. admin}"
: "${ADGUARD_ADMIN_PASSWORD:?Set ADGUARD_ADMIN_PASSWORD}"
: "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL, e.g. you@example.com}"

LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
ALLOW_SELF_SIGNED_FALLBACK="${ALLOW_SELF_SIGNED_FALLBACK:-false}"
INSTALL_RENEW_TIMER="${INSTALL_RENEW_TIMER:-true}"
RENEW_TIMER_ONCALENDAR="${RENEW_TIMER_ONCALENDAR:-*-*-* 03:17:00}"
RENEW_TIMER_RANDOMIZED_DELAY="${RENEW_TIMER_RANDOMIZED_DELAY:-45m}"

RUN_USER="${RUN_USER:-${SUDO_USER:-$USER}}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

require_cmd() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd openssl

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker Engine + Compose plugin..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
fi

systemctl enable --now docker

if id "$RUN_USER" >/dev/null 2>&1; then
  usermod -aG docker "$RUN_USER" || true
fi

cat > "$ROOT_DIR/.env" <<ENVFILE
PUBLIC_DOMAIN=${PUBLIC_DOMAIN}
DUCKDNS_SUBDOMAINS=${DUCKDNS_SUBDOMAINS}
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
ADGUARD_ADMIN_USER=${ADGUARD_ADMIN_USER}
ADGUARD_ADMIN_PASSWORD=${ADGUARD_ADMIN_PASSWORD}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
LETSENCRYPT_STAGING=${LETSENCRYPT_STAGING}
ALLOW_SELF_SIGNED_FALLBACK=${ALLOW_SELF_SIGNED_FALLBACK}
INSTALL_RENEW_TIMER=${INSTALL_RENEW_TIMER}
RENEW_TIMER_ONCALENDAR=${RENEW_TIMER_ONCALENDAR}
RENEW_TIMER_RANDOMIZED_DELAY=${RENEW_TIMER_RANDOMIZED_DELAY}
ENVFILE
chmod 600 "$ROOT_DIR/.env"

if id "$RUN_USER" >/dev/null 2>&1; then
  chown -R "$RUN_USER:$RUN_USER" "$ROOT_DIR"
fi

echo "Running preflight checks..."
ENV_FILE="$ROOT_DIR/.env" STRICT_CERT=false "$ROOT_DIR/scripts/preflight.sh"

ensure_bootstrap_cert() {
  local cert_dir="$ROOT_DIR/letsencrypt/live/$PUBLIC_DOMAIN"
  local fullchain="$cert_dir/fullchain.pem"
  local privkey="$cert_dir/privkey.pem"

  if [[ -f "$fullchain" && -f "$privkey" ]]; then
    return
  fi

  echo "Creating temporary self-signed certificate for $PUBLIC_DOMAIN"
  mkdir -p "$cert_dir"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$privkey" \
    -out "$fullchain" \
    -subj "/CN=$PUBLIC_DOMAIN"
}

echo "Validating compose file..."
docker compose config >/dev/null

echo "Pulling images..."
docker compose pull
echo "Starting core services (without nginx)..."
docker compose up -d adguard duckdns certbot-renew

echo "Applying headless AdGuard initial setup..."
ENV_FILE="$ROOT_DIR/.env" "$ROOT_DIR/scripts/configure-adguard.sh"

echo "Issuing Let's Encrypt certificate before exposing nginx..."
if ENV_FILE="$ROOT_DIR/.env" "$ROOT_DIR/scripts/issue-letsencrypt.sh"; then
  echo "Let's Encrypt certificate issued successfully."
elif [[ "$ALLOW_SELF_SIGNED_FALLBACK" == "true" ]]; then
  echo "Let's Encrypt issuance failed; using self-signed fallback because ALLOW_SELF_SIGNED_FALLBACK=true."
  ensure_bootstrap_cert
else
  echo "Let's Encrypt issuance failed and fallback is disabled. Aborting before nginx startup." >&2
  exit 1
fi

echo "Starting nginx..."
docker compose up -d nginx

if [[ "$INSTALL_RENEW_TIMER" == "true" ]]; then
  echo "Installing automatic Let's Encrypt renewal timer..."
  ENV_FILE="$ROOT_DIR/.env" \
  STACK_DIR="$ROOT_DIR" \
  RUN_USER="$RUN_USER" \
  RENEW_TIMER_ONCALENDAR="$RENEW_TIMER_ONCALENDAR" \
  RENEW_TIMER_RANDOMIZED_DELAY="$RENEW_TIMER_RANDOMIZED_DELAY" \
  "$ROOT_DIR/scripts/install-renew-timer.sh"
fi

echo "Stack status:"
docker compose ps

echo "Done. If docker group was updated, re-login may be required for user: $RUN_USER"
