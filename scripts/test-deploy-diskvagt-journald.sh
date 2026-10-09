#!/usr/bin/env bash
#
# Test af journald-loftet i .github/workflows/deploy-app.yml (S-1290 —
# "Diskvagt på alle bokse: journald får et loft, deployet måler journald, og
# en daglig vagt melder over 85 %").
#
# Hændelsen, 09-10-2026: den interne prod-boks (project, devhub og crm) løb
# tør for disk. 2,0 GB arkiverede journald-journaler lå uden for alt,
# diskvagten ryddede, og vagten sagde kun "99 % → 92 %". Postgres svarede
# «No space left on device», DevHub stod i recovery.
#
# Testen måler fire ting, og de er fire forskellige påstande:
#
#   1. IDEMPOTENS. Trinnet `journald får et loft` skriver
#      /etc/systemd/journald.conf.d/ferm-loft.conf første gang, genstarter
#      journald og rydder ned til loftet — og ANDEN gang gør det INGENTING
#      (ingen systemctl, ingen vacuum) og siger det. En anden værdi i filen
#      skrives om.
#   2. ALDRIG ET FÆLDET DEPLOY. Fejler genstarten, eller svarer boksen slet
#      ikke, går trinnet ud med 0 og en ::warning:: — og en fejlet genstart
#      fjerner filen igen, så næste deploy forsøger forfra.
#   3. RÆKKEFØLGEN. Trinnet ligger efter `Setup SSH` og FØR `Diskvagt og
#      oprydning`, så vagtens FØR-tal måler en boks med loft på.
#   4. DISKVAGTEN MÅLER OG RYDDER JOURNALD. «Disk FØR/EFTER» viser journald og
#      de største poster, og oprydningen kalder `journalctl --vacuum-size` med
#      SAMME loft som trinnet.
#
# Kroppene KLIPPES ud af workflowet frem for at blive kopieret, så testen ikke
# kan komme til at teste en forældet afskrift. systemctl, journalctl, docker
# og ssh er falske: det, der måles, er trinnets beslutninger, ikke systemd.
# Konfigurationsstien omskrives til en midlertidig mappe — testen rører aldrig
# /etc.
#
# Kør: bash scripts/test-deploy-diskvagt-journald.sh [anden-deploy-app.yml]
#
# Peger man den på udgaven FØR S-1290 (`git show origin/main~N:…`), skal den
# fejle allerede ved udklipningen: trinnet findes ikke.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"
LOFT_TRIN="journald får et loft"
VAGT_TRIN="Diskvagt og oprydning"
ETC_STI="/etc/systemd/journald.conf.d"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runner-temp" "$TMP/app"
KONF_DIR="$TMP/etc/systemd/journald.conf.d"
KONF="$KONF_DIR/ferm-loft.conf"
KALD="$TMP/kald.log"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fejl() { FAIL=$((FAIL + 1)); printf '  FEJL  %s\n' "$1"; }

# --- falsk ssh: samler argumenterne og lader en shell parse dem forfra -----
# Som sshd: `$SHELL -c <streng>`, og stdin går uændret videre til `bash -s`.
# FALSK_SSH_NEDE=1 er en boks, der ikke svarer.
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

# --- falsk systemctl og journalctl: logger hvert kald ----------------------
cat > "$TMP/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$KALD"
exit "${FALSK_SYSTEMCTL_RC:-0}"
STUB
cat > "$TMP/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
echo "journalctl $*" >> "$KALD"
case "$*" in
  --disk-usage) echo "Archived and active journals take up 1.9G in the file system." ;;
  --vacuum-size=*) echo "Vacuuming done, freed 1.4G of archived journals from /var/log/journal/abc." ;;
