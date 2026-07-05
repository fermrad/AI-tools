---
description: Create a new fermrad app from the boilerplate and wire up DNS, deploy workflows, and Caddy routing for prod/staging/dev
---

Full end-to-end setup for a new Ferm app: create the repo from the boilerplate, then trigger the Bootstrap App workflow to open PRs for DNS, deploy workflows, and Caddy routing.

## Step 1 — Gather inputs

If not provided as arguments, ask:
- **Repo name** — the new fermrad repo (e.g. `my-app`)
- **Short description** — one sentence describing the app
- **Subdomain** — the public subdomain (e.g. `my-app` → `my-app.ferm.dk` in prod, `staging.my-app.ferm.dk` in staging, `dev.my-app.ferm.dk` in dev)

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
Production: <subdomain>.ferm.dk
Staging:    staging.<subdomain>.ferm.dk
Dev:        dev.<subdomain>.ferm.dk
PR stacks:  {pr-number}.dev.<subdomain>.ferm.dk

Bootstrap will open up to 3 PRs:
  1. DNS records (infrastructure repo)
  2. Deploy workflows (target repo)
  3. Caddy routing blocks (infrastructure repo)
```

## Step 5 — Trigger the bootstrap workflow

```bash
gh workflow run bootstrap-app.yml \
  --repo fermrad/infrastructure \
  --field repo=<repo> \
  --field subdomain=<subdomain>
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
3. **Caddyfile PR** — merge, then trigger **Deploy Caddy** for staging and production environments
