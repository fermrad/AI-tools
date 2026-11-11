#!/usr/bin/env python3
# =====================================================================
# Prøve af scripts/udgiv/udgiv.py — logikken bag udgiv-app.yml (S-1633
# «Udgivelse uden laptop: fælles workflow «udgiv-app.yml» i AI-tools med
# godkendelse via etiket»).
#
# Uden GitHub: et rigtigt git-repo bygges i en midlertidig mappe (så datagaten,
# rev-list og `git show` er de rigtige), og alle API-svar er fixtures i
# FalskApi. Health er en funktion, der svarer en fast sha.
#
# Køres af scripts/test-udgiv-app.sh, som også kører BRUDDENE: en bevidst
# ødelagt kopi af udgiv.py, som denne prøve SKAL fælde.
#
# MÅLETABEL — hvad prøven måler, og hvad den forventer
# ┌────┬──────────────────────────────────────────────────────┬──────────────────────────────┐
# │ #  │ situation                                            │ forventet                    │
# ├────┼──────────────────────────────────────────────────────┼──────────────────────────────┤
# │ S1 │ hverdag vinter, cron 12:07 DK, startet 12:09         │ slot «2026-11-11 12»         │
# │ S2 │ hverdag sommer, samme cron                           │ slot «2026-07-15 12»         │
# │ S3 │ søndag 25-10-2026 (vintertid fra 03:00), 07:07 DK    │ slot «2026-10-25 07»         │
# │ S4 │ søndag 29-03-2026 (sommertid fra 02:00), 07:07 DK    │ slot «2026-03-29 07»         │
# │ S5 │ cron 12:37 forsinket til 13:02 DK                    │ slot 12, ikke 13             │
# │ S6 │ cron 12:07 startet 12:40 (maks 25 min)               │ intet slot (for sent)        │
# │ S7 │ UTC-cron 10:07 og 11:07, vinter og sommer            │ kun den ene giver slot 12    │
# │ S8 │ onsdag 16:07 (16 er kun weekend)                     │ intet slot                   │
# │ S9 │ manuel kørsel i en slot-time                         │ intet slot (kun planlagt)    │
# │ G1 │ prod-ja af MadsSFox på #2 (c2), c3 uden              │ udgiver c2, c3 venter        │
# │ G2 │ prod-ja sat af ferm-hest[bot]                        │ intet udgives                │
# │ G3 │ Jakob satte prod-ja, bot satte den igen bagefter     │ intet udgives                │
# │ G4 │ prod-ja på #3 (c3) → c1 (direkte push) er dækket     │ udgiver c3                   │
# │ G5 │ kraever_godkendelse=false (area51)                   │ udgiver main (c3)            │
# │ D1 │ datafil (update projekt) i c2 uden data-ja           │ udgiver c1, data venter      │
# │ D2 │ samme, data-ja af jb-ferm på #2                      │ udgiver c2                   │
# │ D3 │ samme, data-ja af en agent                           │ udgiver c1                   │
# │ D4 │ kun kortdata (update anlaeg, upsert på person)       │ tilladt uden data-ja         │
# │ D5 │ datafil i første commit efter prod                   │ intet udgives                │
# │ D6 │ .ts-backfill (area51-mønster)                        │ stopper altid uden data-ja   │
# │ D7 │ .sql uden rækkeændring (kun CHECK)                   │ tilladt                      │
# │ K1 │ hovedet rødt på staging, c2 grøn på begge            │ udgiver c2                   │
# │ K2 │ c3 CI grøn/staging rød, c2 staging grøn/CI rød, c1 ø │ intet grønt → intet          │
# │ K3 │ kørsel «vent» (ikke færdig)                          │ ikke grøn                    │
# │ R1 │ udgiv/roed=failure på kandidaten                     │ intet udgives                │
# │ R2 │ udgiv/roed ryddet (nyere success)                    │ udgives                      │
# │ R3 │ indholdskrav i .github/udgiv-kraev.txt ikke opfyldt  │ intet udgives                │
# │ L1 │ tidligere kørsel i slottet rørte boksen              │ «allerede dispatchet»        │
# │ L2 │ tidligere kørsel i slottet stoppede i Setup SSH      │ udgives (nyt forsøg)         │
# │ L3 │ en anden kørsel er i gang                            │ springer over                │
# │ T1 │ toerloeb=true                                        │ udgiv=false, «tørløb — ville» │
# │ T2 │ workflow_dispatch med toerloeb=false                 │ tvunget tørløb               │
# │ H1 │ health svarer ikke                                   │ springer over                │
# │ H2 │ prod-sha ligger ikke på main                         │ springer over                │
# │ H3 │ prod-versionen mangler varsel-scriptet               │ intet udgives                │
# │ U1 │ main(): outputs udgiv/sha/slot og resumé            │ udgiv=true, sha=c2           │
# │ U2 │ main() i tørløb                                      │ udgiv=false, sha tom         │
# │ E1 │ deploy grønt, health svarer sha'en                   │ ingen status skrives         │
# │ E2 │ rød i «Setup SSH», 0 forsøg før                      │ forsøg 1/3, ingen rødliste   │
# │ E3 │ rød i «Setup SSH», 2 forsøg før                      │ forsøg 3/3 + rødliste        │
# │ E4 │ rød i «Run SQL scripts»                              │ rødliste med det samme       │
# │ E5 │ jobs kan ikke læses                                  │ rødliste (laptoppens default)│
# └────┴──────────────────────────────────────────────────────┴──────────────────────────────┘
# =====================================================================
import os
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.environ.get("UDGIV_MODUL_DIR") or os.path.dirname(os.path.abspath(__file__)))
import udgiv  # noqa: E402

