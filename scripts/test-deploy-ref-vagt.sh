#!/usr/bin/env bash
#
# Test af ref-vagten i .github/workflows/deploy-app.yml (project S-452).
#
# Vagten findes, fordi `actions/checkout` slår en FORKORTET commit-SHA op som
# et grennavn. Målt 20-08-2026 på en prod-dispatch af project med
# `ref=1c80196`: `+refs/heads/1c80196`, tre forsøg, 35 sekunder, og til sidst
# `The process '/usr/bin/git' failed with exit code 1` — en fejl, der ikke
# nævner refs med et ord.
#
# Testen måler TRE ting, og den tredje er den, der gør de to første ærlige:
#   1. en forkortet SHA fælder,
#   2. den fulde 40-tegns SHA, grene, tags og fulde refs slipper igennem, og
#   3. beskeden bærer stadig sin VEJ VIDERE — de fulde 40 tegn OG
#      refs/heads-udvejen. En vagt, der fælder med en besked, man ikke kan
#      handle på, har blot flyttet den ulæselige fejl et trin frem.
#
# Punkt 2 er ikke pynt: en vagt, der fælder et lovligt grennavn som `main`
# eller `feat/x`, ville brække alle fire apps udrulning.
#
# `abc1234` står med vilje som en FORVENTET falsk positiv. Et grennavn på 7-39
# hexcifre er lovligt for git, og vagten fælder det. Valget er truffet — se
# begrundelsen i deploy-app.yml — og det står som en prøve her, så det er en
# MÅLT afvejning og ikke en overraskelse for den næste, der læser regexen.
#
# Kroppen KLIPPES ud af workflowet frem for at blive kopieret, så testen ikke
# kan komme til at teste en forældet afskrift.
#
# Kør: bash scripts/test-deploy-ref-vagt.sh [anden-deploy-app.yml]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- klip kroppen ud af workflowet ------------------------------------------
python3 - "$WORKFLOW" "$TMP/vagt.sh" <<'PY'
import sys, yaml
wf, ud = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(wf, encoding="utf-8"))
job = d["jobs"]["ref_gate"]
steps = [s for s in job["steps"] if "run" in s]
if len(steps) != 1:
    sys.exit("FEJL  ref_gate har %d run-trin, forventede 1" % len(steps))
step = steps[0]
if "${{" in step["run"]:
    sys.exit("FEJL  ref_gate interpolerer ${{ }} ind i run-blokken. "
             "Værdien skal komme fra env: og læses som \"$REF\" (S-411/S-418).")
if list(step.get("env", {})) != ["REF"]:
    sys.exit("FEJL  ref_gate skal læse præcis én env-værdi, REF")
open(ud, "w", encoding="utf-8").write(step["run"])
PY
[ -s "$TMP/vagt.sh" ] || { echo "FEJL  kunne ikke klippe vagten ud af $WORKFLOW" >&2; exit 1; }

FEJL=0
# ref | forventet exit (1 = fælder, 0 = slipper igennem) | hvorfor
PROEVER=(
  "1c80196|1|den målte prod-dispatch 20-08-2026"
  "48147db|1|formen DevHubs get_deployments svarer"
  "f25a38e|1|formen commit-overskrifterne viser"
  "DEADBEEF|1|samme fejl, indsat med store bogstaver"
  "1c801964f547c0b3cd4f9ecad775b35cb5fd1bcd|0|den fulde SHA, genkørslen brugte"
  "main|0|defaulten i alle fire apps deploy.yml"
  "staging|0|7 tegn, men ikke hex"
  "dev|0|miljøgrenen"
  "v1.2.3|0|et tag"
  "feat/noget|0|et almindeligt grennavn"
  "s452-ref-vagt|0|denne grens eget navn"
  "refs/heads/abc1234|0|UDVEJEN for et hex-grennavn"
  "refs/tags/abc1234|0|samme udvej for et tag"
  "abc1234|1|FORVENTET falsk positiv — se hovedet"
  "1c801964f547c0b3cd4f9ecad775b35cb5fd1bcd0|0|41 hexcifre er ingen SHA"
)

for p in "${PROEVER[@]}"; do
  IFS='|' read -r ref forventet hvorfor <<< "$p"
  ud="$(REF="$ref" bash "$TMP/vagt.sh" 2>&1)"; fik=$?
  if [ "$fik" -ne "$forventet" ]; then
    echo "FEJL  '$ref' gav exit $fik, forventede $forventet ($hvorfor)"
    echo "      ud: $ud"
    FEJL=1
    continue
  fi
  if [ "$forventet" -eq 1 ]; then
    # Beskeden skal være en GitHub-annotation og bære sin vej videre.
    for krav in "::error" "$ref" "40" "refs/heads/"; do
      case "$ud" in
        *"$krav"*) ;;
        *) echo "FEJL  beskeden for '$ref' mangler '$krav'"; echo "      ud: $ud"; FEJL=1;;
      esac
    done
    echo "ok    '$ref' fælder med en læsbar besked ($hvorfor)"
  else
    echo "ok    '$ref' slipper igennem ($hvorfor)"
  fi
done

if [ "$FEJL" -ne 0 ]; then
  echo
  echo "REF-VAGTEN ER IKKE DEN, DEN SKAL VÆRE."
  exit 1
fi
echo
echo "Ref-vagten ok — ${#PROEVER[@]} prøver."
