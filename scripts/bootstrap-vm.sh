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
# Optional env vars:
#   STACK_DIR (default: /opt/adguard-stack)
#   RUN_USER  (default: current sudo user or current user)

: "${REPO_URL:?Set REPO_URL, e.g. https://gitlab.com/ivan-devops1/adguard-stack.git}"
: "${PUBLIC_DOMAIN:?Set PUBLIC_DOMAIN, e.g. myadguardzi.duckdns.org}"
: "${DUCKDNS_SUBDOMAINS:?Set DUCKDNS_SUBDOMAINS}"
: "${DUCKDNS_TOKEN:?Set DUCKDNS_TOKEN}"
: "${ADGUARD_ADMIN_USER:?Set ADGUARD_ADMIN_USER, e.g. admin}"
: "${ADGUARD_ADMIN_PASSWORD:?Set ADGUARD_ADMIN_PASSWORD}"

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

ensure_bootstrap_cert

echo "Validating compose file..."
docker compose config >/dev/null

echo "Pulling and starting services..."
docker compose pull
docker compose up -d

echo "Applying headless AdGuard initial setup..."
ENV_FILE="$STACK_DIR/.env" "$STACK_DIR/scripts/configure-adguard.sh"

echo "Stack status:"
docker compose ps

echo "Done. If docker group was updated, re-login may be required for user: $RUN_USER"
