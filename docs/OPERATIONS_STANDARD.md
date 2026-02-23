# Operational Documentation Standard

## Objective
Define a minimum, consistent standard to document operation, deployment, security, and recovery of the stack (`AdGuard + Nginx + DuckDNS + Let's Encrypt`) in a reproducible way.

## Principles
- **Executable**: every procedure must include copy/paste-ready commands.
- **Verifiable**: every critical step must include expected validation.
- **Versioned**: docs and operational changes are updated in the same commit/PR.
- **Low ambiguity**: use absolute paths or explicit `cwd` (`cd /path/to/project`).
- **Secure by default**: never include real tokens, private keys, or certificates.

## Required Structure
- `README.md`
  - Clean setup from zero.
  - Required environment variables (`.env`).
  - Exposed ports and purpose.
- `docs/runbook.md`
  - Daily operation: restart, logs, checks, backups.
  - Recovery procedures.
- `docs/troubleshooting.md`
  - Known real failures with diagnosis and fix steps.
- `docs/OPERATIONS_STANDARD.md` (this document)
  - Rules to keep documentation quality consistent.

## Procedure Format
Every new procedure should include:
1. **Purpose** (what it solves).
2. **Preconditions** (permissions, ports, services, variables).
3. **Commands** (single ordered shell block).
4. **Validation** (commands + expected output/behavior).
5. **Rollback/Exit** (how to return to a stable state).

## Minimum Operational Content Requirements
- Bootstrap flow (local and VM) with real execution order.
- TLS policy (LE-first, explicit fallback, automatic renewal).
- One active renewal strategy at a time (`systemd` timer or `certbot-renew`, not both).
- Full timer lifecycle: install, status, uninstall.
- OCI port security checklist.
- Secret rotation steps after exposure.

## Update Rule
Any change to:
- scripts in `scripts/`
- variables in `.env.example`
- ports or behavior in `docker-compose.yml`
must be reflected in `README.md` and, when applicable, in `runbook`/`troubleshooting` in the same PR.

## Operational PR Checklist
- [ ] `docker compose config` passes without errors.
- [ ] New/updated scripts pass `bash -n`.
- [ ] README updated (usage + new variables).
- [ ] Runbook/Troubleshooting updated if operational behavior changed.
- [ ] No secrets in diff (`.env`, tokens, private keys).

## Command Conventions in Docs
- Prefix with `sudo` when required.
- Do not mix commands from different paths without an explicit `cd`.
- Avoid ambiguous placeholders; use explicit examples:
  - `PUBLIC_DOMAIN="myadguardstack.duckdns.org"`
  - `INSTALL_RENEW_TIMER="true"`
