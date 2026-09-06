#!/usr/bin/env bash
#
# Test af BYGGECACHE-oprydningen i "Diskvagt og oprydning" i
# .github/workflows/deploy-app.yml (S-365 — "De interne bokse bærer 42 GB
# byggecache — S-362's oprydning rører dem med vilje ikke", udvidet af
# S-480 — "Én apps deploy sletter naboernes byggecache — `prune -af` er
# dæmon-globalt, ikke app-lokalt").
#
# S-480 flyttede registry-vejen fra `-af` til det samme alderssnit. Blok D og
# E er dén ændrings prøve: D viser, at naboens VARME cache nu overlever en
# registry-udrulning, E at det DØDE stadig ryddes. Peger man testen på
# udgaven før (`git show 489c438:.github/workflows/deploy-app.yml`), skal D
# fejle — det er hele grunden til, at blokken kan måle noget.
#
# Hvorfor den kører mod en RIGTIG docker-dæmon og ikke mod en stub:
# hele reglen hviler på én påstand om buildkit, som ingen stub kan bekræfte —
# at `--filter until=` snitter på hvornår en cachepost SIDST BLEV BRUGT og
# ikke på hvornår den blev SKABT. Er det omvendt, rammer reglen præcis de lag,
# et on-host-byg lever af. Samme form som S-413 — "Hvert deploy efterlader et
# image på boksen — der er ingen regel for hvor mange der beholdes" brugte, og
# af samme grund: dét, der skal måles, er dæmonens adfærd.
#
# ⚠️ Fixturen skiller sine poster ad I TID. S-413 fandt undervejs, at
# `docker images` sorterer på HELE sekunder; byggecachens tidsstempler er
# finere, men snittet skal stadig ligge et sted, hvor de to sider ikke kan nå
# at falde sammen. Derfor et mellemrum på DISKVAGT_TEST_GAP sekunder mellem de
# to byg, og et snit midt imellem dem.
#
# ⚠️ Og fixturen FJERNER sine egne images igen, inden der ryddes. Det er ikke
# oprydning for pænhedens skyld: så længe et image hænger på lagene, er
# cacheposterne `Shared: true`, og en prune henter dem ikke — målt her
# 20-08-2026, hvor et `until`-snit først frigav 12,4 kB og bagefter det hele.
# En fixtur, der glemmer det, ville se ud som om reglen ikke virkede.
#
# Kroppen KLIPPES ud af workflowet frem for at blive kopieret, så testen ikke
# kan komme til at teste en forældet afskrift.
#
# ⚠️ DESTRUKTIV: kroppen kalder `docker builder prune` og `docker image prune`
# mod den dæmon, DOCKER_HOST peger på — begge er GLOBALE. Testen nægter derfor
# at køre på en dæmon, der allerede bærer byggecache eller hængende images,
# medmindre DISKVAGT_TEST_ENGANGSDAEMON=1 siger, at maskinen er en engangsboks
# (det gør CI).
#
# Kør: bash scripts/test-deploy-diskvagt-byggecache.sh [anden-deploy-app.yml]
#
# Det valgfrie argument er dét, der gør bruddet synligt: peger man testen på
# udgaven FØR reglen (fx `git show 78a0d66:.github/workflows/deploy-app.yml`),
# skal den FEJLE på præcis de tilfælde, reglen findes for — en test, der ikke
# kan fejle, måler ingenting.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"
GAP="${DISKVAGT_TEST_GAP:-10}"
BASE_IMAGE="${DISKVAGT_TEST_BASE:-alpine:3}"

