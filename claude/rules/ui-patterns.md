---
name: UI-mønstre
description: Husets opskrift på flader, brugeren skal se — lister, filtre, søgning, sortering, tomme tilstande, gemte visninger, gitterredigering og tegninger. Læses FØR der bygges en ny fane, liste, tabel eller et panel i enhver Ferm-app.
---

# UI-mønstre

Formålet er, at husets skærme kan aflæses ens: at det samme sted altid betyder
det samme, og at man kan gætte, hvad et klik gør, uden at prøve.

Reglen er generaliseret fra `fermrad/project` → `docs/ui-metode.md`, hvor
metoden er bygget, målt og efterprøvet på project's egne flader. Den fulde
udgave med målinger, sagsnumre og kodeeksempler står dér. Her står
**beslutningerne og begrundelserne**. Det, der kun gælder project's kode, er
markeret *«i project: …»*.

---

## Hvornår reglen gælder, og hvad den ikke er

**Bygger du en flade, brugeren skal se — en ny fane, en ny liste, en ny tabel,
et nyt panel — så læs reglen FØR du bygger.** Ikke bagefter, ikke som tjekliste
til PR'en, og ikke kun når fladen er "en liste".

**Hvorfor:** project's issue-log blev bygget som sin egen tabel ved siden af
metoden. Prøverne var grønne, adgangen var rigtig, og den gjorde, hvad der var
bedt om — men den var ikke til at bruge (låste kolonnebredder, der åd
tekstkolonnerne, ingen filtre, ingen søgning, intet kolonnevalg, ingen
klikbare rækker). Klagen kom 20 timer efter udrulningen. Den blev ikke opfattet
som en liste, men som en log, og derfor gælder reglen enhver ny flade.

**Reglen er skrevet, ikke håndhævet.** Der findes endnu ingen delt UI-pakke
(R-59: *«regel nu, pakke senere»*), og kode kan ikke deles direkte mellem
apps, fordi stakken er forskellig:

| App | Next | React | Tailwind | Komponentbibliotek |
|---|---|---|---|---|
| project | 14.2 | 18.3 | 3.4 | intet (egne primitiver i `ui.tsx`) |
| crm, area51, komm, devhub, boilerplate | 16 | 19 | 4 | intet |
| risk | 16-preview | 19 | 4 | shadcn + Base UI |

Derfor deles **opskriften**, ikke komponenterne. Navne som `FilterSpec`,
`EmptyState` og `useState` herunder beskriver en ROLLE; byg rollen i din egen
apps stak, og tjek den installerede version (se `development-practices.md`).

---

## Spejl husets eksisterende udgave — eller skriv hvorfor ikke

Før en ny flade eller kontrol bygges: **find husets eksisterende udgave og
spejl den — eller skriv hvorfor ikke.** Gælder også på tværs af apps.

- **Kopiér ikke en brudt form.** At spejle er ikke at kopiere: tag
  FUNKTIONEN, og lad TALLET følge husets standard. Er et mål i den gamle udgave
  under gulvet (fx et klikmål under 24 px), arves funktionen, ikke tallet.
- **Kan den gamle form ikke rettes med det samme, så bogfør den** (et nyt
  S-punkt) frem for at kopiere den videre.
- **Byggede du uden om husets primitiver, byggede du en ny variant** — og
  varianten arver ingen af de rettelser, de andre har fået.

**Modreglen: en flade må ikke gøres forkert for at ligne de andre.** En
sprinttavle er ikke en liste; en fane, hvor hver kolonne er fri tekst, får
ingen facetter, for en facet, hvor hver værdi kun rammer én række, snitter
ikke — den gentager. Men find gerne det ord, der gør fladen både ens OG sand.

**Fravalg er tilladt og skal STÅ skrevet** med én linjes begrundelse ved
fladens kontrakt (i project: i `src/lib/<flade>-list.ts`). Et fravalg, der er
skrevet ned, kan tages op igen; et, der kun blev truffet, ser ud som en
forglemmelse for den næste — og bliver behandlet som én.

---

## Standardformen for en tabelflade

Viser fladen en tabel — rækker fra en model — så skal dette som udgangspunkt
være der, før man begynder at vælge:

| Skal være der | Afsnit |
|---|---|
| Kanban og liste som visninger i samme kontrakt | URL-kontrakten |
| Gitterredigering, hvis rækkerne rettes hvor de står | Gitterredigering |
| Søgning | Søgning |
| Filtrering — ensartet på tværs af flader | URL-kontrakten |
| Klikbare rækker — rækken fører til sin egen ting | nedenfor |
| Kolonnevalg pr. visning | nedenfor |
| En vej til eksport | nedenfor |

**"Som udgangspunkt", ikke "altid".** En kanban kræver en kolonneakse; har
tabellen intet statuslignende felt, ville et ubetinget krav presse fladen til
at opfinde ét. Et bræt med én søjle er en liste med spildplads. Fravælg — og
skriv det.

**Kolonnevalget har ét sæt PR. VISNING.** Et kort bærer få felter stort, et
gitter mange smalt. Ét fælles valg tvinger det ene til at være forkert. Nøglen
er `(person, flade, visning)`.

**Klikbarhed er en KONTRAKT, ikke en cursor.** Rækken SKAL føre til sin egen
ting, og målet skal vise det, rækken ikke havde plads til. Skjuler du felter for
at give plads, er klikvejen det eneste sted, de findes — **prøv, at hvert skjult
felt er nåeligt gennem klikket.** Uden den prøve er "skjult" og "væk" det samme.
Trykmålet er hele rækken: et klik på noget, der selv har en handling (`a`,
`button`, `input`, `select`, `textarea`, `label`, `[role=button]`, fundet med
`closest`, ikke `matches`), er dets eget; ellers er det rækkens.

**Eksport er en vej, ikke en knap.** Kravet er ikke, at hver flade føder en
`.xlsx`, men at fladen ikke gør en eksport umulig senere: **snittet skal kunne
læses af noget, der ikke er fladen** — rene funktioner, ikke logik i
komponenten. En eksport, der viser andre rækker end skærmen, er værre end ingen
eksport: den ligner et bevis.

