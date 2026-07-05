---
description: Bootstrap a fermrad repo for deployment — wires up DNS, deploy workflows, and Caddy routing for prod/staging/dev
---

Set up a new app for deployment on the Ferm infrastructure. Triggers the Bootstrap App workflow in the infrastructure repo, which opens three PRs automatically.

## Prerequisites (check before proceeding)

Verify all three — stop and tell the user what's missing if any fail:

```bash
# 1. Repo must exist
gh api repos/fermrad/<repo> --silent

# 2. SSH_PRIVATE_KEY must exist in the target repo's Actions secrets
gh api repos/fermrad/<repo>/actions/secrets --jq '[.secrets[].name]' | grep SSH_PRIVATE_KEY

# 3. GH_TOKEN_TERRAFORM must exist in the infrastructure repo
gh api repos/fermrad/infrastructure/actions/secrets --jq '[.secrets[].name]' | grep GH_TOKEN_TERRAFORM
```

- If the **repo doesn't exist**: offer to run `/new-repo` first to create it, then come back to this skill.
- If **`SSH_PRIVATE_KEY` is missing**: tell the user to run the **Terraform GitHub → apply** workflow in infrastructure first to distribute the deploy key.
- If **`GH_TOKEN_TERRAFORM` is missing**: tell the user to add it to the infrastructure repo's Actions secrets.

## Steps

### 1. Gather inputs

If not provided as arguments, ask:
- **Repo name** — the fermrad repo to wire up (e.g. `my-app`)
- **Subdomain** — the public subdomain (e.g. `my-app` → `my-app.ferm.dk` in prod, `staging.my-app.ferm.dk` in staging, `dev.my-app.ferm.dk` in dev)

### 2. Confirm the plan with the user

Print a summary before triggering:

```
Repo:       fermrad/<repo>
Production: <subdomain>.ferm.dk
Staging:    staging.<subdomain>.ferm.dk
Dev:        dev.<subdomain>.ferm.dk
PR stacks:  {pr-number}.dev.<subdomain>.ferm.dk

This will open up to 3 PRs:
  1. DNS records (infrastructure repo)
  2. Deploy workflows (target repo)
  3. Caddy routing blocks (infrastructure repo)
```

### 3. Trigger the workflow

```bash
gh workflow run bootstrap-app.yml \
  --repo fermrad/infrastructure \
  --field repo=<repo> \
  --field subdomain=<subdomain>
```

### 4. Watch the run

```bash
sleep 5
RUN_ID=$(gh run list --repo fermrad/infrastructure --workflow=bootstrap-app.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --repo fermrad/infrastructure --exit-status
```

### 5. Report results

Print the job summary URL: `https://github.com/fermrad/infrastructure/actions/runs/<run-id>`

Then list the PRs that were opened — fetch them from the run logs:

```bash
gh run view $RUN_ID --repo fermrad/infrastructure --log | grep -E 'Opened .* PR:' | grep -oE 'https://github\.com/[^ ]+'
```

### 6. Tell the user what to do next

After the PRs are merged:

1. **DNS PR** — merge, then trigger **Terraform DNS → apply** in infrastructure to make the records live
2. **Deploy workflows PR** — merge into the target repo; staging deploys on every push to `main`, production on release tags
3. **Caddyfile PR** — merge, then trigger **Deploy Caddy** for each environment (staging + production)
