S-962 «Boksene rydder selv op hver uge»

Hjælp: uændret — kun drift

## Hvad
Nyt genbrugsworkflow `.github/workflows/oprydning.yml`, som hver app kan kalde på en ugentlig schedule — ved siden af `diskvagt.yml`. Det rydder op på boksen over ssh:

1. `docker builder prune -af`.
2. Images UDEN container (hverken kørende eller stoppet) i `ghcr.io/fermrad/<app>` slettes — pr. repository bevares det kørende og det forrige (tilbagerulningsvejen).
3. Lokalt byggede `<navn>:latest` uden container (ingen RepoDigests) slettes.
4. Et image med en container (Postgres, Caddy, scrapere …) røres aldrig. Heller ikke andre registre eller hentede images uden container (fx `redis:7`).

Ingen `docker system prune`, ingen `docker volume …`, ingen `docker image prune`. Volumener røres aldrig. Fjernelse sker med `docker image rm <ref>` uden `-f`, så dæmonen selv afviser et image med container.

## Hvorfor 31-10-2026
`ferm-server` var 89 % fuld: images 25,6 GB (10,8 GB kunne frigøres), byggecache 6,6 GB alt ubrugt. Synderne var gamle `devhub:<sha>` / `project:<sha>`, et lokalt `ferm-devhub-app:latest` og cachen. I hånden: 56 %, ingen container rørt.

## Valget: søster-workflow, ikke en tilstand i `diskvagt.yml`
`diskvagt.yml` MÅLER kun, og det er et udtalt løfte i dens hoved (S-1290: en vagt, der også rydder, skjuler det, den findes for at vise). `test-deploy-diskvagt-daglig.sh` fælder enhver `prune`/`image rm` dér. En oprydningstilstand ville bryde løftet eller svække testen. Et søster-workflow genbruger samme ssh-opsætning, GitHub-miljø (`environment: ${{ inputs.environment }}`), Tailscale-nøgle og host-secrets (trinnene er kopieret ordret), så adgangsvejen er den samme — prisen er én fil mere. Diskvagten er uændret.

## Tilbagerulning (spejler `image_keep`, skrevet i filens hoved)
Fredningen kommer fra maskinen (`docker ps -aq` → `docker inspect .Image`), som i deploy-app.yml. `image_keep` er 1 her frem for 3. Tilføjet hensyn: ubrugte images NYERE end det kørende beholdes (kan høre til et deploy i gang eller et mislykket), og det nyeste ubrugte ÆLDRE end det kørende er «forrige». Har et repo intet image i brug, beholdes det nyeste. «De N nyeste ubrugte» alene ville beholde et aldrig kørt image og slette det egentlige forrige.

## Tør kørsel
Input `toer` (boolean) har default **true** — et kald, der glemmer det, sletter intet. Kalderen skal bede om live eksplicit; anbefalet i kalderen:

```yaml
with:
  toer: ${{ github.event_name != 'schedule' }}
```
Manuel dispatch bliver dermed tør af sig selv. Tør kørsel kører kun læsende docker-kommandoer og lister «Ville slette».

## Fejler lukket
Kan disken ikke måles, eller `docker ps`/`inspect`/`images` fejler, eller boksen ingen containere har, slettes der INTET og kørslen er rød. En tom brugt-liste må aldrig læses som «alt er ubrugt».

## Opsummering
Overskrift med disk før → efter, «Frigjort plads», slettede images (kun navne og tags), beholdte tilbagerulningsimages og trinnets log.

## Vagt
`scripts/test-deploy-oprydning.sh` (kobles på `deploy-workflow-test.yml`) kører trinnet mod en falsk docker med tilstand og fixtur fra 31-10-2026. 27 ok, 0 fejl, inkl. måletabel over hvert image og seks KØRTE brud, som alle fældes:

| Brud | Fanget |
|---|---|
| det kørende image slettes | ja |
| det forrige image slettes | ja |
| image med stoppet container slettes (`ps` uden `-a`) | ja |
| en `docker volume prune` sniger sig ind | ja |
| `docker image prune -a` erstatter reglen | ja |
| alle `:latest` slettes uden digest-tjek | ja |

Testen er kun kørt lokalt mod falsk docker; ingen rigtig boks er rørt.

## Berørte repos / opfølgning
Apperne får det først med en pin-opdatering, og den laves fra laptoppen efter merge. Hver app, der skal rydde (devhub, project, crm, area51 …), tilføjer en ugentlig schedule, der kalder `fermrad/AI-tools/.github/workflows/oprydning.yml@<sha>` med `secrets: inherit`. Start med `toer: true` på én boks, læs summaryen, og skift derefter til live. Skal ligge uden for udrulningstidspunkter; «venter»-reglen dækker et image pullet af et deploy i gang, men ikke en container, der er ved at blive genskabt.

Merges af Jakob.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
