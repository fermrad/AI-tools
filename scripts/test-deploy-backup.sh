#!/usr/bin/env bash
#
# Test af backup-trinnet i .github/workflows/deploy-app.yml.
#
# Trinnet kan ikke prøvekøres uden et rigtigt deploy, og dets fejlmåde er tavs:
# vælger det den forkerte container, springer det bare backup'en over og går
# grønt. Det kostede project 210 deploys uden backup (S-211). Derfor testes
# logikken her mod simulerede docker-tilstande — inklusive de faktiske
# container-inventarer fra staging- og prod-boksene.
#
# Scriptet KLIPPER remote-body'en ud af workflowet frem for at kopiere den, så
# testen ikke kan komme til at teste en forældet kopi. Det forudsætter, at
# body'en er fri for ${{ }}-udtryk (alt kommer ind som positionsargumenter) —
# det tjekkes eksplicit nedenfor, fordi netop den egenskab er det, der gør
# trinnet testbart. Indfør ikke ${{ }} i body'en igen.
#
# Kør: bash scripts/test-deploy-backup.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/deploy-app.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SCRIPT="$TMP/backup-body.sh"

# --- Klip remote-body'en ud af "Backup database"-trinnet ------------------
python3 - "$WORKFLOW" "$SCRIPT" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"bash -s -- \"\$BACKUP_DIR\".*?<< 'REMOTE'\n(.*?)\n\s*REMOTE\n", src, re.S)
if not m:
    sys.exit("Kunne ikke finde backup-trinnets REMOTE-heredoc i workflowet.")
body = "\n".join(l[10:] if l.startswith(" " * 10) else l for l in m.group(1).split("\n"))
if "${{" in body:
    sys.exit("Backup-body'en indeholder ${{ }}-udtryk — så kan den ikke testes. "
             "Send værdien ind som positionsargument i stedet.")
open(sys.argv[2], "w").write(body + "\n")
PY
[ -s "$SCRIPT" ] || exit 1

# --- docker-stub: tilstanden styres via miljøvariabler --------------------
cat > "$TMP/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  ps)   if [ "${2:-}" = "-a" ]; then printf '%s\n' $ALL_CONTAINERS
        else printf '%s\n' $RUNNING_CONTAINERS; fi ;;
  exec) printf '%s' "$DUMP_OUTPUT" ;;
esac
STUB
chmod +x "$TMP/docker"
export PATH="$TMP:$PATH"

PASS=0; FAIL=0
BACKUP_DIR="$TMP/backups"

# run_case <beskrivelse> <forventet-exitkode> <forventet-tekst> <env> <container> <slug> <user> <db>
run_case() {
  local desc="$1" want_rc="$2" want_grep="$3"; shift 3
  local out rc ok=1
  out="$(bash "$SCRIPT" "$BACKUP_DIR" "$@" 2>&1)"; rc=$?
  [ "$rc" -eq "$want_rc" ] || ok=0
  [ -z "$want_grep" ] || grep -q "$want_grep" <<<"$out" || ok=0
  if [ $ok -eq 1 ]; then
    PASS=$((PASS + 1)); printf '  ok    %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FEJL  %s (exit %s, ventede %s)\n        %s\n' \
      "$desc" "$rc" "$want_rc" "${out//$'\n'/$'\n        '}"
  fi
}

export DUMP_OUTPUT='-- pg_dump
CREATE TABLE t (id int);'

# Faktiske inventarer, aflæst med `docker ps` 2026-08-08.
STAGING_PUBLIC="ferm-caddy ferm-crm-app ferm-crm-db ferm-devhub-app ferm-devhub-db ferm-os-auth ferm-os-web ferm-project-staging-app ferm-project-staging-db"
STAGING_INTERNAL="ferm-area51-app ferm-area51-db ferm-area51-scraper ferm-caddy ferm-komm-app ferm-komm-db ferm-komm-scraper risk-tool-app risk-tool-db"
PROD_PUBLIC="ferm-area51-app ferm-area51-db ferm-caddy ferm-crm-app ferm-crm-db ferm-devhub-app ferm-devhub-db ferm-project-app ferm-projects-db"

set_box() { export RUNNING_CONTAINERS="$1" ALL_CONTAINERS="${2:-$1}"; }

echo "Backup-trinnet — container-valg og overspringning"

echo " staging, korrekt containernavn:"
set_box "$STAGING_PUBLIC"
run_case "project tager backup af ferm-project-staging-db" 0 '^Backup: ' \
  staging ferm-project-staging-db project projects projects_db
run_case "crm tager backup"    0 '^Backup: ' staging ferm-crm-db    crm    crm    crm_db
run_case "devhub tager backup" 0 '^Backup: ' staging ferm-devhub-db devhub devhub devhub_db
set_box "$STAGING_INTERNAL"
run_case "area51 tager backup (intern boks)" 0 '^Backup: ' \
  staging ferm-area51-db area51 area51 area51_db

