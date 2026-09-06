---
name: pr-preview
description: Deploy a PR branch as a live preview environment on the development Hetzner server, then post the preview URL as a PR comment
argument-hint: <pr-number>
---

# PR Preview Deployment

Rejser en pull request som sin egen stak på dev-boksen, så UI'et kan afprøves live før merge.

## Prerequisites

- PR-grenen er pushet til GitHub
- Repoet har `.github/workflows/deploy-pr-stack.yml` (alle app-repos har det —
  `project`, `devhub`, `komm`, `area51`, `risk`, `crm`)
- GitHub Actions-secrets `DEV_SSH_HOST` og `SSH_PRIVATE_KEY` er sat

## When to use

- "Kan du rejse den her PR til test?"
- "Deploy grenen til dev, så jeg kan se den"
- "Giv mig et link til PR'en kørende"

---

## Adressen

```
https://<PR-nummer>.dev.<app>.ferm.dk
```

Fx `https://245.dev.project.ferm.dk`. Verificeret ens i alle seks app-repos
(`project`, `devhub`, `komm`, `area51`, `risk`, `crm`) — appnavnet er repoets
navn.

> **Ikke `pr-<N>.dev.ferm.dk`.** Det navn har ingen certifikat, og DNS peger
> alligevel på dev-boksen via wildcard, så et opslag "virker" og curl fejler
> først på TLS. Gæt ikke på adressen — læs `Write Caddy snippet`-trinnet i
> repoets egen workflow, hvis du er i tvivl.

---

## Steps

### 1. Find repo og PR

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh pr view <number> --repo $REPO --json headRefName,number,title,url
```

Er der ikke givet et nummer, så spørg hvilken PR der skal rejses.

### 2. Vælg udløser — labelen er standardvejen

Workflowen kan startes på to måder, og **de opfører sig forskelligt**:

| Udløser | Deployer | Poster kommentar |
|---|---|---|
| Labelen `dev-deploy` på PR'en | ja | **ja** |
| `workflow_dispatch` | ja | **nej** i flere repos |

**Brug labelen**, medmindre du fejlsøger:

```bash
gh pr edit <number> --repo $REPO --add-label dev-deploy
```

Kommentar-trinnet er i `project`, `devhub` og `area51` gated på
`if: github.event_name == 'pull_request'`. Et dispatch rejser altså stakken
korrekt og efterlader **intet spor på PR'en** — hvilket er let at læse som "det
lykkedes ikke". I `area51` er URL'en i kommentaren desuden bygget af
`github.event.number`, som er tom ved dispatch.

**Dispatch er til fejlsøgning** — det er den dokumenterede vej, når et deploy
fejler, netop for at undgå gæt-commits mod `main`:

```bash
gh workflow run deploy-pr-stack.yml --repo $REPO --field pr_number=<number>
```

> `ref:`-linjen i checkout-trinnet er ikke pynt: uden den checker
> `workflow_dispatch` default-branchen ud, og stakken kommer op, ser rigtig ud
> og tester `main`.

### 3. Vent på kørslen

Brug en until-løkke, ikke `sleep` med et gæt:

```bash
RUN=$(gh run list --repo $REPO --workflow deploy-pr-stack.yml --limit 1 --json databaseId -q '.[0].databaseId')
until [ "$(gh run view $RUN --repo $REPO --json status -q .status)" = "completed" ]; do sleep 20; done
gh run view $RUN --repo $REPO --json conclusion -q .conclusion
```

### 4. Verificér — mod appen, ikke mod kørslens farve

Workflowens `Verify the stack answers` prøver **indefra på dev-boksen**, så den
siger intet om DNS og certifikat udefra. Tjek begge dele, og bekræft at commit'en
er PR'ens:

```bash
curl -s https://<number>.dev.<app>.ferm.dk/api/health
```

Svaret skal bære PR'ens SHA og `"ref"` pege på grenen eller `pull/<number>` —
ikke `main`. Gør det ikke det, kørte checkout på default-branchen.

### 5. Rapportér URL'en

Skriv den i svaret, også når workflowen selv har postet kommentaren.

---

## Sådan virker workflowen (`deploy-pr-stack.yml`)

1. Checker PR'ens head ud (`refs/pull/<N>/head`)
2. SSH'er til dev-boksen, rsync'er appen til en PR-specifik mappe
3. Kopierer `.env` fra den permanente dev-stak
4. Starter stakken på en PR-specifik port
5. Skriver et Caddy-snippet for `<N>.dev.<app>.ferm.dk` og reloader
6. Verificerer indefra at stakken svarer
7. Poster URL'en som PR-kommentar — **kun på label-stien**

Nedrivning sker automatisk, når PR'en merges eller lukkes
(`teardown-pr-stack.yml`).

---

## Cleanup

```bash
gh workflow run teardown-pr-stack.yml --repo $REPO --field pr_number=<number>
```

---

## Bemærk

`AI-tools` har som det eneste repo `pr-preview.yml` og `pr-preview-cleanup.yml`.
Antag ikke de navne i et app-repo — tjek `.github/workflows/`, hvis noget ser
anderledes ud end beskrevet her.
