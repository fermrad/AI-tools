#!/usr/bin/env bash
#
# Test af, hvordan diskvagtens værdier NÅR FREM til den fjerne shell i
# .github/workflows/deploy-app.yml (S-447 — "Diskvagten i den delte
# deploy-workflow er brækket for ALLE on-host-apps — et tomt argument
# forsvinder i ssh's fladning").
#
# Målt 20-08-2026 på en RIGTIG staging-udrulning af area51 (S-357):
#
#     Diskvagt og oprydning
#     bash: line 2: $4: unbound variable
#
# ssh(1) samler sine restargumenter med mellemrum imellem, og sshd kører
# resultatet som `$SHELL -c <streng>`. Strengen parses altså forfra på den
# anden maskine. `IMAGE_REPO` er TOM pr. konstruktion i on-host-tilstand
# (`build`-jobbet, der sætter den, springes over), og et tomt argument
# efterlader ingenting i den sammensatte streng: resten rykker en plads ned,
# den sidste variabel bliver aldrig sat, og `set -u` dræber scriptet — FØR
# backup, rsync, skema og containere.
#
# Testen måler tre ting, og de er tre forskellige påstande:
#
#   1. DEN GAMLE FORM FÆLDES. Positionsargumenter over ssh + tom `IMAGE_REPO`
#      giver `unbound variable`. En prøve, der ikke kan vise fejlen, beviser
#      ikke, at rettelsen retter noget.
#   2. DEN NYE FORM BESTÅR med præcis samme tomme værdi, og tomheden ANKOMMER
#      som tomhed — ikke som en nabo, der er rykket en plads ned.
#   3. REGISTRY-KONTROLLEN. Med en IKKE-tom `IMAGE_REPO` består BEGGE former.
#      Det er dén kontrol, der gør målingen troværdig: den viser, at det er
#      ARGUMENTET, der forsvinder, og ikke miljøet, testen kører i. Det var
#      også derfor, ingen opdagede fejlen — project kører `registry`.
#
# Plus en statisk vagt: kroppen må ikke læse positionsparametre igen. `%q`
# (#65) gjorde tomheden synlig som `''` og virkede, men lod kanalen stå, hvor
# argument N's betydning afhænger af, at 1..N-1 alle overlevede fladningen —
# og S-365 hængte allerede en femte værdi på halen.
#
# Kroppen KLIPPES ud af workflowet frem for at blive kopieret, så testen ikke
# kan komme til at teste en forældet afskrift. Der er ingen docker-dæmon og
# ingen boks involveret: det, der måles, er ssh's sammensætning, og den kan en
# stub gengive ordret.
#
# Kør: bash scripts/test-deploy-diskvagt-fladning.sh [anden-deploy-app.yml]
#
# Det valgfrie argument er dét, der gør bruddet synligt fra den anden side —
# en test, der ikke kan fejle, måler ingenting. Målt 06-09-2026:
#
#   21f735c (formen fra 20-08, FØR #65)   9 ok, 7 fejl
#   d38582ce (pinnen tre apps står på i   14 ok, 2 fejl
#             dag: #65's `printf %q` på
#             de samme positionsargumenter)
#   denne PR                              16 ok, 0 fejl
#
# ⚠️ Læs de to tal for sig. `d38582ce` består punkt 2 og 3 — #65 lukkede
# udfaldet, og ingen app er brækket i dag. De to fejl er den STATISKE vagt:
# kanalen er stadig positionel, og S-365 hængte allerede en femte værdi på
# halen. Det er dén, denne PR lukker.
#
# ⚠️ Peger man på en fil fra FØR S-365 (fx 78a0d66), afbrydes punkt 2 og 3 med
# "env: mangler BUILDER_KEEP_HOURS". Det er ikke en måling af den fil — den
# æra havde kun fire værdier.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

APP_DIR_SUB="$TMP/app"; mkdir -p "$APP_DIR_SUB" "$TMP/runner-temp"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fejl() { FAIL=$((FAIL + 1)); printf '  FEJL  %s\n' "$1"; }

