---
name: sikkerhedsgennemgang
description: Uafhængig sikkerhedsgennemgang af en gren mod en EKSPLICIT diff-range — nægter at svare på et tomt grundlag. Brug den i stedet for /security-review, når arbejdet ligger i en worktree.
---

Uafhængig sikkerhedsgennemgang af ændringerne på den aktuelle gren.

> ## ⛔ Reglen, skillen findes for
>
> **Sig hvad du læste, eller sig ingenting. En gennemgang, der ikke kan sige,
> hvor mange filer den så, har ikke læst noget.**

## Hvorfor den findes — og hvorfor den ikke hedder `security-review`

`/security-review` er Claude Codes **indbyggede** skill. Den kører mod
**sessionens cwd**, og det er den forudsætning, der brister her: i `fermrad`
er det normale arbejdsform at ligge i en **git-worktree**, mens sessionen står
i den delte klon på `main`.

Når det sker, bliver både fil-listen og diffen **tomme** — og svaret bliver:

> *"Ingen sikkerhedsfund."*

**Med fuld overbevisning, og uden at nævne, at den ikke så noget.** Det er den
farligste form for svar: det ligner et gennemført review, det bliver citeret
som et, og det efterlader intet spor af, at grundlaget manglede.

**Målt tre gange i træk 15-08-2026** (S-359) — snit 1, 2 og 3 af S-45 ramte
alle den samme fejl, og alle tre rørte adgangsmodellen. Havde agenterne stolet
på svaret, var to konkrete huller gået umærket igennem: en `include`, der ville
have vist kunde B's navn i kunde A's kolonne, og et `"use client"`-modul kaldt
fra to serverkomponenter, som hverken byg eller typecheck ville fange.

**16-08-2026 ramte den en fjerde variant:** skillen nægtede at starte, fordi
sessionens cwd ikke var et git-repo. Det var i det mindste højlydt — men det
efterlod dagens adgangsændring uden en uafhængig gennemgang.

Navnet er dansk med vilje: **det må ikke kunne forveksles med den indbyggede**,
og `sikkerhedsgennemgang` er i forvejen husets ord for netop dette i `CLAUDE.md`
og i sprintpunkterne.

## 1. Fastlæg grundlaget — og sig det højt

Alt herunder køres med **eksplicit sti**, aldrig i tillid til sessionens cwd:

```bash
WT=<sti til worktree eller klon>
git -C "$WT" fetch -q origin
BASE=$(git -C "$WT" merge-base origin/main HEAD)
git -C "$WT" diff --stat "$BASE"...HEAD
git -C "$WT" diff --name-only "$BASE"...HEAD | wc -l
```

**Brug tre prikker (`...`), ikke to.** `A..B` viser forskellen mod *nuværende*
`main`, så commits, andre har merget i mellemtiden, tælles med som dine.
`A...B` viser kun grenens eget arbejde fra dens fælles ophav.

## 2. STOP, hvis grundlaget er tomt

**Er antallet nul, må der ikke afgives et svar.** Meld i stedet:

> Jeg kan ikke gennemgå noget: `<range>` giver 0 filer i `<sti>`.
> Kontrollér stien og grenen — sessionens cwd er `<cwd>`.

Og **stop**. Det er hele skillens grund til at findes.

Det er husets egen regel om positive kontroller, vendt mod værktøjet: *en grøn
kørsel beviser intet, før man har set den kunne fejle.* En gennemgang uden
filer er en grøn kørsel, der ikke kunne fejle.

## 3. Gennemgå — som en UAFHÆNGIG læser

Deleger til `security-reviewer`-agenten frem for at læse selv. Den er
læse-kun, kører på Opus, og — vigtigst — **den har ikke skrevet koden.**

```
Agent({
  subagent_type: "security-reviewer",
  prompt: "Gennemgå diffen <BASE>...HEAD i <WT>. FILER: <liste>. " +
          "Fokusér på: adgangs-guards pr. endpoint, hvad der havner i " +
          "RSC-payloaden, aggregater der ikke bærer rækkernes filter, og " +
          "gates der fejler ÅBENT. Rapportér med file:line."
})
```

**Skriv fillisten ind i prompten.** Uden den finder agenten selv sit
grundlag — og så er vi tilbage ved det problem, skillen løser.

**En gennemgang, du selv laver af din egen kode, er den svageste form.** Kan
agenten ikke bruges, så sig det i rapporten frem for at lade det stå åbent.

## 4. Fokusér på det, huset FAKTISK har lækket

Hvert punkt herunder er en fejl, der er fundet i produktion i `fermrad` — ikke
en generisk tjekliste:

- **Hver `"use server"`-eksport er sit eget POST-endpoint.** At kalderen er en
  gatet side tæller ikke. Sidens guard dækker kun siden.
- **Props serialiseres ned i RSC-payloaden.** Et felt, komponenten "bare ikke
  bruger", er stadig læsbart i browseren. Ramte `hiddenModules`,
  `Report.snapshot.frozen` og projektbåndets budgetloft.
- **Et tal skal bære samme filter som rækkerne.** Et `count()` i basen tæller
  bredere end et snit, der sker i hukommelsen.
- **Gates, der fejler ÅBENT.** `row?.projectId ?? null` folder "findes ikke"
  sammen med "ægte projektløs" — og den gren returnerer tavst.
- **Den rigtige gate, ikke den nærmeste.** En projektguard beviser intet om en
  organisations salgsdata; `filterByProjectView` er forkert i arbejdsrummet.
- **Anonyme afvisninger.** "Findes ikke" og "du må ikke" skal give samme svar,
  når kalderen er et håndlavet POST.

## 5. Rapportér — med grundlaget i toppen

Begynd **altid** med, hvad der blev læst:

> Gennemgået `<BASE>...HEAD` i `<sti>`: **N filer**, M linjer.

Derefter fundene med `file:line`, og til sidst **hvad gennemgangen ikke kunne
dække** — en manglende baseadgang, en flade der kræver login, en agent der
ikke kunne køre. Et forbehold, der ikke er skrevet, findes ikke.
