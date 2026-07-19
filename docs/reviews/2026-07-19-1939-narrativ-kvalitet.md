# 1939-narrativer: diagnose, rettelse og facit

**Dato:** 2026-07-19

**Omfang:** lokal, deterministisk behandling af de 539 gitignorerede 1939-poster.

**Prod:** ikke berørt. De allerede loadede 1939-rækker er fortsat staged.

## Konklusion

Den oprindelige A3b-godkendelse var ikke tilstrækkelig. Anker-rate og R1-proxy kunne
være grønne, selv når samme tekstblok blev tildelt mange personer. De verificerede
rodårsager var:

1. gruppe-fallback brugte min/max over alle ankre i `(linje, gruppe)` og kunne derfor
   spænde over flere generationer og sektioner;
2. anker-snit stoppede kun ved næste anker, ikke ved næste nummererede bogpost eller
   sektionsoverskrift;
3. 1939-sidehovedet `Reventlow.` blev ikke fanget af 2018-20-filteret;
4. PDF-tekstlaget leverede fremhævede navne som enkeltbogstaver med mellemrum;
5. `MIN_NARRATIVE_LEN=20` kunne demotere en korrekt, kort bogpost til en enorm fallback.

## Implementeret rettelse

- `clean_1939_text()` fjerner kun den eksakte sidehovedlinje og samler sekvenser på
  mindst fire enkelttegn på samme linje. `1` bliver kun til `l` inde i en sådan
  sekvens. `N. N.`, `f.` og `g.` berøres ikke.
- `extract_text.sh` filtrerer samme sidehoved ved fremtidig PDF-ekstraktion.
- Ankre er udvidet med kilde-/normaliserede navne, vielsesdato, titel, erhverv, gods
  og entydige bognumre. Korte sekundærankre accepteres ikke.
- Slutgrænsen er det tidligste af næste anker, næste nummererede post,
  romertalssektion eller bogstavsektion.
- Entydige huller bindes 1:1 til bogens nummererede poster. Vindueskanter kan bindes
  konservativt via postorden + bognummer.
- Gruppe-fallback nøgles nu på `(vindue, linje, gruppe, forældrenote)`.
- Resterende usikkerhed er synlig i metoderne `struktur-fallback`,
  `gruppe-fallback`, `nabo-fallback` og `kollisions-fallback`; der er ingen skjult
  manuel pass og ingen genereret eller parafraseret prosa.

## Facit før/efter

Målingerne er beregnet af `compute_stats()` mod samme `raw.txt`,
`linked_clean.json` og vindueskort.

| Måling | Før | Efter |
|---|---:|---:|
| Anker | 440 | 500 |
| Gruppe-fallback | 70 | 15 |
| Vindue-fallback | 29 | 0 |
| Strukturfallback / nabo / kollision | 0 | 13 / 7 / 4 |
| Vinduesstore narrativer (≥90 % af region) | 42 | 0 |
| Maksimal længde | 80.192 | 4.377 |
| P95-længde | 14.957 | 1.122 |
| Poster i eksakte duplikatklynger | 98 | 25 |
| Største duplikatklynge | 15 | 5 |
| Narrativer med flere nummererede bogposter | 208 | 13 |
| Sidehovedforekomster i tildelte narrativer | 625 | 0 |
| Narrativer med bogstavspredning | 486 | 0 |
| Mistænkelige `bogstav + 1`-forekomster | 483 | 12 |
| Fremmed unik dato-proxy | 100 | 21 |
| R1/R6-datoproxy | 684/750 | 683/750 |
| Tomme narrativer | 0 | 0 |

R1/R6 falder med ét hit, mens alle direkte overinklusionsmål forbedres markant.
Det bekræfter, at datoproxyen ikke må bruges alene som kvalitetsgate.

Regenererede lokale artefakter:

- `narrative_1939.json`: SHA-256 `14e181f92ee6259ff99454f3f2dac25e9e0ab5a69e2bdc8be7a501ecc54fc868`
- `clean_1939.json`: SHA-256 `4ea461e5b0971a49749418eaef3542a9331422474d0aae5cb1e693a249405da9`
- begge indeholder 539/539 ikke-tomme narrativer; kvalitetsgaten passerer.

Konverter-previewet giver 360 forældrelinks mod det loadede/dokumenterede facit 355.
Det er ikke en skjult tilfældig regression: de gamle, overinklusive narrativer placerede id
313-314 på side 534 og dermed i linje III, mens de korrigerede starter på side 548 ligesom
resten af gruppen 313-317. Alle fem matcher nu entydigt forælder 299 via forældrenoten,
ligger ét slægtled efter og i samme linje IV. Denne grafændring er strukturelt plausibel,
men den er ikke automatisk omfattet af en narrative-only prod-opdatering.

## Repræsentativ korpusvalidering

QA kører over alle 539 poster og alle 16 anvendte vinduer (raw dækker PDF-sider 490-598),
ikke kun de oprindeligt rapporterede eksempler. Den tidligere 80.192-tegns blok for
id 217/218/219/220/221/223 er nu fordelt på fem ankre og én strukturfallback;
længderne er 19-536 tegn. Sidehoved- og bogstavspredningsgates er nul over hele
det regenererede resultat.

## Kendte begrænsninger og gate før publicering

- 39 poster er fortsat ikke almindelige anker-snit: 13 struktur-, 15 gruppe-,
  7 nabo- og 4 kollisionsfallbacks.
- 25 poster indgår fortsat i 11 eksakte duplikatklynger; nogle kan være legitime,
  delte kildeblokke, men de bør stikprøves redaktionelt.
- 13 narrativer rummer mere end én nummereret postmarkør.
- 12 mistænkelige `bogstav + 1`-forekomster er bevidst ikke autokorrigeret, fordi de
  ligger uden for den sikre fire-enkelttegnskontekst. De kræver kildeopslag.
- Ni kildetekster er under 20 tegn. De beholdes, fordi anker og strukturgrænse er
  sikre; en kort korrekt post er bedre end en stor fallback.

Før `red_publicer_udgave` anbefales en manuel, PDF-mod-PDF stikprøve af alle 39
fallbackposter samt de 12 OCR-`1`-forekomster. Det er en kurateringsgate, ikke en
invitation til at omskrive prosaen.

## Foreslået reload-strategi (ikke udført)

1. Tag og verificér en prod-backup efter `docs/fase4-runbook.md`.
2. Genskab `narrative_1939.json` og `clean_1939.json`; gem QA-log og hash, og kræv
   539/539 ikke-tomme narrativer samt ovenstående gates.
3. Rehearsal på en frisk lokal restore af prod. Brug en formålsbygget,
   transaktionel **1939-only narrative updater** med en eksplicit 539-rækkers
   mapping til de eksisterende 1939-personer. Genkør ikke hele den delte loader,
   fordi person-, familie-, assertion- og matchdata allerede er loadet.
4. Fail closed hvis source ikke er entydigt `aar=1939`, hvis de forventede 539
   person-/narrative-matches ikke findes, eller hvis andre source-id'er berøres.
   Verificér row counts, hashes/stikprøver og at alle berørte personer fortsat er
   staged; rollback rehearsal skal være bestået.
5. Kør samme updater i prod først efter eksplicit godkendelse. Publicering er et
   separat redaktionelt trin efter fallback/OCR-gaten.

Narrative-only updateren skal lade de nuværende 355 prod-links urørte. De fem ekstra
preview-links skal enten godkendes og migreres i et separat, eksplicit graftrin eller
forblive staged/uændrede; en narrativrettelse må ikke snige dem ind implicit.
