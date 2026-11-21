---
name: hest-loop
description: Kør husets arbejdsløkke fra feedback til prod. Claude analyserer hvert punkt med fire spørgsmål og bygger; et menneske merger altid og spørges kun før bygningen, når punktet er risikabelt, stort, usikkert eller ønsket udefra. Brug når Claude skal arbejde løbende på DevHub-feedback (timevagten), eller når nogen beder om «kør løkken» / «næste runde».
---

# hest-loop — fra feedback til prod

Timevagtens løkke (feedback → sprint → hesten → PR → merge → udgivelse) med **én fast menneskelig
godkendelse: merge**. Claude tænker selv over hvert punkt (de fire spørgsmål i trin 2) og spørger
kun før bygningen, når det er nødvendigt (trin 3). Aftalt af Franco og Jakob 19-11-2026,
forenklet 21-11-2026: så få menneskelige stop som muligt, men intet når `main` uden et menneske.

**Det er én løkke.** Timevagten følger denne skill. Start ikke en løkke ved siden af den — to
løkker bygger den samme feedback.

**Faste regler**
- **Et menneske merger altid.** Botten (`ferm-hest`) pusher grene og åbner PR'er, men merger
  aldrig. Merge-løkken (`hestevagt-merge.sh`) merger ikke løkkens PR'er.
- **Intet bygges, der ikke består de fire spørgsmål.**
- **Intet forsvinder i stilhed.** Et punkt uden svar venter på den ugentlige gennemgang.

## 0 · Før hver runde
- Husets skills gælder i hvert trin (`repo-recon`, `hest-agent`, `new-pr`, `code-review`).
- Mål hesten som i `hest-agent`. Ingen plads → trin 1–3 kører, intet bygges.
- Højst **3 PR'er venter pr. godkender**. Er loftet nået, bygges intet nyt til den person.

## 1 · Saml
Ny feedback fra alle apps (`list_feedback`, fase *ny*) og sager, hvor afsenderen har svaret
(`afsenderHarSvaret: true`). «Ny» betyder kun, at ingen har koblet den — søg F-nummeret i
sprint-punkterne, før noget oprettes.

## 2 · Analysér — de fire spørgsmål
Claude svarer selv og skriver svarene på punktet:
1. **Findes det allerede?** I appen (søg i koden og hjælperegistrene) og i DevHub (punkter,
   pakker, åbne PR'er).
2. **Er det nødvendigt?** Hvem bad om det, hvor ofte, er det et ægte problem?
3. **Hvilket problem løser det?** Citér feedbacken med F-numre.
4. **Er det en god løsning?** Plus ét alternativ.

| Udfald | Handling |
|---|---|
| **byg** | skriv S-punktet (F → S → R → T), videre til 3 |
| **findes allerede** | svar afsenderen, hvor det findes; luk feedbacken |
| **dublet** | kobl til det eksisterende punkt |
| **ikke nødvendigt** | parkér, grunden skrives på punktet |
| **spørgsmål** | besvar (svar til afsender eller hjælpetekst) |
| **stor idé** (nyt modul, roadmap-niveau) | foreslå en R-pakke; løkken bygger den ikke |

## 3 · Spørg først — kun når det er nødvendigt
Byg straks, medmindre mindst én af disse gælder:
- punktet rører **databasen** (skema, migration, SQL), **adgang/login**, **`/api`-ruter** eller
  **deploy** (workflows, Dockerfile, env);
- det er **større end S** (ca. 150 linjer);
- Claude er **usikker på spørgsmål 2 eller 4**;
- det er et **ønske fra en anden** end Jakob, Mads eller Franco.

Så sættes et kort på hestetavlen i `venter_paa_dig` til godkenderen: de fire svar, **hvorfor**
der spørges, og `byg / ret / parkér / drop`. Et punkt, der bygges uden spørgsmål, får én linje i
timevagtens oversigt: «bygget uden spørgsmål, fordi …», så en forkert vurdering kan ses.

**Godkender** = punktets R, ellers pakkens A, ellers Jakob. DevHub-punkter → Jakob (merge = prod).
Intet svar inden ugens tjek-ind → punktet kommer på listen til den ugentlige gennemgang
(15 min, «beslut eller parkér»). Det parkeres aldrig i stilhed.

## 4 · Byg
Husets faste flow fra `repo-recon`, på hesten efter `hest-agent`, `--model sonnet` (opus kun
ved adgangsmodel eller skema med datatab):
recon → byg + `/run` → test i browser med skærmbilleder før/efter ved 1440×900 og 1280×800
(`Set i browser:`) → hjælpen følger fladen (`Hjælp:`) → `/simplify` → `/code-review`
(+ `sikkerhedsgennemgang` ved adgang, sessioner, uploads og API).
- Små punkter må samles på husets *samling*-gren. Punkter fra listen i trin 3 får egen gren.
- `ferm-hest` åbner kladde-PR'en (`gh-hest pr create`) med skærmbillederne i PR-teksten.
- **Tjek igen på den færdige diff.** Rører PR'en noget fra listen i trin 3, som ikke var
  forventet, skrives det øverst i PR-teksten, og kun Jakob eller Mads må merge.
- **Går den i stå** (agent over 2 timer, CI rød to gange): stop, kort i `venter_paa_dig`:
  «⚠️ S-… stoppet: <grund>. Kræver dig.» Ingen automatiske genforsøg.
> ⚠️ ÅBENT (Jakob): `hest-agent` siger i dag, at agenter aldrig åbner PR'er. Løkken kræver, at
> `ferm-hest` må oprette dem — ikke merge.

## ⏸ 5 · Merge — den faste godkendelse
Kortet flytter til `klar_til_merge`. Godkenderen læser PR'en (resumé, før/efter, CI, hjælp) og
- **merger selv** på GitHub — det kan gøres fra telefonen — eller
- skriver **ret: …** → tilbage til trin 4.

En samling-PR godkendes samlet; kortet lister punkterne på den.
> ⚠️ ÅBENT (Jakob): `main` kræver i dag 0 godkendelser (code owners kun på skema, workflows og
> SQL). Skal «botten merger aldrig» håndhæves af GitHub (1 krævet godkendelse) eller af reglen
> alene?

## 6 · Udgivelse
Som i dag: prod i slottene via `udgiv.yml`, op til nyeste PR med `prod-ja` fra Jakob eller
Mads. DevHub har ingen slots: merge = prod.

## 7 · Luk og forfra
Når health svarer den nye sha: S-punktet → `shipped`, afsenderen får et svar i klart sprog, og
feedbacken lukkes. Kortet → `i_prod`. Derefter forfra fra trin 1.

## Senere — ikke nu
Teams-beskeder · preview-sider (`dev-deploy`, ingen vellykket kørsel siden august — skærmbilleder
i stedet) · timevagten på hesten (R-170) · et «hvem»-felt på hestetavlens kort.
