# Claude GitHub Actions

Reusable workflows and Python scripts for Claude-powered automation.

## Reusable workflows

These live in `.github/workflows/` of the AI-tools repo and are callable from any repo in the `fermrad` org (or any repo that has access).

### Usage in a calling repo

```yaml
# .github/workflows/triage.yml in your repo
name: AI Issue Triage
on:
  issues:
    types: [opened, reopened]
jobs:
  triage:
    uses: fermrad/AI-tools/.github/workflows/ai-issue-triage.yml@main
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

```yaml
# .github/workflows/ci.yml — add compliance as a job
  compliance:
    uses: fermrad/AI-tools/.github/workflows/compliance-check.yml@main
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

```yaml
# .github/workflows/pentest.yml in your repo
name: Penetration Test
on:
  workflow_dispatch:
    inputs:
      target_url:
        required: false
        default: ''
jobs:
  pentest:
    uses: fermrad/AI-tools/.github/workflows/pentest.yml@main
    with:
      target_url: ${{ inputs.target_url }}
```

## Required secrets

| Secret | Required by | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | issue triage, compliance | Calls the Claude API |
| `GITHUB_TOKEN` | all workflows | Auto-provided by GitHub Actions — no setup needed |

> `ANTHROPIC_API_KEY` is required by **issue-triage** and **compliance-check** only. **Pentest does not require it** — its findings come from Semgrep, Trivy, Gitleaks, and `npm audit` and are not AI-analysed.

## Scripts

| Script | Called by |
|---|---|
| `triage-issue.py` | `ai-issue-triage.yml` |
| `compliance-check.py` | `compliance-check.yml` |
| `pentest-report.py` | `pentest.yml` |
