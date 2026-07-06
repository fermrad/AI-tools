---
description: Create a new fermrad app from the boilerplate and wire up DNS, deploy workflows, Caddy routing, and Microsoft Entra SSO registration for prod/staging/dev
---

Full end-to-end setup for a new Ferm app: create the repo from the boilerplate, trigger the Bootstrap App workflow to open PRs for DNS, deploy workflows, and Caddy routing — and optionally register Entra app registrations for both staging and production.

## Step 1 — Gather inputs

If not provided as arguments, ask:
- **Repo name** — the new fermrad repo (e.g. `my-app`)
- **Short description** — one sentence describing the app
- **Subdomain** — the public subdomain (e.g. `my-app` → `my-app.ferm.dk` in prod, `staging.my-app.ferm.dk` in staging)
- **Server type** — `internal` (default — Tailscale VPN only, DNS resolves to internal IPs, Caddyfile.internal) or `public` (internet-facing, DNS resolves to public IPs, Caddyfile.staging/production/dev)

## Step 2 — Create the repo from boilerplate (if it doesn't exist)

Check if the repo already exists:
```bash
gh api repos/fermrad/<repo> --silent 2>/dev/null && echo "exists" || echo "missing"
```

If **missing**, create it from `fermrad/boilerplate`:
```bash
gh repo create fermrad/<repo> \
  --template fermrad/boilerplate \
  --private \
  --description "<description>"
```

Then set up branch protection on `main`:
```bash
gh api repos/fermrad/<repo>/branches/main/protection \
  --method PUT \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": []},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "restrictions": null
}
JSON
```

And create standard labels:
```bash
for label in "bug:D93F0B" "enhancement:0075CA" "security:D93F0B" "compliance:E4E669"; do
  name="${label%%:*}"; color="${label##*:}"
  gh label create "$name" --color "$color" --repo fermrad/<repo> --force
done
```

If the repo **already exists**, skip creation and proceed.

## Step 3 — Check the remaining prerequisite

`SSH_PRIVATE_KEY` must exist in the target repo's Actions secrets (added by Terraform GitHub → apply):
```bash
gh api repos/fermrad/<repo>/actions/secrets --jq '[.secrets[].name]' | grep SSH_PRIVATE_KEY
```

If missing, stop and tell the user: _"Run **Terraform GitHub → apply** in the infrastructure repo first to distribute the deploy key, then re-run this skill."_

Also verify `GH_TOKEN_TERRAFORM` exists in infrastructure:
```bash
gh api repos/fermrad/infrastructure/actions/secrets --jq '[.secrets[].name]' | grep GH_TOKEN_TERRAFORM
```

If missing, stop and tell the user to add it to the infrastructure repo's Actions secrets.

## Step 4 — Confirm the plan

Print a summary before triggering the workflow:

```
Repo:       fermrad/<repo>  (created from boilerplate / already existed)
Server:     internal (Tailscale VPN)  OR  public (internet-facing)
Production: <subdomain>.ferm.dk
Staging:    staging.<subdomain>.ferm.dk
Dev:        dev.<subdomain>.ferm.dk   [public only]
PR stacks:  {pr-number}.dev.<subdomain>.ferm.dk  [public only]

Bootstrap will open up to 3 PRs:
  1. DNS records (infrastructure repo)
  2. Deploy workflows (target repo)
  3. Caddy routing blocks (infrastructure repo — Caddyfile.internal or .staging/.production/.dev)
```

## Step 5 — Trigger the bootstrap workflow

```bash
gh workflow run bootstrap-app.yml \
  --repo fermrad/infrastructure \
  --field repo=<repo> \
  --field subdomain=<subdomain> \
  --field server=<internal|public>
```

## Step 6 — Watch the run

```bash
sleep 5
RUN_ID=$(gh run list --repo fermrad/infrastructure --workflow=bootstrap-app.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --repo fermrad/infrastructure --exit-status
```

## Step 7 — Report results

Print the job summary URL: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

List the PRs that were opened:
```bash
gh run view $RUN_ID --repo fermrad/infrastructure --log | grep -E 'Opened .* PR:' | grep -oE 'https://github\.com/[^ ]+'
```

## Step 8 — Tell the user what to do next

After the PRs are merged:

1. **DNS PR** — merge, then trigger **Terraform DNS → apply** in infrastructure to make the records live
2. **Deploy workflows PR** — merge into the target repo; staging deploys on every push to `main`, production on release tags
3. **Caddyfile PR**:
   - **Public**: merge, then trigger **Deploy Caddy → staging** and **Deploy Caddy → production**
   - **Internal**: merge, then trigger **Deploy Caddy → internal-staging**

---

## Step 9 — Register Entra app registrations (optional, ask first)

Ask: _"Do you want to set up Microsoft Entra SSO for this app now?"_

If yes, check that the Azure CLI is authenticated:
```bash
az account show --query "{tenant:tenantId, account:user.name}" -o table
```

If not logged in, tell the user to run `az login` and re-run this skill.

