#!/usr/bin/env bash
#
# Test af byggecache-ændringerne i .github/workflows/deploy-app.yml (S-1359
# — "Staging-bygget går fra 9 til ~5 min: en mindre Docker-cache (mode=min)
# og Next's egen byggecache gemt mellem kørsler").
#
# Målt 13-10-2026 i projects staging-byg («deploy (staging) / build»):
#
#   trin                                      | tid
#   npm run build (Next)                       | 225 s
#   «exporting to GitHub Actions Cache»        | 187 s
#   «exporting layers» + push                  | 49 s
#   npm ci (kørte fra bunden — ikke CACHED)     | 25 s
#
# `cache-to` har hidtil altid været hårdkodet `mode=max`: alt mellemlag,
# også det flygtige builder-lag, eksporteres til en 10 GB-cache pr. repo —
# og skubber derved deps-laget ud igen. Rettelsen er to ting:
#   1. `cache_mode` (min|max) som input, DEFAULT min.
#   2. `cache_mounts`: et BuildKit cache-mount (Next's .next/cache) gemt
#      mellem kørsler via actions/cache + buildkit-cache-dance.
#
# Testen måler STATISK (parser YAML'en, kører intet docker-byg), fordi det,
# der skal fældes, er KONFIGURATION — en glemt betingelse eller en flyttet
# default — ikke BuildKits faktiske opførsel:
#   1. `cache_mode`-inputtets default er 'min' (ikke 'max').
#   2. `cache-to` bruger `inputs.cache_mode` og er stadig TOM for production.
#   3. `cache-from` er stadig scopet pr. app OG miljø (intet fælles scope).
#   4. De tre cache-mounts-trin (gendan cache-map, actions/cache,
#      buildkit-cache-dance) har ALLE et eksplicit
#      `inputs.environment != 'production'` i deres `if:` — PRODUKTION
#      BYGGER RENT gælder også mount-cachen, og `--no-cache` dækker den
#      IKKE (det er kun lag-cachen).
#   5. De to nye actions (actions/cache, buildkit-cache-dance) er pinnet til
#      en fuld 40-tegns commit-SHA med en versionskommentar, som husets
#      øvrige actions.
#
# Hver af de tre krav i briefen blev kørt som et RIGTIGT brud under
# skrivning (se PR-teksten for de målte røde kørsler og antal FEJL-linjer):
# default tilbage til 'max', `cache-to` uden production-tjekket, og
# cache-mounts-trinnene uden `!= 'production'`. Alle tre fældte testen;
# rettelsen tilbage gjorde den grøn igen.
#
# Kør: bash scripts/test-deploy-byggecache-mode.sh [anden-deploy-app.yml]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/deploy-app.yml}"

python3 - "$WORKFLOW" <<'PY'
import sys, yaml, re

wf = sys.argv[1]
d = yaml.safe_load(open(wf, encoding="utf-8"))
build = d["jobs"]["build"]
steps = build["steps"]
# PyYAML (YAML 1.1) læser den bare nøgle `on:` som booleanen True, ikke
# strengen "on" — samme fælde overalt, hvor denne fil parses med safe_load.
on_block = d.get("on", d.get(True))
inputs = on_block["workflow_call"]["inputs"]

fejl = 0
antal = 0

def ok(msg):
    print("ok    " + msg)

def feil(msg):
    global fejl
    fejl = 1
    print("FEJL  " + msg)

def proeve(beskrivelse, betingelse, fejlbesked):
    global antal
    antal += 1
    if betingelse:
        ok(beskrivelse)
    else:
        feil(fejlbesked)

# --- 1. cache_mode's default er 'min', ikke 'max' --------------------------
cache_mode_default = inputs.get("cache_mode", {}).get("default")
proeve(
    "cache_mode's default er 'min' (målt S-1359: mode=max-exporten alene tog 187 s)",
    cache_mode_default == "min",
    "cache_mode's default er %r, skal være 'min' — en app, der ikke sætter "
    "inputtet, skal IKKE få mode=max tilbage" % (cache_mode_default,),
)

# --- find "Build and push image" ---------------------------------------
push_steps = [s for s in steps if s.get("name") == "Build and push image"]
if len(push_steps) != 1:
    sys.exit("FEJL  forventede 1 'Build and push image'-trin, fandt %d" % len(push_steps))
push_with = push_steps[0].get("with", {})
cache_to = push_with.get("cache-to", "") or ""
cache_from = push_with.get("cache-from", "") or ""

