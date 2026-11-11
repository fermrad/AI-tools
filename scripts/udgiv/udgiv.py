#!/usr/bin/env python3
# =====================================================================
# udgiv.py — logikken bag .github/workflows/udgiv-app.yml (S-1633
# «Udgivelse uden laptop: fælles workflow «udgiv-app.yml» i AI-tools med
# godkendelse via etiket»).
#
#   python3 udgiv.py vaelg   → vælg den sha, der må i prod i dette slot
#   python3 udgiv.py efter   → efter deployet: health, nyt forsøg eller rødliste
#
# Oversat fra laptoppens `hestevagt-dispatch.sh`. Reglerne og deres grunde er
# husets målte erfaringer; datoerne i kommentarerne er fra scriptet. Det nye er
# kun det, Jakob besluttede 11-11-2026:
#
#   1. GODKENDELSE VIA ETIKET. `prod-ja` på en PR, sat af et login i appens
#      `.github/prod-startere.txt` (læst fra main), godkender main TIL OG MED
#      den PR's merge-commit. Aktøren slås op i PR'ens issue-events (seneste
#      `labeled`-event for etiketten). Etiketten alene tæller ikke. `data-ja`
#      virker på samme måde for datamigreringer og afløser `~/.hestevagt-data-ja`.
#   2. Et planlagt workflow må starte prod, når reglerne ligger i workflowet.
#   3. Kun udgivelse flyttes; merge-løkken bliver på laptoppen.
#
# Hvad er ikke taget med fra laptoppen, og hvorfor:
#   · LØBENDE DISPATCH, DAGSTILLADELSE og NATTEVINDUET 22–06. Slottene
#     (Jakob 13-10 og 19-10) har afløst dem; de var filer på laptoppen.
#   · `node scripts/dispatch-sha.mjs --tjek`. Samme spørgsmål stilles af
#     deploy.yml's `prod_ref_port` og AI-tools' `ref_gate`, som
#     kører i den kørsel, vi starter (målt i project's
#     `scripts/prod-ref-port.mjs`).
#   · `hestevagt-godkend.sh`. Miljøet `production` har ingen påkrævede
#     godkendere på GitHub Team; porten er `prod_port` (se PR-teksten).
#
# Alt, der taler med GitHub og health, går gennem `Miljoe`, så prøven
# (test_udgiv.py) kan give API-svar som fixtures og et rigtigt git-repo.
# =====================================================================
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# Trinnene i deploy-jobbet, der ligger FØR noget rører boksen. Stopper
# kørslen i et af dem, er prod urørt (12-10-2026 og 26-10-2026).
FOER_BOKSEN = ("Setup SSH", "Connect to Tailscale", "Set up job")
# Kort- og kontaktdata må gå uden data-ja (Jakob 5-10-2026 ~19:3x: «generelt
# må rettelser til kontakter, kort og lignende gerne skubbes til prod,
# projektdata skal godkendes»). Listen er bevidst kort; udvid kun på Jakobs ord.
KORTDATA = ("anlaeg", "ledning", "zone", "organization", "person", "contact", "sales_contact")
MAKS_FORSOEG = 3
STATUS_ROED = "udgiv/roed"
STATUS_FORSOEG = "udgiv/forsoeg"
AKTIV_STATUS = ("in_progress", "queued", "waiting", "pending", "requested")


class ApiFejl(Exception):
    pass


# ---------------------------------------------------------------- tid og slot
def _cron_felt(felt, lo, hi):
    vaerdier = set()
    for del_ in felt.split(","):
        trin = 1
        if "/" in del_:
            del_, t = del_.split("/", 1)
            trin = int(t)
        if del_ == "*":
            a, b = lo, hi
        elif "-" in del_:
            a, b = (int(x) for x in del_.split("-", 1))
        else:
            a = b = int(del_)
        if a < lo or b > hi or a > b or trin < 1:
            raise ValueError(felt)
        vaerdier.update(range(a, b + 1, trin))
    return vaerdier


