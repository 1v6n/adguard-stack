#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
STRICT_CERT="${STRICT_CERT:-false}"

errors=0
warnings=0

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; warnings=$((warnings + 1)); }
log_error() { echo "[ERROR] $*"; errors=$((errors + 1)); }

require_cmd() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_error "Missing required command: $command_name"
  fi
}

load_env() {
  if [[ ! -r "$ENV_FILE" ]]; then
    log_error "Cannot read env file: $ENV_FILE"
    return
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log_error "Missing required variable: $var_name"
  fi
}

check_port_conflicts() {
  local tcp_ports=(53 80 443 853 3000)
  local udp_ports=(53 853)
  local ss_tcp_probe
  local ss_udp_probe

  if ! ss_tcp_probe="$(ss -ltnp 2>&1 || true)"; then
    ss_tcp_probe=""
  fi
  if ! ss_udp_probe="$(ss -lunp 2>&1 || true)"; then
    ss_udp_probe=""
  fi

  if grep -qi "Cannot open netlink socket" <<<"$ss_tcp_probe$ss_udp_probe"; then
    log_warn "Cannot inspect open ports in this environment (netlink not permitted); skipping port conflict checks"
    return
  fi

  for port in "${tcp_ports[@]}"; do
    local listeners
    listeners="$(ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1' || true)"
    if [[ -n "$listeners" ]] && ! grep -q "docker-proxy" <<<"$listeners"; then
      log_error "TCP port $port is already in use by a non-docker process"
      echo "$listeners"
    fi
  done

  for port in "${udp_ports[@]}"; do
    local listeners
    listeners="$(ss -lunp "sport = :$port" 2>/dev/null | awk 'NR>1' || true)"
    if [[ -n "$listeners" ]] && ! grep -q "docker-proxy" <<<"$listeners"; then
      log_error "UDP port $port is already in use by a non-docker process"
      echo "$listeners"
    fi
  done
}

check_cert_files() {
  local cert_dir="${ROOT_DIR}/letsencrypt/live/${PUBLIC_DOMAIN:-}"
  local fullchain="${cert_dir}/fullchain.pem"
  local privkey="${cert_dir}/privkey.pem"

  if [[ -z "${PUBLIC_DOMAIN:-}" ]]; then
    return
  fi

  if [[ ! -f "$fullchain" || ! -f "$privkey" ]]; then
    if [[ "$STRICT_CERT" == "true" ]]; then
      log_error "Certificate files missing for PUBLIC_DOMAIN=${PUBLIC_DOMAIN}"
    else
      log_warn "Certificate files missing for PUBLIC_DOMAIN=${PUBLIC_DOMAIN} (bootstrap can generate a temporary self-signed cert)"
    fi
  fi
}

log_info "Running preflight checks in $ROOT_DIR"
require_cmd docker
require_cmd ss

if docker compose version >/dev/null 2>&1; then
  log_info "docker compose plugin detected"
else
  log_error "docker compose plugin is not available"
fi

load_env
require_env PUBLIC_DOMAIN
require_env DUCKDNS_SUBDOMAINS
require_env DUCKDNS_TOKEN
require_env ADGUARD_ADMIN_USER
require_env ADGUARD_ADMIN_PASSWORD
check_port_conflicts
check_cert_files

if [[ "$errors" -gt 0 ]]; then
  echo "Preflight failed with ${errors} error(s) and ${warnings} warning(s)."
  exit 1
fi

echo "Preflight passed with ${warnings} warning(s)."
