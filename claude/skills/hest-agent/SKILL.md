---
name: hest-agent
description: Sæt en Claude Code-agent i gang på fermhest (hesten) — husets egen maskine — med en opgave fra DevHub, løsrevet fra din session, og hent rapporten når den er færdig. Brug når arbejde skal køre uden laptoppen, eller når flere agenter skal køre samtidig uden at fylde den lokale maskine.
---

# hest-agent — arbejde på hesten

`fermhest` er husets mini-PC på kontoret (Ryzen 7 5825U, 8C/16T, 14 GB). Den nås som
**`ssh hest`** over Tailscale, uanset hvilket net den står på. Alle `fermrad`-repos ligger
i `~/localprojects/`, dev-Postgres kører på **5433**, Claude Code er logget ind.

Agenten kører som `claude -p` under `nohup`. **Den overlever, at din session og din
laptop lukkes.** Det er hele formålet.

## Før du starter — mål maskinen

```
ssh -o BatchMode=yes hest 'uptime; cd ~/localprojects/<repo> && git status --short | head; git branch --show-current'
```

- Svarer den ikke: den er offline. **Stop.** Fald tilbage til en lokal agent. Meld det.
- **Rør aldrig `~/localprojects/<repo>` selv** — det er hovedtræet, og en anden agent kan stå
  i det. Hver agent får sit eget arbejdstræ under `~/wt/<punkt>` med egen gren og egen
  database. Målt 03-09-2026: worktree + `npm ci` + `prisma generate` tager **17 s**, og
  hovedtræet er urørt imens — også når en anden agent arbejder i det.
- **Loftet er hukommelsen, ikke antallet.** 14 GB; en agent topper på 3–4 GB under tsc og
  build (husets `BYGGE_LOFT_MB`), og `CI — PROJECT` tager det samme, når den kører. **Tre
  agenter ad gangen er realistisk, fire er stramt.** Tjek `free -m` før du starter en fjerde.

## 1 · Skriv briefen til maskinen

Briefen er **hele DevHub-punktet** (hent det med `list_sprint`/`get_*` — agenten på hesten
har ingen DevHub-forbindelse) plus husets regler. Skriv den med en heredoc, så
anførselstegn og `$` overlever:

```
ssh hest 'cat > ~/opgave-<punkt>.md' <<'BRIEF'
Du arbejder i `~/wt/<punkt>` (et worktree af `fermrad/<repo>`) på maskinen `fermhest`. Din database hedder `projects_<punkt>` — den er din alene. Rør ALDRIG `~/localprojects/<repo>`; der arbejder andre.

# Opgaven: <punkt> — "<titel>"
<punktets fulde tekst>

# Sådan skal du arbejde
Læs `CLAUDE.md` i repoet først. Den bærer husets regler, og de gælder.
<punktspecifikke regler: adgangsmodel, fælder, afgrænsning>

## Miljøet på denne maskine
- Prisma 7 indlæser IKKE `.env`. Før `prisma`-kommandoer: `set -a; . ./.env; set +a`
- Typecheck: `NODE_OPTIONS=--max-old-space-size=3072 npx tsc --noEmit` (husets BYGGE_LOFT_MB)
- `npm ci` og `prisma db push` er kørt i dit worktree. Basen er TOM — kør `npm run prisma:seed`, hvis opgaven kræver data. Prøver: `npm test` (~85 s). Byg: `npm run build`.

## Krav
- Måletabel i prøvens hoved, brudt mindst tre gange — kør hvert brud, skøn dem ikke.
- Alt grønt før du pusher: typecheck, prøver, build.
- Arbejd på grenen `<gren>` (den er allerede tjekket ud). Push den.
- ⚠️ `gh` har INGEN auth på denne maskine. Åbn IKKE PR'en — skriv PR-teksten til
  `pr-body-<punkt>.md` i repoets rod og sig i rapporten, at grenen er pushet.
- Nævn aldrig et S-, R-, T- eller F-nummer uden titel.

## Rapport til sidst
Hvad du besluttede og hvorfor. Hvordan hvert brud blev kørt. Hvad du IKKE kunne efterprøve.
BRIEF
```

## 2 · Start agenten

