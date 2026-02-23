# Operations Runbook

## Clean Start (recommended)
1. Prepare environment configuration:
   - `cp .env.example .env` (first run only)
   - Fill required variables in `.env`:
     - `PUBLIC_DOMAIN`
     - `DUCKDNS_SUBDOMAINS`
     - `DUCKDNS_TOKEN`
     - `ADGUARD_ADMIN_USER`
     - `ADGUARD_ADMIN_PASSWORD`
     - `LETSENCRYPT_EMAIL`
2. Run local bootstrap (LE-first flow):
   - `sudo PUBLIC_DOMAIN="your-subdomain.duckdns.org" DUCKDNS_SUBDOMAINS="your-subdomain" DUCKDNS_TOKEN="YOUR_TOKEN" ADGUARD_ADMIN_USER="admin" ADGUARD_ADMIN_PASSWORD="CHANGE_PASSWORD" LETSENCRYPT_EMAIL="you@example.com" LETSENCRYPT_STAGING="false" ALLOW_SELF_SIGNED_FALLBACK="false" INSTALL_RENEW_TIMER="true" bash scripts/bootstrap-local.sh`
3. Confirm status:
   - `sudo docker compose ps`
4. Validate renewal timer:
   - `./scripts/renew-timer-status.sh`
   - If `INSTALL_RENEW_TIMER=true`, `certbot-renew` should be stopped.

## Functional Validation
1. Open `https://<PUBLIC_DOMAIN>` and confirm AdGuard access.
2. Verify DoH endpoint: `https://<PUBLIC_DOMAIN>/dns-query`.
3. Review logs: `./scripts/logs.sh 200`.
4. Validate served certificate:
   - `echo | openssl s_client -connect "<PUBLIC_DOMAIN>:443" -servername "<PUBLIC_DOMAIN>" 2>/dev/null | openssl x509 -noout -issuer -subject -dates`
5. Confirm exposure policy:
   - `3000/tcp` is bound to host loopback (`127.0.0.1`); do not open it in OCI.

## Certificate Renewal
- Recommended mode (Linux with systemd): `adguard-renew.timer`.
  - Manual renewal:
    - `./scripts/renew-letsencrypt.sh`
  - Install/reinstall timer:
    - `sudo ./scripts/install-renew-timer.sh`
  - Check status:
    - `./scripts/renew-timer-status.sh`
  - Uninstall timer:
    - `sudo ./scripts/uninstall-renew-timer.sh`
- Fallback mode (without systemd): `certbot-renew` container.
  - `./scripts/renew-letsencrypt.sh`
  - `docker compose up -d certbot-renew`

## Basic Recovery
1. If Nginx fails, validate config syntax:
   - `docker compose exec nginx nginx -t`
2. Restart affected service:
   - `docker compose restart nginx`
   - `docker compose restart adguard`
3. If issue persists, restart full stack:
   - `docker compose down && docker compose up -d`
4. If bootstrap fails during certificate issuance:
   - validate domain DNS (`dig +short <PUBLIC_DOMAIN>`)
   - inspect `duckdns` and `nginx` logs
   - use `ALLOW_SELF_SIGNED_FALLBACK="true"` only as temporary contingency

## Post-Incident Checklist
- Containers are `Up` in `docker compose ps`.
- Certificates exist under `letsencrypt/live/`.
- DNS resolution and HTTPS access are restored.

## Secret Rotation
- Rotate immediately if any of these are exposed:
  - `DUCKDNS_TOKEN`
  - `ADGUARD_ADMIN_PASSWORD`
- Update `.env`, restart services, and validate access:
  - `sudo docker compose restart duckdns adguard nginx`

## Recommended OCI Port Policy
- `22/tcp`: admin IP only.
- `80/tcp`: public only if using HTTP→HTTPS redirect.
- `443/tcp`: public for HTTPS/DoH.
- `853/tcp`: public for DoT.
- `53/tcp` and `53/udp`: open only if you need classic DNS.
- `853/udp`: open only if you need DoQ.
- `3000/tcp`: do not open (loopback-only local diagnostics).

## Incidents and Diagnostics
- For known issue playbooks, use `docs/troubleshooting.md`.

## Recommended Backups
- Run `./scripts/backup.sh` before major changes.
- Verify backup artifacts in `backups/`.
