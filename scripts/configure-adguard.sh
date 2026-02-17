#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ADGUARD_SETUP_URL="${ADGUARD_SETUP_URL:-http://127.0.0.1:3000}"
ADGUARD_WEB_IP="${ADGUARD_WEB_IP:-0.0.0.0}"
ADGUARD_WEB_PORT="${ADGUARD_WEB_PORT:-80}"
ADGUARD_DNS_IP="${ADGUARD_DNS_IP:-0.0.0.0}"
ADGUARD_DNS_PORT="${ADGUARD_DNS_PORT:-53}"
SETUP_TIMEOUT_SECONDS="${SETUP_TIMEOUT_SECONDS:-90}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Cannot read env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${ADGUARD_ADMIN_USER:?Missing ADGUARD_ADMIN_USER in .env}"
: "${ADGUARD_ADMIN_PASSWORD:?Missing ADGUARD_ADMIN_PASSWORD in .env}"

if [[ -s "$ROOT_DIR/config/adguard/conf/AdGuardHome.yaml" ]]; then
  echo "AdGuard appears already configured (existing config file found). Skipping."
  exit 0
fi

wait_for_setup_api() {
  local elapsed=0
  while (( elapsed < SETUP_TIMEOUT_SECONDS )); do
    if curl -fsS "$ADGUARD_SETUP_URL/install.html" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

if ! wait_for_setup_api; then
  echo "AdGuard setup endpoint did not become ready within ${SETUP_TIMEOUT_SECONDS}s" >&2
  exit 1
fi

payload="$(
  cat <<JSON
{"web":{"ip":"$ADGUARD_WEB_IP","port":$ADGUARD_WEB_PORT},"dns":{"ip":"$ADGUARD_DNS_IP","port":$ADGUARD_DNS_PORT},"username":"$ADGUARD_ADMIN_USER","password":"$ADGUARD_ADMIN_PASSWORD"}
JSON
)"

response_file="$(mktemp)"
http_code="$(curl -sS -o "$response_file" -w "%{http_code}" \
  -X POST "$ADGUARD_SETUP_URL/control/install/configure" \
  -H "Content-Type: application/json" \
  --data "$payload" || true)"
response_body="$(cat "$response_file")"
rm -f "$response_file"

if [[ "$http_code" == "200" ]]; then
  echo "AdGuard initial configuration applied successfully."
  exit 0
fi

if grep -qi "already configured" <<<"$response_body"; then
  echo "AdGuard already configured. Continuing."
  exit 0
fi

echo "Failed to configure AdGuard automatically. HTTP status: $http_code" >&2
echo "Response: $response_body" >&2
exit 1