- Der er **to slags eksport**, ikke to formater af én. **Billedet** (PDF/PNG)
  er sandt, når det viser samme snit som skærmen OG siger, at det er et snit.
  **Datasættet** (CSV/Excel) er sandt, når hver række kan genfindes, og hver
  kolonne betyder det, den hedder. Spørg hvilken en ny eksport er, før du
  vælger format — "både PDF og Excel" er som regel to leverancer.
- **En `.csv` har ingen plads at være ærlig på.** Skal et datasæt bære et
  forbehold (snit, afgrænsning), kræver det et format med et sted at lægge det.

**Et fast tabellayout skal bære et GULV.** Under `table-layout: fixed` får en
kolonne uden bredde det, der er tilovers — og det er NUL, når de faste bredder
fylder tabellen; `min-width` på `<th>` gør intet. Har hver kolonne sin bredde:
`width: max-content` + `min-width: 100%`. Skal nogle FLYDE: fuld bredde +
`min-width` = det låste + et gulv under hver flydende kolonne. Et
`overflow-x: auto` alene er ikke svaret. **Prøv ved MERE end ét kolonnevalg**
— standarden og "vis alle" er de to konfigurationer, ingen bruger.

**Et mål, en prøve skal kunne læse, står som et TAL** (i `style` eller en
konstant), ikke kun som en utility-klasse: jsdom har ingen layoutmotor, og en
bredde, der afhænger af brugerens kolonnevalg, kendes ikke ved byggetid.

---

## Hvor tilstanden bor

Start med fire spørgsmål — svaret afgør resten:

1. **Skal serveren kende svaret?** Skal snittet deles i et link, overleve en
   genindlæsning eller bæres med ved bladring → **URL**.
2. **Er det en substring over rækker, der allerede ligger i browseren?** →
   **lokal komponenttilstand**. En URL for dét er støj (en navigation pr.
   tastetryk og en adresse fuld af halve ord). **Men har fladen et loft,
   ligger rækkerne der IKKE** — så hører søgningen i loaderen. *Et loft og en
   klient-substring på samme flade er en løgn, ikke en afvejning.*
3. **Er det en præference for den enkelte — kolonnevalg, tæthed?** →
   **databasen pr. person**.
4. **Skal rækker rettes, hvor de står?** → appens fælles gitterprimitiver.

| Slags | Bor i | Eksempel |
|---|---|---|
| Snit, serveren skal kende | URL | status, ansvarlig, projekt, periode, sortering |
| Hvilken VISNING listen tegnes som | URL (et `valg`) | tavle/liste/matrix |
| Substring over hentede rækker | lokal tilstand | søgefeltet i en tabel på 40 rækker |
| Præference for den enkelte | databasen pr. person | kolonnevalg, kolonnerækkefølge |

- **Valget træffes pr. KONTROL, ikke pr. flade.** Begge former kan stå på
  samme filterbjælke. Opfører ét felt sig anderledes end de andre, så skriv
  HVORFOR i fladen — ellers kan en bevidst forskel ikke kendes fra en overset.
  Prisen for at blande dem: "er der filtreret?" kan kun se URL-halvdelen, og
  et "Ryd filter"-link rydder ikke lokal tilstand — giv rydningen en
  tilbagekaldsfunktion oven i navigationen.
- **Et UDVALG er et snit**, ikke en præference (fx "disse fem pakker side om
  side"): det skal overleve en genindlæsning og kunne deles. Prøven er, hvad
  tilstanden ER, ikke hvad den ligner. Nøgl et udvalg på ID, ikke på et
  nummer, der er en POSITION.
- **En præference kan gøre en kolonne usynlig — den må ALDRIG gøre en
  synlig.** Hold **fravalgt** (brugerens, gemt) adskilt fra **utilgængelig**
  (adgang, udledt ved hver tegning, ikke gemt, ikke i vælgeren). Gaten hører
  på serveren; en utilgængelig kolonnes data sendes ikke til klienten. Et
  fravalg af en kolonne, der lige nu er utilgængelig, bevares.
- **Databasen, ikke `localStorage`, for præferencer.** Kolonnevalg hører til
  personen, ikke maskinen. Det er strengere end gængs anbefaling og et bevidst
  valg — ret det ikke tilbage. En gemt opsætning er *et ønske, ikke en
  sandhed*: normaliseringen skal altid kunne føre tilbage til standarden, også
  når en kolonne er forsvundet fra koden. En ukendt nøgle falder bort.
- **Ikke enhver præference skal huskes — spørg, hvad den SKJULER.** Et gemt
  kolonnevalg fjerner noget, man kan SE mangler (overskriften er væk,
  vælgeren står ved siden af). En gemt foldning fjerner rækker og tal, og
  fladen ser bare kortere ud næste gang — **foldning huskes ikke**; fladen
  åbner fuldt udfoldet. Vælger man alligevel at gemme noget, der fjerner
  rækker, skal fladen selv sige, hvad den skjuler, to steder.
- **Er en præference for stor til punktet, bliver den stående, hvor den er,
  og grunden skrives ned.** Den flyttes ikke et tredje sted hen.
- **Delt login uden person** (en adgangskode flere deler): det gemte må huske,
  hvordan en FLADE ser ud (kolonner for denne skærm), ikke hvem der kigger
  (favoritter). Funktionen, der falder bort, forklares ÉN gang på fladen — ikke
  pr. række og ikke med en knap, der intet kan gøre.

### Gemte visninger og en standardvisning

Har appen gemte visninger, gælder:

- **En gemt visning bærer kun en rute og en query-streng.** Alt i en adresse
  går gennem parseren og ud i chips, snitlinje og "Viser 12 af 340" — så den
  kan ikke indsnævre tavst. Giv aldrig modellen et frit felt til "resten af
  UI-tilstanden" (tæthed, foldning): så kan den skjule rækker uden at sige det.
- **En gemt visning er et ønske.** Peger den på en værdi, der ikke findes
  mere, repareres den IKKE (en tom facet betyder alt — "Rådgivere" ville blive
  til "alle"). Værdien bliver stående, listen viser færre rækker, og fladen
  siger, hvad der faldt bort — målt mod rækker, kalderen må se.
- **Et snit, der er sat som standard, SKAL være synligt.** Standarden bliver
  til en ADRESSE: den rene adresse omdirigeres til visningens egen, så chips og
  antal står som ved ethvert andet snit.
- **Standarden overtrumfer aldrig en adresse.** Bærer adressen et snit (også
  kun en sortering), åbner standarden ikke — ellers betyder et delt link
  noget forskelligt hos afsender og modtager.
- **Vejen tilbage til det ufiltrerede er ét klik og kræver sin egen
  parameter** (i project: `?standard=fra`), uden for filterkontrakten, så en
  gemt visning ikke kan gemme sit eget fravalg. En stribe navngiver standarden,
  så længe der er en.

---

## URL-kontrakten

**Parsning og serialisering er rene, testede funktioner i et lib-modul —
aldrig i en komponentfil.** Én kontraktfil pr. flade med spec'en OG dens
betydning (hvad en facetværdi matcher, hvad en sorteringsnøgle betyder,
hvordan valgmuligheder udledes) og **ingen databasekald** — opslaget bor i en
søsterfil.

*I project:* `src/lib/list-filter.ts` (`FilterSpec`, `parseFilter`,
`filterHref`), én `src/lib/<flade>-list.ts` pr. flade, opslag i
`<flade>-data.ts`. Referencefladen er `/resources`.

**Hvorfor én fil pr. flade og ikke én fælles:** spec'en er aldrig alene (en
fælles fil samler alles matchning uden ejer eller skiller spec fra betydning);
en fælles fil bliver et importnav, der trækker alle domænekonstanter ind i
hver klients bundt; og flader bygget af parallelle punkter kolliderer ikke.

