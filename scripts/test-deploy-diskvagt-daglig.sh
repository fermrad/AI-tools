#!/usr/bin/env bash
#
# Test af den daglige diskvagt, .github/workflows/diskvagt.yml (S-1290 —
# "Diskvagt på alle bokse: journald får et loft, deployet måler journald, og
# en daglig vagt melder over 85 %").
#
# Den daglige vagt findes, fordi deployets diskvagt kun måler, NÅR der
# deployes. 09-10-2026 løb den interne prod-boks fuld af journald-journaler,
# og intet havde råbt, før Postgres svarede «No space left on device».
#
# Testen måler fire ting:
#
#   1. SAMME MÅLEKROP. Kroppen mellem `MÅLEKROP START` og `MÅLEKROP SLUT` er
#      ORD FOR ORD ens i deploy-app.yml og diskvagt.yml. En genbrugsworkflow
#      kan ikke læse en scriptfil fra AI-tools (runneren har kun kalderens
#      checkout), så kroppen står to steder — og denne sammenligning er det,
#      der gør to kopier forsvarlige. Samme form som backup-kroppen i
#      backup-db.yml / scripts/test-deploy-backup.sh.
#   2. KUN MÅLING. Ingen prune, ingen vacuum, ingen rm i diskvagt.yml's trin.
#   3. TÆRSKLERNE, strengt større end: 85 % er grøn, 86 % gul (::warning::,
#      exit 0), 90 % stadig gul, 91 % rød (::error::, exit 1). En boks, der
#      ikke svarer, eller en df, der ikke kan læses, er RØD — vagten fejler
#      LUKKET.
#   4. SUMMARYEN bærer procenten, status og hvad der fylder (journald,
#      Docker-posterne).
#
# Kroppen KLIPPES ud af workflowet frem for at blive kopieret. ssh, df,
# docker og journalctl er falske; den falske ssh kører den fjerne krop
# lokalt, præcis som sshd ville (`$SHELL -c <streng>`, stdin videre).
#
# Kør: bash scripts/test-deploy-diskvagt-daglig.sh [anden-diskvagt.yml] [anden-deploy-app.yml]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISKVAGT="${1:-$REPO_ROOT/.github/workflows/diskvagt.yml}"
DEPLOY="${2:-$REPO_ROOT/.github/workflows/deploy-app.yml}"
MAAL_TRIN="Mål disken"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runner-temp"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fejl() { FAIL=$((FAIL + 1)); printf '  FEJL  %s\n' "$1"; }

[ -f "$DISKVAGT" ] || { echo "FEJL  $DISKVAGT findes ikke."; exit 1; }

echo "1) Samme målekrop i deploy-app.yml og diskvagt.yml"
klip_maalekrop() { # klip_maalekrop <workflow> <udfil>
  python3 - "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^([ \t]*)# ── MÅLEKROP START.*?\n(.*?)^[ \t]*# ── MÅLEKROP SLUT", src, re.S | re.M)
if not m:
    sys.exit("Ingen MÅLEKROP START/SLUT-markører i %s." % sys.argv[1])
ind = len(m.group(1))
krop = "\n".join(l[ind:] if l.startswith(" " * ind) else l for l in m.group(2).split("\n"))
if "${{" in krop:
    sys.exit("Målekroppen i %s indeholder GitHub-udtryk." % sys.argv[1])
open(sys.argv[2], "w", encoding="utf-8").write(krop)
PY
}
if klip_maalekrop "$DEPLOY" "$TMP/krop-deploy.sh" && klip_maalekrop "$DISKVAGT" "$TMP/krop-daglig.sh"; then
  if diff -u "$TMP/krop-deploy.sh" "$TMP/krop-daglig.sh" > "$TMP/krop.diff"; then
    ok "målekroppen er ORD FOR ORD ens ($(wc -l < "$TMP/krop-deploy.sh" | tr -d ' ') linjer)"
  else
    fejl "målekroppen er FORSKELLIG i de to filer — rettes den ene, skal den anden med:"
    sed 's/^/        /' "$TMP/krop.diff"
  fi
  for f in maal_pct vis_df vis_poster; do
    grep -q "^$f() {" "$TMP/krop-daglig.sh" && ok "målekroppen definerer $f" || fejl "målekroppen mangler $f"
  done
else
  fejl "målekroppen kunne ikke klippes ud af begge filer"
fi

echo
echo "2) Statisk: workflow_call, defaults og KUN måling"
if python3 - "$DISKVAGT" "$MAAL_TRIN" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
on = wf.get(True) or wf.get("on")   # PyYAML læser `on:` som True
fejl = []
inp = (on or {}).get("workflow_call", {}).get("inputs", {})
if not inp.get("environment", {}).get("required"):
    fejl.append("input 'environment' er ikke påkrævet")