# --- 2. cache-to bruger cache_mode og er tom for production ----------------
proeve(
    "cache-to er tom for production og bruger inputs.cache_mode for andre miljøer",
    "inputs.environment == 'production' && ''" in cache_to
    and "inputs.cache_mode" in cache_to,
    "cache-to mangler enten production-tjekket eller inputs.cache_mode: %r" % (cache_to,),
)

# --- 3. cache-from er stadig scopet pr. app OG miljø ------------------------
proeve(
    "cache-from er stadig scopet pr. app OG miljø (intet fælles scope)",
    "inputs.app_slug" in cache_from and "inputs.environment" in cache_from,
    "cache-from's scope mangler app_slug eller environment: %r" % (cache_from,),
)

# --- 4. cache_mounts default er tom -----------------------------------------
cache_mounts_default = inputs.get("cache_mounts", {}).get("default")
proeve(
    "cache_mounts's default er '' (ingen mount-cache for en app, der ikke sætter inputtet)",
    cache_mounts_default == "",
    "cache_mounts's default er %r, skal være ''" % (cache_mounts_default,),
)

# --- 5. de tre cache-mounts-trin findes og er gated mod production --------
wanted_names = [
    "Gendan cache-map til runner.temp (uden for byggekonteksten, samme disk)",
    "Cache byggecache-mounts",
    "Injicér byggecache-mounts i bygget",
]
by_name = {s.get("name"): s for s in steps}
for navn in wanted_names:
    trin = by_name.get(navn)
    proeve(
        "'%s' findes i build-jobbet" % navn,
        trin is not None,
        "trinnet '%s' findes ikke i build-jobbet" % navn,
    )
    if trin is None:
        continue
    if_udtryk = trin.get("if", "") or ""
    proeve(
        "'%s' har inputs.environment != 'production' i sin if: (PRODUKTION BYGGER RENT gælder også mount-cachen)" % navn,
        "inputs.environment != 'production'" in if_udtryk,
        "'%s' mangler production-gaten i sin if: (%r) — en prod-udrulning ville "
        "kunne genbruge en dev/staging-mounts indhold, som --no-cache ikke dækker"
        % (navn, if_udtryk),
    )

# --- 6. de to nye actions er pinnet til en fuld SHA med versionskommentar --
# YAML-parseren smider kommentaren væk, så `uses:`-værdien er kun
# "repo@sha" — versionskommentaren tjekkes derfor i den RÅ fil, linje for
# linje, som actionlint og mennesker begge læser den.
raw_lines = open(wf, encoding="utf-8").read().splitlines()
proeve(
    "actions/cache er pinnet til en fuld 40-tegns SHA med versionskommentar",
    any(re.search(r"uses: actions/cache@[0-9a-f]{40} # v\d", l) for l in raw_lines),
    "fandt ingen 'uses: actions/cache@<40-hex> # v...'-linje i filen",
)
proeve(
    "buildkit-cache-dance er pinnet til en fuld 40-tegns SHA med versionskommentar",
    any(
        re.search(
            r"uses: reproducible-containers/buildkit-cache-dance@[0-9a-f]{40} # v\d",
            l,
        )
        for l in raw_lines
    ),
    "fandt ingen 'uses: reproducible-containers/buildkit-cache-dance@<40-hex> # v...'-linje i filen",
)

# 20-10-2026: buildkit-cache-dance OMDØBER sin scratch-mappe i arbejdsmappen
# til cache-mappen. Lå cache-mappen under /tmp (en anden disk på GitHubs
# runnere), fejlede omdøbningen med EXDEV og jobbet gik rødt (project staging).
proeve(
    "cache-mounts ligger under runner.temp, ikke /tmp (samme disk som arbejdsmappen — EXDEV 20-10-2026)",
    "/tmp/ferm-cache-mounts" not in "\n".join(l for l in raw_lines if not l.lstrip().startswith("#"))
    and any("runner.temp }}/ferm-cache-mounts" in l for l in raw_lines),
    "cache-mounts-mappen skal være ${{ runner.temp }}/ferm-cache-mounts — /tmp ligger på en anden disk, og cache-dance's omdøbning fejler med EXDEV",
)

print()
if fejl:
    print("BYGGECACHE-ÆNDRINGEN ER IKKE DEN, DEN SKAL VÆRE.")
    sys.exit(1)
print("Byggecache-vagten ok — %d prøver." % antal)
PY