esac
exit 0
STUB
# docker: kun kulisse for diskvagtens krop (punkt 4).
cat > "$TMP/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "info -f")   echo "/" ;;
  "system df") printf 'Images|12.4GB|8.1GB (65%%)\nContainers|210MB|0B (0%%)\nLocal Volumes|3.2GB|0B (0%%)\nBuild Cache|4.7GB|4.7GB\n' ;;
  "image prune")   echo "Total reclaimed space: 0B" ;;
  "builder prune") echo "Total:  0B" ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" KALD

# --- klip et trin ud (env: + run:) -----------------------------------------
# Værdierne fra trinnets EGET env: eksporteres ordret; stien til journald's
# konfiguration omskrives til den midlertidige mappe.
uddrag_trin() { # uddrag_trin <trinnavn> <udfil>
  ETC_STI="$ETC_STI" KONF_DIR="$KONF_DIR" python3 - "$WORKFLOW" "$1" "$2" <<'PY'
import os, sys, yaml, shlex
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
st = next((s for s in steps if s.get("name") == sys.argv[2]), None)
if st is None:
    sys.exit("Trinnet '%s' findes ikke i %s." % (sys.argv[2], sys.argv[1]))
run = st["run"]
if "${{" in run:
    sys.exit("Trinnets run: indeholder GitHub-udtryk — så kan det ikke køres her.")
env = {k: str(v) for k, v in (st.get("env") or {}).items() if "${{" not in str(v)}
run = run.replace(os.environ["ETC_STI"], os.environ["KONF_DIR"])
pre = "\n".join("export %s=%s" % (k, shlex.quote(v)) for k, v in env.items())
open(sys.argv[3], "w", encoding="utf-8").write(pre + "\n" + run + "\n")
PY
}

LOFT_SH="$TMP/loft.sh"
uddrag_trin "$LOFT_TRIN" "$LOFT_SH" || { echo "FEJL  kunne ikke klippe '$LOFT_TRIN' ud — findes trinnet?"; exit 1; }
grep -qF "$KONF_DIR" "$LOFT_SH" \
  && ok "trinnet klippet ud, og konfigurationsstien peger på testens mappe (ikke /etc)" \
  || { fejl "trinnet nævner ikke $ETC_STI — testen kan ikke omdirigere den"; exit 1; }

koer_loft() {
  : > "$KALD"
  ( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp"
    bash "$LOFT_SH" ) 2>&1
}
OENSKET="$(printf '[Journal]\nSystemMaxUse=500M')"

echo
echo "1) Første deploy: filen findes ikke — skrives, journald genstartes og ryddes"
UD="$(koer_loft)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem (exit 0)" || fejl "trinnet fejlede (exit $RC): $UD"
[ -f "$KONF" ] && [ "$(cat "$KONF")" = "$OENSKET" ] \
  && ok "ferm-loft.conf er ordret [Journal] + SystemMaxUse=500M" \
  || fejl "ferm-loft.conf har forkert indhold: $(cat "$KONF" 2>/dev/null || echo '(findes ikke)')"
grep -qx "systemctl restart systemd-journald" "$KALD" \
  && ok "systemctl restart systemd-journald blev kaldt" || fejl "journald blev ikke genstartet. Kald: $(tr '\n' ';' < "$KALD")"
grep -qx "journalctl --vacuum-size=500M" "$KALD" \
  && ok "journalctl --vacuum-size=500M blev kaldt" || fejl "journald blev ikke ryddet ned til loftet"
grep -q "::notice title=journald fik et loft" <<<"$UD" \
  && ok "loggen siger, at loftet blev sat" || fejl "ingen notice om, at loftet blev sat"
[ "$(grep -n 'restart' "$KALD" | cut -d: -f1)" -lt "$(grep -n 'vacuum' "$KALD" | cut -d: -f1)" ] \
  && ok "genstart FØR vacuum (journald skal have læst loftet først)" || fejl "vacuum kom før genstarten"

echo
echo "2) Næste deploy: filen er uændret — trinnet gør INTET og siger det"
UD="$(koer_loft)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem (exit 0)" || fejl "trinnet fejlede (exit $RC)"
grep -q "^systemctl" "$KALD" && fejl "systemctl blev kaldt, selv om intet var ændret: $(tr '\n' ';' < "$KALD")" \
  || ok "ingen systemctl — journald er ikke genstartet"
