S-877 — bootstrap-app synker feedback-widgeten og sætter DevHub-tokenet op

Brugeren oplever: en ny app fra bootstrap-app sender feedback til DevHub fra første dag i stedet for en forældet widget uden token.

## Hvad der er målt (før jeg skrev)

- `claude/skills/bootstrap-app/SKILL.md` på `origin/main` (735fc9c) er den eneste fil i skillen (ingen scripts). Den nævnte hverken `sync-feedback-widget.sh`, `DEVHUB_APP_SLUG` eller `DEVHUB_INGEST_TOKEN`. Intet var allerede dækket.
- `scripts/sync-feedback-widget.sh` findes på `origin/main` i `fermrad/lib` (`git ls-tree` efter fetch). Jeg har IKKE kørt scriptet — skillen kører det først ved en rigtig bootstrap. Uprøvet.
- Boilerplate `origin/main` (efter S-853 «boilerplate skifter til den vendorede feedback-widget», #36) har `DEVHUB_APP_SLUG = "<appname>"` i `src/lib/feedback.ts`, `DEVHUB_INGEST_TOKEN` i `.env.example` og `DEVHUB_INGEST_TOKEN: ${DEVHUB_INGEST_TOKEN:-}` i `docker-compose.deploy.yml`. Skillens trin passer til det.
- Repoets egne tjek: kun `claude-conventions-check.yml` (SKILL.md-frontmatter: `name` = mappenavn, `description` findes). Kørt lokalt med samme logik: grønt for alle skills. Ingen markdown-lint eller scripts i repoet; ingen script rørt, så ingen `bash -n`-kørsel af nye scripts (`scripts/sync-skills.sh` kørt med `bash -n` og selve synken: OK).

## Hvad der er rettet

Kun `claude/skills/bootstrap-app/SKILL.md` (og den genererede kopi i `.claude/skills/bootstrap-app/` via `scripts/sync-skills.sh`; filerne er identiske):

- **Step 2b** — synk feedback-widgeten fra `fermrad/lib` efter klon/find-replace, før første commit, med begrundelsen (vendor-kopien forældes mellem bootstraps).
- **Step 11** — opret appen i DevHub og notér sluggen; tjek `DEVHUB_APP_SLUG` når slug ≠ repo-navn (ukendt slug = 201 med `appId: null`); `DEVHUB_INGEST_TOKEN` pr. miljø i `.env` + `environment:` i alle compose-filer (S-223 «area51 kører på komms API-nøgle»). Skillen siger eksplicit, at Jakob opretter tokenet selv, og at det aldrig skal i chatten eller repoet.
- **Step 12** — afsluttende tjek: uden token «Feedback er ikke slået til i dette miljø»; med token en prøve-feedback, der skal ligge under den rigtige app i DevHub (ikke `appId: null`).

## Hemmeligheds-vejen: valgt `.env` på boksen + compose `environment` — og hvorfor

Briefen antog, at S-1515 «App-hemmelighederne flyttes ind i GitHub-miljøerne» og S-1517 «Org-hemmelighederne ind i appens GitHub-miljøer» gør GitHub-miljøerne til vejen ind på boksen, og at deploy-workflowet «skriver ud». Det passer ikke med koden:

- `deploy-app.yml` skriver ingen app-hemmeligheder til boksen. Miljøet (`environment: ${{ inputs.environment }}`, S-1497 «R-156 BP1») bærer boks-hemmelighederne (host, SSH-nøgle); rsync ekskluderer `.env*` (linje ~1699); compose startes mod boksens eksisterende `.env`.
- I `fermrad/infrastructure` (lokal klon, `84dc506`/S-1515) går S-1515 den modsatte vej: `hemmeligheder-til-miljoe` LÆSER værdierne fra boksens kørende `.env` og kopierer dem ind i GitHub-miljøet, så CI-job kan bruge dem uden repo-niveau-hemmeligheder. Boksens `.env` er stadig kilden, appen læser.

Derfor beskriver skillen `.env` + compose som vejen ind i appen og nævner miljøerne som kopier til CI. Tokenet behøver ikke ligge i GitHub-miljøet (ingen CI-job bruger det). Hvis infrastructure senere får en vej, der skriver miljø-hemmeligheder ud til boksen, skal Step 11 punkt 3 skiftes — Jakob bedes bekræfte, at det ikke allerede er sket på en gren, jeg ikke kan se.

## Fund, ikke rettet

- Step 10 beder om `.env` ved SSH på boksen og at «rebuild og redeploy» bager `NEXT_PUBLIC_ENTRA_ENABLED` ind — uændret, men samme hemmeligheds-vej som Step 11.
- Step 10 står ikke i forhold til compose-fælden (S-223): Entra-variablerne nævnes kun i `.env`, ikke i compose `environment:`. Bør tilføjes af et separat punkt.
- Skillen har ingen trin for selve find-replace/klon af boilerplaten (`gh repo create --template` kopierer, men `<appname>` erstattes ingen steder beskrevet). Step 2b antager, at det er sket.
- Step 2 sætter `required_pull_request_reviews` osv. via API — ikke vurderet mod nuværende husregler.
- `scripts/sync-skills.sh` genererede også ændringer i 6 andre skills og to nye mapper (`hest-agent`, `sikkerhedsgennemgang`): `.claude/skills/` på main er altså forældet. Jeg har fortrudt dem for at holde PR'en til punktet; en separat sync-PR er værd.

## Efter merge

- Skillen synkes til laptoppen (`setup-tool`).
- Ingen app-repoer berørt.

Hjælp: uændret — AI-tools har ingen AI-hjælp-flade
