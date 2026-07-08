---
name: pr-preview
description: Deploy a PR branch as a live preview environment on the development Hetzner server, then post the preview URL as a PR comment
argument-hint: <pr-number>
---

# PR Preview Deployment

Deploys a pull request to the `ferm-development` Hetzner server so the UI can be tested live before merging.

## Prerequisites

- The `ferm-development` Hetzner project exists and has a running server
- The server SSH key is available locally
- The PR branch is pushed to GitHub
- GitHub Actions secret `DEV_SSH_HOST` is set (the dev server IP)

## When to use

Use this skill when someone asks:
- "Can you spin up this PR for testing?"
- "Deploy this branch to dev so I can see it"
- "Give me a link to this PR running live"

---

## Steps

### 1. Detect the current repo

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 2. Identify the PR

If a PR number is provided (`/pr-preview 42`), use it. Otherwise ask: "Which PR or branch should I deploy?"

```bash
gh pr view <number> --json headRefName,number,title,url --repo $REPO
```

### 3. Trigger the preview deployment

```bash
gh workflow run pr-preview.yml \
  --repo $REPO \
  --field pr_number=<number>
```

### 4. Wait for the deployment to complete

```bash
sleep 5
RUN_ID=$(gh run list --repo $REPO --workflow pr-preview.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $RUN_ID --repo $REPO
```

### 5. Report the preview URL

The workflow posts the URL as a PR comment automatically. Also output it here:

```
Preview live at: https://pr-<number>.dev.ferm.dk
```

---

## How the workflow works (`pr-preview.yml`)

See `.github/workflows/pr-preview.yml` in the repo. The workflow:

1. Checks out the PR branch
2. SSHs into the dev server
3. Pulls the branch, builds the Docker image for the changed app
4. Starts the container on a PR-specific port mapped to a subdomain (`pr-<N>.dev.ferm.dk`)
5. Posts a GitHub comment on the PR with the URL
6. The preview is torn down automatically when the PR is merged or closed (via a separate `cleanup-preview.yml` workflow)

---

## Cleanup

Previews are cleaned up automatically. To tear one down manually:

```bash
gh workflow run cleanup-preview.yml \
  --repo $REPO \
  --field pr_number=<number>
```
