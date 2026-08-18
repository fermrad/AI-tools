#!/usr/bin/env bash
#
# Test af citeringen ind i den FJERNE shell i .github/workflows/deploy-app.yml
# (S-354 punkt 2).
#
# Hvert `ssh … "<kommando>"` i workflowet sender en STRENG. ssh(1) samler sine
# restargumenter med mellemrum imellem, og sshd kører resultatet som
# `$SHELL -c <streng>` — som root på målserveren. Runnerens egne
# anførselstegn er væk længe før det sker, så en værdi, der interpoleres ind i
# strengen, parses EN GANG TIL på den anden side.
#
# Det var derfor `export GIT_REF='${GIT_REF}'` var et hul: `GIT_REF` er appens
# branchnavn, og `git check-ref-format --branch "feat/x'\$(whoami)'y"` siger
# god. Værdien lukkede sin egen enkeltcitering, og resten kørte som root.
#
# Testen er ikke en mønstersøgning — den KØRER trinnene mod en falsk ssh, der
# genskaber sammensætningen og genparsningen, og måler to ting:
#   1. et fjendtligt branchnavn eksekverer IKKE på den fjerne side, og
#   2. det ankommer ORDRET, mens de variabler, der SKAL ekspandere, stadig gør.
# Punkt 2 er det halve af testen med vilje: en citering, der lukker hullet og
# brækker udrulningen, er ikke en rettelse.
#
# Kroppene KLIPPES ud af workflowet frem for at blive kopieret, så testen ikke
# kan komme til at teste en forældet afskrift.
#
# Kør: bash scripts/test-deploy-remote-quoting.sh [anden-deploy-app.yml]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Valgfrit argument: en anden workflow-fil (bruges til at vise, at testen
# FEJLER på udgaven før rettelsen — en test, der ikke kan fejle, måler intet).
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

APP_DIR_SUB="$TMP/app"; mkdir -p "$APP_DIR_SUB"
MARKER="$TMP/EKSEKVERET"

# Et branchnavn, git faktisk accepterer, og som bryder ud af en enkeltcitering.
PAYLOAD="feat/x'\$(whoami>$MARKER)'y"
if command -v git >/dev/null && ! git check-ref-format --branch "$PAYLOAD" >/dev/null 2>&1; then
  echo "FEJL  prøven er ikke et lovligt branchnavn længere — vælg et andet." >&2
  exit 1
fi

# --- falsk ssh: samler argumenterne og lader en shell parse dem forfra -------
cat > "$TMP/ssh" <<'STUB'
#!/usr/bin/env bash
cmd=(); host_seen=0
while [ $# -gt 0 ]; do
  case "$1" in
    -i|-o) shift 2;;
    -*) shift;;
    root@*) host_seen=1; shift;;
    *) [ "$host_seen" -eq 1 ] && cmd+=("$1"); shift;;
  esac
done
bash -c "${cmd[*]}"
STUB
chmod +x "$TMP/ssh"

# docker-stubben rapporterer, hvad den fjerne side FAKTISK fik at se.
cat > "$TMP/docker" <<'DSTUB'
#!/usr/bin/env bash
[ "$1" = "compose" ] && printf 'PWD=%s\nGIT_SHA=%s\nGIT_REF=%s\nAPP_IMAGE=%s\n' \
  "$PWD" "${GIT_SHA-}" "${GIT_REF-}" "${APP_IMAGE-}"
exit 0
DSTUB
chmod +x "$TMP/docker"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/rsync"; chmod +x "$TMP/rsync"
export PATH="$TMP:$PATH"