if inp.get("warn_percent", {}).get("default") != 85:
    fejl.append("warn_percent har ikke default 85")
if inp.get("fail_percent", {}).get("default") != 90:
    fejl.append("fail_percent har ikke default 90")
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
navne = [s.get("name") for s in steps]
if sys.argv[2] not in navne:
    fejl.append("trinnet '%s' findes ikke" % sys.argv[2])
else:
    if "${{" in steps[navne.index(sys.argv[2])]["run"]:
        fejl.append("måletrinnets run: indeholder GitHub-udtryk")
oprydning = re.compile(r"\bprune\b|--vacuum|\brm\s|\bimage\s+rm\b|\bvolume\s+rm\b|\btruncate\b")
for s in steps:
    for linje in (s.get("run") or "").splitlines():
        if linje.strip().startswith("#"):
            continue
        if oprydning.search(linje):
            fejl.append("'%s' rydder op: %s" % (s.get("name"), linje.strip()))
if fejl:
    print("\n".join(fejl)); sys.exit(1)
PY
then
  ok "workflow_call med environment (påkrævet), warn 85, fail 90; ingen oprydning i nogen run:"
else
  fejl "diskvagt.yml's grænseflade eller måle-kun-regel er brudt (se ovenfor)"
fi

# --- falske værktøjer ------------------------------------------------------
cat > "$TMP/bin/ssh" <<'STUB'
#!/usr/bin/env bash
[ "${FALSK_SSH_NEDE:-0}" = "1" ] && { echo "ssh: connect to host boks.example port 22: Connection timed out" >&2; exit 255; }
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
# df: FALSK_PCT er forbruget; FALSK_DF_RC != 0 er en df, der ikke kan læses.
cat > "$TMP/bin/df" <<'STUB'
#!/usr/bin/env bash
[ "${FALSK_DF_RC:-0}" != "0" ] && { echo "df: cannot read table of mounted file systems" >&2; exit "$FALSK_DF_RC"; }
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
if [ "$1" = "-hP" ]; then
  echo "/dev/sda1 75G 64G 11G ${FALSK_PCT}% /"
else
  echo "/dev/sda1 78643200 67108864 11534336 ${FALSK_PCT}% /"
fi
STUB
cat > "$TMP/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  --disk-usage) echo "Archived and active journals take up 488.0M in the file system." ;;
  *) echo "journalctl $* er ikke tilladt i en måle-vagt" >&2; exit 99 ;;
esac
STUB
cat > "$TMP/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "info -f")   echo "/" ;;
  "system df") printf 'Images|12.4GB|8.1GB (65%%)\nContainers|210MB|0B (0%%)\nLocal Volumes|3.2GB|0B (0%%)\nBuild Cache|4.7GB|4.7GB\n' ;;
  *) echo "docker $* er ikke tilladt i en måle-vagt" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

# --- klip måletrinnet ud ---------------------------------------------------
MAAL_SH="$TMP/maal.sh"
python3 - "$DISKVAGT" "$MAAL_TRIN" "$MAAL_SH" <<'PY' || { echo "FEJL  kunne ikke klippe '$MAAL_TRIN' ud"; exit 1; }
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
st = next((s for s in steps if s.get("name") == sys.argv[2]), None)
if st is None:
    sys.exit("Trinnet '%s' findes ikke." % sys.argv[2])
open(sys.argv[3], "w", encoding="utf-8").write(st["run"] + "\n")
PY

koer() { # koer <pct> [warn] [fail] — sætter UD, RC og SUM
  local summary="$TMP/summary.md"
  : > "$summary"
  UD="$( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" \
           GITHUB_STEP_SUMMARY="$summary" FALSK_PCT="$1" \
           WARN_PCT="${2:-85}" FAIL_PCT="${3:-90}"
         bash "$MAAL_SH" 2>&1 )"
  RC=$?
  SUM="$(cat "$summary")"
}
har()     { grep -qF -- "$2" <<<"$1"; }
groen()   { # groen <pct>
  koer "$1"
  [ "$RC" -eq 0 ] && ! har "$UD" "::warning" && ! har "$UD" "::error" \
    && ok "$1 % er grøn (exit 0, ingen annotation)" || fejl "$1 % skulle være grøn — exit $RC: $(grep '::' <<<"$UD")"
}
gul()     { # gul <pct>
  koer "$1"
  [ "$RC" -eq 0 ] && har "$UD" "::warning title=Disken på production-boksen fylder ($1 %)" && ! har "$UD" "::error" \
    && ok "$1 % er gul (::warning::, exit 0)" || fejl "$1 % skulle være gul — exit $RC: $(grep '::' <<<"$UD")"
}
roed()    { # roed <pct>
  koer "$1"
  [ "$RC" -eq 1 ] && har "$UD" "::error title=Disken på production-boksen er næsten fuld ($1 %)" \
    && ok "$1 % er rød (::error::, exit 1)" || fejl "$1 % skulle være rød — exit $RC: $(grep '::' <<<"$UD")"
}

