---
name: Infrastructure Safety Rules
description: Rules for working with Ferm's production and staging servers — what you must never do and what you must always do before touching infrastructure
---

# Infrastructure Safety Rules

These rules apply any time you are working with server infrastructure, Docker containers, databases, Terraform, or Nginx configuration on Ferm's Hetzner servers.

---

## NEVER — prohibited actions (require explicit written approval from tech lead)

### Data
- **Never delete database volumes** — not in production, not in staging. `docker volume rm`, `rm -rf /var/lib/postgresql`, or any equivalent is permanently destructive.
- **Never run `DROP TABLE`, `TRUNCATE`, or `DELETE` without a `WHERE` clause** on any environment that contains real data.
- **Never drop a Postgres schema or database** without a verified, tested backup.
- **Never delete user-uploaded files or object storage buckets** containing application data.

### Secrets
- **Never commit secrets, API tokens, or passwords** to any git repository — even private ones.
- **Never log secret values** in CI output, application logs, or issue comments.
- **Never rotate a production secret without coordinating a zero-downtime rollout** — rotating without updating all consumers causes an outage.

### Infrastructure
- **Never run `terraform destroy` on production** without explicit written approval from the tech lead.
- **Never force-push or hard-reset a branch that CI has already passed** — this breaks the audit trail.
- **Never modify firewall rules to expose additional ports** without documenting the business reason.
- **Never kill or restart the shared `ferm-crm-nginx` container** without first verifying a rollback plan — it takes down all six subdomains simultaneously.

---

## ALWAYS — required before any infrastructure change

### Before touching the server
1. **Read `docs/ferm-tech-stack.md`** in full — it contains the current state of running containers, networks, and known gotchas from previous sessions.
2. **Check `docker ps`** on the server to confirm which containers are currently running.
3. **Test the change in development or staging** before applying to production.

### Before applying Terraform
1. **Run `terraform plan`** and read every line before `terraform apply`.
2. **Check for `destroy` actions** in the plan — any resource destruction requires explicit confirmation.
3. **Use the correct `-var-file`** — applying production tfvars against the staging state file causes cross-environment corruption.

### Before changing Nginx config
1. **Run `nginx -t`** (inside the container) to validate syntax before reloading.
2. **Keep a copy of the working config** so you can roll back with a single `scp` if the new config causes a 502/504.
3. **Use `nginx -s reload`**, not a container restart — reload is graceful (zero dropped connections).

### After any production change
1. **Update `docs/ferm-tech-stack.md`** with a dated entry in the update log.
2. **Verify all six subdomains** respond correctly: `curl -I https://crm.ferm.dk` etc.

---

## ISO 27001 / SOC2 alignment

| Rule | Control |
|---|---|
| Never delete production data without approval | A.8.2 — Information Classification & A.10.1 — Cryptographic controls |
| No secrets in git or logs | A.9.4 — System & application access control |
| Always test in staging first | A.14.2 — Security in development & support |
| Validate Nginx before reload | A.12.1 — Operational procedures |
| Update change log after production changes | A.12.1 — Change management |
| No extra firewall ports without documented reason | A.13.1 — Network security management |
| Terraform plan before apply | A.12.4 — Logging & monitoring (change audit trail) |

---

## Incident response

If something goes wrong:
1. **Don't panic, don't make it worse** — stop making changes.
2. **Check logs first**: `docker logs <container> --tail 200`
3. **Roll back the last config change** before investigating root cause.
4. **Contact Mads** (tech lead) immediately for production incidents.
5. **Document what happened** in `docs/ferm-tech-stack.md` update log.