HVERDAG = "12 17 22"
WEEKEND = "07 12 16 22"
JAKOB, MADS, BOT = "jb-ferm", "MadsSFox", "ferm-hest[bot]"


def utc(s):
    return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)


class FalskApi:
    def __init__(self):
        self.prs = {}          # sha → [pr]
        self.events = {}       # nr → [event]
        self.runs = {}         # (workflow, sha) → (status, conclusion)
        self.statusser = {}    # sha → [status], nyeste først
        self.tidligere = []    # kørsler af kalderen i slottet
        self.jobs = {}         # run-id → [job]
        self.fejl = set()      # stier (regex), der kaster ApiFejl
        self.posts = []

    def get(self, sti):
        for f in self.fejl:
            if re.search(f, sti):
                raise udgiv.ApiFejl(sti)
        if m := re.fullmatch(r"/repos/\{repo\}/commits/(\w+)/pulls", sti):
            return self.prs.get(m[1], [])
        if m := re.fullmatch(r"/repos/\{repo\}/issues/(\d+)/events\?per_page=100&page=(\d+)", sti):
            return self.events.get(int(m[1]), []) if m[2] == "1" else []
        if m := re.fullmatch(r"/repos/\{repo\}/actions/workflows/([\w.-]+)/runs\?head_sha=(\w+)&event=push&per_page=1", sti):
            k = self.runs.get((m[1], m[2]))
            return {"workflow_runs": [{"status": k[0], "conclusion": k[1]}] if k else []}
        if m := re.fullmatch(r"/repos/\{repo\}/commits/(\w+)/statuses\?per_page=100", sti):
            return self.statusser.get(m[1], [])
        if re.fullmatch(r"/repos/\{repo\}/actions/runs/9000", sti):
            return {"workflow_id": 77}
        if re.fullmatch(r"/repos/\{repo\}/actions/workflows/77/runs\?created=%3E%3D[\dT:Z-]+&per_page=50", sti):
            return {"workflow_runs": [{"id": 9000, "status": "in_progress"}] + self.tidligere}
        if m := re.fullmatch(r"/repos/\{repo\}/actions/runs/(\d+)(/attempts/\d+)?/jobs\?per_page=100&page=1", sti):
            return {"jobs": self.jobs.get(int(m[1]), [])}
        raise AssertionError(f"ingen fixture for {sti}")

    def post(self, sti, data):
        self.posts.append((sti, data))
        return {}


def pr(nr, merge_sha, *etiketter):
    return {"number": nr, "merged_at": "2026-11-11T09:00:00Z", "base": {"ref": "main"},
            "merge_commit_sha": merge_sha, "labels": [{"name": e} for e in etiketter]}


