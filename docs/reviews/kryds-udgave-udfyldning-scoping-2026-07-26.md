# Scoping: kryds-udgave-udfyldning af forældrelinks — billigere vej end trin 2

**Dato:** 2026-07-26 · **Status:** analyse, intet implementeret · **Beslutning:** trin 2 udskudt
**Forudsætter:** [`stikproeve-audit-1939-baseline-2026-07-26.md`](stikproeve-audit-1939-baseline-2026-07-26.md)

Auditen fandt ~51 % mangelfulde forældrelink i 1939 og pegede på trin 2 (re-ekstraktion) som
løsningen. Denne analyse viser at **størstedelen af hullet allerede er lukket** — af brugerens
eget matcharbejde, uden en eneste skrivning til basen.

---

## Fundet

`collapseSameAs.ts:306-318` omskriver `parentChild`-kanter til kanoniske id'er og unionerer dem.
Når en 1939-person er `samme_som`-matchet med sin 2018-20-modpart, arver den fælles identitet
altså modpartens forældrekanter. Læseren ser forældrene, selv om 1939-rækken i basen ingen har.

Konsekvensen, målt:

| Forældrelink, 1939 (539 hovedposter) | Antal |
|---|---|
| Har eget link i basen | 355 |
| Mangler eget link | 184 |
| — **dækket via samme_som-match** | **114** |
| — reelt udækket | **70** |
| Har kun én forælder | 69 |
| — **komplet via match** (modparten har begge) | **57** |
| — stadig kun én | 12 |

**Data-lag: 253 af 539 (47 %) mangelfulde. Læser-lag: 82 af 539 (15 %).**
Matcharbejdet lukker ~68 % af hullet gratis.

Til sammenligning har 2018-20 kun 25 poster uden link, hvoraf 23 er reelt udækkede — den
udgave har intet at hente fra 1939.

### Konkrete eksempler

| 1939 | 2018-20-modpart | Forældre der allerede vises |
|---|---|---|
| nr 15 `Henrik [Reventlow] (Grove)` | I-28 `Hinrich` | Iwan von Reventlow + Beke von Pogwisch |
| nr 33 `Iven` | I-44 `Iwan` | Hartwich + Ghese NN |
| nr 35 `Elsebe` | I-46 `Elsebe` | Hartwich + Ghese NN |

nr 35's modpart (I-46) indgik i 2018-20-stikprøven og er dér verificeret ordret mod bogen —
kæden fra bog til skærm er altså efterprøvet i begge ender for netop det tilfælde.

---

---

## Efterprøvet ved at køre den rigtige `collapseSameAs` mod prod-data

SQL-genimplementeringer af reglen var upålidelige. Den afgørende måling er lavet ved at dumpe
`person`, `family_member` og `samme_som` fra prod (read-only, `tmp/dump-collapse-input.R`) og
køre den **faktiske** `collapseSameAs` over dem (`tmp/run-collapse.ts`, vite-node).

| Måling | Antal |
|---|---|
| samme_som-kanter | 434 |
| Accepterede grupper | **140** |
| **Karantænerede grupper** | **287** |
| — årsag | 100 % `konkurrerende forældre` |
| — alle på tværs af 1939↔2018-20 | 287 |

**Korrektion til tallene ovenfor:** af de 114 forældreløse 1939-poster arver **110** faktisk
forældrene; de sidste 4 er blokeret fordi et *andet* medlem af deres gruppe har en konflikt.
Læser-synligt hul bliver dermed 86 af 539, ikke 82.

### De 287 er ikke uenighed mellem bøgerne

Testet ved at kanonisere forældrene med *alle* samme_som-grupper i stedet for kun de accepterede:
0 af de 287 skyldes kaskade — men navnene afslører hvad der faktisk sker:

| 1939 siger | 2018-20 siger |
|---|---|
| `Bertram + Christine Rantzau` | `Bartram + Christina von Rantzau` |
| `Cay Friedrich + Hedevig Ida Buchwald` | `Cay Friedrich + Hedwig Ida von Buchwaldt` |
| `Henning + Margarethe Rumohr` | `Henning + Margaretha von Rumohr` |

Det er **de samme mennesker med forskellig stavemåde**. Karantænen skyldes ikke at bøgerne er
uenige, men at *forældrene endnu ikke er matchet til hinanden* — kun børnene er.

### Det gør oprydningen meget billig

