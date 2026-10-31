#!/usr/bin/env bash
#
# Test af den ugentlige oprydning, .github/workflows/oprydning.yml (S-962 —
# "Boksene rydder selv op hver uge").
#
# Testen kører trinnet «Ryd op» mod en falsk ssh, df og docker. Den falske
# docker har TILSTAND (images og containere i filer), så en sletning
# faktisk fjerner imaget, og den afviser — som den rigtige — `image rm` af et
# image, en container hænger på. Fixturen spejler målingen 31-10-2026 på
# `ferm-server`: gamle devhub-/project-images uden container, et lokalt bygget
# ferm-devhub-app:latest, en byggecache — og Postgres, Caddy og en scraper,
# der ikke må røres.
#
# Fem ting måles:
#
#   1. STATISK: workflow_call, `toer` er default true, ingen `system prune`,
#      ingen `volume`, ingen `image prune`, og `builder prune -af` er der.
#   2. MÅLETABEL: live-kørslen sletter PRÆCIS de forventede images, beholder
#      det kørende og det forrige pr. repository, og rører aldrig et image
#      med en container (kørende eller stoppet).
#   3. TØRKØRSEL: lister, hvad der ville blive slettet, og ændrer intet —
#      docker-loggen indeholder kun læsende kald.
#   4. FEJLER LUKKET: en df, der ikke kan læses, eller en docker ps, der
#      fejler, sletter ingenting.
#   5. KØRTE BRUD: kroppen ødelægges bevidst på fem måder, og testens
#      invarianter SKAL fælde hver af dem. En vagt, der aldrig er set fælde
#      noget, har ikke bevist, at den kan.
#
# Kør: bash scripts/test-deploy-oprydning.sh [anden-oprydning.yml]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="${1:-$REPO_ROOT/.github/workflows/oprydning.yml}"
TRIN="Ryd op"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runner-temp" "$TMP/state"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fejl() { FAIL=$((FAIL + 1)); printf '  FEJL  %s\n' "$1"; }

[ -f "$WF" ] || { echo "FEJL  $WF findes ikke."; exit 1; }

echo "1) Statisk: grænseflade og forbudte kommandoer"
if python3 -I - "$WF" "$TRIN" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
on = wf.get(True) or wf.get("on")
fejl = []
inp = (on or {}).get("workflow_call", {}).get("inputs", {})
if not inp.get("environment", {}).get("required"):
    fejl.append("input 'environment' er ikke påkrævet")
if inp.get("toer", {}).get("default") is not True or inp.get("toer", {}).get("type") != "boolean":
    fejl.append("'toer' er ikke en boolean med default true")
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
navne = [s.get("name") for s in steps]
if sys.argv[2] not in navne:
    fejl.append("trinnet '%s' findes ikke" % sys.argv[2])
elif "${{" in steps[navne.index(sys.argv[2])]["run"]:
    fejl.append("oprydningstrinnets run: indeholder GitHub-udtryk")
forbudt = re.compile(r"system\s+prune|\bvolume\b|image\s+prune|\brmi\b|image\s+rm\s+(-\S*f|--force)|docker\s+rm\b|container\s+prune")
alle = "\n".join((s.get("run") or "") for s in steps)
for linje in alle.splitlines():
    if linje.strip().startswith("#"):
        continue
    if forbudt.search(linje):
        fejl.append("forbudt kommando: " + linje.strip())
if "builder prune -af" not in alle:
    fejl.append("`docker builder prune -af` mangler")
if fejl:
    print("\n".join(fejl)); sys.exit(1)
PY
then ok "workflow_call, toer=true som default, ingen system/volume/image-prune, builder prune -af til stede"
else fejl "workflowets grænseflade eller forbudt-listen er brudt (se ovenfor)"; fi

# --- falske værktøjer ------------------------------------------------------
cat > "$TMP/bin/ssh" <<'STUB'
#!/usr/bin/env bash
[ "${FALSK_SSH_NEDE:-0}" = "1" ] && { echo "ssh: connect: Connection timed out" >&2; exit 255; }
cmd=(); host_seen=0
while [ $# -gt 0 ]; do
  if [ "$host_seen" -eq 1 ]; then cmd+=("$1"); shift; continue; fi
  case "$1" in
    -i|-o) shift 2;;
    -*) shift;;
    root@*) host_seen=1; shift;;
    *) shift;;
  esac