echo
echo "3) Tærsklerne — strengt større end, warn 85 / fail 90"
groen 50
groen 85
gul 86
gul 90
roed 91
roed 100

echo
echo "   … og en app kan flytte dem"
koer 75 70 80
[ "$RC" -eq 0 ] && har "$UD" "::warning" && ok "75 % med warn 70 / fail 80 er gul" || fejl "75 % med warn 70 / fail 80 er ikke gul (exit $RC)"
koer 81 70 80
[ "$RC" -eq 1 ] && har "$UD" "::error" && ok "81 % med warn 70 / fail 80 er rød" || fejl "81 % med warn 70 / fail 80 er ikke rød (exit $RC)"
koer 50 85 'halvfems'
[ "$RC" -eq 1 ] && har "$UD" "::error title=Ugyldig tærskel" && ok "en tærskel, der ikke er et tal, fælder vagten" || fejl "en ugyldig tærskel gik igennem (exit $RC)"

echo
echo "4) Fejler LUKKET"
UD="$( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" \
         GITHUB_STEP_SUMMARY="$TMP/summary.md" FALSK_PCT=50 FALSK_SSH_NEDE=1 WARN_PCT=85 FAIL_PCT=90
       bash "$MAAL_SH" 2>&1 )"; RC=$?
[ "$RC" -eq 1 ] && har "$UD" "::error title=Diskvagten kunne ikke måle production-boksen" \
  && ok "en boks, der ikke svarer, er rød" || fejl "en boks, der ikke svarer, gav exit $RC: $(grep '::' <<<"$UD")"
UD="$( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" \
         GITHUB_STEP_SUMMARY="$TMP/summary.md" FALSK_PCT=50 FALSK_DF_RC=1 WARN_PCT=85 FAIL_PCT=90
       bash "$MAAL_SH" 2>&1 )"; RC=$?
# df fejler: kroppens `set -e` dør i vis_df, før ##DISK_PCT skrives — og
# runneren skal da kalde det rødt, ikke grønt.
[ "$RC" -eq 1 ] && har "$UD" "::error title=Diskvagten kunne ikke måle production-boksen" \
  && ok "en df, der ikke kan læses, er rød" || fejl "en ulæselig df gav exit $RC: $(grep '::' <<<"$UD")"
har "$(cat "$TMP/summary.md")" "KUNNE IKKE MÅLE" && ok "summaryen siger 'KUNNE IKKE MÅLE'" || fejl "summaryen siger ikke, at målingen fejlede"

echo
echo "5) Summaryen bærer tallene"
koer 87
har "$SUM" "## Diskvagt — production: 87 % (ADVARSEL — over 85 %)" && ok "overskrift med miljø, procent og status" || fejl "overskriften mangler. Fik: $(head -n 1 <<<"$SUM")"
grep -Eq '^  journald +488\.0M$' <<<"$SUM" && ok "journald (488.0M) står i summaryen" || fejl "journald står ikke i summaryen"
grep -Eq '^  docker images +12\.4GB' <<<"$SUM" && ok "docker images står i summaryen" || fejl "docker images står ikke i summaryen"
grep -Eq '^  docker build cache +4\.7GB' <<<"$SUM" && ok "byggecachen står i summaryen" || fejl "byggecachen står ikke i summaryen"
grep -Eq '^  docker local volumes +3\.2GB' <<<"$SUM" && ok "volumes står i summaryen" || fejl "volumes står ikke i summaryen"
grep -Eq '^  / +87% brugt' <<<"$SUM" && ok "df-linjen for / står i summaryen" || fejl "df-linjen står ikke i summaryen"
har "$SUM" "##DISK_PCT" && fejl "maskinlinjen ##DISK_PCT lækker ind i summaryen" || ok "ingen maskinlinjer i summaryen"
har "$UD" "ikke tilladt i en måle-vagt" && fejl "vagten kaldte en kommando, der ændrer boksen" || ok "vagten kaldte kun målende kommandoer"

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