def sat(navn, login):
    return {"event": "labeled", "label": {"name": navn}, "actor": {"login": login}}


def job(navn, konklusion, *trin):
    return {"name": navn, "conclusion": konklusion,
            "steps": [{"name": n, "conclusion": k} for n, k in trin]}


class Repo:
    """prod = c0 → c1 (direkte push) → c2 (#2) → c3 (#3) = main."""

    def __init__(self, data_c2=None, data_c1=None, varsel_i_prod=True, kraev=None):
        self.dir = tempfile.mkdtemp(prefix="udgiv-proeve-")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        self.skriv(".github/prod-startere.txt", f"# hvem må starte prod\n{JAKOB}\n{MADS}\n")
        self.skriv(".github/workflows/deploy.yml", "on:\n  workflow_call:\n    inputs:\n      varsel_minutter: {}\n")
        if varsel_i_prod:
            self.skriv("scripts/driftsvarsel-saet.ts", "// varsel\n")
        self.skriv("src/a.ts", "export const a = 0\n")
        self.c0 = self.commit("chore: grundlag")
        self.skriv("src/a.ts", "export const a = 1\n")
        if data_c1:
            self.skriv(*data_c1)
        self.c1 = self.commit("fix: direkte push (S-101)")
        self.skriv("src/b.ts", "export const b = 2\n")
        if data_c2:
            self.skriv(*data_c2)
        self.c2 = self.commit("feat: noget (S-102) (#2)")
        self.skriv("src/c.ts", "export const c = 3\n")
        if kraev:
            self.skriv(".github/udgiv-kraev.txt", kraev)
        self.c3 = self.commit("feat: mere (S-103) (#3)")
        self.git("update-ref", "refs/remotes/origin/main", self.c3)

    def git(self, *a):
        return subprocess.run(["git", "-C", self.dir, *a], check=True, capture_output=True, text=True).stdout.strip()

    def skriv(self, sti, tekst):
        p = os.path.join(self.dir, sti)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(tekst)

    def commit(self, besked):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", besked)
        return self.git("rev-parse", "HEAD")


def alt_groent(api, repo, ci="ci.yml"):
    for c in (repo.c1, repo.c2, repo.c3):
        api.runs[("deploy.yml", c)] = ("completed", "success")
        if ci:
            api.runs[(ci, c)] = ("completed", "success")


def env(repo, **over):
    e = {
        "KLON": repo.dir, "HOVEDGREN": "main", "HOVED": "origin/main", "APP": "project",
        "URL": "https://project.example", "DATA_MOENSTER": "^scripts/sql/", "CI_WORKFLOW": "ci.yml",
        "STAGING_WORKFLOW": "deploy.yml", "KRAEVER_GODKENDELSE": "true",
        "SLOTS_HVERDAG": HVERDAG, "SLOTS_WEEKEND": WEEKEND, "TIDSZONE": "Europe/Copenhagen",
        "CRON_TIDSZONE": "Europe/Copenhagen", "MAKS_FORSINKELSE": "25",
        "VARSEL_SCRIPT": "scripts/driftsvarsel-saet.ts", "TOERLOEB": "false",
        "SCHEDULE": "7,37 12,17,22 * * 1-5", "EVENT_NAME": "schedule",
        "STARTERE_FIL": ".github/prod-startere.txt", "KRAEV_FIL": ".github/udgiv-kraev.txt",
        "DEPLOY_JOB_MOENSTER": "(^|/ )deploy$", "RUN_ID": "9000", "RUN_ATTEMPT": "1",
    }
    e.update(over)
    return e


NU = utc("2026-11-11T11:09:00")  # onsdag 12:09 dansk vintertid


def koer(repo, api, nu=NU, prod=None, **over):
    m = udgiv.Miljoe(env(repo, **over), api, lambda url: repo.c0 if prod is None else prod, nu, sove=lambda s: None)
    return udgiv.vaelg(m), "\n".join(m.linjer)


def godkendt(api, repo, nr=2, login=MADS):
    sha = repo.c2 if nr == 2 else repo.c3
    api.prs[sha] = [pr(nr, sha, "prod-ja")]
    api.events[nr] = [sat("prod-ja", login)]