done
bash -c "${cmd[*]}"
STUB
# df: forbruget i KiB ligger i state/used_kb; disken er 100.000.000 KiB.
cat > "$TMP/bin/df" <<'STUB'
#!/usr/bin/env bash
[ "${FALSK_DF_RC:-0}" != "0" ] && { echo "df: cannot read table" >&2; exit "$FALSK_DF_RC"; }
used="$(cat "$FALSK_STATE/used_kb")"
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/sda1 100000000 $used $((100000000 - used)) $(( (used * 100 + 99999999) / 100000000 ))% /"
STUB
# docker: images.txt = «ID REF DIGESTS» nyeste først; containere.txt = «CID IMAGEID kørende|stoppet».
cat > "$TMP/bin/docker" <<'STUB'
#!/usr/bin/env bash
S="$FALSK_STATE"
echo "docker $*" >> "$S/kald.log"
forbudt() { echo "FORBUDT: docker $*" >> "$S/kald.log"; echo "docker $* er ikke tilladt" >&2; exit 99; }
case "$1 ${2:-}" in
  "info -f") echo "/" ;;
  "system df") printf 'Images|25.6GB|10.8GB (42%%)\nContainers|210MB|0B (0%%)\nLocal Volumes|3.2GB|0B (0%%)\nBuild Cache|6.6GB|6.6GB\n' ;;
  "ps -aq") [ "${FALSK_PS_RC:-0}" != "0" ] && exit "$FALSK_PS_RC"; cut -d' ' -f1 "$S/containere.txt" ;;
  "ps -q")  awk '$3=="kørende" {print $1}' "$S/containere.txt" ;;
  "inspect -f")
    shift 2
    for c in "$@"; do awk -v c="$c" '$1==c {print $2}' "$S/containere.txt"; done ;;
  "images --no-trunc") awk '{print $1" "$2}' "$S/images.txt" ;;
  "image inspect") awk -v id="$5" '$1==id {print $3; exit}' "$S/images.txt" ;;
  "image rm")
    [ $# -eq 3 ] || forbudt "$@"
    ref="$3"
    id="$(awk -v r="$ref" '$2==r {print $1; exit}' "$S/images.txt")"
    [ -n "$id" ] || { echo "Error: No such image: $ref" >&2; exit 1; }
    if awk -v i="$id" '$2==i {f=1} END {exit !f}' "$S/containere.txt"; then
      echo "Error: conflict: unable to remove repository reference \"$ref\" (must force) - container is using its referenced image" >&2
      echo "AFVIST: $ref" >> "$S/kald.log"; exit 1
    fi
    grep -vF -- " $ref " "$S/images.txt" > "$S/images.ny"; mv "$S/images.ny" "$S/images.txt"
    echo "$ref" >> "$S/slettet.log"
    echo $(( $(cat "$S/used_kb") - 1000000 )) > "$S/used_kb"
    echo "Untagged: $ref" ;;
  "builder prune")
    [ "${3:-}" = "" ] && [ "${FALSK_BYGGEPRUNE:-af}" = "af" ] || true
    echo "$*" | grep -qx 'builder prune -af' || forbudt "$@"
    echo $(( $(cat "$S/used_kb") - 6600000 )) > "$S/used_kb"
    echo "Total: 6.6GB" ;;
  *) forbudt "$@" ;;
esac
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
export FALSK_STATE="$TMP/state"

