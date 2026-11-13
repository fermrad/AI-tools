#!/usr/bin/env bash
# Prøve af udgiv-app.yml's logik (S-1633 «Udgivelse uden laptop: fælles
# workflow «udgiv-app.yml» i AI-tools med godkendelse via etiket»).
#
# 1. scripts/udgiv/test_udgiv.py skal være grøn mod den rigtige udgiv.py.
#    Måletabellen står i prøvens hoved.
# 2. BRUD: hvert brud er en bevidst ødelagt kopi af udgiv.py. Prøven SKAL
#    fælde dem alle — en prøve, der ikke kan se bruddet, måler ingenting.
#    Erstatningen skal findes præcis én gang, ellers er bruddet forældet,
#    og scriptet fejler i stedet for at bestå tavst. Er en prøve navngivet
#    (4. argument), skal netop den være blandt dem, der fælder bruddet.
# 3. Workflowet skal være gyldig YAML og bruge GITHUB_TOKEN alene.
set -u
cd "$(dirname "$0")/.."
FEJL=0
ok()  { echo "ok   - $*"; }
nej() { echo "FEJL - $*"; FEJL=1; }

if python3 -I scripts/udgiv/test_udgiv.py 2>/tmp/udgiv-proeve.$$; then
  ok "prøven er grøn mod udgiv.py ($(grep -oE 'Ran [0-9]+ tests' /tmp/udgiv-proeve.$$))"
else
  cat /tmp/udgiv-proeve.$$; nej "prøven er rød mod udgiv.py"
fi
rm -f /tmp/udgiv-proeve.$$

brud() { # navn  gammel  ny  [prøven, der skal fælde det]
  local dir; dir=$(mktemp -d)
  if ! python3 -I - "$dir" "$2" "$3" <<'PY'
import sys
d, gammel, ny = sys.argv[1:]
s = open("scripts/udgiv/udgiv.py").read()
if s.count(gammel) != 1:
    sys.exit(f"erstatningen findes {s.count(gammel)} gange")
open(f"{d}/udgiv.py", "w").write(s.replace(gammel, ny))
PY
  then nej "brud $1: kunne ikke laves (forældet?)"; rm -rf "$dir"; return; fi
  local ud; ud=$(UDGIV_MODUL_DIR="$dir" python3 -I scripts/udgiv/test_udgiv.py 2>&1)
  if [ $? = 0 ]; then
    nej "brud $1 blev IKKE fældet"
  elif [ -n "${4:-}" ] && ! printf '%s\n' "$ud" | grep -Eq "^(FAIL|ERROR): $4 "; then
    nej "brud $1 fældes, men ikke af $4"
  else
    ok "brud $1 fældes${4:+ af $4}"
  fi
  rm -rf "$dir"
}

brud "(a) prod-ja sat af et login uden for listen tæller" \
  '    if not login or login not in startere:' \
  '    if not login:' \
  test_g2_sat_af_en_uden_for_listen
brud "(b) en commit efter den godkendte PR udgives" \
  '        top = graense
' \
  '        top = hoved
' \
  test_g1_kun_til_og_med_den_godkendte_pr
brud "(c) en datamigrering uden data-ja udgives" \
  'blok = [(c, f) for c in linje for f in blokerende_data(m, c, startere)]' \
  'blok = []' \
  test_d1_uden_data_ja
brud "(d1) fast UTC+2 i stedet for Europe/Copenhagen (sommer-/vintertid)" \
  '    tz = ZoneInfo(slot_tz)' \
  '    tz = timezone(timedelta(hours=2))' \
  test_s1_vinter
brud "(d2) slottet regnes fra starttiden, ikke den planlagte tid" \
  '    lokal = planlagt.astimezone(tz)' \
  '    lokal = nu_utc.astimezone(tz)' \
  test_s5_forsinket_over_timeskiftet
brud "(e) kandidaten skal kun være grøn på CI ELLER staging" \
  'return ci == "success" and dep == "success", ci, dep' \
  'return ci == "success" or dep == "success", ci, dep' \
  test_k2_groen_paa_hver_sin
brud "(f) en kørsel, der stoppede i Setup SSH, rødlistes med det samme" \
  'if not koert or foerste in FOER_BOKSEN:' \
  'if not koert:' \
  test_e2_setup_ssh
brud "(g) slottet tjekkes ikke for en tidligere udgivelse" \
  '    if s == "brugt":' \
  '    if False:' \
  test_l1_slot_brugt
brud "(h) prod-ja sat før et senere push tæller som godkendelse" \
  '    if tid <= push:' \
  '    if False:' \
  test_p1_push_efter_etiketten
brud "(i) sidste push måles på commit-datoen, så en falsk ældre dato slipper igennem" \
  '    return min(tider) if tider else None' \
  '    return m.git("log", "-1", "--format=%cI", sha).strip()' \
  test_i1_falsk_aeldre_commit_dato
brud "(j) en datafil i et direkte push udgives" \
  'kræver manuel prod-start af en fra prod-startere.txt")
            return blok' \
  'kræver manuel prod-start af en fra prod-startere.txt")
            return []' \
  test_j1_datafil_i_direkte_push

W=.github/workflows/udgiv-app.yml
if python3 -c "import yaml,sys; yaml.safe_load(open('$W'))" 2>/dev/null; then ok "$W er gyldig YAML"; else nej "$W er ikke gyldig YAML"; fi
if grep -nE 'secrets\.' "$W" | grep -v 'secrets.GITHUB_TOKEN' | grep -q .; then nej "$W bruger andre hemmeligheder end GITHUB_TOKEN"; else ok "$W bruger kun GITHUB_TOKEN"; fi
if grep -q 'write-all\|contents: write' "$W"; then nej "$W beder om skriveadgang til indhold"; else ok "$W har ingen contents: write"; fi

[ "$FEJL" = 0 ] && echo "ALLE OK" || { echo "NOGET FEJLEDE"; exit 1; }