# ------------------------------------------------------------------ slot
class Slot(unittest.TestCase):
    def slot(self, nu, cron="7 12,17,22 * * 1-5", cron_tz="Europe/Copenhagen", weekend=WEEKEND, maks=25):
        return udgiv.find_slot(nu, cron, cron_tz, "Europe/Copenhagen", HVERDAG, weekend, maks)[0]

    def test_s1_vinter(self):
        self.assertEqual(self.slot(utc("2026-11-11T11:09:00")), "2026-11-11 12")

    def test_s2_sommer(self):
        self.assertEqual(self.slot(utc("2026-07-15T10:09:00")), "2026-07-15 12")

    def test_s3_skift_til_vintertid(self):
        self.assertEqual(self.slot(utc("2026-10-25T06:08:00"), "7 7,12,16,22 * * 0,6"), "2026-10-25 07")
        self.assertIsNone(self.slot(utc("2026-10-25T05:08:00"), "7 7,12,16,22 * * 0,6"))

    def test_s4_skift_til_sommertid(self):
        self.assertEqual(self.slot(utc("2026-03-29T05:08:00"), "7 7,12,16,22 * * 0,6"), "2026-03-29 07")
        self.assertIsNone(self.slot(utc("2026-03-29T06:08:00"), "7 7,12,16,22 * * 0,6"))

    def test_s5_forsinket_over_timeskiftet(self):
        # 12:37 DK planlagt, startet 13:02 DK → stadig slot 12, ikke 13.
        self.assertEqual(self.slot(utc("2026-11-11T12:02:00"), "7,37 12,13,17,22 * * 1-5"), "2026-11-11 12")

    def test_s6_for_sent(self):
        self.assertIsNone(self.slot(utc("2026-11-11T11:40:00")))

    def test_s7_utc_cron(self):
        cron = "7 10,11 * * 1-5"
        self.assertIsNone(self.slot(utc("2026-11-11T10:08:00"), cron, "UTC"))
        self.assertEqual(self.slot(utc("2026-11-11T11:08:00"), cron, "UTC"), "2026-11-11 12")
        self.assertEqual(self.slot(utc("2026-07-15T10:08:00"), cron, "UTC"), "2026-07-15 12")
        self.assertIsNone(self.slot(utc("2026-07-15T11:08:00"), cron, "UTC"))

    def test_s8_weekendtid_paa_hverdag(self):
        self.assertIsNone(self.slot(utc("2026-11-11T15:08:00"), "7 16 * * *"))

    def test_s9_manuel(self):
        self.assertIsNone(udgiv.find_slot(NU, "", "Europe/Copenhagen", "Europe/Copenhagen", HVERDAG, WEEKEND, 25)[0])

    def test_cron_navne_afvises(self):
        self.assertIsNone(self.slot(NU, "7 12 * * MON"))


# --------------------------------------------------------- godkendelse
class Godkendelse(unittest.TestCase):
    def setUp(self):
        self.r, self.a = Repo(), FalskApi()
        alt_groent(self.a, self.r)

    def test_g1_kun_til_og_med_den_godkendte_pr(self):
        godkendt(self.a, self.r)
        v, log = koer(self.r, self.a)
        self.assertTrue(v.udgiv, log)
        self.assertEqual(v.sha, self.r.c2)
        self.assertIn("1 commit(s) efter", log)
        m = udgiv.Miljoe(env(self.r), self.a, lambda url: self.r.c0, NU)
        ud = udgiv.resume(m, v)
        self.assertIn(f"| project | `{self.r.c0[:8]}` | `{self.r.c2[:8]}` | S-101 S-102 | udgives |", ud)
        self.assertIn("Holdt tilbage: 1 commit(s) efter", ud)

    def test_g2_sat_af_en_uden_for_listen(self):
        godkendt(self.a, self.r, login=BOT)
        v, log = koer(self.r, self.a)
        self.assertFalse(v.udgiv, log)
        self.assertIn("ferm-hest[bot], som ikke står", log)

    def test_g3_seneste_event_taeller(self):
        godkendt(self.a, self.r)
        self.a.events[2] = [sat("prod-ja", JAKOB), {"event": "unlabeled", "label": {"name": "prod-ja"}}, sat("prod-ja", BOT)]
        self.assertFalse(koer(self.r, self.a)[0].udgiv)

    def test_g4_direkte_push_under_godkendt_pr(self):
        godkendt(self.a, self.r, nr=3)
        v, log = koer(self.r, self.a)
        self.assertEqual(v.sha, self.r.c3, log)

    def test_g5_area51_uden_godkendelse(self):
        v, log = koer(self.r, self.a, KRAEVER_GODKENDELSE="false")
        self.assertEqual(v.sha, self.r.c3, log)

    def test_etiket_fjernet_igen(self):
        self.a.prs[self.r.c2] = [pr(2, self.r.c2)]  # ingen etiket nu
        self.a.events[2] = [sat("prod-ja", JAKOB)]
        self.assertFalse(koer(self.r, self.a)[0].udgiv)

    def test_uden_startere_fil_godkendes_intet(self):
        godkendt(self.a, self.r, login=JAKOB)
        v, log = koer(self.r, self.a, STARTERE_FIL=".github/findes-ikke.txt")
        self.assertFalse(v.udgiv, log)


