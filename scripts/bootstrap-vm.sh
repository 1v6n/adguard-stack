#!/usr/bin/env bash
set -euo pipefail

# Portable Linux bootstrap for this Docker Compose stack.
# Required env vars:
#   REPO_URL
#   PUBLIC_DOMAIN
#   DUCKDNS_SUBDOMAINS
#   DUCKDNS_TOKEN
#   ADGUARD_ADMIN_USER
#   ADGUARD_ADMIN_PASSWORD
#   LETSENCRYPT_EMAIL
# Optional env vars:
#   STACK_DIR (default: /opt/adguard-stack)
#   RUN_USER  (default: current sudo user or current user)
#   LETSENCRYPT_STAGING (default: false)
#   ALLOW_SELF_SIGNED_FALLBACK (default: false)
#   INSTALL_RENEW_TIMER (default: true)
#   RENEW_TIMER_ONCALENDAR (default: *-*-* 03:17:00)
#   RENEW_TIMER_RANDOMIZED_DELAY (default: 45m)

: "${REPO_URL:?Set REPO_URL, e.g. https://gitlab.com/ivan-devops1/adguard-stack.git}"
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

STACK_DIR="${STACK_DIR:-/opt/adguard-stack}"
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
require_cmd git
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

if [[ -d "$STACK_DIR/.git" ]]; then
  echo "Updating repository at $STACK_DIR"
  git -C "$STACK_DIR" pull --ff-only
else
  echo "Cloning repository into $STACK_DIR"
  git clone "$REPO_URL" "$STACK_DIR"
fi

cat > "$STACK_DIR/.env" <<ENVFILE
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
chmod 600 "$STACK_DIR/.env"

if id "$RUN_USER" >/dev/null 2>&1; then
  chown -R "$RUN_USER:$RUN_USER" "$STACK_DIR"
fi

cd "$STACK_DIR"

echo "Running preflight checks..."
ENV_FILE="$STACK_DIR/.env" STRICT_CERT=false "$STACK_DIR/scripts/preflight.sh"

ensure_bootstrap_cert() {
  local cert_dir="$STACK_DIR/letsencrypt/live/$PUBLIC_DOMAIN"
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
ENV_FILE="$STACK_DIR/.env" "$STACK_DIR/scripts/configure-adguard.sh"

echo "Issuing Let's Encrypt certificate before exposing nginx..."
if ENV_FILE="$STACK_DIR/.env" "$STACK_DIR/scripts/issue-letsencrypt.sh"; then
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
  ENV_FILE="$STACK_DIR/.env" \
  STACK_DIR="$STACK_DIR" \
  RUN_USER="$RUN_USER" \
  RENEW_TIMER_ONCALENDAR="$RENEW_TIMER_ONCALENDAR" \
  RENEW_TIMER_RANDOMIZED_DELAY="$RENEW_TIMER_RANDOMIZED_DELAY" \
  "$STACK_DIR/scripts/install-renew-timer.sh"
fi

echo "Stack status:"
docker compose ps

echo "Done. If docker group was updated, re-login may be required for user: $RUN_USER"