# --- fixturen: 31-10-2026 på ferm-server ----------------------------------
# Format: ID REF DIGESTS (nyeste først). Tilføjet ' ' efter REF, så grep -F ' ref '
# i den falske `image rm` rammer præcis én linje.
fixtur() {
  cat > "$TMP/state/images.txt" <<'IMG'
sha256:d5 ghcr.io/fermrad/devhub:sha5 1 
sha256:d4 ghcr.io/fermrad/devhub:sha4 1 
sha256:d3 ghcr.io/fermrad/devhub:sha3 1 
sha256:d2 ghcr.io/fermrad/devhub:sha2 1 
sha256:p4 ghcr.io/fermrad/project:p4 1 
sha256:p3 ghcr.io/fermrad/project:p3 1 
sha256:p2 ghcr.io/fermrad/project:p2 1 
sha256:p1 ghcr.io/fermrad/project:p1 1 
sha256:c2 ghcr.io/fermrad/crm:c2 1 
sha256:c1 ghcr.io/fermrad/crm:c1 1 
sha256:c0 ghcr.io/fermrad/crm:c0 1 
sha256:o2 ghcr.io/fermrad/gammel:o2 1 
sha256:o1 ghcr.io/fermrad/gammel:o1 1 
sha256:l1 ferm-devhub-app:latest 0 
sha256:l2 ferm-crm-app:latest 0 
sha256:pg postgres:16 1 
sha256:cd caddy:2 1 
sha256:sc ghcr.io/fermrad/scraper:s1 1 
sha256:rd redis:7 1 
sha256:nl nginx:latest 1 
IMG
  # Linjerne i images.txt ender med mellemrum; REF-feltet er felt 2.
  cat > "$TMP/state/containere.txt" <<'CON'
c-devhub sha256:d5 kørende
c-project sha256:p3 kørende
c-crm sha256:c2 stoppet
c-crmapp sha256:l2 kørende
c-pg sha256:pg kørende
c-caddy sha256:cd kørende
c-scraper sha256:sc stoppet
CON
  echo 89000000 > "$TMP/state/used_kb"
  : > "$TMP/state/kald.log"; : > "$TMP/state/slettet.log"
}

# --- klip trinnet ud -------------------------------------------------------
KROP="$TMP/oprydning.sh"
python3 -I - "$WF" "$TRIN" "$KROP" <<'PY' || { echo "FEJL  kunne ikke klippe '$TRIN' ud"; exit 1; }
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
st = next((s for s in steps if s.get("name") == sys.argv[2]), None)
if st is None:
    sys.exit("Trinnet '%s' findes ikke." % sys.argv[2])
open(sys.argv[3], "w", encoding="utf-8").write(st["run"] + "\n")
PY

koer() { # koer <krop> <toer 0|1> — sætter UD, RC og SUM; kører mod en frisk fixtur
  local krop="$1" toer="$2" summary="$TMP/summary.md"
  fixtur; : > "$summary"
  UD="$( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" \
           GITHUB_STEP_SUMMARY="$summary" TOER="$toer"
         bash "$krop" 2>&1 )"
  RC=$?
  SUM="$(cat "$summary")"
}
tilbage() { # hvilke refs ligger der nu?
  awk '{print $2}' "$TMP/state/images.txt" | sort
}
har() { grep -qF -- "$2" <<<"$1"; }

FORVENTET_SLETTET="ferm-devhub-app:latest
ghcr.io/fermrad/crm:c0
ghcr.io/fermrad/devhub:sha2
ghcr.io/fermrad/devhub:sha3
ghcr.io/fermrad/gammel:o1
ghcr.io/fermrad/project:p1"
# Ting, der ALDRIG må forsvinde: alt med en container, det kørende, det forrige.
ALDRIG="ghcr.io/fermrad/devhub:sha5
ghcr.io/fermrad/devhub:sha4
ghcr.io/fermrad/project:p4
ghcr.io/fermrad/project:p3
ghcr.io/fermrad/project:p2
ghcr.io/fermrad/crm:c2
ghcr.io/fermrad/crm:c1
ghcr.io/fermrad/gammel:o2
ferm-crm-app:latest
postgres:16
caddy:2
ghcr.io/fermrad/scraper:s1
redis:7
nginx:latest"