# -------------------------------------------------------------- datagate
class Data(unittest.TestCase):
    def lav(self, sti, tekst, data_ja=None, i_c1=False, moenster="^scripts/sql/"):
        r = Repo(data_c1=(sti, tekst) if i_c1 else None, data_c2=None if i_c1 else (sti, tekst))
        a = FalskApi()
        alt_groent(a, r)
        godkendt(a, r, nr=3)
        if data_ja:
            a.prs[r.c2] = [pr(2, r.c2, "data-ja")]
            a.events[2] = [sat("data-ja", data_ja)]
        return koer(r, a, DATA_MOENSTER=moenster), r

    def test_d1_uden_data_ja(self):
        (v, log), r = self.lav("scripts/sql/600-x.sql", "update projekt set navn = 'x';\n")
        self.assertEqual(v.sha, r.c1, log)
        self.assertIn("ÆNDRER PROD-DATA", log)

    def test_d2_med_data_ja(self):
        (v, log), r = self.lav("scripts/sql/600-x.sql", "update projekt set navn = 'x';\n", data_ja=JAKOB)
        self.assertEqual(v.sha, r.c3, log)

    def test_d3_data_ja_af_agent(self):
        (v, log), r = self.lav("scripts/sql/600-x.sql", "update projekt set navn = 'x';\n", data_ja=BOT)
        self.assertEqual(v.sha, r.c1, log)

    def test_d4_kun_kortdata(self):
        sql = ("-- kort\ncreate temp table t as select 1;\nupdate anlaeg set x = 1;\ninsert into t values (1);\n"
               "insert into person (id) values (1) on conflict (id) do update set navn = 'a';\n")
        (v, log), r = self.lav("scripts/sql/601-kort.sql", sql)
        self.assertEqual(v.sha, r.c3, log)
        self.assertIn("kun kort-/kontaktdata", log)

    def test_d4b_truncate_paa_kortdata_stopper(self):
        (v, log), r = self.lav("scripts/sql/602.sql", "truncate anlaeg;\n")
        self.assertEqual(v.sha, r.c1, log)

    def test_d5_data_foerst(self):
        (v, log), r = self.lav("scripts/sql/600-x.sql", "delete from projekt;\n", i_c1=True)
        self.assertFalse(v.udgiv, log)
        self.assertIn("ingen kode foran datamigreringen", log)

    def test_d6_ts_backfill(self):
        (v, log), r = self.lav("scripts/backfill-x.ts", "console.log(1)\n",
                               moenster="^scripts/([^/]*\\.sql|backfill-|sql/)")
        self.assertEqual(v.sha, r.c1, log)

    def test_d7_kun_check(self):
        (v, log), r = self.lav("scripts/sql/500-check.sql", "alter table x add constraint c check (y > 0);\n")
        self.assertEqual(v.sha, r.c3, log)


