# AdGuard Stack

Container-based infrastructure for secure DNS using AdGuard Home, TLS proxying with Nginx, dynamic DNS updates via DuckDNS, and automated certificate lifecycle management.

## Structure
- `docker-compose.yml`: service and network definitions.
- `nginx_conf/default.conf`: HTTPS reverse proxy and DoH endpoint (`/dns-query`).
- `config/adguard/`: persistent AdGuard configuration and data.
- `letsencrypt/`: certificate files and renewal state.
- `scripts/`: operational automation (`up.sh`, `logs.sh`, `check.sh`, `backup.sh`, `preflight.sh`, `configure-adguard.sh`, `issue-letsencrypt.sh`, `renew-letsencrypt.sh`, `install-renew-timer.sh`, `uninstall-renew-timer.sh`, `renew-timer-status.sh`, `bootstrap-vm.sh`, `bootstrap-local.sh`).
- `docs/runbook.md`: daily operations and recovery procedures.
- `docs/troubleshooting.md`: common incidents and step-by-step fixes.
- `.gitlab-ci.yml`: CI checks for Compose and Nginx.

## Requirements
- Docker Engine + Docker Compose plugin.
- Default runtime ports: `53`, `80`, `443`, `853`.
- Port `3000` is bound to loopback only (`127.0.0.1`) for AdGuard diagnostics/recovery.
- A DuckDNS domain with a valid token.

## Environment Setup
```bash
cp .env.example .env
```
- Set `PUBLIC_DOMAIN`, `DUCKDNS_SUBDOMAINS`, `DUCKDNS_TOKEN`, `ADGUARD_ADMIN_USER`, `ADGUARD_ADMIN_PASSWORD`, `LETSENCRYPT_EMAIL`, `LETSENCRYPT_STAGING`, `ALLOW_SELF_SIGNED_FALLBACK`, `INSTALL_RENEW_TIMER`, `RENEW_TIMER_ONCALENDAR`, and `RENEW_TIMER_RANDOMIZED_DELAY` in `.env`.

## First Local Deployment (Recommended)
Run inside the repository:
```bash
sudo PUBLIC_DOMAIN="your-subdomain.duckdns.org" \
DUCKDNS_SUBDOMAINS="your-subdomain" \
DUCKDNS_TOKEN="YOUR_TOKEN" \
ADGUARD_ADMIN_USER="admin" \
ADGUARD_ADMIN_PASSWORD="CHANGE_PASSWORD" \
LETSENCRYPT_EMAIL="you@example.com" \
LETSENCRYPT_STAGING="false" \
ALLOW_SELF_SIGNED_FALLBACK="false" \
INSTALL_RENEW_TIMER="true" \
bash scripts/bootstrap-local.sh
```

If you have not cloned the repository yet:
```bash
git clone https://github.com/1v6n/adguard-stack.git
cd adguard-stack
```

## Remote Bootstrap (clone/update in `/opt/adguard-stack`)
Use this when running from any location and you want the script to manage clone/pull:
```bash
sudo REPO_URL="https://github.com/1v6n/adguard-stack.git" \
PUBLIC_DOMAIN="myadguardzi.duckdns.org" \
DUCKDNS_SUBDOMAINS="myadguardzi" \
DUCKDNS_TOKEN="YOUR_TOKEN" \
ADGUARD_ADMIN_USER="admin" \
ADGUARD_ADMIN_PASSWORD="CHANGE_PASSWORD" \
LETSENCRYPT_EMAIL="you@example.com" \
LETSENCRYPT_STAGING="false" \
ALLOW_SELF_SIGNED_FALLBACK="false" \
INSTALL_RENEW_TIMER="true" \
bash /path/to/adguard-stack/scripts/bootstrap-vm.sh
```
Bootstrap runs `scripts/preflight.sh`, starts core services without `nginx`, applies headless AdGuard setup, issues Let's Encrypt certificates, then starts `nginx`. Renewal mode is selected automatically: `systemd` timer when `INSTALL_RENEW_TIMER=true`, or `certbot-renew` container when `INSTALL_RENEW_TIMER=false`. If issuance fails, bootstrap aborts unless `ALLOW_SELF_SIGNED_FALLBACK=true`.

## Daily Operation (initialized stack)
```bash
./scripts/up.sh
```

## Post-Bootstrap Checklist
- `sudo docker compose ps`
- `./scripts/renew-timer-status.sh`
- `curl -vk https://<PUBLIC_DOMAIN>`
- Verify the served certificate:
  - `echo | openssl s_client -connect "<PUBLIC_DOMAIN>:443" -servername "<PUBLIC_DOMAIN>" 2>/dev/null | openssl x509 -noout -issuer -subject -dates`

## Validation
```bash
./scripts/check.sh
```

## Logs
```bash
./scripts/logs.sh
# last 200 lines
./scripts/logs.sh 200
```

## Backups
```bash
./scripts/backup.sh
# keep 14 backups
KEEP_BACKUPS=14 ./scripts/backup.sh
```

## Basic Operations
- Restart Nginx proxy:
  ```bash
  docker compose restart nginx
  ```
- Check container status:
  ```bash
  docker compose ps
  ```

## Security Notes
- Never commit tokens or private keys to public repositories.
- Keep sensitive values in `.env` and out of version control.

## Oracle Cloud (OCI) Ports to Open
- `22/tcp`: only from your admin IP (SSH).
- `443/tcp`: HTTPS/DoH through Nginx.
- `853/tcp`: DoT.
- Optional: `80/tcp` (HTTP redirect), `53/tcp+udp` (classic DNS), `853/udp` (DoQ).
- Do not open `3000/tcp` in OCI; it is loopback-only for local diagnostics.
- Detailed policy and operational criteria: `docs/runbook.md`.

## Operational References
- Daily operations, certificate renewal, and timer lifecycle: `docs/runbook.md`.
- Common incidents and fixes: `docs/troubleshooting.md`.
- Documentation quality standard for future changes: `docs/OPERATIONS_STANDARD.md`.