TMP="$(mktemp -d)"
KOER_ID="s365-$$-$(date +%s)"
NABO_TAG="diskvagt-test-nabo:$KOER_ID"
GAMMEL_TAG="diskvagt-test-gammel:$KOER_ID"
NY_TAG="diskvagt-test-ny:$KOER_ID"
DOED_TAG="diskvagt-test-doed:$KOER_ID"
oprydning() {
  docker image rm -f "$NABO_TAG" "$GAMMEL_TAG" "$NY_TAG" "$DOED_TAG" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap oprydning EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fejl() { FAIL=$((FAIL + 1)); printf '  FEJL  %s\n' "$1"; }

# --- Klip remote-body'en ud af "Diskvagt og oprydning"-trinnet -------------
SCRIPT_BODY="$TMP/diskvagt-body.sh"
python3 - "$WORKFLOW" "$SCRIPT_BODY" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
trin = src.split("- name: Diskvagt og oprydning", 1)
if len(trin) != 2:
    sys.exit("Kunne ikke finde trinnet 'Diskvagt og oprydning' i %s." % sys.argv[1])
m = re.search(r"<< 'REMOTE'.*?\n(.*?)\n\s*REMOTE\n", trin[1], re.S)
if not m:
    sys.exit("Kunne ikke finde diskvagtens REMOTE-heredoc i %s." % sys.argv[1])
body = "\n".join(l[10:] if l.startswith(" " * 10) else l for l in m.group(1).split("\n"))
if "${{" in body:
    sys.exit("Diskvagt-body'en indeholder GitHub-udtryk — så kan den ikke testes. "
             "Send værdien ind som en navngiven tildeling på stdin i stedet "
             "(se S-447 og noten i trinnet).")
open(sys.argv[2], "w").write(body + "\n")
PY
[ -s "$SCRIPT_BODY" ] || exit 1
echo "  ok    kroppen klippet ud af $(basename "$WORKFLOW") (ingen GitHub-udtryk)"

# --- Dæmonen skal være der, og den skal være tom ---------------------------
if ! docker info >/dev/null 2>&1; then
  echo "FEJL  ingen docker-dæmon. Denne test måler dæmonens adfærd og kan ikke stubbes." >&2
  exit 1
fi
if [ "${DISKVAGT_TEST_ENGANGSDAEMON:-0}" != "1" ]; then
  CACHE_FOER="$(docker buildx du 2>/dev/null | awk -F'\t' '/^Total:/ {print $2}')"
  DANGLING="$(docker images -f dangling=true -q | wc -l | tr -d ' ')"
  if [ "${CACHE_FOER:-0B}" != "0B" ] || [ "$DANGLING" != "0" ]; then
    cat >&2 <<AFVIS
FEJL  dæmonen er ikke tom (byggecache: ${CACHE_FOER:-?}, hængende images: $DANGLING).
      Kroppen kalder GLOBALE prunes, så testen ville rydde din egen cache.
      Peg DOCKER_HOST på en engangsdæmon, eller sæt
      DISKVAGT_TEST_ENGANGSDAEMON=1 hvis maskinen er brug-og-smid-væk.
AFVIS
    exit 1
  fi
fi
if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  if ! docker pull -q "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "FEJL  kan hverken finde eller hente basis-imaget '$BASE_IMAGE'." >&2
    echo "      Sæt DISKVAGT_TEST_BASE til et image, maskinen allerede har." >&2
    exit 1
  fi
fi

# --- Fixtur: to byg med et målt mellemrum, og en nabo, der ikke må røres ---
mkdir -p "$TMP/nabo" "$TMP/gammel" "$TMP/ny"
byg() { docker build --pull=false -q -t "$2" "$TMP/$1" >/dev/null 2>&1; }

# Naboen bliver liggende som TAGGET image hele vejen. Den er kontrollen på
# punkt 2 i oprydningen: `docker image prune -f` uden `-a` må aldrig røre et
# image med et tag.
printf 'FROM %s\nRUN echo %s-nabo > /nabo\n' "$BASE_IMAGE" "$KOER_ID" > "$TMP/nabo/Dockerfile"
byg nabo "$NABO_TAG" || { echo "FEJL  kunne ikke bygge nabo-fixturen" >&2; exit 1; }

# `delt` bygges af BEGGE — det er posten, der er SKABT før snittet og BRUGT
# efter det. Overlever den ikke, snitter reglen på skabelsestidspunktet, og så
# er den forkert til en boks, der bygger.
printf 'FROM %s\nRUN echo %s-delt > /delt\nRUN echo %s-gammel > /gammel\n' \
  "$BASE_IMAGE" "$KOER_ID" "$KOER_ID" > "$TMP/gammel/Dockerfile"
printf 'FROM %s\nRUN echo %s-delt > /delt\nRUN echo %s-ny > /ny\n' \
  "$BASE_IMAGE" "$KOER_ID" "$KOER_ID" > "$TMP/ny/Dockerfile"

byg gammel "$GAMMEL_TAG" || { echo "FEJL  kunne ikke bygge gammel-fixturen" >&2; exit 1; }
docker image rm "$GAMMEL_TAG" >/dev/null 2>&1 || true
T_GAMMEL="$(date +%s)"

sleep "$GAP"

byg ny "$NY_TAG" || { echo "FEJL  kunne ikke bygge ny-fixturen" >&2; exit 1; }
docker image rm "$NY_TAG" >/dev/null 2>&1 || true
T_NY="$(date +%s)"

# --- Aflæsning -------------------------------------------------------------
# `docker buildx du --format json` findes ikke i alle buildx-udgaver (macOS
# 0.21 kan det ikke, boksene kan), så der læses fra --verbose, som begge kan.
poster() { docker buildx du --verbose 2>/dev/null | sed -n 's/^Description:[[:space:]]*//p'; }
har_post()   { poster | grep -q -- "$1"; }
har_image()  { docker image inspect "$1" >/dev/null 2>&1; }

krav() { # krav <beskrivelse> <0=skal-findes|1=skal-væk> <markør>
  if har_post "$3"; then [ "$2" = "0" ] && ok "$1" || fejl "$1 (posten er der stadig)"
  else [ "$2" = "1" ] && ok "$1" || fejl "$1 (posten er væk)"; fi
}

# S-447: kroppen læser ikke længere `$1..$5`. Værdierne kommer som NAVNGIVNE
# tildelinger, runneren skriver foran kroppen på stdin, så en tom værdi ikke
# kan forsvinde i ssh's fladning. Testen kalder derfor kroppen med de samme
# navne i miljøet — samme binding, uden en ssh imellem.
koer() { # koer <registry_mode> <builder_keep_hours>
  APP_DIR="$TMP" \
  IMAGE_REPO="" \
  IMAGE_KEEP=3 \
  REGISTRY_MODE="$1" \
  BUILDER_KEEP_HOURS="$2" \
  bash "$SCRIPT_BODY" 2>&1
}

echo
echo "A) Reglen er SLUKKET som standard (builder_keep_hours: 0)"
UD="$(koer 0 0)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem" || fejl "trinnet fejlede (exit $RC)"
grep -q "urørt" <<<"$UD" && ok "loggen siger at cachen er urørt" || fejl "loggen nævner ikke at cachen er urørt"
krav "gammel cachepost overlever" 0 "$KOER_ID-gammel"
krav "delt cachepost overlever"   0 "$KOER_ID-delt"
krav "ny cachepost overlever"     0 "$KOER_ID-ny"
har_image "$NABO_TAG" && ok "nabo-imaget overlever" || fejl "nabo-imaget forsvandt"

echo
echo "B) En ugyldig værdi fælder trinnet FØR noget er rørt"
UD="$(koer 0 'en uge')"; RC=$?
[ "$RC" -ne 0 ] && ok "trinnet stopper (exit $RC)" || fejl "trinnet gik igennem på en ugyldig værdi"
grep -q "builder_keep_hours" <<<"$UD" && ok "beskeden nævner inputtet" || fejl "beskeden nævner ikke inputtet"
krav "intet blev ryddet undervejs" 0 "$KOER_ID-gammel"

echo
echo "C) Reglen er SLÅET TIL — snittet ligger mellem de to byg"
# Snittet midt imellem: alt ubrugt siden før midtpunktet skal væk, alt brugt
# efter skal blive. Timer og ikke sekunder, fordi det er inputtets enhed —
# brøkdelen er dét, der gør en uge-regel prøvbar på ti sekunder.
NU="$(date +%s)"
MIDT=$(( (T_GAMMEL + T_NY) / 2 ))
TIMER="$(awk -v s=$(( NU - MIDT )) 'BEGIN { printf "%.6f", s / 3600 }')"
echo "     mellemrum ${GAP}s, snit $(( NU - MIDT ))s tilbage i tiden = ${TIMER} timer"
UD="$(koer 0 "$TIMER")"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem" || fejl "trinnet fejlede (exit $RC)"
krav "gammel cachepost er RYDDET"                        1 "$KOER_ID-gammel"
krav "delt cachepost overlever (skabt før, brugt efter)" 0 "$KOER_ID-delt"
krav "ny cachepost overlever"                            0 "$KOER_ID-ny"
har_image "$NABO_TAG" && ok "nabo-imaget overlever" || fejl "nabo-imaget forsvandt"

echo
echo "D) registry-tilstand FEJER IKKE naboens varme cache væk (S-480)"
# Dette er punktets kerne, og det er dét, `-af` gjorde forkert. `docker
# builder prune -af` er DÆMON-GLOBALT: det rammer værtens cache, ikke appens.
# `delt` og `ny` er lige blevet BRUGT af fixturens byg — de er præcis det, en
# nabo-app ville genbruge ved sit næste byg. Uden et tal fra appen falder
# registry-vejen tilbage på husets default (168 timer), og så skal begge stå.
#
# ⚠️ Peger man testen på udgaven FØR S-480, skal DENNE blok fejle på begge
# krav: dér ryddede `-af` dem uanset alder. Det er sådan, testen kan fælde
# den gamle adfærd.
UD="$(koer 1 0)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem" || fejl "trinnet fejlede (exit $RC)"
grep -q "168 timer" <<<"$UD" && ok "loggen nævner husets registry-default" || fejl "loggen nævner ikke defaulten på 168 timer"
grep -q -- "-af" <<<"$UD" && fejl "loggen nævner stadig -af" || ok "ingen -af i registry-vejen"
krav "delt cachepost OVERLEVER (varm, ville være røget på -af)" 0 "$KOER_ID-delt"
krav "ny cachepost OVERLEVER (varm, ville være røget på -af)"   0 "$KOER_ID-ny"
har_image "$NABO_TAG" && ok "nabo-imaget overlever stadig" || fejl "nabo-imaget forsvandt"

echo
echo "E) registry-tilstand rydder stadig det DØDE"
# Mildere er ikke det samme som tandløs: S-362's grund — "staging-boksen løb
# tør for disk efter ti deploys" — står ved magt, og reglen skal stadig hente
# det, ingen har rørt. Frisk fixtur, fordi C allerede tog `gammel`.
mkdir -p "$TMP/doed"
printf 'FROM %s\nRUN echo %s-doed > /doed\n' "$BASE_IMAGE" "$KOER_ID" > "$TMP/doed/Dockerfile"
byg doed "$DOED_TAG" || { echo "FEJL  kunne ikke bygge doed-fixturen" >&2; exit 1; }
docker image rm "$DOED_TAG" >/dev/null 2>&1 || true
T_DOED="$(date +%s)"

sleep "$GAP"

# Genbyg `ny`: det RØRER `delt` og `ny` igen, så deres "sidst brugt"-ur
# nulstilles og lander på den unge side af snittet. Det er hele pointen med
# until= — den varme post ældes aldrig ud.
byg ny "$NY_TAG" || { echo "FEJL  kunne ikke genbygge ny-fixturen" >&2; exit 1; }
docker image rm "$NY_TAG" >/dev/null 2>&1 || true
T_NY2="$(date +%s)"

NU="$(date +%s)"
MIDT2=$(( (T_DOED + T_NY2) / 2 ))
TIMER2="$(awk -v s=$(( NU - MIDT2 )) 'BEGIN { printf "%.6f", s / 3600 }')"
echo "     mellemrum ${GAP}s, snit $(( NU - MIDT2 ))s tilbage i tiden = ${TIMER2} timer"
UD="$(koer 1 "$TIMER2")"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem" || fejl "trinnet fejlede (exit $RC)"
krav "død cachepost er RYDDET"                     1 "$KOER_ID-doed"
krav "delt cachepost overlever (brugt efter snit)" 0 "$KOER_ID-delt"
krav "ny cachepost overlever"                      0 "$KOER_ID-ny"
har_image "$NABO_TAG" && ok "nabo-imaget overlever stadig" || fejl "nabo-imaget forsvandt"

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
