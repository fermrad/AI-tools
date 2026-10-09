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
# ── S-547: production-porten ────────────────────────────────────────────────
#
# Til `ENVIRONMENT=production` er vagten en port: kun en fuld 40-tegns SHA med
# små bogstaver, og den skal findes på origin (`gh api repos/<repo>/commits/
# <sha>` → 200 med samme SHA). Testen kører kroppen mod en FALSK `gh` på PATH
# og måler:
#   4. alt andet end 40 hex fældes i production — `main`, tom, forkortelser,
#      grene, tags, store bogstaver — og fældes FØR origin spørges (falsk gh
#      tæller kald: endpointet svarer 200 på `main`, så rækkefølgen er bærende),
#   5. 422 er et nej, 404/5xx er «kunne ikke spørge» med sin egen titel og tre
#      forsøg, et forbigående 502 slipper igennem på andet forsøg, og et svar
#      med en ANDEN SHA fældes,
#   6. en squash-merget PR-head-SHA (ikke på nogen levende gren) slipper
#      igennem, når API'et svarer 200 — der er intet klon-tjek at falde i,
#   7. dev og staging er uændrede og spørger aldrig gh.
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
forventet_env = {
    "REF": "${{ inputs.checkout_ref }}",
    "ENVIRONMENT": "${{ inputs.environment }}",
    "REPO": "${{ github.repository }}",
    "GH_TOKEN": "${{ github.token }}",
}
if step.get("env", {}) != forventet_env:
    sys.exit("FEJL  ref_gate skal læse præcis %s fra env:, fik %r"
             % (forventet_env, step.get("env")))
if step.get("shell") != "bash":
    sys.exit("FEJL  ref_gate skal køre med shell: bash (kroppen bruger [[ =~ ]])")
# S-547: porten spørger API'et, ikke en klon — se hovedet i deploy-app.yml.
if any("uses" in s for s in job["steps"]):
    sys.exit("FEJL  ref_gate må ikke checke ud: et klon-tjek afviser "
             "squash-mergede PR-head-SHA'er, som origin har")
if job.get("permissions") != {"contents": "read"}:
    sys.exit("FEJL  ref_gate skal have permissions: {contents: read}, fik %r"
             % job.get("permissions"))
if "ref_gate" not in d["jobs"]["build"].get("needs", []):
    sys.exit("FEJL  build skal stå med needs: [ref_gate]")
if "needs.ref_gate.result == 'success'" not in d["jobs"]["deploy"].get("if", ""):
    sys.exit("FEJL  deploy's if skal kræve needs.ref_gate.result == 'success' "
             "— !cancelled() kører ellers videre efter en fældet vagt")
open(ud, "w", encoding="utf-8").write(step["run"])
PY
[ -s "$TMP/vagt.sh" ] || { echo "FEJL  kunne ikke klippe vagten ud af $WORKFLOW" >&2; exit 1; }

# --- falsk gh -----------------------------------------------------------------
# Logger hvert kald og svarer efter FAKE_GH. Formerne er de målte fra
# dispatch-sha.mjs (project, 18-08-2026): kendt SHA → exit 0 og .sha; opdigtet
# 40-hex → HTTP 422 «No commit found for SHA»; ukendt repo → HTTP 404.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
[ -n "${GH_TOKEN:-}" ] || { echo "gh: ingen GH_TOKEN" >&2; exit 4; }
sti="$2"; sha="${sti##*/}"
case "$FAKE_GH" in
  ok)    echo "$sha" ;;
  422)   echo "gh: No commit found for SHA: $sha (HTTP 422)" >&2; exit 1 ;;
  404)   echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  anden) echo "0000000000000000000000000000000000000000" ;;
  flak)  n="$(cat "$GH_LOG.n" 2>/dev/null || echo 0)"; echo $((n+1)) > "$GH_LOG.n"
         if [ "$n" -eq 0 ]; then echo "gh: HTTP 502: Bad Gateway" >&2; exit 1; fi
         echo "$sha" ;;
  *)     echo "falsk gh: ukendt FAKE_GH='$FAKE_GH'" >&2; exit 9 ;;
esac
GH
chmod +x "$TMP/bin/gh"

FEJL=0

# koer <miljø> <ref> <falsk gh> → sætter UD, FIK og KALD
koer() {
  : > "$TMP/gh.log"; rm -f "$TMP/gh.log.n"
  UD="$(PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" FAKE_GH="$3" REF_GATE_PAUSE=0 \
        ENVIRONMENT="$1" REF="$2" REPO="fermrad/test-app" GH_TOKEN="falsk" \
        bash "$TMP/vagt.sh" 2>&1)"; FIK=$?
  KALD="$(wc -l < "$TMP/gh.log" | tr -d ' ')"
}

# --- dev og staging: S-452's prøver, uændrede (punkt 1-3 og 7) -----------------
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