# ----------------------------------------------------------------- grøn
class Groen(unittest.TestCase):
    def setUp(self):
        self.r, self.a = Repo(), FalskApi()
        alt_groent(self.a, self.r)
        godkendt(self.a, self.r, nr=3)

    def test_k1_hovedet_roedt(self):
        self.a.runs[("deploy.yml", self.r.c3)] = ("completed", "failure")
        v, log = koer(self.r, self.a)
        self.assertEqual(v.sha, self.r.c2, log)

    def test_k2_groen_paa_hver_sin(self):
        self.a.runs[("deploy.yml", self.r.c3)] = ("completed", "failure")
        self.a.runs[("ci.yml", self.r.c2)] = ("completed", "failure")
        self.a.runs.pop(("ci.yml", self.r.c1))
        v, log = koer(self.r, self.a)
        self.assertFalse(v.udgiv, log)
        self.assertIn("ingen grøn commit", log)

    def test_k3_vent(self):
        for c in (self.r.c1, self.r.c2, self.r.c3):
            self.a.runs[("ci.yml", c)] = ("in_progress", None)
        self.assertFalse(koer(self.r, self.a)[0].udgiv)


# ------------------------------------------------- rødliste, krav, slot
class Bremser(unittest.TestCase):
    def setUp(self):
        self.r, self.a = Repo(), FalskApi()
        alt_groent(self.a, self.r)
        godkendt(self.a, self.r, nr=3)

    def test_r1_roedlistet(self):
        self.a.statusser[self.r.c3] = [{"context": "udgiv/roed", "state": "failure", "description": "x"}]
        self.assertFalse(koer(self.r, self.a)[0].udgiv)

    def test_r2_ryddet(self):
        self.a.statusser[self.r.c3] = [{"context": "udgiv/roed", "state": "success"},
                                       {"context": "udgiv/roed", "state": "failure"}]
        self.assertTrue(koer(self.r, self.a)[0].udgiv)

    def test_r1b_roedlisten_kan_ikke_laeses(self):
        self.a.fejl.add("/statuses")
        self.assertFalse(koer(self.r, self.a)[0].udgiv)

    def test_r3_indholdskrav(self):
        r = Repo(kraev="src/a.ts vand\n")
        a = FalskApi()
        alt_groent(a, r)
        godkendt(a, r, nr=3)
        v, log = koer(r, a)
        self.assertFalse(v.udgiv, log)
        self.assertIn("mangler rettelsen", log)

    def test_l1_slot_brugt(self):
        self.a.tidligere = [{"id": 8000, "status": "completed"}]
        self.a.jobs[8000] = [job("deploy / deploy (production) / deploy", "success", ("Run SQL scripts", "success"))]
        v, log = koer(self.r, self.a)
        self.assertFalse(v.udgiv, log)
        self.assertIn("allerede dispatchet", log)

    def test_l2_slot_proeves_igen(self):
        self.a.tidligere = [{"id": 8000, "status": "completed"}]
        self.a.jobs[8000] = [job("deploy / deploy (production) / deploy", "failure", ("Setup SSH", "failure"))]
        self.assertTrue(koer(self.r, self.a)[0].udgiv)

    def test_l3_anden_koersel(self):
        self.a.tidligere = [{"id": 8000, "status": "in_progress"}]
        self.assertFalse(koer(self.r, self.a)[0].udgiv)

    def test_t1_toerloeb(self):
        v, log = koer(self.r, self.a, TOERLOEB="true")
        self.assertFalse(v.udgiv)
        self.assertIn("tørløb — ville udgive", log)

    def test_t2_manuel_er_altid_toer(self):
        v, log = koer(self.r, self.a, EVENT_NAME="workflow_dispatch", SCHEDULE="")
        self.assertFalse(v.udgiv, log)

    def test_h1_health(self):
        v, log = koer(self.r, self.a, prod="")
        self.assertFalse(v.udgiv)
        self.assertIn("health svarer ikke", log)

    def test_h2_prod_ikke_paa_main(self):
        self.assertFalse(koer(self.r, self.a, prod="f" * 40)[0].udgiv)

    def test_h3_varsel_script(self):
        r = Repo(varsel_i_prod=False)
        a = FalskApi()
        alt_groent(a, r)
        godkendt(a, r, nr=3)
        v, log = koer(r, a)
        self.assertFalse(v.udgiv, log)
        self.assertIn("varsel-scriptet", log)

    def test_uden_for_slot(self):
        v, log = koer(self.r, self.a, nu=utc("2026-11-11T12:30:00"))
        self.assertFalse(v.udgiv, log)