# --- falsk ssh: samler argumenterne og lader en shell parse dem forfra ------
# Præcis det, sshd gør: `$SHELL -c <streng>`. Stdin går uændret videre, så
# `bash -s` læser sin krop derfra, som den ville over en rigtig forbindelse.
cat > "$TMP/ssh" <<'STUB'
#!/usr/bin/env bash
# Flag spises kun FØR værten. Alt efter værten er den fjerne kommando — også
# `-s` og `--`, som ssh selv rører lige så lidt ved.
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
chmod +x "$TMP/ssh"

# --- falsk docker: kroppen skal kunne løbe igennem uden en dæmon -----------
# Den ægte dæmon-adfærd måles af scripts/test-deploy-diskvagt-byggecache.sh.
# Her er docker kun kulisse; det målte er, hvad kroppen FIK at vide.
cat > "$TMP/docker" <<'DSTUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "info -f")   echo "/" ;;
  "ps -aq")    : ;;
  "images "*|"images --no-trunc") : ;;
  "image prune")   echo "Total reclaimed space: 0B" ;;
  "builder prune") echo "Total:  0B" ;;
  *) : ;;
esac
exit 0
DSTUB
chmod +x "$TMP/docker"
export PATH="$TMP:$PATH"

# --- klip diskvagtens REMOTE-krop ud ---------------------------------------
KROP="$TMP/remote-krop.sh"
python3 - "$WORKFLOW" "$KROP" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
trin = src.split("- name: Diskvagt og oprydning", 1)
if len(trin) != 2:
    sys.exit("Kunne ikke finde trinnet 'Diskvagt og oprydning' i %s." % sys.argv[1])
m = re.search(r"<< 'REMOTE'.*?\n(.*?)\n\s*REMOTE\n", trin[1], re.S)
if not m:
    sys.exit("Kunne ikke finde diskvagtens REMOTE-heredoc i %s." % sys.argv[1])
body = "\n".join(l[10:] if l.startswith(" " * 10) else l for l in m.group(1).split("\n"))
open(sys.argv[2], "w", encoding="utf-8").write(body + "\n")
PY
[ -s "$KROP" ] || exit 1
ok "diskvagtens krop klippet ud af $(basename "$WORKFLOW")"

# --- klip HELE trinnet ud (env: + run:) og indsæt prøvens værdier ----------
# Værdierne indsættes PR. NAVN og ikke ved at gætte på `${{ }}`-udtrykkene:
# det, testen skal måle, er transporten, ikke hvordan Actions staver.
uddrag_trin() { # uddrag_trin <image_repo> <registry_mode> <udfil>
  IMAGE_REPO_SUB="$1" REGISTRY_SUB="$2" APP_DIR_SUB="$APP_DIR_SUB" \
  python3 - "$WORKFLOW" "$3" <<'PY'
import os, sys, yaml, shlex
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
st = next((s for s in steps if s.get("name") == "Diskvagt og oprydning"), None)
if st is None:
    sys.exit("Trinnet 'Diskvagt og oprydning' findes ikke i %s." % sys.argv[1])
vaerdier = {
    "APP_DIR": os.environ["APP_DIR_SUB"],
    "IMAGE_REPO": os.environ["IMAGE_REPO_SUB"],
    "IMAGE_KEEP": "3",
    "REGISTRY_MODE": os.environ["REGISTRY_SUB"],
    "BUILDER_KEEP_HOURS": "0",
    "WARN_PCT": "90",
    "FAIL_PCT": "100",
}
mangler = [k for k in vaerdier if k not in (st.get("env") or {})]
if mangler:
    sys.exit("Trinnets env: mangler " + ", ".join(mangler) +
             " — testen kan ikke sætte en værdi, trinnet ikke tager imod.")
run = st["run"]
if "${{" in run:
    sys.exit("Trinnets run: indeholder GitHub-udtryk — så kan det ikke køres her.")
pre = "\n".join("export %s=%s" % (k, shlex.quote(v)) for k, v in vaerdier.items())
open(sys.argv[2], "w", encoding="utf-8").write(pre + "\n" + run + "\n")
PY
}

# --- de to transporter -----------------------------------------------------
# NY: hele trinnet, som workflowet skriver det i dag.
koer_ny() { # koer_ny <image_repo> <registry_mode>
  local trin="$TMP/trin.sh"
  uddrag_trin "$1" "$2" "$trin" || return 111
  ( export HOST=boks.example DEPLOY_ENV=staging RUNNER_TEMP="$TMP/runner-temp"
    bash "$trin" ) 2>&1
}

