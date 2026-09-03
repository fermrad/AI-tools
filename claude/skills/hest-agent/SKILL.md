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
- Er `git status` ikke ren, eller står den ikke på `main`: **en anden agent er i gang.**
  Stop. Én agent pr. repo ad gangen på hesten — der er ét arbejdstræ.

## 1 · Skriv briefen til maskinen

Briefen er **hele DevHub-punktet** (hent det med `list_sprint`/`get_*` — agenten på hesten
har ingen DevHub-forbindelse) plus husets regler. Skriv den med en heredoc, så
anførselstegn og `$` overlever:

```
ssh hest 'cat > ~/opgave-<punkt>.md' <<'BRIEF'
Du arbejder i `~/localprojects/<repo>` (repo `fermrad/<repo>`) på maskinen `fermhest`.

# Opgaven: <punkt> — "<titel>"
<punktets fulde tekst>

# Sådan skal du arbejde
Læs `CLAUDE.md` i repoet først. Den bærer husets regler, og de gælder.
<punktspecifikke regler: adgangsmodel, fælder, afgrænsning>

## Miljøet på denne maskine
- Prisma 7 indlæser IKKE `.env`. Før `prisma`-kommandoer: `set -a; . ./.env; set +a`
- Typecheck: `NODE_OPTIONS=--max-old-space-size=3072 npx tsc --noEmit` (husets BYGGE_LOFT_MB)
- `npm ci` er kørt, basen er seedet. Prøver: `npm test` (~85 s). Byg: `npm run build`.

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
cd ~/localprojects/<repo>
set -a; . ./.env; set +a
git fetch -q origin && git checkout -q -b <gren> origin/main
nohup claude -p "$(cat ~/opgave-<punkt>.md)" --dangerously-skip-permissions > ~/<punkt>.log 2>&1 &
echo "startet — pid $!"'
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
ssh hest 'cd ~/localprojects/<repo> && git log --oneline origin/main..HEAD && git diff --stat origin/main...HEAD'
```

## 4 · Åbn PR'en fra laptoppen

Grenen er pushet, men PR'en er ikke åbnet — det er et **tjekpunkt**, ikke en mangel.

```
cd ~/localprojects/<lokal-klon> && git fetch origin <gren>
ssh hest 'cat ~/localprojects/<repo>/pr-body-<punkt>.md' > /private/tmp/pr-body-<punkt>.md
gh pr create --repo fermrad/<repo> --base main --head <gren> --title "<titel>" --body-file /private/tmp/pr-body-<punkt>.md
```

Derefter husets almindelige merge-rytme (se `new-pr`, `code-review`).

## 5 · Ryd op på hesten

```
ssh hest 'cd ~/localprojects/<repo> && rm -f pr-body-<punkt>.md && git checkout -q main && git pull -q --ff-only origin main && git branch -D <gren>; rm -f ~/opgave-<punkt>.md ~/<punkt>.log'
```

Gør det **efter** PR'en er åbnet — ikke før. Ryddes grenen, før den er set, er arbejdet
kun på origin.

## Fælder, målt 02–03-09-2026

- **`PATH` mangler `~/.npm-global/bin`** i ikke-interaktive shells → `claude: command not found`.
- **`pgrep -f claude` matcher sin egen ssh-kommando.** Brug `ps -p <pid>` eller
  `ps -eo args | grep "[c]laude"`, ellers svarer kontrollen altid ja.
- **Kørselsværten deler maskinen.** `CI — PROJECT` for `fermrad/project` kører her. En agent
  og et CI-job samtidig deler 16 tråde — det virker, men mål tiderne, hvis noget ser
  langsomt ud. Runneren tager ét job ad gangen.
- **Strømtest uafprøvet** (pr. 03-09-2026): `Restore on AC Power Loss` er sat, aldrig set
  virke. Er hesten offline efter et strømsvigt, er det derfor.

## Hvornår IKKE hesten

- Opgaven rører **prod-data eller prod-nøgler** — hesten har ingen, og skal ikke have dem.
- Opgaven kræver **DevHub-skrivning undervejs** (bogføring, kommentarer). Agenten på hesten
  har ingen DevHub-forbindelse; bogfør fra laptoppen på baggrund af rapporten.
- Der **allerede kører** en agent i samme repo på hesten.