# Invarianterne, som både den rigtige og de ødelagte kroppe måles mod.
# Returnerer 0 hvis ALT er som det skal være; skriver årsagerne til STDOUT.
invarianter() {
  local ok=0 slettet; slettet="$(sort "$TMP/state/slettet.log")"
  [ "$slettet" = "$FORVENTET_SLETTET" ] || { echo "slettet ≠ forventet: $(tr '\n' ' ' <<<"$slettet")"; ok=1; }
  local nu; nu="$(tilbage)"
  while read -r r; do
    grep -qxF -- "$r" <<<"$nu" || { echo "ALDRIG-image forsvandt: $r"; ok=1; }
  done <<<"$ALDRIG"
  grep -q '^AFVIST' "$TMP/state/kald.log" && { echo "forsøgte at slette image med container: $(grep '^AFVIST' "$TMP/state/kald.log" | head -n 1)"; ok=1; }
  grep -q '^FORBUDT' "$TMP/state/kald.log" && { echo "forbudt docker-kald: $(grep '^FORBUDT' "$TMP/state/kald.log" | head -n 1)"; ok=1; }
  grep -qE '^docker (volume|system prune|image prune)' "$TMP/state/kald.log" && { echo "volume/system/image-prune kaldt"; ok=1; }
  return "$ok"
}

echo
echo "2) Live: måletabel (fixtur = ferm-server 31-10-2026, disken 89 %)"
koer "$KROP" 0
if invarianter > "$TMP/inv.txt"; then
  ok "præcis de forventede 6 images slettet, intet med container rørt"
else
  fejl "live-kørslen brød en invariant:"; sed 's/^/        /' "$TMP/inv.txt"
fi
[ "$RC" -eq 0 ] && ok "exit 0" || fejl "live gav exit $RC: $(grep -E '::' <<<"$UD")"
grep -qx 'docker builder prune -af' <(sed 's/^$//' "$TMP/state/kald.log") && ok "docker builder prune -af kaldt" || fejl "byggecachen blev ikke ryddet"
awk '/^docker builder prune/ {b=NR} /^docker image rm/ && !r {r=NR} END {exit !(b && r && b<r)}' "$TMP/state/kald.log" \
  && ok "byggecachen ryddes FØR images" || fejl "rækkefølgen er ikke byggecache → images"
har "$SUM" "## Ugentlig oprydning — production: 89 % → 77 % (LIVE)" && ok "overskrift: 89 % → 77 %" || fejl "overskriften er forkert: $(head -n 1 <<<"$SUM")"
har "$SUM" "Frigjort plads: **12.0 GB**" && ok "frigjort plads: 12.0 GB (byggecache 6,6 GB + 6 images à 1,0 GB i fixturen)" || fejl "frigjort plads forkert: $(grep Frigjort <<<"$SUM")"
for r in $FORVENTET_SLETTET; do har "$SUM" "- \`$r\`" || fejl "summaryen mangler slettet image $r"; done
har "$SUM" "### Slettede images (6)" && ok "summaryen opregner de 6 slettede images" || fejl "summaryen tæller ikke 6 slettede"
har "$SUM" "- \`ghcr.io/fermrad/devhub:sha4\`" && ok "summaryen viser det beholdte forrige (devhub:sha4)" || fejl "summaryen viser ikke det beholdte forrige"

echo
echo "   Måletabel — hvad skete der med hvert image"
printf '   %-38s %-14s %s\n' "image" "container" "udfald"
fixtur
koer "$KROP" 0
while read -r id ref _; do
  [ -n "$ref" ] || continue
  fixtur_c="$(awk -v i="$id" '$2==i {print $3; exit}' <<'CON'
c-devhub sha256:d5 kørende
c-project sha256:p3 kørende
c-crm sha256:c2 stoppet
c-crmapp sha256:l2 kørende
c-pg sha256:pg kørende
c-caddy sha256:cd kørende
c-scraper sha256:sc stoppet
CON
)"
  if grep -qxF -- "$ref" "$TMP/state/slettet.log"; then u="SLETTET"; else u="beholdt"; fi
  printf '   %-38s %-14s %s\n' "$ref" "${fixtur_c:--}" "$u"