| | Antal |
|---|---|
| Karantænerede grupper | 287 |
| Distinkte forældrepar involveret | 143 |
| Forældre uden match i dag | **133** |

Og de klumper: ét forældrepar frigiver alle sine børn på én gang.

| Frigives | Forældrepar |
|---|---|
| 14 børn | Cay Friedrich + Hedevig Ida Buchwald ↔ Cay Friedrich + Hedwig Ida von Buchwaldt |
| 11 børn | Christian Ditlev + Benedicte Margrethe Brockdorff ↔ Christian Detlef + Benedicte Margaretha von Brockdorff |
| 10 børn | Detlev + Anna Margretha von Jessen ↔ Detlef + Anna Margretha von Jessen |
| 9 børn | Henning + Margarethe Rumohr ↔ Henning + Margaretha von Rumohr |

**~133 forældre-matches frigiver 287 karantænerede par.** Det er redaktør-arbejde i den
eksisterende UI, ikke kode.

## Hvad det betyder for trin 2

Trin 2 blev begrundet i "~184 forældreløse poster". Det reelle, læser-synlige tal er **82**,
og de 82 er netop de poster der **ikke** har en matchet modpart — altså dem hvor 2018-20
heller ikke kender forældrene. Re-ekstraktion af 1939 vil derfor ikke løse dem uden bedre
upstream-ekstraktion, hvilket er præcis den konklusion A3b nåede.

**Trin 2's værdi falder markant.** Den resterende begrundelse er ikke længere forældrelinks,
men de ~42 fakta-tomme poster hvor en dato står synligt i prosaen uden at være blevet til et
faktum (capture-gap målt i kvalitetsvurderingen).

---

## Tre veje, i stigende omkostning

### A. Gør ingenting — dokumentér at 51 % er et data-lags-tal (anbefalet)

Auditens 51 % er korrekt om basen og misvisende om oplevelsen. Rettelsen er at skrive begge tal.
Kræver én empirisk bekræftelse i den kørende app: slå nr 35 `Elsebe` op og se om forældrene
`Hartwich + Ghese NN` vises. Kode-læsning + SQL peger entydigt den vej, men er ikke det samme
som at have set det.

**Omkostning:** minutter. **Risiko:** ingen.

### B. Materialisér de dækkede kanter i basen

Skriv forældrelinket på 1939-personen som en ny påstand med citation til **source 1**
(2018-20) — ikke til 1939. Det er indfødt i evidensmodellen: 2018-20 *er* en kilde der udtaler
sig om personen, og invariant 1 kræver netop at påstanden bærer sin egen kilde.

Værdi ud over visning:
- GEDCOM-eksport og andre ikke-kollapsede aftagere ser kanterne
- Robust hvis et match senere fjernes eller karantæneres
- Data-laget bliver sandt, ikke kun projektionen

Af de 114 dækkede har **96** en forælder der *også* er matchet til en 1939-person, så kanten
kan skrives helt inden for 1939's id-rum. De sidste 18 ville blive kanter på tværs af udgaver —
tilladt af den polymorfe relation, men værd at beslutte bevidst.

**Omkostning:** dette er den *samme* loader-kapacitet som trin 2 kræver (upsert på
`person_external_id`, append af påstande til eksisterende personer) — men med data der allerede
ligger i basen, verificeret af brugeren. Ingen LLM, ingen PDF, ingen re-ekstraktion.
**Det gør B til den rigtige måde at bygge trin 2's loader på:** øv mekanikken mod kendt-god
data først, og find først derefter ud af om re-ekstraktion overhovedet er nødvendig.

### C. Trin 2 som oprindeligt beskrevet — udskudt

Re-ekstraktion af fakta for ~184 forældreløse + ~42 fakta-tomme poster. Flere sessioner.
Loader-koden er den risikable del, fordi ingen del af pipelinen udfører den operation i dag.

---

## Forbehold

- "Dækket via match" forudsætter at begge udgaver er indlæst i samme graf. 1939 er `staged`,
  så en anonym besøgende ser dem ikke — men ser heller ikke 1939 overhovedet. For den
  indloggede bruger (eneste publikum i dag) holder det.
- Analysen er lavet med SQL og kodelæsning, ikke ved at åbne appen. Se A.
- Tallene gælder forældrelinks. Auditens øvrige fund (capture-gap, OCR-fejl i kildehenvisninger,
  parser-huller) berøres ikke af matcharbejdet.