class Cron:
    """Fem felter, tal, lister, intervaller og `*/n`. Navne (MON, JAN) afvises."""

    def __init__(self, udtryk):
        f = udtryk.split()
        if len(f) != 5:
            raise ValueError(udtryk)
        self.minut = _cron_felt(f[0], 0, 59)
        self.time = _cron_felt(f[1], 0, 23)
        self.dag = _cron_felt(f[2], 1, 31)
        self.maaned = _cron_felt(f[3], 1, 12)
        self.ugedag = {d % 7 for d in _cron_felt(f[4], 0, 7)}  # søndag = 0
        self.dag_alle = f[2] == "*"
        self.ugedag_alle = f[4] == "*"

    def passer(self, lokal):
        if lokal.minute not in self.minut or lokal.hour not in self.time or lokal.month not in self.maaned:
            return False
        dag_ok = lokal.day in self.dag
        ugedag_ok = lokal.isoweekday() % 7 in self.ugedag
        if self.dag_alle and self.ugedag_alle:
            return True
        if self.dag_alle:
            return ugedag_ok
        if self.ugedag_alle:
            return dag_ok
        return dag_ok or ugedag_ok  # cron: begge sat → ELLER


def planlagt_tid(cron, nu_utc, tz, maks_minutter):
    """Det seneste minut <= nu, hvor cron passer i tz — højst maks_minutter tilbage.

    GitHubs `schedule` kan komme minutter for sent. Slottet regnes derfor fra
    det PLANLAGTE tidspunkt (fundet ud fra `github.event.schedule`), ikke fra
    det tidspunkt, kørslen tilfældigvis startede.
    """
    t = nu_utc.replace(second=0, microsecond=0)
    for _ in range(maks_minutter + 1):
        if cron.passer(t.astimezone(tz)):
            return t
        t -= timedelta(minutes=1)
    return None