class Udgang(unittest.TestCase):
    """main() skriver outputs og resumé — `udgiv=true` er det, der åbner for deployet."""

    def koer_main(self, **over):
        r, a = Repo(), FalskApi()
        alt_groent(a, r)
        godkendt(a, r)
        d = tempfile.mkdtemp()
        e = env(r, GITHUB_REPOSITORY="fermrad/x", GITHUB_TOKEN="t", UDGIV_NU=NU.isoformat(),
                GITHUB_OUTPUT=f"{d}/out", GITHUB_STEP_SUMMARY=f"{d}/sum", **over)
        gamle = (dict(os.environ), udgiv.GitHubApi, udgiv.health_sha)
        os.environ.clear()
        os.environ.update(e)
        udgiv.GitHubApi, udgiv.health_sha = (lambda repo, token: a), (lambda url: r.c0)
        try:
            self.assertEqual(udgiv.main(["udgiv.py", "vaelg"]), 0)
        finally:
            os.environ.clear()
            os.environ.update(gamle[0])
            udgiv.GitHubApi, udgiv.health_sha = gamle[1], gamle[2]
        return r, open(f"{d}/out").read(), open(f"{d}/sum").read()

    def test_udgiv_true_med_sha(self):
        r, out, resume = self.koer_main()
        self.assertIn("udgiv=true\n", out)
        self.assertIn(f"sha={r.c2}\n", out)
        self.assertIn("slot=2026-11-11 12\n", out)
        self.assertIn("🚀 udgiver", resume)

    def test_toerloeb_giver_ingen_sha(self):
        r, out, _ = self.koer_main(TOERLOEB="true")
        self.assertIn("udgiv=false\n", out)
        self.assertIn("sha=\n", out)


# ----------------------------------------------------------------- efter
class Efter(unittest.TestCase):
    def koer(self, resultat, jobs=None, forsoeg=0, health=None):
        r, a = Repo(), FalskApi()
        a.jobs[9000] = jobs or []
        a.statusser[r.c2] = [{"context": "udgiv/forsoeg", "state": "error"}] * forsoeg
        if jobs is None:
            a.fejl.add("/jobs")
        m = udgiv.Miljoe(env(r, SHA=r.c2, PROD_FOER=r.c0, DEPLOY_RESULTAT=resultat, SLOT="2026-11-11 12"),
                         a, lambda url: health or r.c2, NU, sove=lambda s: None)
        udgiv.efter(m)
        return [d["context"] for _, d in a.posts], "\n".join(m.linjer)

    def test_e1_groen(self):
        poster, log = self.koer("success", [])
        self.assertEqual(poster, [])
        self.assertIn("health svarer", log)

    def test_e2_setup_ssh(self):
        poster, log = self.koer("failure", [job("udgiv / deploy (production) / deploy", "failure", ("Setup SSH", "failure"))])
        self.assertEqual(poster, ["udgiv/forsoeg"], log)

    def test_e3_tredje_gang(self):
        poster, log = self.koer("failure", [job("udgiv / deploy (production) / deploy", "failure", ("Setup SSH", "failure"))], forsoeg=2)
        self.assertEqual(poster, ["udgiv/forsoeg", "udgiv/roed"], log)

    def test_e3b_stoppede_i_driftsvarsel(self):
        poster, _ = self.koer("failure", [job("udgiv / Driftsvarsel", "failure", ("Sæt varslet", "failure")),
                                          job("udgiv / deploy (production) / deploy", "skipped")])
        self.assertEqual(poster, ["udgiv/forsoeg"])

    def test_e4_run_sql(self):
        poster, _ = self.koer("failure", [job("udgiv / deploy (production) / deploy", "failure",
                                              ("Setup SSH", "success"), ("Run SQL scripts", "failure"))])
        self.assertEqual(poster, ["udgiv/roed"])

    def test_e5_jobs_ulaeselige(self):
        self.assertEqual(self.koer("failure", None)[0], ["udgiv/roed"])


if __name__ == "__main__":
    unittest.main(buffer=True)
