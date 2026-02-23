# Troubleshooting Guide

> Recommended canonical path for manual operations: `~/adguard-stack`.
> Use `/opt/adguard-stack` only if you deployed with `bootstrap-vm.sh`.

## Known Incidents and Fixes

### 1) `failed to bind host port ... :53 ... address already in use`
- **Cause**: Host DNS service (`systemd-resolved`) is already listening on port `53`.
- **Diagnosis**:
  ```bash
  sudo ss -ltnup | grep ':53 '
  ```
- **Fix**:
  ```bash
  sudo mkdir -p /etc/systemd/resolved.conf.d
  cat <<'CFG' | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf
  [Resolve]
  DNSStubListener=no
  DNSStubListenerExtra=
  CFG
  sudo systemctl restart systemd-resolved
  ```

### 2) `no configuration file provided: not found`
- **Cause**: `docker compose` is executed outside the project directory.
- **Fix**:
  ```bash
  cd ~/adguard-stack
  # or, if you used remote bootstrap:
  # cd /opt/adguard-stack
  docker compose ps
  ```

### 3) `.env` permission denied
- **Cause**: `.env` was created by root and cannot be read by the runtime user.
- **Fix**:
  ```bash
  # local stack:
  sudo chown "$USER:$USER" ~/adguard-stack/.env
  chmod 600 ~/adguard-stack/.env
  # remote stack:
  # sudo chown <user>:<group> /opt/adguard-stack/.env
  ```

### 4) Nginx crash loop: missing certificate
- **Cause**: TLS files are missing in `letsencrypt/live/<domain>/`.
- **Fix**:
  - Preferred flow: LE-first (`ALLOW_SELF_SIGNED_FALLBACK=false`), issue certificate before starting `nginx`.
  - Contingency only: allow self-signed fallback with `ALLOW_SELF_SIGNED_FALLBACK=true`.

### 5) `No route to host` when curling public IP from inside the VM
- **Cause**: Cloud networking behavior (hairpin/routing constraints).
- **Fix**: validate locally through `127.0.0.1` and validate externally from another host.

### 6) `/home/.../.env: line ... 03:17:00: command not found`
- **Cause**: `RENEW_TIMER_ONCALENDAR` in `.env` is missing quotes.
- **Fix**:
  ```bash
  sed -i 's/^RENEW_TIMER_ONCALENDAR=.*/RENEW_TIMER_ONCALENDAR="*-*-* 03:17:00"/' .env
  ```

### 7) `502 Bad Gateway` while Nginx is up but AdGuard is unreachable
- **Cause**: path/project mismatch (stack started from one directory, config edited in another) or AdGuard still in first-run state (`/install.html`).
- **Fix**:
  ```bash
  sudo docker inspect adguard --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
  # edit config in the real mounted path and restart from that same project directory
  ```

### 8) Duplicate renewal or unexpected Nginx restarts
- **Cause**: both `systemd` timer and `certbot-renew` container are active.
- **Fix**:
  ```bash
  # recommended mode
  ./scripts/renew-timer-status.sh
  docker compose stop certbot-renew

  # fallback mode (without systemd)
  sudo ./scripts/uninstall-renew-timer.sh
  docker compose up -d certbot-renew
  ```

## Quick Validation Sequence
```bash
cd ~/adguard-stack
sudo docker compose ps
curl -v http://127.0.0.1:80
curl -vk https://127.0.0.1:443
# optional (direct AdGuard diagnostics only):
# curl -v http://127.0.0.1:3000
```

## Port Policy and Base Operations
- For port policy and daily operations, see `docs/runbook.md`.