grep -q "vacuum" "$KALD" && fejl "trinnet ryddede, selv om intet var ændret" || ok "ingen vacuum i trinnet"
grep -q "intet ændret" <<<"$UD" && ok "loggen siger 'intet ændret'" || fejl "loggen siger ikke, at intet blev ændret: $UD"
grep -q "::warning\|::notice" <<<"$UD" && fejl "en uændret boks gav en annotation" || ok "ingen annotation på en uændret boks"
grep -q "^Skrev " <<<"$UD" && fejl "filen blev skrevet om" || ok "filen er ikke skrevet om"
[ "$(cat "$KONF")" = "$OENSKET" ] && ok "indholdet står urørt" || fejl "indholdet ændrede sig: $(cat "$KONF")"

echo
echo "3) Filen findes med et ANDET loft — skrives om og genstartes"
printf '[Journal]\nSystemMaxUse=2G\n' > "$KONF"
UD="$(koer_loft)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går igennem (exit 0)" || fejl "trinnet fejlede (exit $RC)"
[ "$(cat "$KONF")" = "$OENSKET" ] && ok "loftet er rettet til 500M" || fejl "filen blev ikke rettet: $(cat "$KONF")"
grep -qx "systemctl restart systemd-journald" "$KALD" && ok "journald genstartet" || fejl "journald ikke genstartet"

echo
echo "4) Genstarten fejler — ADVARSEL, ikke et fældet deploy, og filen fjernes"
rm -f "$KONF"
UD="$(FALSK_SYSTEMCTL_RC=1 koer_loft)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går ud med 0 (deployet fortsætter)" || fejl "trinnet fældede deployet (exit $RC)"
grep -q "::warning title=journald-loftet kunne ikke sættes" <<<"$UD" \
  && ok "::warning:: om, at loftet ikke kunne sættes" || fejl "ingen ::warning::. Fik: $UD"
grep -q "fejl-genstart" <<<"$UD" && ok "advarslen navngiver genstarten" || fejl "advarslen siger ikke, hvad der fejlede"
[ -e "$KONF" ] && fejl "filen blev liggende — næste deploy ville tro, loftet virker" \
  || ok "filen er fjernet igen, så næste deploy forsøger forfra"
UD="$(koer_loft)"; RC=$?
grep -qx "systemctl restart systemd-journald" "$KALD" \
  && ok "næste deploy skriver og genstarter igen" || fejl "næste deploy forsøgte ikke igen"

echo
echo "5) Boksen svarer ikke — ADVARSEL, ikke et fældet deploy"
UD="$(FALSK_SSH_NEDE=1 koer_loft)"; RC=$?
[ "$RC" -eq 0 ] && ok "trinnet går ud med 0" || fejl "trinnet fældede deployet (exit $RC)"
grep -q "::warning title=journald-loftet kunne ikke sættes på production-boksen (intet svar)" <<<"$UD" \
  && ok "::warning:: med 'intet svar'" || fejl "ingen advarsel om en boks, der ikke svarer. Fik: $UD"

echo
echo "6) Statisk: placering, continue-on-error og samme loft begge steder"
if python3 - "$WORKFLOW" "$LOFT_TRIN" "$VAGT_TRIN" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = wf["jobs"]["deploy"]["steps"]
navne = [s.get("name") for s in steps]
loft, vagt = sys.argv[2], sys.argv[3]
fejl = []
if not (navne.index("Setup SSH") < navne.index(loft) < navne.index(vagt)):
    fejl.append("rækkefølge: %s" % navne[:navne.index(vagt) + 1])
lt = steps[navne.index(loft)]
if lt.get("continue-on-error") is not True:
    fejl.append("loft-trinnet mangler continue-on-error: true")