done <<'LISTE'
sha256:d5 ghcr.io/fermrad/devhub:sha5
sha256:d4 ghcr.io/fermrad/devhub:sha4
sha256:d3 ghcr.io/fermrad/devhub:sha3
sha256:d2 ghcr.io/fermrad/devhub:sha2
sha256:p4 ghcr.io/fermrad/project:p4
sha256:p3 ghcr.io/fermrad/project:p3
sha256:p2 ghcr.io/fermrad/project:p2
sha256:p1 ghcr.io/fermrad/project:p1
sha256:c2 ghcr.io/fermrad/crm:c2
sha256:c1 ghcr.io/fermrad/crm:c1
sha256:c0 ghcr.io/fermrad/crm:c0
sha256:o2 ghcr.io/fermrad/gammel:o2
sha256:o1 ghcr.io/fermrad/gammel:o1
sha256:l1 ferm-devhub-app:latest
sha256:l2 ferm-crm-app:latest
sha256:pg postgres:16
sha256:cd caddy:2
sha256:sc ghcr.io/fermrad/scraper:s1
sha256:rd redis:7
sha256:nl nginx:latest
LISTE

echo
echo "3) Tørkørsel: lister, ændrer intet"
koer "$KROP" 1
[ ! -s "$TMP/state/slettet.log" ] && ok "intet image slettet" || fejl "tørkørslen slettede: $(tr '\n' ' ' < "$TMP/state/slettet.log")"
! grep -qE '^docker (image rm|builder prune)' "$TMP/state/kald.log" && ok "docker-loggen har kun læsende kald (ingen image rm, ingen builder prune)" || fejl "tørkørslen kaldte en skrivende docker-kommando"
[ "$(cat "$TMP/state/used_kb")" = "89000000" ] && ok "diskforbruget er uændret (89 %)" || fejl "diskforbruget ændrede sig"
for r in $FORVENTET_SLETTET; do har "$SUM" "- \`$r\`" || fejl "tørkørslens summary mangler $r"; done
har "$SUM" "### Ville slette (6)" && ok "summaryen lister de 6, der ville blive slettet" || fejl "summaryen siger ikke «Ville slette (6)»"
har "$SUM" "TØRKØRSEL — intet slettet" && ok "summaryen siger TØRKØRSEL" || fejl "summaryen siger ikke TØRKØRSEL"
har "$SUM" "Frigjort plads: **0.0 GB**" && ok "frigjort plads: 0.0 GB" || fejl "tørkørslen har frigjort plads"

echo
echo "4) Fejler LUKKET — ingenting slettes"
fixtur; : > "$TMP/summary.md"
UD="$( export HOST=b DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" GITHUB_STEP_SUMMARY="$TMP/summary.md" TOER=0 FALSK_DF_RC=1
       bash "$KROP" 2>&1 )"; RC=$?
[ "$RC" -eq 1 ] && [ ! -s "$TMP/state/slettet.log" ] && ! grep -q '^docker builder' "$TMP/state/kald.log" \
  && ok "en df, der ikke kan læses: rød, og hverken cache eller images rørt" || fejl "ulæselig df: exit $RC, slettet: $(cat "$TMP/state/slettet.log")"
har "$UD" "::error title=Oprydningen kunne ikke måle" && ok "::error:: ved ulæselig måling" || fejl "ingen ::error:: ved ulæselig måling"
fixtur; : > "$TMP/summary.md"
UD="$( export HOST=b DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" GITHUB_STEP_SUMMARY="$TMP/summary.md" TOER=0 FALSK_PS_RC=1
       bash "$KROP" 2>&1 )"; RC=$?
[ "$RC" -eq 1 ] && [ ! -s "$TMP/state/slettet.log" ] \
  && ok "en docker ps, der fejler: rød, og INTET image slettet (tom BRUGT-liste ≠ «alt er ubrugt»)" || fejl "docker ps fejlede: exit $RC, slettet: $(cat "$TMP/state/slettet.log")"
fixtur; : > "$TMP/state/containere.txt"; : > "$TMP/summary.md"
UD="$( export HOST=b DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" GITHUB_STEP_SUMMARY="$TMP/summary.md" TOER=0
       bash "$KROP" 2>&1 )"; RC=$?