def find_slot(nu_utc, schedule, cron_tz, slot_tz, slots_hverdag, slots_weekend, maks_minutter):
    """→ (slot eller None, tekstlinjer). slot = 'ÅÅÅÅ-MM-DD TT' i slot_tz."""
    tz = ZoneInfo(slot_tz)
    linjer = []
    if schedule:
        try:
            cron = Cron(schedule)
        except ValueError:
            return None, None, [f"   ⛔ kan ikke læse cron '{schedule}' — intet udgives"]
        planlagt = planlagt_tid(cron, nu_utc, ZoneInfo(cron_tz), maks_minutter)
        if planlagt is None:
            nu_l = nu_utc.astimezone(tz)
            return None, None, [
                f"{nu_l:%a %d-%m %H:%M} dansk tid — ingen planlagt tid for '{schedule}' "
                f"inden for {maks_minutter} min (for sent) — kun måling"]
        forsinkelse = int((nu_utc - planlagt).total_seconds() // 60)
        hvornaar = f"planlagt {planlagt.astimezone(tz):%H:%M}, startet {forsinkelse} min senere"
    else:
        planlagt = nu_utc
        hvornaar = "manuel kørsel, ingen schedule"
    lokal = planlagt.astimezone(tz)
    weekend = lokal.isoweekday() >= 6
    tider = (slots_weekend if weekend else slots_hverdag).split()
    linjer.append(f"{lokal:%a %d-%m %H:%M} dansk tid ({hvornaar}) — {'WEEKEND' if weekend else 'hverdag'}")
    slot = None
    if any(int(t, 10) == lokal.hour for t in tider):
        slot = f"{lokal:%Y-%m-%d} {lokal.hour:02d}"
    if slot and schedule:
        linjer.append(f"   faste dispatch-tider: {' '.join(tider)} — tiden {slot} er åben")
    elif slot:
        linjer.append(f"   faste dispatch-tider: {' '.join(tider)} — tiden {slot}, men kun en planlagt kørsel må udgive")
        slot = None
    else:
        linjer.append(f"   faste dispatch-tider: {' '.join(tider)} — ikke nu, kun måling")
    return slot, lokal, linjer


# ------------------------------------------------------------- datagaten
def _uden_kommentarer(tekst):
    return [re.sub(r"--.*$", "", linje) for linje in tekst.split("\n")]


def maal_tabeller(tekst):
    """Tabeller, en datafil skriver i (insert/update/delete/merge), i små bogstaver.

    `on conflict … do update set` er en upsert på INSERT'ens egen tabel, ikke
    en opdatering af tabellen «set» (8-10-2026: stoppede et punkt i 550/610).
    """
    tabeller = set()
    for linje in _uden_kommentarer(tekst):
        linje = re.sub(r"do[ \t]+update[ \t]+set", "do_update_set", linje.lower())
        for m in re.finditer(r"\b(insert[ \t]+into|update|delete[ \t]+from|merge[ \t]+into)[ \t]+([a-z0-9_\".]+)", linje):
            t = m.group(2).replace('"', "")
            tabeller.add(re.sub(r"^public\.", "", t))
    return sorted(tabeller)


def kun_kortdata(tekst):
    linjer = [l.lower() for l in _uden_kommentarer(tekst)]
    if any(re.search(r"\btruncate\b|drop[ \t]+(table|column)", l) for l in linjer):
        return False
    temp = set()
    for l in linjer:
        for m in re.finditer(r"create[ \t]+(temporary|temp)[ \t]+table[ \t]+(if[ \t]+not[ \t]+exists[ \t]+)?([a-z0-9_\"]+)", l):
            temp.add(m.group(3).replace('"', ""))
    for t in maal_tabeller(tekst):
        if t in KORTDATA or t in temp:
            continue
        return False
    return True


def aendrer_raekker(tekst):
    # Kun en fil, der faktisk RØRER RÆKKER, stopper. Målt 30-09-2026:
    # `500-anlaegsregister-fortrolighed.sql` tilføjer kun CHECK-regler til to
    # nye, tomme tabeller — den skal ikke holde en udgivelse tilbage.
    return any(re.search(r"\b(insert|update|delete|truncate|merge)\b|drop[ \t]+(table|column)", l, re.I)
               for l in _uden_kommentarer(tekst))


# ----------------------------------------------------------------- miljøet
class GitHubApi:
    def __init__(self, repo, token):
        self.repo, self.token = repo, token

    def _kald(self, metode, sti, data=None):
        url = "https://api.github.com" + sti.replace("{repo}", self.repo)
        req = urllib.request.Request(url, method=metode, data=json.dumps(data).encode() if data else None, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        try:
            with urllib.request.urlopen(req, timeout=30) as svar:
                return json.load(svar)
        except (urllib.error.URLError, TimeoutError, ValueError) as e:
            raise ApiFejl(f"{metode} {sti}: {e}") from e

    def get(self, sti):
        return self._kald("GET", sti)

    def post(self, sti, data):
        return self._kald("POST", sti, data)


def health_sha(url):
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/api/health", timeout=20) as svar:
            return str(json.load(svar).get("sha") or "")
    except Exception:
        return ""


class Miljoe:
    """Alt, der kommer udefra. Prøven bygger sin egen med fixtures."""

    def __init__(self, env, api, health, nu, sove=time.sleep):
        self.env, self.api, self.health, self.nu, self.sove = env, api, health, nu, sove
        self.linjer = []
        self.klon = env["KLON"]
        self._pr_cache = {}

    def log(self, linje):
        print(linje, flush=True)
        self.linjer.append(linje)

    def git(self, *args, tjek=True):
        p = subprocess.run(["git", "-C", self.klon, *args], capture_output=True, text=True, errors="replace")
        if tjek and p.returncode:
            raise RuntimeError(f"git {' '.join(args)}: {p.stderr.strip()}")
        return p.stdout

    def git_ok(self, *args):
        return subprocess.run(["git", "-C", self.klon, *args], capture_output=True).returncode == 0

    def flag(self, navn):
        return self.env.get(navn, "").strip().lower() == "true"


# ------------------------------------------------------------- opslagene
def laes_liste(m, sti):
    """Ikke-tomme linjer uden #-kommentarer fra en fil på main (tom, hvis den mangler)."""
    if not m.git_ok("cat-file", "-e", f"{m.env['HOVED']}:{sti}"):
        return None
    return [l.strip() for l in m.git("show", f"{m.env['HOVED']}:{sti}").splitlines()
            if l.strip() and not l.strip().startswith("#")]


def udfald(m, workflow, sha):
    """success | failure | cancelled | … | vent | '' — kun PUSH-kørsler.

    Kun push (7-10-2026): et prod-deploy registreres med main's hoved-sha som
    head_sha, uanset hvilken ref det udruller — så et RØDT prod-deploy af en
    ældre commit lignede et rødt STAGING-deploy af hovedet.
    """
    try:
        runs = m.api.get(f"/repos/{{repo}}/actions/workflows/{workflow}/runs?head_sha={sha}&event=push&per_page=1")
    except ApiFejl:
        return ""
    k = (runs.get("workflow_runs") or [None])[0]
    if not k:
        return ""
    return k.get("conclusion") or "" if k.get("status") == "completed" else "vent"


def prs_for(m, sha):
    """PR'er, der er merget ind i hovedgrenen og bærer commit'en."""
    if sha not in m._pr_cache:
        try:
            prs = m.api.get(f"/repos/{{repo}}/commits/{sha}/pulls")
        except ApiFejl:
            prs = []
        m._pr_cache[sha] = [p for p in prs if p.get("merged_at") and (p.get("base") or {}).get("ref") == m.env["HOVEDGREN"]]
    return m._pr_cache[sha]


def etiket(m, pr, navn, startere):
    """→ (gyldig, login). Etiketten skal sidde på PR'en NU, og det SENESTE
    `labeled`-event for den skal være sat af et login i prod-startere.txt."""
    if navn not in [l.get("name") for l in pr.get("labels") or []]:
        return False, None
    events, side = [], 1
    while True:
        try:
            del_ = m.api.get(f"/repos/{{repo}}/issues/{pr['number']}/events?per_page=100&page={side}")
        except ApiFejl:
            return False, None
        events += del_
        if len(del_) < 100:
            break
        side += 1
    sat = [e for e in events if e.get("event") == "labeled" and (e.get("label") or {}).get("name") == navn]
    if not sat:
        return False, None
    login = (sat[-1].get("actor") or {}).get("login")
    return bool(login) and login in startere, login


def statusser(m, sha):
    return m.api.get(f"/repos/{{repo}}/commits/{sha}/statuses?per_page=100")


def er_roed(m, sha):
    """Rødlisten er commit-statussen `udgiv/roed` på sha'en (nyeste først)."""
    for s in statusser(m, sha):
        if s.get("context") == STATUS_ROED:
            return s.get("state") == "failure", s.get("description") or ""
    return False, ""


def klassificer(jobs, moenster):
    """→ ('urort'|'roert', første røde trin). Spejler laptoppens `*)`-gren."""
    deploy = [j for j in jobs if re.search(moenster, j.get("name") or "")]
    koert = [j for j in deploy if j.get("conclusion") not in (None, "skipped")]
    roede = [s.get("name") for j in deploy for s in j.get("steps") or [] if s.get("conclusion") == "failure"]
    foerste = roede[0] if roede else ""
    if not koert or foerste in FOER_BOKSEN:
        return "urort", foerste
    return "roert", foerste


def run_jobs(m, sti):
    jobs, side = [], 1
    while True:
        svar = m.api.get(f"{sti}?per_page=100&page={side}")
        jobs += svar.get("jobs") or []
        if len(svar.get("jobs") or []) < 100:
            return jobs
        side += 1


def slot_status(m, slot_start_utc):
    """→ 'fri' | 'laast' (en anden udgivelse kører) | 'brugt' (udgivet i slottet)."""
    egen = m.env["RUN_ID"]
    wf = m.api.get(f"/repos/{{repo}}/actions/runs/{egen}")["workflow_id"]
    fra = slot_start_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    runs = m.api.get(f"/repos/{{repo}}/actions/workflows/{wf}/runs?created=%3E%3D{fra}&per_page=50")
    for r in runs.get("workflow_runs") or []:
        if str(r["id"]) == str(egen):
            continue
        if r.get("status") in AKTIV_STATUS:
            return "laast"
        jobs = run_jobs(m, f"/repos/{{repo}}/actions/runs/{r['id']}/jobs")
        if klassificer(jobs, m.env["DEPLOY_JOB_MOENSTER"])[0] == "roert":
            return "brugt"
    return "fri"


def s_numre(m, fra, til):
    titler = m.git("log", "--format=%s", f"{fra}..{til}")
    return " ".join(sorted(set(re.findall(r"S-[0-9]+", titler)), key=lambda s: int(s[2:])))


def titel(m, sha, n):
    return m.git("log", "-1", "--format=%s", sha).strip()[:n]


def blokerende_data(m, c, startere):
    """Datafiler i commit'en c (mod første forælder), der ÆNDRER RÆKKER i prod
    og ikke er godkendt. En `.ts`-backfill kan ikke læses og stopper altid."""
    filer = [f for f in m.git("diff", "--diff-filter=AM", "--name-only", f"{c}^", c).split()
             if re.search(m.env["DATA_MOENSTER"], f)]
    blok = []
    for f in filer:
        if f.endswith(".sql"):
            tekst = m.git("show", f"{c}:{f}")
            if not aendrer_raekker(tekst):
                continue
            if kun_kortdata(tekst):
                m.log(f"   · {f} skriver kun kort-/kontaktdata ({' '.join(maal_tabeller(tekst))} ) — tilladt (Jakob 5-10)")
                continue
        blok.append(f)
    if blok:
        for pr in prs_for(m, c):
            gyldig, login = etiket(m, pr, "data-ja", startere)
            if gyldig:
                for f in blok:
                    m.log(f"   · {f} har data-ja på #{pr['number']} (sat af {login}) — tilladt")
                return []
            if login:
                m.log(f"   · data-ja på #{pr['number']} er sat af {login}, som ikke står i prod-startere.txt — tæller ikke")
    return blok


# ------------------------------------------------------------------ vælg
class Valg:
    def __init__(self):
        self.udgiv = False
        self.sha = self.prod = self.slot = ""
        self.s_numre = ""
        self.stop = ""   # hvorfor intet udgives
        self.holdt = []  # hvad der er skåret fra (godkendelse, data)


def vaelg(m):
    v = Valg()
    e = m.env
    try:
        maks = int(e.get("MAKS_FORSINKELSE", "25"))
    except ValueError:
        maks = 25
    slot, lokal, linjer = find_slot(m.nu, e.get("SCHEDULE", ""), e["CRON_TIDSZONE"], e["TIDSZONE"],
                                    e["SLOTS_HVERDAG"], e["SLOTS_WEEKEND"], maks)
    for l in linjer:
        m.log(l)
    toerloeb = m.flag("TOERLOEB")
    if not toerloeb and e.get("EVENT_NAME") != "schedule":
        m.log("   (ikke en planlagt kørsel — køres som tørløb)")
        toerloeb = True

    def stop(grund, linje):
        m.log(linje)
        v.stop = grund
        return v

    app = e["APP"]
    m.log("")
    m.log(f"===== {app} =====")
    hoved = m.git("rev-parse", e["HOVED"]).strip()
    prod = m.health(e["URL"])
    v.prod = prod
    if not prod:
        return stop("health svarer ikke med en sha", "   ❌ health svarer ikke med en sha — springer over")
    if prod == hoved:
        return stop("prod = main", f"   ✔ prod = main ({hoved[:8]}) — intet at dispatche")
    if not re.fullmatch(r"[0-9a-f]{40}", prod) or not m.git_ok("merge-base", "--is-ancestor", prod, hoved):
        return stop("prod-sha'en ligger ikke på main",
                    f"   ⛔ prod svarer {prod[:12]}, som ikke ligger på main — springer over")
    m.log(f"   prod {prod[:8]} → main {hoved[:8]}")
    m.log(f"   punkter i udgivelsen: {s_numre(m, prod, hoved)} ")

    startere = laes_liste(m, e["STARTERE_FIL"])
    if startere is None:
        m.log(f"   · {e['STARTERE_FIL']} findes ikke på main — ingen etiket kan godkende noget")
        startere = []
    linje = list(reversed(m.git("rev-list", "--first-parent", f"{prod}..{hoved}").split()))  # ældste først

    # ⭐ GODKENDELSE (Jakob 11-11-2026): kun op til og med merge-commit'en af
    # den nyeste PR med gyldig `prod-ja`. Commits efter den venter; commits
    # uden PR under den er godkendt af PR'en oven på dem.
    top = hoved
    if m.flag("KRAEVER_GODKENDELSE"):
        graense = None
        for c in reversed(linje):
            for pr in prs_for(m, c):
                if pr.get("merge_commit_sha") != c:
                    continue
                gyldig, login = etiket(m, pr, "prod-ja", startere)
                if gyldig:
                    graense = c
                    m.log(f"   🔒 godkendt til og med {c[:8]} (#{pr['number']} prod-ja sat af {login})")
                    break
                if login:
                    m.log(f"   · prod-ja på #{pr['number']} er sat af {login}, som ikke står i prod-startere.txt — tæller ikke")
            if graense:
                break
        if not graense:
            return stop("ingen gyldig prod-ja", "   ⏸ ingen PR med gyldig prod-ja mellem prod og main — intet udgives")
        if graense != hoved:
            efter_g = len(linje) - 1 - linje.index(graense)
            m.log(f"   ✂ udgiver kun op til {graense[:8]}; {efter_g} commit(s) efter venter på prod-ja")
            v.holdt.append(f"{efter_g} commit(s) efter {graense[:8]} venter på prod-ja")
        top = graense
        linje = linje[:linje.index(graense) + 1]

    # ⭐ SKÅRET FØR DATA (5-10-2026): udgiv op til commit'en FØR den første, der
    # bringer en datafil uden data-ja. Første-forældre-linjen fra prod, så en
    # ældre datamigrering aldrig kan smutte med.
    blok = [(c, f) for c in linje for f in blokerende_data(m, c, startere)]
    if blok:
        m.log("   ⛔ udgivelsen ÆNDRER PROD-DATA — venter på data-ja:")
        for _, f in blok:
            m.log(f"      {f}")
        foerste = blok[0][0]
        if linje.index(foerste) == 0:
            return stop("datamigrering uden data-ja", "   ⏸ ingen kode foran datamigreringen — intet at dispatche uden data-ja")
        top = linje[linje.index(foerste) - 1]
        m.log(f"   ✂ udgiver kun op til {top[:8]} (før {foerste[:8]}: {titel(m, foerste, 60)})")
        v.holdt.append(f"datamigrering i {foerste[:8]} venter på data-ja")

    # Main's hoved er sjældent grønt i dagtimerne (målt 3-10-2026). Er det
    # ikke grønt, tages den NYESTE commit mellem prod og toppen, der er grøn på
    # BÅDE CI og staging. Datagaten har allerede set hele vejen op.
    def groen(sha):
        ci = udfald(m, e["CI_WORKFLOW"], sha) if e.get("CI_WORKFLOW") else "success"
        dep = udfald(m, e["STAGING_WORKFLOW"], sha)
        return ci == "success" and dep == "success", ci, dep

    ok, ci, dep = groen(top)
    if not ok:
        m.log(f"   ⏳ hovedet {top[:8]} er ikke grønt (CI={ci or 'ingen'} staging={dep or 'ingen'}) — leder efter den nyeste grønne")
        fundet = None
        for k in m.git("rev-list", "--first-parent", f"{prod}..{top}").split()[1:16]:
            if groen(k)[0]:
                fundet = k
                break
        if not fundet:
            return stop("ingen grøn commit", "   ⏳ ingen grøn commit mellem prod og main endnu — dispatches ikke")
        top = fundet
        m.log(f"   ↳ bruger {top[:8]}: {titel(m, top, 70)}")
    m.log(f"   ✔ grøn på {top[:8]} (CI og staging)")
    v.sha = top
    v.s_numre = s_numre(m, prod, top)

    # ⛔ INDHOLDSKRAV (7-10-2026): `<fil> <mønster>` pr. linje i
    # .github/udgiv-kraev.txt på main — udgiv kun en sha, hvor filen
    # indeholder mønstret (545 uden 'vand').
    for kr in laes_liste(m, e["KRAEV_FIL"]) or []:
        dele = kr.split(None, 1)
        if len(dele) < 2:
            continue
        fil, moenster = dele
        indhold = m.git("show", f"{top}:{fil}", tjek=False)
        if moenster not in indhold:
            return stop("mangler rettelsen (indholdskrav)",
                        f"   ⛔ {top[:8]} mangler rettelsen ({fil} skal indeholde {moenster}, {e['KRAEV_FIL']}) — dispatches ikke")

    # ⛔ EN SHA, DER GAV ET RØDT PROD-DEPLOY, UDGIVES IKKE IGEN (7-10-2026).
    try:
        roed, hvorfor = er_roed(m, top)
    except ApiFejl:
        return stop("rødlisten kan ikke læses", f"   ⛔ kan ikke læse rødlisten for {top[:8]} — dispatches ikke")
    if roed:
        return stop("rødlistet", f"   ⛔ {top[:8]} gav et RØDT prod-deploy — dispatches ikke igen ({STATUS_ROED}: {hvorfor}); venter på en nyere grøn commit")

    # ⚠️ DRIFTSVARSEL 5 MINUTTER FØR (Jakob 1-10-2026). deploy.yml skal kende
    # `varsel_minutter`, og PROD's egen version skal have varsel-scriptet
    # (S-1122 «Prod-deployet sætter selv driftsvarslet 5 minutter før genstart
    # — også om natten»: den version, der bringer scriptet ud, kan ikke selv
    # bruge det).
    if "varsel_minutter" not in m.git("show", f"{e['HOVED']}:.github/workflows/{e['STAGING_WORKFLOW']}", tjek=False):
        return stop("deploy.yml kan ikke sætte driftsvarslet",
                    "   ⛔ deploy.yml kan ikke selv sætte driftsvarslet endnu — udgivelse er lukket, indtil det kan")
    if e.get("VARSEL_SCRIPT") and not m.git_ok("cat-file", "-e", f"{prod}:{e['VARSEL_SCRIPT']}"):
        return stop("prod har ikke varsel-scriptet",
                    f"   ⛔ prod-versionen {prod[:8]} har ikke varsel-scriptet endnu — første dispatch skal ske med Jakobs manuelle varsel og varsel_minutter=0")

    if not slot:
        return stop("uden for de faste tider", "   (uden for de faste tider — ville være klar)")
    slot_start = lokal.replace(minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    try:
        s = slot_status(m, slot_start)
    except (ApiFejl, KeyError):
        return stop("kørselslisten kan ikke læses", "   ⛔ kan ikke læse tidligere kørsler i slottet — dispatches ikke")
    if s == "laast":
        return stop("en anden udgivelse kører", "   en anden udgivelse er i gang — springer over")
    if s == "brugt":
        return stop("allerede udgivet i slottet", f"   (allerede dispatchet i tiden {slot} — venter på næste faste tid)")
    v.slot = slot
    if toerloeb:
        return stop("tørløb", f"   (tørløb — ville udgive {top[:8]} med driftsvarsel 5 min)")
    v.udgiv = True
    m.log(f"   🚀 udgiver {top} med driftsvarsel 5 min (slot {slot})")
    return v


# ------------------------------------------------------------------ efter
def efter(m):
    e = m.env
    sha, res, rid = e["SHA"], e.get("DEPLOY_RESULTAT", ""), e["RUN_ID"]
    m.log(f"===== {e['APP']} — efter deployet: {e.get('PROD_FOER', '')[:8]} → {sha[:8]} (slot {e.get('SLOT', '')}) =====")
    if res == "success":
        m.log(f"   ✔ deploy grøn (kørsel {rid})")
        # Containeren kan være et øjeblik om at svare med den nye version.
        efter_sha = ""
        for _ in range(18):
            efter_sha = m.health(e["URL"])
            if efter_sha == sha:
                break
            m.sove(10)
        if efter_sha == sha:
            m.log(f"   ✔ health svarer {sha} — sæt punkterne til shipped")
            return 0
        m.log(f"   ⚠️ health svarer {efter_sha or 'intet'}, ikke {sha[:8]} (efter 3 min)")
        print(f"::warning title=Health svarer ikke den udgivne sha::{efter_sha or 'intet'} ≠ {sha}")
        return 0
    try:
        jobs = run_jobs(m, f"/repos/{{repo}}/actions/runs/{rid}/attempts/{e.get('RUN_ATTEMPT', '1')}/jobs")
        klasse, trin = klassificer(jobs, e["DEPLOY_JOB_MOENSTER"])
    except ApiFejl:
        klasse, trin = "roert", ""  # laptoppen: ukendt → regnes som rødt
    if klasse == "urort":
        # 12-10 og 26-10-2026: kørslen stoppede i «Driftsvarsel»/«Setup SSH»,
        # FØR noget rørte boksen. Ikke et rødt deploy; prøves igen, højst 3 gange.
        n = sum(1 for s in statusser(m, sha) if s.get("context") == STATUS_FORSOEG)
        m.api.post(f"/repos/{{repo}}/statuses/{sha}", {
            "state": "error", "context": STATUS_FORSOEG,
            "description": f"forsøg {n + 1}/{MAKS_FORSOEG}: stoppede før boksen ({trin or 'før deploy-jobbet'}), kørsel {rid}"})
        if n < MAKS_FORSOEG - 1:
            m.log(f"   ⚠️ kørsel {rid} ({res}) stoppede, før boksen blev rørt ({trin or 'før deploy-jobbet'}) — prod er urørt; prøves igen næste runde ({n + 1}/{MAKS_FORSOEG})")
            return 0
        m.log(f"   ❌ kørsel {rid} stoppede før deploy for {MAKS_FORSOEG}. gang — {sha[:8]} rødlistes; se GitHub")
    else:
        m.log(f"   ❌ deploy RØD (kørsel {rid}: {res}) — se GitHub; {sha[:8]} dispatches ikke igen")
    m.api.post(f"/repos/{{repo}}/statuses/{sha}", {
        "state": "failure", "context": STATUS_ROED,
        "description": f"rødt prod-deploy i kørsel {rid} ({trin or res})"[:140]})
    return 0


# ------------------------------------------------------------------ udgang
def resume(m, v=None):
    e = m.env
    ud = [f"## Udgivelse — {e['APP']}", ""]
    if v is not None:
        ud += ["| app | fra (prod) | til | S-numre | udfald |", "|---|---|---|---|---|",
               f"| {e['APP']} | `{v.prod[:8] or '—'}` | `{v.sha[:8] or '—'}` | {v.s_numre or '—'} | "
               f"{'udgives' if v.udgiv else 'intet udgives: ' + (v.stop or '—')} |", ""]
        if v.holdt:
            ud += [f"Holdt tilbage: {'; '.join(v.holdt)}", ""]
    ud += ["```", *m.linjer, "```", ""]
    return "\n".join(ud)


def main(argv):
    fase = argv[1] if len(argv) > 1 else ""
    env = dict(os.environ)
    env.setdefault("HOVEDGREN", "main")
    env.setdefault("HOVED", f"origin/{env['HOVEDGREN']}")
    nu = datetime.fromisoformat(env["UDGIV_NU"]) if env.get("UDGIV_NU") else datetime.now(timezone.utc)
    m = Miljoe(env, GitHubApi(env["GITHUB_REPOSITORY"], env["GITHUB_TOKEN"]), health_sha, nu)
    if fase == "vaelg":
        v = vaelg(m)
        ud = {"udgiv": "true" if v.udgiv else "false", "sha": v.sha if v.udgiv else "",
              "prod_foer": v.prod, "slot": v.slot}
        if env.get("GITHUB_OUTPUT"):
            with open(env["GITHUB_OUTPUT"], "a") as f:
                f.writelines(f"{k}={v_}\n" for k, v_ in ud.items())
        kode = 0
    elif fase == "efter":
        v = None
        kode = efter(m)
    else:
        print("brug: udgiv.py vaelg|efter", file=sys.stderr)
        return 2
    if env.get("GITHUB_STEP_SUMMARY"):
        with open(env["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(resume(m, v))
    return kode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