a = str((lt.get("env") or {}).get("JOURNALD_LOFT"))
b = str((steps[navne.index(vagt)].get("env") or {}).get("JOURNALD_LOFT"))
if a != b or a != "500M":
    fejl.append("JOURNALD_LOFT er '%s' i loft-trinnet og '%s' i diskvagten" % (a, b))
if fejl:
    print("\n".join(fejl)); sys.exit(1)
PY
then
  ok "Setup SSH → journald får et loft → Diskvagt og oprydning; continue-on-error; JOURNALD_LOFT=500M begge steder"
else
  fejl "placering, continue-on-error eller loftet er forkert (se ovenfor)"
fi

echo
echo "7) Diskvagten: «Disk FØR/EFTER» viser journald og de største poster, og oprydningen rydder journald"
VAGT_SH="$TMP/vagt.sh"
uddrag_trin "$VAGT_TRIN" "$VAGT_SH" || { fejl "kunne ikke klippe '$VAGT_TRIN' ud"; VAGT_SH=""; }
if [ -n "$VAGT_SH" ]; then
  : > "$KALD"
  UD="$( export HOST=boks.example DEPLOY_ENV=production RUNNER_TEMP="$TMP/runner-temp" \
           APP_DIR="$TMP/app" IMAGE_REPO="" IMAGE_KEEP=3 REGISTRY_MODE=0 BUILDER_KEEP_HOURS=0 \
           WARN_PCT=100 FAIL_PCT=100
         bash "$VAGT_SH" 2>&1 )"; RC=$?
  [ "$RC" -eq 0 ] && ok "diskvagten går igennem (exit 0)" || fejl "diskvagten fejlede (exit $RC): $UD"
  # De to læses indirekte via ${!del} i løkken nedenfor.
  # shellcheck disable=SC2034
  FOER_DEL="$(sed -n '/── Disk FØR oprydning/,/── Images/p' <<<"$UD")"
  # shellcheck disable=SC2034
  EFTER_DEL="$(sed -n '/── Disk EFTER oprydning/,/^Diskforbrug:/p' <<<"$UD")"
  for del in FOER_DEL EFTER_DEL; do
    navn="${del%_DEL}"; [ "$navn" = "FOER" ] && navn="FØR"
    tekst="${!del}"
    grep -Eq '^  journald +1\.9G$' <<<"$tekst" && ok "Disk $navn viser journald (1.9G)" || fejl "Disk $navn viser ikke journald. Fik: $tekst"
    grep -Eq '^  docker images +12\.4GB +\(kan frigøres: 8\.1GB \(65%\)\)$' <<<"$tekst" \
      && ok "Disk $navn viser docker images" || fejl "Disk $navn viser ikke docker images"
    grep -Eq '^  docker build cache +4\.7GB' <<<"$tekst" && ok "Disk $navn viser byggecachen" || fejl "Disk $navn viser ikke byggecachen"
    grep -Eq '^  docker local volumes +3\.2GB' <<<"$tekst" && ok "Disk $navn viser volumes" || fejl "Disk $navn viser ikke volumes"
  done
  grep -q "── journald over loftet (500M)" <<<"$UD" && ok "oprydningen har et journald-punkt" || fejl "oprydningen nævner ikke journald"
  grep -qx "journalctl --vacuum-size=500M" "$KALD" \
    && ok "oprydningen kalder journalctl --vacuum-size=500M" || fejl "oprydningen ryddede ikke journald. Kald: $(tr '\n' ';' < "$KALD")"
  # Rækkefølgen inde i trinnet: vacuum skal ske FØR EFTER-målingen, ellers
  # måler EFTER ikke det, oprydningen fik ud af det.
  awk '/── journald over loftet/ {j=NR} /── Disk EFTER oprydning/ {e=NR} END {exit !(j && e && j < e)}' <<<"$UD" \
    && ok "journald ryddes FØR 'Disk EFTER' måles" || fejl "journald ryddes efter EFTER-målingen"
fi

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
