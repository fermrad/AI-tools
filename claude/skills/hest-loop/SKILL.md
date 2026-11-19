---
name: hest-loop
description: Kør husets arbejdsløkke fra feedback til prod med to godkendelser — idéen før der bygges, resultatet før der merges. Brug når Claude skal arbejde løbende på DevHub-feedback (timevagten), eller når nogen beder om «kør løkken» / «næste runde».
---


# hest-loop — fra feedback til prod med to stop

Løkken er timevagtens arbejde (feedback → sprint → hesten → PR → merge → udgivelse), men den
**stopper to gange** og spørger et menneske. Aftalt af Franco og Jakob 19-11-2026: Claude må
gerne foreslå og bygge, men vi beslutter, hvad der bygges, og hvad der kommer på `main`.

**De to faste regler**
- **Intet bygges uden et «byg».** Intet merges uden et «merge». Intet svar = punktet står stille.
- **Botten merger aldrig.** `ferm-hest` pusher grene, et menneske merger. Kun godkendte
  ændringer når `main`.

## 0 · Før hver runde
- Læs husets skills (repo-recon, hest-agent, new-pr) — de gælder i hvert trin herunder.
- Mål hesten som i `hest-agent` «Før du starter — mål maskinen». Er der ikke plads, bygges der
  ikke i denne runde; trin 1–4 må godt køre.

## 1 · Saml
Ny feedback fra alle apps (`list_feedback`, fase *ny*). «Ny» betyder kun, at ingen har koblet
den endnu — søg F-nummeret i sprint-punkterne, før noget oprettes.

## 2 · Analysér
For hver feedback: bug, ønske eller spørgsmål? Findes punktet allerede? Hvilken arbejdspakke
(R) og hvilket spor (T) hører den til? Hvem er R på pakken — det er den, der spørges.

## 3 · Filtrér — vi skal ikke afvise ligegyldige punkter hele tiden
- Dublet → kobl til det eksisterende punkt.
- Spørgsmål → besvar (hjælpetekst eller svar til afsender), intet punkt.
- Støj eller allerede løst → parkér med en grund.
Alt det står nederst i oversigten, uden at nogen skal svare.

## 4 · Skriv punktet
Opret S-punktet som `idea`, koblet F → S → R → T (DevHub kræver kæden).
> ⚠️ ÅBENT: oprettes punktet som `idea` før stop 1, eller først efter «byg»?

## ⏸ Stop 1 — idéen (Teams)
Én samlet oversigt, højst 2× om dagen (fx 9:00 og 14:00), til hver R. Kort nok til en telefon:

```
🐴 3 nye idéer · svar med nummer

1) S-1720 «Kort: ét kort over listen overalt» (project)
   Problem: 2 brugere farer vild på Arwos-kortet (F-812, F-815)
   Idé: samme kort+liste som fælleskortet
   Alternativ: fjern kun det tredje kort
   Størrelse: lille
   → byg / ret / parkér / drop

Klaret af mig, intet svar nødvendigt:
· F-820 = dublet af S-1650, koblet
```
Svar: `1 byg, 2 drop allerede løst, 3 ret: kun på projektkortet`.
- **byg** → `planned`, videre til 5. **ret** → skriv om, med i næste oversigt.
  **parkér** / **drop** → sæt status, skriv grunden på punktet.
- Intet svar → én påmindelse i næste oversigt, derefter står punktet parkeret.
> ⚠️ ÅBENT: Teams fra en hovedløs session på hesten kræver eget Microsoft-login (samme
> problem som DevHub-login i R-170). Indtil da sendes fra laptoppen.

## 5 · Byg
Husets faste flow fra `repo-recon`: recon → byg + `/run` → test i browser (`Set i browser:`) →
`/simplify` → `/code-review` → `/new-pr` (kladde-PR). Kør på hesten efter `hest-agent`,
`--model sonnet` som standard.
- **Egen gren, intet på `main`.**
- PR'en åbnes fra laptoppen, som `hest-agent` trin 4 siger.
> ⚠️ ÅBENT: små punkter samles i dag på én *samling*-gren (husregel 06-11). Så viser én
> preview flere ændringer. Godkendes de samlet, eller får hvert punkt sin egen gren?

## 6 · Preview
Sæt etiketten `dev-deploy` på PR'en → `deploy-pr-stack.yml` rejser
`https://<PR>.dev.project.ferm.dk`. Den forsvinder igen, når PR'en lukkes.
- Previewen har sin egen database med **opdigtede data** (seed) — af sikkerhedsgrunde: appen
  kører `db push` med grenens ikke-godkendte skema, før den starter, og dev-boksen er ikke
  stedet for rigtige kundedata. Ting, der kræver rigtige data, ses først på staging.
- Kun `project` har previews i dag.
> ⚠️ ÅBENT: hvordan logger man ind på en preview? Og stakken er sidst brugt 04-08-2026
> (#264) — prøv den, før løkken hviler på den.

## ⏸ Stop 2 — resultatet (Teams)
Ét kort pr. punkt, når det er klar:
```
🐴 Klar til at se · S-1720 «Kort: ét kort over listen»
Ændret: Arwos-siden bruger nu fælleskortet + listen
[før] [efter]
Prøv den: https://2231.dev.project.ferm.dk
CI grøn · hjælp rettet
→ merge / ret: …
```
- **merge** → **merges med det samme**, ingen ekstra runde: PR'en markeres klar og merges til
  `main` på godkenderens eget login (laptop-sessionen), aldrig som `ferm-hest` → staging.
- **ret: …** → tilbage til 5 med rettelsen.

## 7 · Udgivelse
Prod kun i slottene via `udgiv.yml` og kun op til nyeste PR med `prod-ja` fra Jakob eller Mads.
Når health svarer den nye sha: S-punktet → `shipped`, koblet feedback lukker selv.
> ⚠️ ÅBENT: er stop 2 nok, eller bliver `prod-ja` et tredje stop?

## 8 · Besked og forfra
```
✅ I prod 12:00 · S-1720 · F-812, F-815 lukket
```
Går noget i stå (CI rød to gange, bygget dør), sendes kun: `⚠️ S-1720 stoppet: CI rød to gange.
Kræver dig.` Derefter forfra fra 1.