**Parametrene er danske og komma-adskilte:** `?status=todo,doing`,
`?ansvarlig=<id>`, `?soeg=`, `?sorter=`, `?retning=op|ned`, `?visning=`. En
URL, brugeren kan læse og selv rette i, er en del af pointen.

**Omdøbes en parameter, læses det gamle navn som alias i PARSEREN — og skrives
aldrig videre.** Bærer en adresse begge, vinder det nye. Ellers dør aliaset
aldrig ud. Giv ikke et alias til en flade, der aldrig har haft det gamle navn
— det ville opfinde en fortid. Prøv det: åbn fladen med det gamle navn, klik på
hvad som helst, og se adressen komme tilbage med det nye.

### Facet, valg og fladens egne parametre

| | Facet | Valg (`valg`) | Fladens egen parameter |
|---|---|---|---|
| Værdier | flere | præcis én, lukket liste, med standard | — |
| Tom betyder | ALT | standarden | — |
| Tæller som filter / får chip | ja | nej | nej |
| "Ryd filter" | rydder den | lader den stå | lader den stå |
| Eksempel | `?status=` | `?visning=kanban` | `?tab=orgs` (et andet datasæt) |

- **Visningen hører i SAMME kontrakt som filtrene.** Lå den ved siden af, tabte
  et visningsklik filtrene og et facetklik visningen — to parametre, der slog
  hinanden ihjel på skift, uden fejl nogen steder. Prøv: skift visning med et
  filter sat, og se at BEGGE overlever klikket.
- **Prøven er DATASÆTTET, ikke komponenten.** Samme rækker fra samme loader,
  læst med samme vokabular ⇒ et `valg`, også når én værdi tegnes af en anden
  komponent. Skifter parameteren DATASÆT (facetter og sorteringsnøgler ville
  betyde noget andet), er den fladens egen; kontrakten føjer så til dens sti
  med `&`, ikke et hårdkodet `?`.
- **Et valg må vælge PULJEN** (fx "uafklarede"). Så følger to krav: puljen
  skæres FØR loftet, og det ufiltrerede antal er PULJENS, ikke bestandens.
  Afgrænsningen skal kunne læses som en linje på fladen, og emnet i
  tomtilstanden følger visningen.
- **Et valg må styre GEOMETRIEN** (skala, faser) og bliver stadig ikke et
  filter — så længe værdisættet er lukket. En fri zoomfaktor kvantiseres til
  et sæt eller hører ikke i kontrakten.
- **En visning må gerne stå uden filterbjælke**; parameteren bliver i
  adressen og virker igen ved et skift tilbage.

### Reglerne kontrakten håndhæver

- **Tom parameter betyder ALT.** Det gør en tom URL til den fulde liste.
- **Ugyldige værdier frafiltreres frem for at kaste.** En tastefejl skal vise
  for meget, ikke skjule alt i tavshed.