echo " staging, prod-navn (fejlen i S-211) skal larme:"
set_box "$STAGING_PUBLIC"
run_case "forkert navn fejler og udpeger den kørende container" 1 'ferm-project-staging-db' \
  staging ferm-projects-db project projects projects_db

echo " production uændret:"
set_box "$PROD_PUBLIC"
run_case "project tager backup" 0 '^Backup: ' prod ferm-projects-db project projects projects_db
run_case "crm tager backup"     0 '^Backup: ' prod ferm-crm-db     crm     crm     crm_db

echo " ægte førstedeploy skal stadig springe over:"
set_box "$STAGING_PUBLIC"
run_case "ny app uden containere på en boks med andre apps" 0 'førstedeploy' \
  staging ferm-nyapp-db nyapp nyapp nyapp_db
set_box ""
run_case "ny app på en tom boks" 0 'førstedeploy' \
  staging ferm-nyapp-db nyapp nyapp nyapp_db

echo " en stoppet database er ikke et førstedeploy:"
set_box "ferm-caddy" "ferm-caddy ferm-crm-db"
run_case "stoppet container fejler i stedet for at springe over" 1 'findes, men kører ikke' \
  staging ferm-crm-db crm crm crm_db

echo " tom pg_dump fejler stadig (#214):"
set_box "$STAGING_PUBLIC"
DUMP_OUTPUT="" run_case "tom dump giver fejl, ikke en 20-bytes .gz" 1 'er tom' \
  staging ferm-crm-db crm crm crm_db

echo
echo "Container-valget på runneren (uden for heredoc'en)"

# Selve S-211-rettelsen er de fem linjer, der vælger container ud fra miljøet.
# De ligger i run:-blokken med ${{ inputs.* }}, så de testes ved at oversætte
# udtrykkene til shell-variabler. Samtidig kræves det, at backup-trinnet og
# SQL-trinnene vælger PRÆCIS ens — det var uenigheden mellem dem, der var fejlen.
python3 - "$WORKFLOW" "$TMP" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
START = 'DB_CONTAINER="${{ inputs.db_container }}"'
blocks = []
for i, line in enumerate(lines):
    if line.strip() != START:
        continue
    # Blokken er fra DB_CONTAINER=... til og med den første efterfølgende `fi`.
    for j in range(i + 1, min(i + 12, len(lines))):
        if lines[j].strip() == "fi":
            blocks.append([l.strip() for l in lines[i:j + 1]])
            break
    else:
        sys.exit(f"Fandt intet afsluttende `fi` til container-valget på linje {i+1}.")
if len(blocks) != 3:
    sys.exit(f"Ventede 3 container-valg (backup + 2x SQL), fandt {len(blocks)}.")
norm = {"\n".join(b) for b in blocks}
if len(norm) != 1:
    sys.exit("Backup- og SQL-trinnene vælger container FORSKELLIGT — "
             "det var præcis fejlen i S-211.\n\n---\n".join(norm))
shell = re.sub(r"\$\{\{ inputs\.(\w+) \}\}", r"${\1}", "\n".join(blocks[0]))
open(sys.argv[2] + "/resolve.sh", "w").write(shell + '\necho "$DB_CONTAINER"\n')
PY
[ -f "$TMP/resolve.sh" ] || exit 1
echo "  ok    backup- og SQL-trinnene vælger container ens"
PASS=$((PASS + 1))

# resolve_case <beskrivelse> <forventet> <miljø> <prod> <staging-override> <dev-override>
resolve_case() {
  local desc="$1" want="$2"
  local got
  got="$(DEPLOY_ENV="$3" db_container="$4" staging_db_container="$5" dev_db_container="$6" \
         bash "$TMP/resolve.sh")"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); printf '  ok    %s\n' "$desc"
  else
    FAIL=$((FAIL + 1)); printf '  FEJL  %s: fik %s, ventede %s\n' "$desc" "$got" "$want"
  fi
}

# project: override sat for både staging og dev — kernen i S-211.
resolve_case "project/staging vælger staging-navnet" ferm-project-staging-db \
  staging ferm-projects-db ferm-project-staging-db ferm-project-db
resolve_case "project/dev vælger dev-navnet" ferm-project-db \
  dev ferm-projects-db ferm-project-staging-db ferm-project-db
resolve_case "project/production vælger prod-navnet" ferm-projects-db \
  production ferm-projects-db ferm-project-staging-db ferm-project-db

# crm/devhub/area51: ingen override — skal falde tilbage på prod-navnet.
resolve_case "crm/staging uden override falder tilbage" ferm-crm-db \
  staging ferm-crm-db "" ""
resolve_case "devhub/staging uden override falder tilbage" ferm-devhub-db \
  staging ferm-devhub-db "" ""
resolve_case "area51/staging uden override falder tilbage" ferm-area51-db \
  staging ferm-area51-db "" ""
resolve_case "crm/production uden override" ferm-crm-db \
  production ferm-crm-db "" ""

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