# GAMMEL: kroppen fra workflowet, men sendt over ssh som POSITIONSARGUMENTER —
# kanalen fra S-362, som noten "Citering ind i en fjern shell" øverst i filen
# allerede havde frarådet. Genskabt her og ikke kopieret fra en gammel fil, så
# den gamle form testes mod den NUVÆRENDE krop.
koer_gammel() { # koer_gammel <image_repo> <registry_mode>
  local krop="$TMP/gammel-krop.sh"
  # Tildelingerne skal ligge EFTER kroppens egen `set -euo pipefail`, præcis
  # som i den gamle form — ellers er `set -u` ikke i kraft, når de læses, og
  # fejlen ville blive tavs i stedet for højlydt.
  { head -n 1 "$KROP"
    printf 'APP_DIR="$1"; IMAGE_REPO="$2"; IMAGE_KEEP="$3"; REGISTRY_MODE="$4"\n'
    printf 'BUILDER_KEEP_HOURS="$5"\n'
    tail -n +2 "$KROP"
  } > "$krop"
  head -n 1 "$KROP" | grep -q 'set -euo pipefail' || {
    echo "FEJL  kroppens første linje er ikke 'set -euo pipefail' — den gamle form kan ikke genskabes troværdigt." >&2
    return 112
  }
  ( export HOST=boks.example
    APP_DIR="$APP_DIR_SUB" IMAGE_REPO="$1" IMAGE_KEEP=3 REGISTRY_MODE="$2" BUILDER_KEEP_HOURS=0
    "$TMP/ssh" -i ~/.ssh/deploy_key -o BatchMode=yes "root@${HOST}" \
      bash -s -- "$APP_DIR" "$IMAGE_REPO" "$IMAGE_KEEP" "$REGISTRY_MODE" "$BUILDER_KEEP_HOURS" \
      < "$krop" ) 2>&1
}

# GAMMEL, som den stod 20-08: fire værdier, ingen builder_keep_hours endnu.
# Kun de to linjer, fejlen faktisk døde på — det er dén, der gengiver
# fejlbeskeden ORDRET, og en historisk form kan pr. definition ikke klippes ud
# af den nuværende fil.
koer_gammel_2008() { # koer_gammel_2008 <image_repo>
  local krop="$TMP/gammel-2008.sh"
  cat > "$krop" <<'GAMMEL'
set -euo pipefail
APP_DIR="$1"; IMAGE_REPO="$2"; IMAGE_KEEP="$3"; REGISTRY_MODE="$4"
echo "ANKOM APP_DIR=[$APP_DIR] IMAGE_REPO=[$IMAGE_REPO] IMAGE_KEEP=[$IMAGE_KEEP] REGISTRY_MODE=[$REGISTRY_MODE]"
GAMMEL
  ( export HOST=boks.example
    APP_DIR="$APP_DIR_SUB" IMAGE_REPO="$1" IMAGE_KEEP=3 REGISTRY_MODE="${2:-0}"
    "$TMP/ssh" -i ~/.ssh/deploy_key -o BatchMode=yes "root@${HOST}" \
      bash -s -- "$APP_DIR" "$IMAGE_REPO" "$IMAGE_KEEP" "$REGISTRY_MODE" \
      < "$krop" ) 2>&1
}

REGISTRY_REPO="ghcr.io/fermrad/area51"

echo
echo "1) on-host (IMAGE_REPO er TOM) — den GAMLE form skal fældes"
UD="$(koer_gammel_2008 "")"; RC=$?
[ "$RC" -ne 0 ] && ok "trinnet dør (exit $RC)" || fejl "den gamle form gik igennem på en tom IMAGE_REPO"
grep -q 'unbound variable' <<<"$UD" \
  && ok "fejlen er 'unbound variable'" || fejl "fejlen er ikke 'unbound variable'"
grep -q 'line 2: \$4: unbound variable' <<<"$UD" \
  && ok "ORDRET som målt 20-08-2026: 'line 2: \$4: unbound variable'" \
  || fejl "beskeden er ikke den målte. Fik: $UD"