ANTAL=0
for miljoe in staging dev; do
  for p in "${PROEVER[@]}"; do
    IFS='|' read -r ref forventet hvorfor <<< "$p"
    ANTAL=$((ANTAL+1))
    koer "$miljoe" "$ref" ok
    if [ "$FIK" -ne "$forventet" ]; then
      echo "FEJL  $miljoe '$ref' gav exit $FIK, forventede $forventet ($hvorfor)"
      echo "      ud: $UD"
      FEJL=1
      continue
    fi
    if [ "$KALD" -ne 0 ]; then
      echo "FEJL  $miljoe '$ref' spurgte gh $KALD gange — dev/staging må aldrig spørge origin"
      FEJL=1
    fi
    if [ "$forventet" -eq 1 ]; then
      # Beskeden skal være en GitHub-annotation og bære sin vej videre.
      for krav in "::error" "$ref" "40" "refs/heads/"; do
        case "$UD" in
          *"$krav"*) ;;
          *) echo "FEJL  beskeden for $miljoe '$ref' mangler '$krav'"; echo "      ud: $UD"; FEJL=1;;
        esac
      done
      echo "ok    $miljoe '$ref' fælder med en læsbar besked ($hvorfor)"
    else
      echo "ok    $miljoe '$ref' slipper igennem ($hvorfor)"
    fi
  done
done

# --- production: S-547 (punkt 4-6) --------------------------------------------
FULD="1c801964f547c0b3cd4f9ecad775b35cb5fd1bcd"
# ref | falsk gh | forventet exit | forventede gh-kald | krav i beskeden (;-delt) | hvorfor
PROD=(
  "main|ok|1|0|::error;'main';grennavn;40|defaulten i alle fire apps formularer — fælder FØR origin, der ville svare 200"
  "|ok|1|0|::error;TOM;40|tom ref ville checke hændelsens gren ud uden en læselig værdi"
  "1c80196|ok|1|0|::error;1c80196;forkortet;40|den målte prod-dispatch 20-08-2026"
  "abc1234|ok|1|0|::error;forkortet|hex-grennavn: til prod hjælper refs/heads/-udvejen ikke"
  "refs/heads/main|ok|1|0|::error;refs/heads/main;grennavn|en fuld ref er stadig en gren, der flytter sig"
  "refs/heads/abc1234|ok|1|0|::error;grennavn|S-452's udvej er ingen vej til production"
  "v1.2.3|ok|1|0|::error;v1.2.3|et tag"
  "feat/noget|ok|1|0|::error;feat/noget|en PR-gren — kun staging"
  "1C801964F547C0B3CD4F9ECAD775B35CB5FD1BCD|ok|1|0|::error;store bogstaver|health rapporterer git rev-parse HEAD med små"
  "${FULD}0|ok|1|0|::error;40|41 hexcifre"
  "$FULD|ok|0|1||den fulde SHA, origin har"
  "f2a437610710715bc1b9c086e83793b7556b6ca2|ok|0|1||squash-merget PR 1191's head-SHA: ikke på main, men API'et svarer 200"
  "$FULD|422|1|1|::error;findes ikke;$FULD;fermrad/test-app|opdigtet SHA (16-08-2026)"
  "$FULD|404|1|3|::error;Kunne ikke;IKKE et nej;contents: read;HTTP 404|token uden adgang er ikke et nej om SHA'en — tre forsøg"
  "$FULD|flak|0|2||et forbigående 502 slipper igennem på andet forsøg"
  "$FULD|anden|1|1|::error;anden SHA|origin svarede med en anden SHA"
)

for p in "${PROD[@]}"; do
  IFS='|' read -r ref gh forventet kald krav hvorfor <<< "$p"
  ANTAL=$((ANTAL+1))
  koer production "$ref" "$gh"
  if [ "$FIK" -ne "$forventet" ]; then
    echo "FEJL  production '$ref' (gh=$gh) gav exit $FIK, forventede $forventet ($hvorfor)"
    echo "      ud: $UD"
    FEJL=1
    continue
  fi
  if [ "$KALD" -ne "$kald" ]; then
    echo "FEJL  production '$ref' (gh=$gh) spurgte gh $KALD gange, forventede $kald ($hvorfor)"
    FEJL=1
    continue
  fi
  if [ "$kald" -gt 0 ] && ! grep -qxF "api repos/fermrad/test-app/commits/$ref --jq .sha" "$TMP/gh.log"; then
    echo "FEJL  production '$ref' spurgte ikke kalderens repo: $(head -1 "$TMP/gh.log")"
    FEJL=1
  fi
  if [ -n "$krav" ]; then
    IFS=';' read -r -a kravliste <<< "$krav"
    for k in "${kravliste[@]}"; do
      case "$UD" in
        *"$k"*) ;;
        *) echo "FEJL  beskeden for production '$ref' (gh=$gh) mangler '$k'"; echo "      ud: $UD"; FEJL=1;;
      esac
    done
  fi
  echo "ok    production '${ref:-<tom>}' (gh=$gh) → exit $FIK, $KALD gh-kald ($hvorfor)"
done

# En nylinje i ref'en må ikke kunne smugle en ekstra workflow-kommando ind:
# fejlen skal være ÉN ::-linje.
ANTAL=$((ANTAL+1))
koer production $'main\n::warning::smuglet' ok
if [ "$FIK" -ne 1 ] || [ "$(printf '%s\n' "$UD" | grep -c '^::')" -ne 1 ]; then
  echo "FEJL  en ref med nylinje gav exit $FIK og disse ::-linjer:"; printf '%s\n' "$UD" | grep '^::'
  FEJL=1
else
  echo "ok    production med nylinje i ref'en → én ::error-linje"
fi

if [ "$FEJL" -ne 0 ]; then
  echo
  echo "REF-VAGTEN ER IKKE DEN, DEN SKAL VÆRE."
  exit 1
fi
echo
echo "Ref-vagten ok — $ANTAL prøver."