Create **two separate registrations** — one for staging, one for production (Entra requires separate redirect URIs per app registration):

### Staging registration

```bash
STAGING_APP_ID=$(az ad app create \
  --display-name "Ferm <AppName> (Staging)" \
  --web-redirect-uris "https://staging.<subdomain>.ferm.dk/api/auth/entra/callback" \
  --query appId -o tsv)
echo "Staging Client ID: $STAGING_APP_ID"
```

Add Graph delegated permissions (`openid`, `profile`, `email`, `offline_access`):
```bash
# Look up current Graph permission IDs from the live service principal
GRAPH_ID="00000003-0000-0000-c000-000000000000"
OPENID=$(az ad sp show --id $GRAPH_ID --query "oauth2PermissionScopes[?value=='openid'].id" -o tsv)
PROFILE=$(az ad sp show --id $GRAPH_ID --query "oauth2PermissionScopes[?value=='profile'].id" -o tsv)
EMAIL=$(az ad sp show --id $GRAPH_ID --query "oauth2PermissionScopes[?value=='email'].id" -o tsv)
OFFLINE=$(az ad sp show --id $GRAPH_ID --query "oauth2PermissionScopes[?value=='offline_access'].id" -o tsv)

az ad app permission add --id $STAGING_APP_ID --api $GRAPH_ID \
  --api-permissions "$OPENID=Scope" "$PROFILE=Scope" "$EMAIL=Scope" "$OFFLINE=Scope"
az ad app permission admin-consent --id $STAGING_APP_ID
```

Generate client secret (shown once — save immediately):
```bash
STAGING_SECRET=$(az ad app credential reset \
  --id $STAGING_APP_ID \
  --display-name "bootstrap $(date +%Y-%m-%d)" \
  --years 2 \
  --query password -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "=== STAGING — save to 1Password ==="
echo "ENTRA_TENANT_ID=$TENANT_ID"
echo "ENTRA_CLIENT_ID=$STAGING_APP_ID"
echo "ENTRA_CLIENT_SECRET=$STAGING_SECRET"
echo "ENTRA_REDIRECT_URI=https://staging.<subdomain>.ferm.dk/api/auth/entra/callback"
echo "NEXT_PUBLIC_ENTRA_ENABLED=true"
```

### Production registration

Repeat with the production subdomain:
```bash
PROD_APP_ID=$(az ad app create \
  --display-name "Ferm <AppName>" \
  --web-redirect-uris "https://<subdomain>.ferm.dk/api/auth/entra/callback" \
  --query appId -o tsv)

az ad app permission add --id $PROD_APP_ID --api $GRAPH_ID \
  --api-permissions "$OPENID=Scope" "$PROFILE=Scope" "$EMAIL=Scope" "$OFFLINE=Scope"
az ad app permission admin-consent --id $PROD_APP_ID

PROD_SECRET=$(az ad app credential reset \
  --id $PROD_APP_ID \
  --display-name "bootstrap $(date +%Y-%m-%d)" \
  --years 2 \
  --query password -o tsv)

echo "=== PRODUCTION — save to 1Password ==="
echo "ENTRA_TENANT_ID=$TENANT_ID"
echo "ENTRA_CLIENT_ID=$PROD_APP_ID"
echo "ENTRA_CLIENT_SECRET=$PROD_SECRET"
echo "ENTRA_REDIRECT_URI=https://<subdomain>.ferm.dk/api/auth/entra/callback"
echo "NEXT_PUBLIC_ENTRA_ENABLED=true"
```

---

## Step 10 — Entra follow-up checklist

After the registrations are created, tell the user:

1. **Save both sets of credentials to 1Password** — the secrets above are shown once and cannot be retrieved again. Create two separate entries: _"Ferm \<AppName\> Entra (Staging)"_ and _"Ferm \<AppName\> Entra (Prod)"_.

2. **Add `.env` vars on the servers** — once the DNS and Caddy PRs are merged and the subdomains are live, SSH into each server and append to `/opt/ferm-<repo>/.env`:
   ```
   NEXT_PUBLIC_ENTRA_ENABLED=true
   ENTRA_TENANT_ID=<tenant>
   ENTRA_CLIENT_ID=<client-id-for-this-env>
   ENTRA_CLIENT_SECRET=<secret-for-this-env>
   ENTRA_REDIRECT_URI=https://<subdomain>.ferm.dk/api/auth/entra/callback
   ```
   Then rebuild and redeploy so `NEXT_PUBLIC_ENTRA_ENABLED` is baked into the build.

3. **Add users** — in the app's admin interface, ensure each person who should be able to log in has an account with a matching work email and `is_user = true`.

4. **Test** — open `/login` and click "Log in with Microsoft". A successful redirect back without `?error=` means the registration is working.

> **Troubleshooting**: `token_exchange_failed` / `AADSTS7000215` means the client secret is wrong or expired. Run `az ad app credential reset --id <APP_ID>` to rotate it and update `.env`.