echo
echo "   … og med den nuværende krop rykker fejlen bare én plads ned"
UD="$(koer_gammel "" 0)"; RC=$?
[ "$RC" -ne 0 ] && ok "trinnet dør stadig (exit $RC)" || fejl "den gamle form gik igennem"
grep -q 'unbound variable' <<<"$UD" \
  && ok "'unbound variable' — S-365's femte værdi flyttede kun nummeret" \
  || fejl "ingen 'unbound variable'. Fik: $UD"

echo
echo "2) on-host (IMAGE_REPO er TOM) — den NYE form skal bestå"
UD="$(koer_ny "" 0)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem (exit 0)" || fejl "trinnet fejlede (exit $RC)"
grep -q 'unbound variable' <<<"$UD" && fejl "der er stadig en 'unbound variable'" \
  || ok "ingen 'unbound variable'"
# Tomheden skal ANKOMME som tomhed. Kroppens on-host-gren er kun nåelig, når
# REGISTRY_MODE=0 ELLER IMAGE_REPO er tom — og den beviser dermed, at ingen
# nabo er rykket ned i pladsen.
grep -q 'intet SHA-tagget repo at rydde i' <<<"$UD" \
  && ok "IMAGE_REPO ankom TOM (kroppen valgte on-host-grenen)" \
  || fejl "kroppen så ikke en tom IMAGE_REPO. Fik: $UD"
grep -q '^Diskforbrug på staging efter oprydning: [0-9]\+%' <<<"$UD" \
  && ok "vagten nåede frem til sin måling" || fejl "vagten nåede aldrig sin måling. Fik: $UD"

echo
echo "3) registry-kontrol (IMAGE_REPO er IKKE tom) — begge former skal bestå"
echo "   Det er kontrollen, der viser, at det er ARGUMENTET og ikke miljøet."
UD="$(koer_gammel "$REGISTRY_REPO" 1)"; RC=$?
[ "$RC" -eq 0 ] && ok "den GAMLE form går igennem (exit 0)" || fejl "den gamle form fejlede (exit $RC): $UD"
grep -qF "Images i '$REGISTRY_REPO'" <<<"$UD" \
  && ok "værdien ankom ordret i den gamle form" || fejl "værdien ankom ikke ordret. Fik: $UD"

UD="$(koer_ny "$REGISTRY_REPO" 1)"; RC=$?
[ "$RC" -eq 0 ] && ok "den NYE form går igennem (exit 0)" || fejl "den nye form fejlede (exit $RC): $UD"
grep -qF "Images i '$REGISTRY_REPO'" <<<"$UD" \
  && ok "værdien ankom ordret i den nye form" || fejl "værdien ankom ikke ordret. Fik: $UD"

echo
echo "4) Statisk: kanalen må ikke blive positionel igen"
# Kun DOBBELTciterede `"$1"` / `"${1}"` og `$@`/`$*` tælles. Kroppens awk- og
# sed-programmer er ENKELTciterede og bruger `$5`/`$6` om awk's egne felter —
# de er ikke shellens positionsparametre og må ikke fælde vagten.
POSMOENSTER='"\$\{?[1-9]\}?"|\$[@*]'
if grep -Eq "$POSMOENSTER" "$KROP"; then
  fejl "diskvagtens krop læser positionsparametre igen ($(grep -Eo "$POSMOENSTER" "$KROP" | sort -u | tr '\n' ' '))"
  echo "        Bind på NAVN: skriv 'NAVN=%q\\n' foran kroppen på stdin og lad"
  echo "        ssh-kommandoen være konstant. Se S-447 og noten øverst i filen."
else
  ok "kroppen læser ingen positionsparametre"
fi

if python3 - "$WORKFLOW" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
st = next((s for s in steps if s.get("name") == "Diskvagt og oprydning"), None)
run = (st or {}).get("run") or ""
m = re.search(r"^\s*\}?\s*\|?\s*ssh .*?(?=\n\s*\n)", run, re.S | re.M)
kald = m.group(0) if m else run
sys.exit(1 if re.search(r"bash\s+-s\s+--", kald) else 0)
PY
then
  ok "ssh-kommandoen bærer ingen positionsargumenter"
else
  fejl "ssh-kommandoen bruger 'bash -s --' igen — værdierne parses af den fjerne login-shell"
fi

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