# --- klip trinnets krop (og dets env:) ud af workflowet ----------------------
extract_step() {
  APP_DIR_SUB="$APP_DIR_SUB" python3 - "$WORKFLOW" "$1" "$2" <<'PY'
import os, re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
for st in steps:
    if st.get("name") != sys.argv[2]:
        continue
    def interp(t):
        t = str(t)
        t = re.sub(r"\$\{\{\s*inputs\.app_dir\s*\}\}", os.environ["APP_DIR_SUB"], t)
        t = re.sub(r"\$\{\{\s*inputs\.compose_service\s*\}\}", "app", t)
        t = re.sub(r"\$\{\{\s*secrets\.[^}]*\}\}", "hemmelighed", t)
        return re.sub(r"\$\{\{[^}]*\}\}", "X", t)
    pre = ["export %s='%s'" % (k, interp(v).replace("'", "'\\''"))
           for k, v in (st.get("env") or {}).items()]
    open(sys.argv[3], "w").write("\n".join(pre) + "\n" + interp(st["run"]) + "\n")
    sys.exit(0)
sys.exit("Trin ikke fundet i deploy-app.yml: " + sys.argv[2])
PY
}

PASS=0; FAIL=0
check() {  # check <trinnavn>
  local step="$1" body="$TMP/body.sh" out ok=1
  extract_step "$step" "$body" || { echo "  FEJL  $step: kunne ikke klippes ud"; FAIL=$((FAIL+1)); return; }
  rm -f "$MARKER"
  out="$(
    HOST=boks.example DEPLOY_ENV=staging \
    COMPOSE_FLAGS='-f docker-compose.staging.yml' \
    GIT_SHA=deadbeef GIT_REF="$PAYLOAD" \
    APP_IMAGE=ghcr.io/fermrad/app:deadbeef \
    bash "$body" 2>&1
  )"

  # 1. Ingen eksekvering på den fjerne side.
  if [ -e "$MARKER" ]; then
    ok=0; echo "  FEJL  $step: prøven KØRTE på den fjerne side ($(cat "$MARKER"))"
  fi
  # 2. Værdien ankom ordret …
  if ! grep -qxF "GIT_REF=$PAYLOAD" <<<"$out"; then
    ok=0; echo "  FEJL  $step: GIT_REF ankom ikke ordret. Fik: $(grep '^GIT_REF=' <<<"$out")"
  fi
  # 3. … og resten ekspanderer stadig.
  grep -qxF "GIT_SHA=deadbeef" <<<"$out" || { ok=0; echo "  FEJL  $step: GIT_SHA ekspanderer ikke længere"; }
  grep -qxF "PWD=$APP_DIR_SUB" <<<"$out" || { ok=0; echo "  FEJL  $step: cd ramte ikke app-mappen"; }

  if [ $ok -eq 1 ]; then PASS=$((PASS+1)); printf '  ok    %s\n' "$step"
  else FAIL=$((FAIL+1)); printf '        %s\n' "${out//$'\n'/$'\n        '}"; fi
}

echo "Fjendtligt branchnavn gennem de trin, der sender GIT_REF til en root-shell"
check "Build and restart containers"
check "Build image"
check "Start containers"

# --- statisk: den gamle form må ikke snige sig ind igen ---------------------
echo
echo "Den gamle form må ikke findes i nogen ssh-streng"
if python3 - "$WORKFLOW" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
bad = []
pat = re.compile(r"'\$\{[A-Za-z_][A-Za-z0-9_]*\}'")
for jn, job in wf["jobs"].items():
    for st in job.get("steps", []):
        run = st.get("run") or ""
        if "ssh " not in run:
            continue
        for m in pat.finditer(run):
            bad.append(f"{st.get('name')}: {m.group(0)}")
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
then
  PASS=$((PASS+1)); echo "  ok    ingen '\${VAR}' interpoleret ind i en fjern kommandostreng"
else
  FAIL=$((FAIL+1))
  echo "  FEJL  en værdi er enkeltciteret ind i en fjern kommandostreng igen."
  echo "        Brug Q_VAR=\$(printf '%q' \"\$VAR\") og indsæt \${Q_VAR} UDEN anførselstegn."
fi

echo
echo "$PASS ok, $FAIL fejl"
[ "$FAIL" -eq 0 ]