- **Værdier, der ikke kan valideres (id'er, koder), slipper igennem** og
  matcher ingen række.
- **Sæt kun en lukket værdiliste, når kolonnen er lukket i SKEMAET** — ikke
  når en konstant opremser de sædvanlige. Ellers frafiltreres en rigtig, men
  ukendt værdi, og listen viser alt i stedet for det, brugeren pegede på.
  Udled facetværdierne af data; brug konstanten som rækkefølge og etiket, med
  ukendte værdier bagest.
- **Nøgl på det, brugeren ser** (projektkoden, ikke id'et; navnet, når der
  ikke er et id) — **medmindre det synlige er en POSITION** (et WBS-nummer kan
  omnummereres; et delt link ville så tavst vise noget andet). Escape
  skilletegnet i værdier, der kan indeholde det (`"Nielsen, Hansen & Co"`).
- **Det uvalgte udelades** — også standardsorteringen — så den ufiltrerede
  liste har den korte, delbare adresse.
- **En gentaget parameter er ikke to filtre**; kontrakten læser den første.
- **Hver side parser selv filteret.** Ellers ændrer chippen kun URL'en, mens
  serveren bygger hele listen.
- **Filtrér FØR modellen og totalerne bygges.**
- **Facetternes valgmuligheder udledes af de rækker, kalderen FAKTISK må se** —
  en menu må ikke røbe mere end listen.
- **To flader med samme slags parameter:** del navnet, når betydningen deles;
  find et andet, når den ikke gør. Samme navn med to betydninger er det
  værste af de tre udfald. Flertal er flervalg, ental er enkeltvalg.

### Når fladen er et træ

- **Snittet beholder forfædrene til enhver træffer**, så resultatet er et
  gyldigt undertræ — ingen række mangler sin forælder.
- **Forfædrene er ikke træffere, og det skal SES og SIGES.** Tone dem ned, og
  skriv tallene ud: *"1 række matcher — 2 er kun med for at holde strukturen."*
- **Facetværdier udledes af STRUKTUREN, aldrig af en dybde** — med samme
  funktion, visningen selv bruger.
- **En sortering gælder SØSKENDE** og rører aldrig stien.
- **Rammen står fast** (tidsakse, milepælsstribe, faser regnes af hele
  datasættet), og fladen siger, at snittet skærer i rækkerne, ikke i rammen.
- Skjul eller fremhæv er begge forsvarlige — valget uden begrundelse er ikke.

### En redigerende vælger over en åben kolonne

**En `<select>` skal altid have en option, der matcher den gemte værdi.**
Ligger værdien uden for vokabularet, får den sin egen — valgt, deaktiveret og
mærket `⚠ <værdi> — ukendt værdi` (mærket FORREST, så det overlever
afkortning). Den mappes ikke til en gyldig værdi, og feltet låses ikke. Ellers
viser browseren den første option, og et utilsigtet klik skriver den. Reglen
bor i lib, ikke i hver vælger.

**Rækker et skift ud over fladen** (fx arkivering), siges konsekvensen dér,
hvor der klikkes — med appens egen markup, ikke `window.confirm`. Hvilke
værdier der spørger, står som et opslag pr. værdi, så en ny værdi tvinger et
svar.

---

## Søgning: tre slags, de fyrer ikke ens

| Slags | Fyrer | Tilstand | Eksempel |
|---|---|---|---|
| Klient-substring over hentede rækker | pr. tastetryk | lokal | tabel med 40 rækker |
| Server-snit over en liste, serveren bygger | ved Enter eller blur | URL (`?soeg=`) | stor aktionsliste |
| Puljeopslag mod noget ikke hentet | afdæmpet 300 ms, fra 2 tegn | lokal, ikke URL | deltagervælger mod kontaktbogen |

- **Facetter først, søgefelt som supplement** (facetnavigation måles hurtigere
  end fritekst alene).
- **Et server-snit har stadig en kladde i klienten, og den skal følge
  adressen**, når den ændrer sig udefra ("Ryd filter", piller, frem/tilbage).
  Ellers skriver kladden sig selv tilbage ved næste blur. Reglen hører til
  FELTET, ikke kalderen.
- **Søgefeltet er `type="search"`** med synlig etiket eller `aria-label` og
  et kryds, der rydder. `Escape` rydder, `/` sætter fokus. To komponenter, én
  pr. slags — at vælge forkert giver enten en historikpost pr. bogstav eller et
  snit, der ikke kan deles.
- **Et server-søgeendpoint er en adgangsflade.** Det gates i LOADEREN, ikke på
  siden (en guard på siden er et gulv, ikke et bevis), og en loader, der kaldes
  fra flere flader, filtrerer frem for at kaste. Lav ikke et nyt endpoint ved
  siden af en afgrænset loader.

---

## Mængde og udfald

### Ingen liste henter ubegrænset

| Antal rækker (ufiltreret) | Gør |
|---|---|
| < 200 | hent alt, filtrér i browseren |
| 200–2.000 | hent med loft, og **sig afkortningen højt** |
| > 2.000 | serverpaginering; filter og sortering i adressen |

- Tærsklen gælder den **ufiltrerede** liste. En liste, der tavst holder op ved
  500, er en liste, man træffer forkerte beslutninger ud fra.
- **Loaderen returnerer rækkerne, antallet uden loftet og loftet** (i project:
  `{ raekker, matchende, loft }`) — aldrig et nøgent array. Så kan ingen flade
  modtage et snit uden at kunne se, om det er afkortet.
- **Rækkefølgen er `pulje → facetter → sortering → loft`, altid.** Skæres der
  før snittet, er "top 200" en vilkårlig delmængde. Ingen facet filtrerer i
  browseren på en flade med loft. Bevis: samme rækkesæt ved stigende og
  faldende sortering betyder, at snittet ligger forkert.
- **Tællingen bærer nøjagtig samme filter som hentningen** — ét delt
  `where`, eller antal og rækker skåret af samme array. Et antal, der tæller
  bredere end rækkerne, lækker, hvad der findes uden for kalderens adgang.
- **Bed aldrig om et tal, du allerede har.**
- **Undtagelse:** en flade, der tegner et BILLEDE af en helhed (roadmap,
  tidslinje), henter alt — ellers falder noder tavst ud af tegningen. Skriv
  begrundelsen ved kontrakten.

### De fire udfald — de to tomme må ikke sige det samme

| Udfald | Skal stå | Må IKKE stå |
|---|---|---|
| Ingen data | "Ingen aktioner endnu." + vejen ind | "matcher ikke" |
| Filtreret til nul | "Ingen aktioner matcher filtrene." + **Ryd filter** | "endnu", en opfordring til at oprette |
| Fejl | hvad der gik galt, og en vej videre | en tom liste, der ligner nul rækker |
| Afkortet | "Viser 200 af 1.412 — snævr ind for at se resten." | ingenting — heller ikke når et søgeord har tømt skærmen |

**Skelnen sker på det UFILTREREDE antal, ikke på et "er der filtreret?"-flag.**
Et flag kan ikke skelne "dit filter skjuler noget" fra "der er ikke noget at
skjule" — så får en tom base "Ryd filter" i stedet for "opret den første". Ret
det ikke tilbage til et flag; det ligner en forenkling og er et tab af
information.

Fire tal, som er nemme at bytte om (de er alle `number`):

| Tal | Er | Afgør |
|---|---|---|
| vist | rækker tegnet nu, efter fladens eget snit | tom mod ikke-tom |
| hentet | rækker, loaderen leverede | afkortningen |
| matchende | snittet uden loft | afkortningen |
| ufiltreret | hele puljen før filteret | tom mod filtreret |

- **Afkortningen er en egenskab ved HENTNINGEN.** Et klient-søgeord, der tømmer
  skærmen, har ikke afskaffet de rækker, loftet lod ligge. Med et klientsnit
  er "hentet" og "vist" forskellige, og beskeden skifter verbum: *"Hentet 200
  af 314 … Søgefeltet leder kun i de 200 hentede."*
- **"Ryd filter" står også i TOMTILSTANDEN**, hvor brugeren kigger.
- **Antallet står altid:** "Viser 12 af 340".
- **Hjælpeteksten må kun pege på kontroller, fladen HAR** (ingen "fjern en
  chip" på en flade uden chips), **og kun love det, de kan UDRETTE.** "Sortér
  for at vælge, hvilke der kommer med" er kun sandt, hvis loaderen sorterer
  FØR loftet — det er loaderens svar, ikke spec'ens, og det kan være
  forskelligt pr. visning. **Et signal skal udledes af det lag, egenskaben
  faktisk bor i**, ellers bliver det usandt, uden at nogen rører det.
- **En pulje, der ALDRIG kan have indhold for denne beskuer** (pr. adgang):
  udvid ikke visningen, og skjul den heller ikke (den tilbydes ofte flere
  steder). Tilbyd den til alle, og lad den AFVISE sig selv som en værdi, fladen
  tegner — ikke en tomtilstand, ikke en fejl. Teksten siger, at visningen ikke
  er partens — **aldrig hvor meget der ligger derude.**

### Print og dokumenter

- **Loftet er en skærmregel; en print-rute henter alt** — op til et absolut
  tag (ikke uendeligt; loftet er et argument, en bruger kan sende), og bider
  taget, siges det på arket.
- **En print-rute er en læseflade og bærer KALDERENS snit.** Uden snittet
  betyder "alt" alt, der findes; med det, alt hun må se.
- **Dokumentet erklærer sit eget snit og sin mængde** i hovedet — chipsene
  forsvinder ved print. Mængden må ikke sige "alt" til en afgrænset part, og
  totalen tælles inden for snittet.
- **Ikke alle flader har en printvej.** En kanban med træk-og-slip er ikke et
  dokument; en ubrugelig PDF er værre end ingen knap. Skriv til- og fravalg.
- **Brevhovedet og andre gentagne dokumentdele tegnes ÉT sted.** Kopier driver,
  og forskellen rammer modtageren, der ikke har en skærm at holde arket op
  imod.

---

## Sortering

- **Sortering er en del af URL-kontrakten** — ikke `localStorage`, ikke en
  separat mekanisme. `?sorter=<nøgle>&retning=op|ned`. **Nøglen er kolonnens
  navn i koden**, ikke overskriften.
- **Klik på overskriften: samme kolonne vender retningen, en ny starter
  stigende.** To tilstande, ikke tre — "usorteret" er usynlig i overskriften.
- **Standardsorteringen udelades af adressen** og er dén, en ukendt nøgle
  falder tilbage til. "Ingen standard" er gyldigt og betyder "serverens egen
  orden står".
- **En sortering på en fravalgt kolonne BESTÅR** — en præference må ikke
  omskrive et delt link. Sig det i en linje: "Sorteret efter Deadline —
  kolonnen er skjult".
- **Nøglerne udledes af kolonneregistret**, så en overskrift ikke kan se
  klikbar ud uden at virke.
- **Sortering tæller ikke som et filter**; "Ryd filter" lader den stå.
- **Sortér ét sted.** Står snittet i URL'en, sorterer loaderen, og klienten
  sorterer ikke om. To ordninger er fejlen, ikke stedet.
- **Deler flere visninger én loader, skærer loftet langs den orden, visningen
  faktisk tegner.** En sortering valgt i listen må ikke flytte, hvilke kort der
  står på tavlen.
- **Læg altid en stabil tiebreak i bunden — og vend den ikke med retningen.**
- **Ukendt (`null`) sorteres nederst i BEGGE retninger.**
- **Tilgængelighed:** kun den sorterede kolonne bærer
  `aria-sort="ascending|descending"` (aldrig `"none"` på resten). Overskriften
  er et fokuserbart LINK inde i `<th>` — sorteringen er en adresse og skal
  kunne deles og åbnes i ny fane. `<th>` er ikke selv klikbar.

---

## Betjening

- **Et snit, der er sat som standard, skal være synligt** — som en chip, man
  kan se og slå fra, også når den er slukket. Og det står i ADRESSEN som en
  værdi, ikke som et fravær: ellers findes der ingen adresse for den fulde
  liste. Vælg helst standarden FRA og lad den være ét klik væk.
- **Et snit må ikke opstå EFTER hydrering.** En værdi fra browseren
  (`localStorage`) er en identitet eller en præference, ikke et filter: den må
  bestemme, hvad en chip PEGER på ("Mine" → `?ansvarlig=<id>`), men aldrig selv
  sætte snittet. Prøv: genindlæs, og se om indholdet skifter uden et klik.
- **Aktive filtre fjernes ét ad gangen**, i en fast rækkefølge, så chipsene ikke
  flytter sig. "Ryd alt" er et supplement. "Ryd filter" rydder facetter og
  fritekst og lader sortering og valg stå.
- **Multivælgeren er ikke `<select multiple>`** (uanvendelig på berøring, kan
  ikke vise antal). Den er et **disclosure med native checkboxes**:
  `aria-expanded`, fokus ind ved åbning og tilbage ved `Escape`. **Den er med
  vilje ikke en ARIA-listbox** — en halv listbox lover piletaster, den ikke
  har, og er værre end et helt disclosure. Den kan heller ikke være en
  `<form method="get">`, der ville serialisere `?status=a&status=b`.
- **Facetværdier i et TRÆ tegnes som et træ:** grene lukkede som standard,
  foldningen lokal — men **ingen VALGT værdi må kunne foldes væk** (dens gren
  står åben og låst). Indrykningen følger antallet af synlige forfædre, ikke
  tegn i etiketten. Mål tab-stoppene; en folde-knap er selv et.
- **Noget, der KLÆBER, betales med et målt tal.** Skil identiteten (det, der
  skal blive stående) fra referencen (det, der må rulle væk), og skriv loftet
  som en konstant. Ingen komprimering ved scroll — den flytter alt under sig
  og findes hverken i adressen eller på serveren.
- **Enter må ikke være sendevejen i et felt, der kan rumme flere linjer.** Den
  synlige knap er sendevejen; ⌘/Ctrl+Enter er en tilføjelse (findes ikke på et
  tablettastatur); Enter alene laver en linje. To felter, der opsamler det
  samme, binder Enter ens.
- **En kontrol skal HEDDE alt det, den kan.** En tooltip er ikke synlighed (den
  findes ikke på berøring). Navngiv ikke kun den ene halvdel.
- **Navnet på en kontrol bor ét sted**, når andre tekster peger på det.
- **En tom mulighed er ikke en manglende funktion.** Tegnes noget kun, når der
  er data, så sig på den tomme flade, at det kan lade sig gøre — neutralt, grå
  og én sætning, uden at påstå en værdi ("ingen prognose" er ikke "0 kr."), og
  adskilt fra forbeholdene for den udfyldte tilstand.

---

## Gitterredigering

**Redigerbare celler bor ét sted pr. app.** Byg ikke en ny udgave ved siden af
(i project: `InlineText`, `InlineNumber`, `InlineDate`, `DeleteCellButton`,
`useGridCommit`, `useGridKeyboard` og `SkrivendeVaelger` i
`src/components/ui.tsx`). Gem-på-blur er det rigtige for regnearksagtige gitre;
eksplicit Rediger/Gem/Annullér hører til admin-tabeller, hvor en rettelse er
sjælden.

1. **Gem på BLUR, ikke pr. tastetryk.**
2. **Serverværdien hører i cellens `key`.** Ellers kan en forældet DOM-værdi
   skrive sig oven på en nyere ændring under en ren TAB-gennemgang. Den
   dyreste at glemme.
3. **`badInput` afvises, tolkes ikke som tomt** (dansk decimalkomma i et
   talfelt ville ellers slette tallet). En ryddet dato er en gyldig dato; en
   halvtastet er ikke.
4. **Skriv kun, når værdien FAKTISK er ændret.**
5. **`Escape` fortryder, `Enter` gemmer og går én række ned** (samme kolonne;
   gruppe- og sumrækker springes over).
6. **En afvist skrivning vises i det delte lag** (`role="alert"`, spærrer ikke
   siden) og **fører værdien tilbage** — aldrig en `alert()`.
7. **Et tal formateres, når cellen ikke har fokus, og vises råt under
   indtastning.** `da-DK` skriver 1.500,50, et talfelt kun 1500.5; et
   formateret tal må aldrig nå skrivningen.
8. **Et gitter er ÉT tab-stop** (rovende `tabIndex`, piletaster mellem celler,
   Home/End, Ctrl+Home/End, `Enter`/`F2` ind, `Escape` ud). Navigationen bor
   på CELLEN, ikke i feltet — piletaster i et tal- eller datofelt ændrer
   værdien. **Én fokuserbar pr. celle**; en knap mere får sin egen celle (det
   koster nul tab-stop). Sæt ikke `aria-rowcount`/`aria-colindex`, når alle
   rækker står i DOM'en — forkert ARIA er værre end ingen. Fjernes den
   fokuserede række (foldning), gives fokus til nærmeste overlevende celle.
9. **En `<select>`, der SKRIVER i `onChange`, skal værnes** — også uden for et
   gitter. På Windows og Linux skifter piletaster, Home/End og PageUp/PageDown
   valget i en lukket, fokuseret vælger og fyrer `change` med det samme; macOS
   åbner listen, så fejlen er usynlig på en Mac. Værnet griber på `keydown`
   (`Alt`+pil slipper igennem). Type-ahead standses ikke (et bogstav er eneste
   vej gennem en lang liste med tastatur) — den **afdæmpes til én skrivning**
   og kan **fortrydes** fra et ikke-blokerende bånd (`role="status"`), der
   fører værdien tilbage i FELTET. En afdæmpet skrivning må aldrig tabes
   (blur, afmontering og `pagehide` sender). En vælger, der kun sætter lokal
   tilstand, forbliver en almindelig `<select>`.
10. **En FLYDENDE kolonne skal have et gulv** (`min-width` på cellen), ellers
    æder smallere kolonner den på en smal skærm. Afkortning frem for
    ombrydning, med hele teksten i `title`.
11. **Ombrydning er et valgfrit, slukket flag på tekstcellen** — kun på en
    flydende kolonne. Værdien er stadig én linje: Enter laver aldrig et
    linjeskift, og indsatte linjeskift fladgøres. Højden måles om ved
    indtastning, kolonnebredde og vinduesbredde.

- **Et træ er ikke et gitter** (`tree`/`treeitem`, ikke `grid`). Giv det ikke
  gitterets tastaturkrog; giv det en tastevej til det, der kun kunne nås med
  dobbeltklik.
- **En pivoteret celle er ikke rækkens felt** — den skriver i den model, den
  faktisk hører til.

---

## Vælgere: en lang `<select>` er også en liste

En vælger, hvis optioner kommer fra BASEN (møder, aktioner, personer,
WBS-noder), vokser af sig selv. **Skellet er længden, ikke navnet.** Svaret er
**gruppering + rækkefølge**:

- **Søgning fravalgt** — `<select>` har type-ahead, og et søgefelt oven i ville
  være to slags søgning, der ikke fyrer ens.
- **Afgrænsning fravalgt** — færre poster i en SKRIVENDE vælger fjerner værdier,
  brugeren så ikke kan sætte, tavst.
- **Gruppering med `<optgroup>`** fjerner intet, kræver ingen ny betjening og
  virker i en gittercelle.

Tre regler: **ingen post må forsvinde** (hver post ud igen præcis én gang);
**gruppens hoved er selv en post**, når hovedet er en værdi (`<optgroup label>`
kan ikke vælges); **er der kun én gruppe, tegnes ingen overskrift** (ingen
`<optgroup>`, ikke `label=""`). På et snittet træ rulles loftet op til
nærmeste TILSTEDEVÆRENDE forfader — aldrig et hoved hentet fra en node, snittet
holder tilbage.

**En vælger kan ikke gruppere efter mere, end dens payload bar** — tilføj
feltet i loaderen. Datoer grupperes og etiketteres i appens tidszone (et
`DateTime` omregnes; en ren kalenderdato gør ikke), så overskrift og post ikke
siger hver sit.

---

## Tomme felter, kanter og hjælpetekst

**En tom celle er også en tilstand, og kanten er det eneste, der siger det.**
Et tomt felt uden kant tegner ingen pixel — en nyåbnet flade kan se nøjagtig ud
som før.

| Tilstand | Kanten |
|---|---|
| tom og skrivbar | stiplet — en ramme, der ikke er lukket, læses som "endnu ikke" |
| udfyldt | fuldt optrukket, rolig |
| låst | gennemsigtig — en kant, man ikke kan skrive i, er en løgn |

Præcis ÉN kantfarve pr. tilstand (to utilities afgøres af stilarkets orden). Den
låste beholder sin bredde, så feltet ikke hopper, når det låses op. Reglen er en
FUNKTION, ikke tre CSS-varianter — så den kan prøves, og `:placeholder-shown`
virker ikke på datofelter.

**Et afsnit kendes på sit NAVN og sin KANT.** En kant, der OMSLUTTER (kort,
panel, modal, knap), skal klare **3 : 1** mod baggrunden (WCAG 1.4.11); en
streg, der DELER (tabelrækker, afsnitsskel), gør ikke — hæves alle, bliver
fladen et gitter. Prøv kontrasten mod appens faktiske palet, ikke klassenavnet.

**En placeholder er ikke en tom-felt-tekst:**

| Overflade | Teksten siger |
|---|---|
| læsevisning, hvor teksten står I STEDET for en værdi | en TILSTAND: "Ikke udfyldt" — aldrig en instruks om at klikke |
| `placeholder` i et åbent felt | hvad feltet er TIL: "Beskriv hvad arbejdspakken indeholder" |

Ingen af dem må navngive en kontrol eller en gestus: en sætning om
interaktionen bliver usand, næste gang interaktionen flytter sig. Bydeform er
tilladt, når den handler om indholdet. Placeholders er konkrete og
eksemplificerende. Datofelter tegner aldrig deres placeholder — giv dem ingen.
Bygges en (i)-hjælp: trykmål ≥ 24 px, tastaturnåbar, og aldrig det eneste sted,
en regel står.

---

## Et filter skal kunne finde det TOMME

**Et filter, der kun kan vælge værdier, kan aldrig finde rækkerne, der
mangler en** — og det er netop dem, man leder efter, når man rydder op.

- **"Uden værdi" er en ERKLÆRET sentinel i kontrakten**, ikke en streng skrevet
  ind i fladens værdiliste og ikke en ny konstant pr. flade.
- **Tre tilstande må ikke falde sammen** i adressen: ikke sat (tom liste =
  alt), sat til "uden", sat til en værdi — og begge dele.
- **En facet UDEN erklæringen strimler sentinel'en** — så fejler et gammelt link
  ÅBENT (viser alt) frem for tavst tomt.
- **Kaldestedet ser aldrig sentinel'en som en værdi**; reglen bor ét sted.
- **"Uden …" tilbydes kun, når den kan give en række.**
- **Ikke på en facet, der i forvejen ER ja/nej** — to veje til samme snit er en
  fælde.

## Et filter på en flade, der udleder opad

Arver en celle sin værdi fra en forælder, som snittet skjuler: **cellen siger,
at kilden ligger uden for snittet** ("Arvet fra Projektering — uden for
filteret"). Snittet beholder IKKE kilderækkerne (så svarer det ikke på
spørgsmålet), og kilden står ikke tom (så falder "arvet" og "uafklaret"
sammen). Udledningen sker på den ufiltrerede bestand — et filter ændrer, hvad
man SER, aldrig hvad værdien ER. Menuen bygges af den ufiltrerede bestand.

---

## Når svaret er en tegning og ikke en liste

**En tegning er svaret, når RELATIONEN mellem rækkerne er det, læseren kom
efter.** Er det rækken, læseren skal handle på, er en liste stadig svaret.

- **En tegning arver listens adgang:** den dannes af de rækker, kalderen har
  fået — aldrig af det fulde datasæt. Den arver ordenen (en sti læses som en
  sekvens af tal; `1.10` efter `1.9`) og de fire udfald.
- **Den arver PAYLOADEN:** en tegning kan ikke vise mere, end dataene bar.
  Regn det ikke alligevel af nutidens data — tegn det, der er, og lad
  tegningen sige, hvad den ikke kan.
- **Rammen er også en oplysning.** Vinduet (aksens ender, et bånds spænd)
  regnes af DET, TEGNINGEN TEGNER, aldrig af loaderens ramme. **Farven kan bære
  et tal** — en statusfarve, der udledes af budget, er en budgetoplysning.
- **Én tegning, N flader:** én komponent uden hooks og uden klient-direktiv,
  farver fra et REGISTER (en ny nøgle er en typefejl), mål som tal — så skærm
  og print bruger samme eksemplar. To udgaver driver fra hinanden, og
  forskellen ses først af den, der kun har arket.
- **Er forskellen mellem to kaldesteder en MÆNGDE af felter, gøres mængden til
  en navngivet prop** — ikke to komponenter. En delt skrivevej skal kunne
  UDELADE et felt (`undefined`), ikke rydde det (`null`).
- **På et kort flytter en etiket RUNDT om sit eget mærke, aldrig væk fra det.**
  Det, der ikke kan tegnes, tælles og peger på, hvor det kan læses.
- **En legende udledes af det TEGNEDE**, ikke af vokabularet. Slukket lag: ingen
  post. Tændt, men tomt i udsnittet: "0 i udsnittet". Findes slet ikke: ingen
  post.
- **Før en ny skala, tilstand eller kontrol: se efter, om bestillingen er et LAG
  på noget, der allerede tegnes.** Et lag koster ingen tilstand; et vokabular,
  der vokser, koster overalt.

**Tre slags tilstand på en tegning — prøven er: hvem ejer valget?**

| Kontrol | Slags | Bor |
|---|---|---|
| niveau-loft ("vis ikke dybere end") | snit — læserens | adressen |
| foldning | lokal — læserens | lokal tilstand, huskes ikke |
| skala og periode på et udgivet dokument | dokumentets — forfatterens | gemt og frosset med dokumentet |

- **Niveauet er et LOFT, aldrig en fast dybde** (Jakobs beslutning
  25-08-2026). En fast dybde taber rækker på grene, der er kortere; et loft
  ruller op til forfaderen og kan ikke tabe noget. Dybde regnes af stien,
  aldrig af et visningsnummer.
- **Fraværet af en gemt indstilling betyder "udled", aldrig "brug
  standarden"** — ellers skifter hvert udgivet dokument udseende den dag,
  feltet kommer.
- **En valgt periode skjuler ikke lydløst:** det, der falder uden for, tælles
  og siges, og perioden skrives ud, også når den intet holdt ude.
- **En foldet gruppe siger, hvad den skjuler**, i knappens tilgængelige navn
  sammen med `aria-expanded`.

---

## Fortrolighed: et snit på identitet er en egenskab ved FLADEN

Når rækker skal anonymiseres eller skjules, før de forlader huset:

- **Aksen er fladen, ikke læseren.** Den, der beskyttes imod, har typisk intet
  login (hun får en PDF), og den, der er logget ind som ekstern, kan være
  dataenes ejer. Spørg: er det her et arbejdsbord (viser alt) eller et artefakt
  (kan lægges i hånden på nogen)? Skriv svaret pr. flade i et register, som
  loaderne læser.
- **Anonymisering måles felt for felt:** fjern ethvert felt, der peger på en
  bestemt ting — og al fritekst. **En prik på et kort uden navn anonymiserer
  ikke**; koordinatet er identiteten.
- **Fraværet af et valg fejler lukket** — og vælg "lukket" efter den akse,
  funktionen beskytter (identitet ⇒ anonymisér, ikke skjul hele rækken).
- **Det, snittet tog, tælles** på sin egen linje, navngiver vejen ind og fryser
  med i et udgivet dokument. Nummerér de anonyme EFTER, at de skjulte er
  trukket ud — ellers røber hullet positionen.

## Standard i koden, overskrivning i basen

Skal en tekst eller indstilling fra et register i koden kunne redigeres:
**registret er STANDARDEN, basen er OVERSKRIVNINGEN** — felt for felt, `null`
er standarden, og tom streng normaliseres til `null`. Snit FØR opslaget, så en
overskrivning ikke kan nå noget, registret ikke tillader. Opfind ikke et
ejerskab eller en adgangsakse i forbifarten.

---

## Tal og enheder

- **Ingen ny formattering af et tal, appen allerede formaterer** (beløb, timer,
  afvigelser). I project: `formatBeløb`, `formatTimer`, `<Afvigelse>`.
- **Bærer tallet en retning, bærer det også farven** — "+5" og "−5" må ikke
  læses ens. Kan fladen ikke farve, så skriv hvorfor.
- **Prøv fortegnet i begge retninger og på nul.**

---

## Prøver: hvordan en UI-regel bevises

- **En negativ påstand skal kunne FEJLE.** "Der er ingen felter" bygget på en
  ARIA-rolle bliver sand af den forkerte grund, når elementets type skifter
  (`type="number"` → `"text"` fjerner `spinbutton`). Er rollen snævrere end
  begrebet, så skriv en **positivkontrol i SAMME prøve**, eller påstå på
  elementet i stedet for rollen. Prøv altid det positive udslag med samme navn
  først.
- **Mål GEOMETRIEN, ikke at et element findes:** koordinater, antal og hele
  punktstrengen. Skriv formlen af i prøven (importér ikke tegnerens egen). Læs
  elementer og attributter — en `<svg>` og en `<optgroup>` har ingen brugbar
  rolle. En påstand om en IMPORT er ikke en påstand om en tegning.
- **Prøv KOMBINATIONERNE af snit**, ikke ét ad gangen (et loft, der bider, OG et
  søgeord).
- **Prøv begge retninger af en påstand:** én flade, hvor sætningen skal stå, og
  én, hvor den ikke må.
- **En ren TAB-gennemgang og en piletast-gennemgang af et gitter lader
  databasen være urørt.** Billig, og fanger den dyreste fejl.
- **Brug ægte tastetryk** mod en fokuseret vælger; et syntetisk `change`
  springer værnet over. Tæl skrivninger (server-kald), ikke `change`-hændelser.
- **Fixturen skal kunne skelne reglerne:** mindst ti søskende (`"1.9" < "1.10"`
  fejler først ved den tiende), et tomt OG et udfyldt felt i samme visning,
  to rækker i hver ende, data i en rækkefølge, der er uenig med den forventede,
  en værdi uden for vokabularet, en afgrænset bruger — og en positivkontrol, så
  en nul-måling betyder noget.
- **Tab-stop, bredder og klæbning måles i en browser** — jsdom flytter ikke
  fokus og lægger ikke layout.
- **Grib efter VIRKNINGEN, ikke navnet**, når en klasse af tilfælde skal tælles,
  og tæl ikke kommentarer med. Skriv tallet som en DATERET observation, eller
  lad være.
- **En vagt, man tror er bredere end den er, er værre end ingen vagt.** Byg ikke
  en vagt, der lader som om.

---

## Tjekliste før PR

- [ ] Fandt du husets eksisterende udgave og spejlede den — eller står det
      skrevet hvorfor ikke?
- [ ] Tabelflade: visninger, søgning, filtrering, klikbare rækker, kolonnevalg
      pr. visning og et snit, en eksport kan læse — eller skrevne fravalg.
- [ ] Hver slags tilstand bor, hvor afsnittet siger; ingen klient-substring i
      URL'en; ingen klient-substring på en flade med loft.
- [ ] Parsning/serialisering er rene, testede funktioner uden for komponenten,
      med en test, der serialiserer og læser tilbage til det samme.
- [ ] Tom parameter = alt; ugyldige værdier frafiltreres; den ufiltrerede liste
      har den korte adresse; parametrene er danske.
- [ ] Visning og sortering står i samme kontrakt som filtrene, og et
      visningsskift bevarer filtrene.
- [ ] Listen har et loft, afkortningen siges, antallet står, og loftet skærer
      til sidst. Tællingen bærer samme filter som hentningen.
- [ ] Alle fire udfald — og deres kombinationer — er afprøvet; de to tomme
      skelnes på det ufiltrerede antal.
- [ ] Hjælpetekster peger kun på kontroller, fladen har, og lover kun, hvad de
      kan.
- [ ] Et standard-snit er synligt og står i adressen; intet snit opstår efter
      hydrering.
- [ ] Hvert aktivt filter kan fjernes for sig; "Ryd filter" står også i
      tomtilstanden og lader sorteringen stå.
- [ ] Facetter kan vælge "uden værdi", hvor attributten kan være tom.
- [ ] Tastatur: fokus ind og ud af multivælgeren, `Escape` lukker og fortryder,
      gitteret er ét tab-stop, den sorterede kolonne bærer `aria-sort`.
- [ ] Gitter: appens fælles celler, serverværdien i `key`, TAB- og
      piletast-gennemgang skriver intet, skrivende vælgere er værnet.
- [ ] Tomme felter har en synlig (stiplet) kant; omsluttende kanter klarer 3 : 1.
- [ ] Søgeendpoints er gatet i loaderen; ændringer i adgang er kørt gennem
      `/security-review`.
- [ ] Negative påstande har en positivkontrol i samme prøve.