[ "$RC" -eq 1 ] && [ ! -s "$TMP/state/slettet.log" ] \
  && ok "en boks uden containere: rød, intet slettet" || fejl "boks uden containere: exit $RC, slettet: $(cat "$TMP/state/slettet.log")"
fixtur; : > "$TMP/summary.md"
UD="$( export HOST=b DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" GITHUB_STEP_SUMMARY="$TMP/summary.md" TOER=0 FALSK_SSH_NEDE=1
       bash "$KROP" 2>&1 )"; RC=$?
[ "$RC" -eq 1 ] && har "$UD" "::error title=Oprydningen kunne ikke måle" && ok "en boks, der ikke svarer: rød" || fejl "ssh nede: exit $RC"

echo
echo "5) KØRTE BRUD — kroppen ødelægges, og invarianterne SKAL fælde den"
BRUD_FANGET=0; BRUD_I_ALT=0
brud() { # brud <navn> <hvad testen forventer fanget> <sed-udtryk-på-kroppen> [python-erstatning]
  local navn="$1" hvad="$2" sedexpr="$3" mut="$TMP/brud.sh"
  sed -e "$sedexpr" "$KROP" > "$mut"
  if cmp -s "$KROP" "$mut"; then
    fejl "brud «$navn»: sed-udtrykket ændrede intet — bruddet er ikke indført"; return
  fi
  koer "$mut" 0
  BRUD_I_ALT=$((BRUD_I_ALT + 1))
  if invarianter > "$TMP/inv.txt"; then
    printf '   %-52s %s\n' "$navn" "IKKE fanget  ← testen er for svag"
    fejl "brud «$navn» blev IKKE fanget af invarianterne"
  else
    BRUD_FANGET=$((BRUD_FANGET + 1))
    printf '   %-52s %s\n' "$navn" "fanget: $(head -n 1 "$TMP/inv.txt" | cut -c1-70)"
    ok "brud «$navn» fanget ($hvad)"
  fi
}
printf '   %-52s %s\n' "brud" "udfald"
# a) Det kørende image slettes: fredningen af BRUGT-ids slås fra.
brud "det kørende image slettes" "ALDRIG-image forsvandt eller dæmonen afviste" \
  's/if \[ -n "\${BRUGT\[\$ID\]:-}" \]; then/if false; then/'
# b) Det forrige slettes: ingen rollback-plads.
brud "det forrige image slettes" "forrige forsvandt" \
  's/if \[ -z "\${FORRIGE\[\$repo\]:-}" \]; then/if false; then/'
# c) Et image med en STOPPET container slettes: fredningen læser kun kørende.
brud "image med stoppet container slettes (ps uden -a)" "crm:c2 / scraper forsvandt" \
  's/docker ps -aq/docker ps -q/'
# d) En volume-prune sniger sig ind.
brud "en volume-prune sniger sig ind" "forbudt docker-kald" \
  's/^\( *\)echo "── Byggecache: docker builder prune -af"/\1docker volume prune -f >\/dev\/null 2>\&1; echo "── Byggecache: docker builder prune -af"/'
# e) `docker image prune -a` i stedet for pr.-repository-reglen.
brud "docker image prune -a erstatter reglen" "forbudt docker-kald" \
  's/^\( *\)echo "── Images uden container (/\1docker image prune -a -f >\/dev\/null 2>\&1; echo "── Images uden container (/'
# f) Lokale :latest slettes uden at tjekke digests (hentet redis:latest-slags).
brud "alle :latest uden container slettes (ingen digest-tjek)" "ferm-crm-app:latest m.fl." \
  's/if \[ "\$DIGESTS" = "0" \] \&\& \[ -z "\${BEHOLD_ID\[\$ID\]:-}" \]; then/if true; then/'
echo
printf '   %d af %d brud fanget\n' "$BRUD_FANGET" "$BRUD_I_ALT"
[ "$BRUD_I_ALT" -ge 3 ] && [ "$BRUD_FANGET" -eq "$BRUD_I_ALT" ] && ok "alle indførte brud blev fanget (mindst 3 kørt)" || fejl "ikke alle brud blev fanget"

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