```
ssh hest 'export PATH=$HOME/.npm-global/bin:$PATH
cd ~/localprojects/<repo> && git fetch -q origin
git worktree add -q ~/wt/<punkt> -b <gren> origin/main
cd ~/wt/<punkt>
cp ~/localprojects/<repo>/.env .env && sed -i "s|/projects_db?|/projects_<punkt>?|" .env
docker exec ferm-projects-db psql -U projects -d projects_db -qc "CREATE DATABASE projects_<punkt>"
export $(grep "^export NPM_TOKEN" ~/.bashrc | sed "s/^export //" | head -1)
npm ci >/dev/null 2>&1
set -a; . ./.env; set +a
npx prisma db push --skip-generate >/dev/null 2>&1 && npx prisma generate >/dev/null 2>&1
nohup claude -p "$(cat ~/opgave-<punkt>.md)" --dangerously-skip-permissions > ~/<punkt>.log 2>&1 &
echo "startet — pid $! i ~/wt/<punkt> mod projects_<punkt>"'
```

`--dangerously-skip-permissions` er det, laptoppens agenter også kører med — forskellen
er maskinen, ikke tilliden. Hesten har egen GitHub-nøgle og kan pushe.

**Sig til brugeren, at agenten kører, og at den overlever laptoppen.** Gæt ikke på
varighed — et S-punkt af størrelse S/M tager typisk ½–1½ time.

## 3 · Hent rapporten

```
ssh hest 'ps -o pid,etime --no-headers -p <pid> 2>/dev/null || echo AFSLUTTET; tail -60 ~/<punkt>.log'
```

Loggen er tom, mens agenten arbejder; rapporten kommer samlet til sidst. **Læs den
kritisk** — agenter melder undertiden "grønt", hvor de mener "ikke rødt". Efterprøv:

```
ssh hest 'cd ~/wt/<punkt> && git log --oneline origin/main..HEAD && git diff --stat origin/main...HEAD'
```

## 4 · Åbn PR'en fra laptoppen

Grenen er pushet, men PR'en er ikke åbnet — det er et **tjekpunkt**, ikke en mangel.

```
cd ~/localprojects/<lokal-klon> && git fetch origin <gren>
ssh hest 'cat ~/wt/<punkt>/pr-body-<punkt>.md' > /private/tmp/pr-body-<punkt>.md
gh pr create --repo fermrad/<repo> --base main --head <gren> --title "<titel>" --body-file /private/tmp/pr-body-<punkt>.md
```

Derefter husets almindelige merge-rytme (se `new-pr`, `code-review`).

## 5 · Ryd op på hesten

```
ssh hest 'cd ~/localprojects/<repo> && git worktree remove ~/wt/<punkt> --force && git branch -D <gren>
docker exec ferm-projects-db psql -U projects -d projects_db -qc "DROP DATABASE projects_<punkt>"
rm -f ~/opgave-<punkt>.md ~/<punkt>.log'
```

Gør det **efter** PR'en er åbnet — ikke før. Ryddes worktree'et, før grenen er set, er
arbejdet kun på origin. Hovedtræet og dets base `projects_db` er ikke rørt af nogen af
trinnene — det er hele pointen.

## Fælder, målt 02–03-09-2026

- **`PATH` mangler `~/.npm-global/bin`** i ikke-interaktive shells → `claude: command not found`.
- **`pgrep -f claude` matcher sin egen ssh-kommando.** Brug `ps -p <pid>` eller
  `ps -eo args | grep "[c]laude"`, ellers svarer kontrollen altid ja.
- **Kørselsværten deler maskinen.** `CI — PROJECT` for `fermrad/project` kører her. Agenter
  og et CI-job samtidig deler 16 tråde — det virker, men mål tiderne, hvis noget ser
  langsomt ud. Runneren tager ét job ad gangen; CI's postgres er sin egen container på 5432,
  agenternes baser ligger i dev-instansen på 5433.
- **Strømtest uafprøvet** (pr. 03-09-2026): `Restore on AC Power Loss` er sat, aldrig set
  virke. Er hesten offline efter et strømsvigt, er det derfor.

## Hvornår IKKE hesten

- Opgaven rører **prod-data eller prod-nøgler** — hesten har ingen, og skal ikke have dem.
- Opgaven kræver **DevHub-skrivning undervejs** (bogføring, kommentarer). Agenten på hesten
  har ingen DevHub-forbindelse; bogfør fra laptoppen på baggrund af rapporten.
- `free -m` viser under ~4 GB tilgængelig — så er der ikke plads til én mere. Vent, eller kør den lokalt.
