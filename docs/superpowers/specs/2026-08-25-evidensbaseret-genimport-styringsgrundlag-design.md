# Styringsgrundlag for evidensbaseret genimport

**Dato:** 2026-08-25  
**Status:** Godkendt design; dokumentpakken er endnu ikke implementeret  
**Scope:** Import og genimport af trykte DAA-årbøger, herunder kildebevaring,
fortolkning, identitetsafstemning, kanonisk promotion og publicering

## 1. Formål

Projektets oprindelige retning skal kunne overleve lange implementeringsforløb,
skift mellem mennesker og LLM'er og nødvendige afstikkere for konkrete
årbøger. Det kræver en lille, autoritativ dokumentpakke, hvor værdier,
prioriteter, teknisk mål og aktuel status ikke blandes sammen.

Styringsgrundlaget skal:

- fastholde den evidensbaserede genimport som det overordnede produktmål;
- gøre retningen obligatorisk synlig for både Claude og Codex;
- forhindre, at en nærliggende udgavespecifik opgave stiltiende bliver et nyt
  programspor;
- gøre det tydeligt, hvornår noget kun er specificeret eller isoleret bygget,
  og hvornår det faktisk virker ende-til-ende;
- bevare gamle planer og reviews som historik uden at lade dem konkurrere med
  den gældende status.

Styringsgrundlaget gælder i første omgang kun genimport- og årbogsarbejdet. Det
gør ikke roadmapet bindende for projektets øvrige produkt-, web-, mobil- eller
formidlingsspor.

## 2. Valgt model

Der vælges en lagdelt dokumentmodel med fire autoritative dokumenter:

1. `docs/evidensbaseret-genimport/vision.md`
2. `docs/evidensbaseret-genimport/roadmap.md`
3. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`
4. `docs/evidensbaseret-genimport/status.md`

Dokumenterne har forskellige roller og ændringsmyndigheder. Ingen af dem må
kopieres i fuld længde ind i LLM-instruktioner eller andre statusdokumenter.
Instruktionerne skal i stedet pege på den autoritative kilde og kræve en fast
læserækkefølge.

En enkelt samlet fil blev fravalgt, fordi vision, roadmap og dagsstatus da igen
ville flyde sammen. Automatisk CI-håndhævelse blev fravalgt i første omgang,
fordi den manuelle styringsmodel bør afprøves, før projektet påtager sig endnu
en kontrolmekanisme.

## 3. Dokumenternes myndighed

### 3.1 Vision og værdigrundlag

`vision.md` er det stabile svar på, hvorfor arbejdet findes, og hvilke værdier
der ikke må ofres for en lokal gevinst. Dokumentet skal indeholde:

- den ikke-tekniske vision;
- bindende principper om kildebevaring, synlig usikkerhed, menneskelig
  afgørelse og én fysisk person på tværs af kildeoptrædener;
- kravet om en fælles metode med små udgavespecifikke profiler;
- ikke-mål, herunder perfekt OCR, tvungen sikkerhed og udtræk af alt til den
  kanoniske model;
- en ikke-teknisk definition af, hvornår genimportprogrammet er lykkedes;
- reglerne for at ændre visionen.

Visionen må kun ændres efter en udtrykkelig beslutning fra projektejeren.
Ændringen skal samtidig registreres i `docs/decisions.md`.

### 3.2 Roadmap

`roadmap.md` er den styrende prioritering. Det skal angive ét aktivt
programmål, dets stopport og rækkefølgen af de efterfølgende mål.

Den indledende rækkefølge er:

1. afslut C3 ved den planlagte integration-, rehearsal- og stopport uden
   automatisk produktionskørsel;
2. gør narrativer entydigt knyttet til den konkrete kildepost;
3. generalisér varige writer- og batchmekanismer;
4. giv DAA 2018-20 samme grundlæggende kildeproveniens som 1939;
5. færdiggør den fælles kæde fra klausulobservation over fortolkning og
   identitetsafgørelse til godkendt promotion og synlig kildevisning;
6. kør den fælles kæde på begge referenceudgaver;
7. bevis generaliseringen med en tredje årbog.

Roadmappets rækkefølge må kun ændres gennem en begrundet beslutningspost. En
implementerende agent må ikke selv omprioritere programmet.

### 3.3 Teknisk målarkitektur

`teknisk-maalarkitektur.md` er den stabile oversættelse fra vision til
systemadfærd. Det skal beskrive:

- den fælles ende-til-ende-kæde fra original bog til offentlig visning;
- ansvarsgrænsen mellem fælles importmotor og udgavespecifik profil;
- de oplysninger og beslutninger, der bevares ved hvert trin;
- adskillelsen mellem observation, fortolkning, identitet, promotion og
  publicering;
- hvordan én kanonisk person sameksisterer med flere særskilte
  kildeoptrædener og narrativer;
- gater, redaktionelle beslutninger, genkørsel og fortrydelse;
- de egenskaber, der beviser, at en funktion er generel;
- hvilke parallelle og ældre veje målarkitekturen på sigt skal erstatte.

Dokumentet må ikke være en ny implementeringsplan. Det indeholder derfor ikke
aktuelle rækketal, fil-for-fil-opgaver, detaljerede SQL-signaturer eller
midlertidige batchnavne. Levende kode og databasesource-of-truth afgør de
tekniske detaljer; `status.md` afgør den aktuelle modenhed.

Målarkitekturen ændres kun, når et bindende arkitekturprincip ændres. Sådanne
ændringer kræver samme beslutningsspor som visionen.

### 3.4 Status

`status.md` er et dateret, efterprøvbart øjebliksbillede. Det skal indeholde:

- verificeringsdato og commit;
- det aktive roadmapmål og dets stopport;
- hvad der er specificeret, isoleret implementeret, integreret ende-til-ende
  og produktionsverificeret;
- aktuelle blokeringer og næste tilladte arbejde;
- hvilke produktionstal der er live-verificerede, og hvilke der kun stammer
  fra en ældre måling;
- henvisninger til de vigtigste beviser, ikke kopier af dem.

Status må aldrig ændre visionen eller roadmappets rækkefølge stiltiende. Den
opdateres ved afslutningen af hver fase og før en ny genimportplan påbegyndes,
hvis gren, kode eller produktionsforhold har ændret sig væsentligt.

## 4. Obligatorisk synlighed for LLM'er

Følgende indgange opdateres med korte, scope-afgrænsede instruktioner:

- rodens `CLAUDE.md`;
- en ny rod-`AGENTS.md` for Codex;
- `.claude/skills/daa-extract/SKILL.md`;
- `docs/README.md`.

Ved arbejde med DAA-import, genimport, source records, source personas,
fortolkning, identitetsafstemning, promotion eller importpublicering skal en
agent først læse dokumenterne i denne rækkefølge:

1. vision;
2. roadmap;
3. teknisk målarkitektur;
4. status.

Instruktionen skal samtidig sige, at historiske specs, planer, reviews og
changelog ikke må bruges som aktuel programstatus, når de fire dokumenter
dækker spørgsmålet. Levende skema og kode er fortsat autoritative for tekniske
detaljer, der kan være ændret siden statussnapshotet.

`AGENTS.md` afgrænses udtrykkeligt til genimport- og årbogsarbejdet, så den
ikke gør andre produktspor afhængige af dette roadmap. Den eksisterende
`mobile/AGENTS.md` ændres ikke.

## 5. Adgangskrav til nyt udviklingsarbejde

Enhver ny plan eller implementeringsopgave inden for scope skal angive:

1. hvilket roadmapmål den tilhører;
2. hvilket led i den fælles værdikæde den lukker;
3. om leverancen er generel, en udgaveprofil eller midlertidig
   legacy-afvikling;
4. hvilken redaktionel eller brugerrettet værdi den muliggør;
5. hvilket konkret bevis der gør leverancen færdig;
6. hvilke parallelle eller ældre workflows den erstatter.

Kan en opgave ikke besvare disse seks spørgsmål, er den som udgangspunkt uden
for scope og kræver en udtrykkelig beslutning, før den planlægges.

Udgavespecifik kode er legitim i profiler, parsere og private
arbejdsartefakter. Nye permanente tabeller, RPC'er eller fælles workflows med
en konkret udgave i identiteten kræver en undtagelsesbeslutning i
`docs/decisions.md`.

## 6. Arbejds- og modenhedsregler

### 6.1 Ét hovedmål ad gangen

Roadmappet har højst ét aktivt programmål. Et nyt genimportspor må ikke startes,
før målet har nået sin stopport, medmindre projektejeren udtrykkeligt ændrer
prioriteringen.

### 6.2 Fire ærlige modenhedstilstande

Funktionalitet beskrives med én af fire tilstande:

- `specificeret`;
- `isoleret implementeret`;
- `integreret ende-til-ende`;
- `produktionsverificeret`.

Tests af et isoleret fundament er ikke bevis for, at den samlede funktion er
færdig. Et roadmapmål rykker kun til ende-til-ende eller produktionsverificeret
på baggrund af det bevis, målet selv kræver.

### 6.3 Kontrollerede afbrydelser

Et akut dataintegritets- eller produktionsproblem må afbryde roadmappet. Det
skal registreres som en afgrænset hændelse med indgangsgrund, slutkriterium og
tilbagevenden til det aktive mål. Hændelsen må ikke stiltiende blive et nyt
programspor.

## 7. Historik og statuskilder

Eksisterende specs, planer og reviews bevares uændret som beslutnings- og
implementeringshistorik. De fire nye dokumenter erstatter dem ikke som bevis
for tidligere arbejde, men de erstatter dem som indgang til gældende vision,
prioritering, målarkitektur og status.

`docs/decisions.md` registrerer:

- at den lagdelte styringsmodel er vedtaget;
- dokumenternes myndighed og ændringsregler;
- fremtidige ændringer i vision, målarkitektur og roadmaprækkefølge;
- eventuelle godkendte undtagelser fra kravet om generelle permanente
  overflader.

`docs/changelog.md` registrerer oprettelsen af dokumentpakken og senere
konkrete statusændringer, men er ikke selv roadmap eller statusorakel.

## 8. Første statussnapshot

Den første `status.md` skal være læse-kun afstemt mod den aktuelle worktree og
skal mindst fastholde:

- 1939-proveniens og narrativpublicering som en væsentlig delleverance;
- den generelle extraction-/fortolknings-/promotionkæde som uafsluttet;
- 2018-20-proveniens og fælles import som uafsluttet;
- C3 som langt implementeret i kode, men endnu ikke dokumenteret gennem den
  planlagte samlede integration, disposable rehearsal og produktions-GO;
- at produktionstal fra 2026-08-22 ikke er genverificeret i denne
  dokumentationsopgave;
- det aktive programmål som C3's planlagte rehearsal- og stopport, uden
  automatisk produktionsmutation.

Snapshotet må ikke opfinde aktuel produktionsstatus. Driftfølsomme påstande
mærkes med verificeringsdato eller som ikke genverificerede.

## 9. Verifikation

Implementeringen verificeres ved at:

- kontrollere, at alle nye og ændrede Markdown-links peger på eksisterende
  filer;
- kontrollere, at `CLAUDE.md`, rod-`AGENTS.md`, `/daa-extract`-skillen og
  dokumentationsindekset har samme læserækkefølge og scope;
- søge efter modstridende myndighedspåstande i de ændrede indgange;
- søge efter `TBD`, `TODO`, placeholders og uklare statusmarkører i den nye
  dokumentpakke;
- køre `git diff --check`;
- gennemlæse dokumentpakken i rækkefølge som både projektleder og
  implementerende agent.

Der tilføjes ingen CI-kode i denne omgang. Hvis manuel styring ikke forhindrer
ny dokumentationsdrift, kan en senere, særskilt opgave foreslå en lille lint,
der kræver roadmapkobling og færdigbevis i nye genimportplaner.

## 10. Uden for scope

Denne dokumentationsopgave:

- ændrer ingen produktionsdata eller databaseobjekter;
- ændrer ingen import-, review- eller publiceringskode;
- afslutter ikke C3 og giver ingen produktions-GO;
- omskriver ikke historiske planer eller reviews;
- gør ikke genimport-roadmappet bindende for andre projektspor;
- indfører ikke CI-håndhævelse;
- løser ikke de tekniske roadmapmål, men gør deres rækkefølge og færdigbeviser
  bindende for kommende arbejde.
