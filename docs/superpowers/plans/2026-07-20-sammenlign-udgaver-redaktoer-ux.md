# "Sammenlign udgaver" — brugbar identitetsvurdering for redaktøren — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redaktørens tværudgave-triage i "Sammenlign udgaver" (`web/src/components/SammenlignUdgaver.tsx`) skal gøres brugbar til reel identitetsvurdering: (1) kandidat-rækkerne skal vise nok diskriminerende information til at to samtidige navnefættre (fx to "Detlev"'er) fra forskellige bogudgaver kan skelnes — i dag viser rækkerne kun matcherens egne score-inputs tilbage; (2) der skal være en reel, filtrerbar oversigt over allerede trufne match-beslutninger (bekræftet/afvist, hvem, hvornår, fold-status, fortryd) — i dag findes kun en publicerings-gate-liste med navn+årstal.

**Status:** Planlagt (endnu ikke påbegyndt). Dateret 2026-07-20. Baseret på research+design-analyse gennemført 2026-07-20 (verificeret mod koden).

## Analyse (verificeret i koden 2026-07-20)

### Grundproblemet: UI'et viser matcherens egne inputs tilbage

De fire signaler en kandidat-række viser i dag — `navn {sim}` · `fødsel ✓/—` · `død ✓/—` · `køn ✓/✗` (`SammenlignUdgaver.tsx` linje 279-281) — er *præcis* de fire felter `matchUdgaver` selv scorer på (`scorePair`, `matchUdgaver.ts:107-114`). At vise dem tilbage til redaktøren er cirkulært: hvis matcheren allerede har rangeret to samtidige "Detlev" ens (samme navnenøgle, overlappende fødselsvindue, samme køn), så er de fire tal *per konstruktion* næsten identiske for begge kandidater. De kan derfor ikke bruges til at skelne dem — det er nøjagtig den situation brugeren beskriver.

`RedMatchPerson` (`matchUdgaver.ts:278-286`) bærer kun `id, navn, koen, foedsel{min,max}, doed{min,max}, sourceIds, staged`, og `fetchMatchPersoner` (`redaktionRead.ts:993-1002`) henter ikke mere. Det er hele redaktørens beslutningsgrundlag.

### De felter der REELT diskriminerer to navnefættre — og som allerede findes i modellen

For to samtidige "Detlev Reventlow" født ca. 1660 er de afgørende forskelle:

- **Forældre** (`family_member` rolle=`partner` i den familie personen er `barn` i). To Detlev'er med forskellige fædre er trivielt forskellige personer. Dette er også *den* dimension `collapseSameAs` karantænerer på ("konkurrerende forældre", `collapseSameAs.ts:160-171`) — så det er dobbelt relevant.
- **Ægtefælle(r) + børn** (`family_member` i personens egne `partner`-familier). "Gift med Anna Sophie / far til fem" vs. "ugift, ingen børn" afgør sagen.
- **Linje/gren + bog-reference** (`person_external_id.linje/nr/slaegtled_lokal/slaegtled_gennem/kuld` + `lineage.kode/navn`, `schema.sql:138-171`). Bogens egen nummerering ("III-58" vs. "V-1") er redaktørens naturlige nøgle og udelukker/bekræfter ofte et match direkte. NB: netop ved 1939 vs. 2018-20 kan grenene være omstruktureret, så gren-forskel er et *hint*, ikke en hård udelukkelse.
- **Titel og øvrige daterede fakta** (`fact` faktatype `titel/dåb/begravelse/floruit/naturalisering` — allerede understøttet i `FELT_FAKTATYPE`, `redaktionWrite.ts:12-15`). En "oberst" adskiller sig fra en "amtmand".
- **Narrativ-teksten** (`narrative`, én pr. `source_id`) — det redaktøren i praksis læser: prosaen nævner selv embeder, godser, krydsreferencer. Det stærkeste enkeltbevis, og i dag helt fraværende i fladen.
- **Embeder/godser** (`relation` → `organisation`/`estate`) — "til Christianssæde" vs. "til Frisenvold".

Konklusion: alle diskriminatorer eksisterer allerede i basen og har allerede læse-funktioner (se datalags-afsnittet). Manglen er udelukkende i read-udvalget og i UI-præsentationen — ikke i datamodellen.

### "Allerede matchet"-oversigten i dag

Dagens `afklarede`-sektion (`SammenlignUdgaver.tsx:223-264`) viser kun `visning(a) = visning(b)` (navn+årstal) og et fold-status-badge, og eksisterer primært som publicerings-gate. Det er ikke en audit-flade: der er ingen "hvem/hvornår", ingen søgning/filtrering, ingen fortryd, og ingen mulighed for at genåbne beslutningen med fuld kontekst. Med 176 bekræftede matches i dag er søgning/filtrering nødvendig for at gøre listen brugbar.

### Designretning: to-trins-flow (afgørende for overblik ved hundredvis af kandidater)

For meget info pr. række dræber triage-overblikket. Løsningen er progressiv afsløring:

**Trin 1 — kompakt liste (beriget, men stadig tæt).** Behold den nuværende arbejdsliste-struktur (aabne/afklarede/formodet_nye fra `buildArbejdsliste`, `sammenlign.ts`). Berig hver kandidat-række med de *billige* diskriminatorer der kan hentes eagerly uden narrativ-tekst: fulde navn + titel, fødsel–død span (som i dag), **forældre-navne** ("f. af Christian D. R. & Anna S."), **linje/gren + bog-nr** ("III-58, Holstenske linje"), tier-badge + score (behold — det er stadig et nyttigt triage-signal). Allerede med dette er klage 1 delvist afhjulpet: to Detlev'er med forskellige forældre og forskellige bog-numre kan nu skelnes uden at åbne noget.

**Trin 2 — udvidet side-by-side ved ekspansion.** Klik på en kandidat (eller "Sammenlign"-knap) folder en to-kolonne-visning ud, kilde A (ny udgave) mod kilde B (eksisterende base), felt-for-felt justeret:

| | Kilde A (fx DAA 1939) | Kilde B (fx 2018-20) |
|---|---|---|
| Navn + titel | ... | ... |
| Fødsel / død | dato + kilde-citat | dato + citat |
| Forældre | far, mor (med link) | far, mor |
| Ægtefælle(r) | ... | ... |
| Børn | ... | ... |
| Linje / gren + bog-nr | III-58 | V-1 |
| Embeder / godser | ... | ... |
| Narrativ | fuld tekst (scrollboks) | fuld tekst |

Design-principper:

- **Fremhæv enighed/uenighed visuelt** (grøn=samstemmende felt, rød/gul=afvigende) så redaktøren scanner forskelle frem for at læse to kolonner lineært.
- **Fold-advarsel proaktivt øverst i panelet**, ikke bagefter. `foldHint`/`previewSammeSom` findes allerede (`SammenlignUdgaver.tsx:162-168`) og giver "→ vil IKKE folde: konkurrerende forældre …". Flyt den op som en fremtrædende advarsel med `foldAdvice`-teksten *før* Bekræft-knappen.
- **Bekræft/Afvis-knapperne bliver i det udvidede panel**, med den fulde kontekst synlig — så beslutningen tages informeret.
- Narrativ-teksten kan indledningsvis vises som uddrag (fx første 400 tegn) med "vis hele" for at holde panelet håndterbart; men da den kun hentes ved ekspansion (lazy) er fuld tekst acceptabelt.

### Designretning: audit/browse-oversigt over trufne beslutninger

En selvstændig, filtrerbar/søgbar liste over trufne beslutninger (både `samme_som` og `ikke_samme_som`), hvor hver post viser:

- begge personer med navn + år + **linje/gren + bog-nr** (nok kontekst til at genkende uden at genåbne sammenligningen)
- beslutningstype: bekræftet samme / afvist forskellig
- **hvem + hvornår**: fra `change_set` (`operation='red_samme_som'`, `actor_navn`, `actor_rolle`, `created_at`, `subjekt_id`=kanonisk; `schema.sql:2087-2099`). Dette er audit-trailen der svarer på "hvem besluttede dette, og hvornår" — kritisk for en anden redaktør eller samme redaktør måneder senere.
- **score på beslutningstidspunktet** (rekomputeret deterministisk — se Alternativer, punkt 4)
- **fold-status** (folder offentligt / karantæne + grund) — genbrug `foldHint`/`karantaeneByPersonId`
- **"Fortryd"-knap** → `Change { art:'fjernSammeSom', relationId }` (write-arten findes allerede, `redaktionWrite.ts:271`; RPC `red_fjern_samme_som`) → dry-run/LIVE via `submitChange`, præcis som Bekræft/Afvis. Kræver `relationId`, som dagens fetch ikke returnerer (se datalags-afsnittet).

Filtre/søgning: fritekst på navn, filter på kilde-udgave, på linje/gren, og på fold-status ("vis kun links der ikke folder endnu" — den handlingsorienterede delmængde).

Ekspansion i denne liste genbruger det samme side-by-side-panel fra trin 2 (én komponent, to indgange), så en tidligere beslutning kan verificeres med fuld kontekst uden at genopbygge noget manuelt.

### Datalag — nye/udvidede fetch-funktioner og typer

**Eager (billigt) — berig trin-1-listen.** Udvid `fetchMatchPersoner` (`redaktionRead.ts:993`) og `RedMatchPerson` med felter der kan hentes samlet og småt:

- **Bog-reference/linje**: `person_external_id` hentes allerede for `sourceIds` — tilføj blot `linje, nr, slaegtled_lokal, slaegtled_gennem, kuld` til det select. Join `lineage` (via `fetchLineages`, findes allerede, `redaktionRead.ts:491`) for gren-navn.
- **Titel**: den valgte `titel`-konklusion pr. person (samme fact→conclusion→assertion-mønster som fødsel/død allerede bruger i `buildMatchPersoner`, `matchUdgaver.ts:296` — udvid faktatype-filteret fra `['fødsel','død']` til også `'titel'`).
- **Forældre-navne**: kan udledes af den allerede-hentede `familieGraf` (`fetchFamilyGraph`, `redaktionRead.ts:1024`) + `byId`-navneopslag, uden ny query — `parentChild` giver forældre-id'er, `personer` giver navnene.

Dette gør trin 1 markant mere brugbart uden nye net-runder af betydning. Enten udvid `RedMatchPerson`, eller introducér en tynd parallel `KandidatOverblik`-type for at holde matcher-kernens type ren (matcheren har kun brug for de fem MatchFrame-felter — jf. `buildMatchFrame`).

**Lazy (dyrt) — kun ved ekspansion.** Ny komposit-fetch, fx `fetchKandidatDetalje(personId)`, der **genbruger de eksisterende per-person-funktioner** frem for at bygge nyt:

- `fetchPersonEvidence(personId)` — fulde felter + kilde-citater (`redaktionRead.ts:125`)
- `fetchNarrativer('person', Number(personId))` — narrativ pr. udgave (`redaktionRead.ts:311`)
- `fetchPersonFamilie(personId, model)` — ægtefæller + børn + forældre (`redaktionRead.ts:618`)
- `fetchPersonRelationer(personId)` — embeder/godser via `resolveOrgEstateNames` (`redaktionRead.ts:637`)
- valgfrit `fetchRedPersonMedia(personId)` for portræt (`redaktionRead.ts:755`)

Disse kaldes for de to sider (A og B) *kun* når panelet åbnes, og bør caches pr. personId i komponentens state (samme person optræder som kandidat for flere andre).

**Audit-fladen.**

- **Udvid `fetchSammeSomPar`** (`redaktionRead.ts:1013`) til også at returnere `relation.id` — i dag kaster den `parseIkkeSammeSomPar` væk og beholder kun `aId/bId`. Uden `relationId` kan hverken "Fortryd" eller en præcis audit-post bygges. Tilsvarende for `fetchIkkeSammeSomPar`.
- **Ny `fetchMatchAudit`**: join `change_set` (`operation IN ('red_samme_som','red_fjern_samme_som')`) for `actor_navn/created_at`. NB: der findes i dag *ingen* `change_set`-læsning i `web/src/data` (bekræftet — ingen match), så dette er en helt ny, lille read-funktion. Grovkobling: `change_set.subjekt_id` = kanonisk person = `objektId`; ved flere links til samme kanoniske skelnes via `change_event.row_pk` (`schema.sql:2101-2110`) om nødvendigt.

**Performance/skala.**

- **Narrativ-tekst må ALDRIG hentes eagerly for alle kandidater.** ~1700 personer × fuld prosa er både net- og hukommelses-tungt og unødvendigt for triage. Lazy-ved-ekspansion er ikke-forhandlelig her.
- `fetchMatchPersoner` bærer allerede en dokumenteret skala-advarsel (`redaktionRead.ts:989-992`) om URL-længde ved `.in('target_id', factIds)`. At tilføje `'titel'` til faktatype-filteret øger rækkeantallet marginalt — acceptabelt ved PoC-volumen, men det bekræfter retningen i den eksisterende note: et **server-side view** (fact→conclusion→assertion → ét interval + titel + bog-ref pr. person) er den rigtige skala-fix, udskudt (Fase 4).
- Audit-listen (176 rækker) er triviel; filtrering/søgning sker klient-side.

## Global Constraints

- **Matcher-kernen urørt i sin logik:** `scorePair`/`assignTiers`/`buildMatchFrame` (`packages/core/src/matchUdgaver.ts`) ændres ikke funktionelt — kun typen `RedMatchPerson` (eller en parallel `KandidatOverblik`-type) udvides additivt. Matcheren har kun brug for de fem MatchFrame-felter.
- **Fold-motoren urørt:** `collapseSameAs` og karantæne-reglerne ændres IKKE. `foldHint`/`previewSammeSom`/`foldAdvice` (fra 2026-07-18-planen) genbruges — flyttes/fremhæves kun i UI.
- **Bliv på redaktions-læsestien:** den offentlige `fetchPersonDetail`/`DetailPanel`-sti kører `collapseSameAs` (folder netop de dubletter vi skal *sammenligne*) og er RLS-filtreret (skjuler `staged`/privat). Redaktionen skal have det ufoldede, ufiltrerede datasæt — `SammenlignUdgaver` bygger allerede sit eget `rawDb` (linje 81-90).
- **Ingen DB-migration i v1:** ingen nye RPC'er, views eller skema-ændringer (jf. samme-som-planens Fase A-gate). Alt komponeres af eksisterende, testede klient-fetches. Server-side view revurderes ved skala (Fase 4).
- **Lazy-hentning er ikke-forhandlelig:** narrativ/evidens/familie/relationer hentes KUN ved panel-ekspansion, cached pr. personId.
- **Skrive-vejene genbruges uændret:** Bekræft/Afvis/Fortryd går gennem `submitChange` (dry-run → LIVE) med de eksisterende arter `sammeSom`/`ikkeSammeSom`/`fjernSammeSom` (`redaktionWrite.ts`). Ingen nye write-arter.
- **Commits:** Conventional Commits (dansk), ingen Claude-attribution, slut med `Claude-Session: https://claude.ai/code/session_0173wh8BpUpToPEtWKiKbBX3`.

## Fil-struktur

| Fil | Ansvar |
|---|---|
| `web/src/data/redaktionRead.ts` (mod) | Udvid `fetchMatchPersoner` (bog-ref/linje/titel); ny `fetchKandidatDetalje` (komposit af eksisterende per-person-fetches); udvid `fetchSammeSomPar`/`fetchIkkeSammeSomPar` med `relationId`; ny `fetchMatchAudit` (change_set-join) |
| `packages/core/src/matchUdgaver.ts` (mod) | Udvid `RedMatchPerson` (+ `buildMatchPersoner`) additivt, eller tilføj parallel `KandidatOverblik`-type |
| `web/src/components/SammenlignUdgaver.tsx` (mod) | Berigede kandidat-rækker (Fase 1); ekspanderbare rækker → lazy montering af sammenligningspanel (Fase 2) |
| `web/src/components/KandidatSammenligning.tsx` (ny) | To-kolonne side-by-side-panel: felt-justeret, enighed/uenighed-fremhævning, fold-advarsel øverst, Bekræft/Afvis i panelet. Genbruges af audit-oversigten |
| `web/src/components/MatchOversigt.tsx` (ny) eller udvidet `afklarede`-sektion | Filtrerbar/søgbar audit-liste: hvem/hvornår/score/fold-status, "Fortryd" via `fjernSammeSom` |
| `web/src/data/sammenlign.ts` (evt. mod) | `buildArbejdsliste`-strukturen bevares; evt. små type-udvidelser til berigede rækker |
| `web/src/data/redaktionWrite.ts` (uændret) | `fjernSammeSom`-arten (linje 271) findes allerede og genbruges |

## Fase 1 — Berig den kompakte liste (højest værdi / lavest risiko)

Rent additivt, ingen DB-migration, ingen ny komponent. Løser klage 1 delvist og klage 2's "genkendbarhed" delvist. Kan leveres og verificeres isoleret.

- [ ] **1.1** `web/src/data/redaktionRead.ts`: udvid `fetchMatchPersoner` (`redaktionRead.ts:993-1002`) — tilføj `linje, nr, slaegtled_lokal, slaegtled_gennem, kuld` til det eksisterende `person_external_id`-select; join gren-navn via `fetchLineages` (`redaktionRead.ts:491`); udvid faktatype-filteret fra `['fødsel','død']` til også `'titel'` (jf. skala-noten `redaktionRead.ts:989-992` — marginal rækkeforøgelse, acceptabel ved PoC-volumen).
- [ ] **1.2** `packages/core/src/matchUdgaver.ts`: udvid `RedMatchPerson` (`matchUdgaver.ts:278-286`) + `buildMatchPersoner` (`matchUdgaver.ts:296`) additivt med titel/bog-ref/linje — eller tilføj en tynd parallel `KandidatOverblik`-type så matcher-kernens type holdes ren. Eksisterende matcher-tests skal forblive grønne uændret.
- [ ] **1.3** `web/src/components/SammenlignUdgaver.tsx`: udled forældre-navne af den allerede-hentede `familieGraf` (`fetchFamilyGraph`, `redaktionRead.ts:1024`) + `byId`-navneopslag (ingen ny query); vis i hver kandidat-række: fulde navn + titel, fødsel–død span, forældre-navne ("f. af Christian D. R. & Anna S."), linje/gren + bog-nr ("III-58, Holstenske linje"); behold tier-badge + score.
- [ ] **1.4** Kør tests (`packages/core`: `npm test`; `web`: `npx tsc -b` + `npm test`) — ingen regressioner.

## Fase 2 — Side-by-side sammenligningspanel (kernen i klage 1)

- [ ] **2.1** `web/src/data/redaktionRead.ts`: ny `fetchKandidatDetalje(personId)` der komponerer de eksisterende per-person-fetches: `fetchPersonEvidence` (`redaktionRead.ts:125`), `fetchNarrativer('person', Number(personId))` (`redaktionRead.ts:311`), `fetchPersonFamilie` (`redaktionRead.ts:618`), `fetchPersonRelationer` (`redaktionRead.ts:637`), valgfrit `fetchRedPersonMedia` (`redaktionRead.ts:755`). Ingen ny DB-overflade.
- [ ] **2.2** `web/src/components/KandidatSammenligning.tsx` (ny): to-kolonne-panel (kilde A mod kilde B), felt-justeret pr. række (navn+titel, fødsel/død med kilde-citat, forældre, ægtefæller, børn, linje/gren+bog-nr, embeder/godser, narrativ i scrollboks); visuel enighed/uenighed-fremhævning (grøn=samstemmende, rød/gul=afvigende); fold-advarsel (`foldHint`/`foldAdvice`) fremhævet ØVERST i panelet, før Bekræft-knappen; Bekræft/Afvis-knapperne placeret I panelet med fuld kontekst synlig. Narrativ indledningsvis som uddrag (fx første 400 tegn) med "vis hele".
- [ ] **2.3** `web/src/components/SammenlignUdgaver.tsx`: gør kandidat-rækker ekspanderbare (klik eller "Sammenlign"-knap) → montér `KandidatSammenligning` lazy; `fetchKandidatDetalje` kaldes for de to sider KUN ved åbning og caches pr. personId i komponentens state (samme person optræder som kandidat for flere andre).
- [ ] **2.4** Kør tests + typecheck — ingen regressioner.

## Fase 3 — Audit/browse-oversigt (klage 2)

- [ ] **3.1** `web/src/data/redaktionRead.ts`: udvid `fetchSammeSomPar` (`redaktionRead.ts:1013`) og `fetchIkkeSammeSomPar` til også at returnere `relation.id` (i dag kastes den væk og kun `aId/bId` beholdes) — forudsætning for både "Fortryd" og præcise audit-poster.
- [ ] **3.2** `web/src/data/redaktionRead.ts`: ny `fetchMatchAudit` — join `change_set` (`operation IN ('red_samme_som','red_fjern_samme_som')`) for `actor_navn`/`actor_rolle`/`created_at` (`schema.sql:2087-2099`). Grovkobling: `change_set.subjekt_id` = kanonisk person = `objektId`; ved flere links til samme kanoniske skelnes via `change_event.row_pk` (`schema.sql:2101-2110`) om nødvendigt. Første `change_set`-læsning i `web/src/data` overhovedet — hold den lille.
- [ ] **3.3** `web/src/components/MatchOversigt.tsx` (ny) eller udvid den eksisterende `afklarede`-sektion (`SammenlignUdgaver.tsx:223-264`): liste over trufne beslutninger (både `samme_som` og `ikke_samme_som`), hver post med: begge personer (navn + år + linje/gren + bog-nr), beslutningstype, hvem+hvornår (fra audit-fetchen), score rekomputeret deterministisk via `scorePair` på de to `MatchFrame`s (via `buildMatchFrame` — IKKE opslag i arbejdslistens par, jf. Alternativer punkt 4), fold-status via `foldHint`/`karantaeneByPersonId`.
- [ ] **3.4** Filtre/søgning (klient-side, 176 rækker er trivielt): fritekst på navn, filter på kilde-udgave, på linje/gren, og på fold-status ("vis kun links der ikke folder endnu").
- [ ] **3.5** "Fortryd"-knap pr. `samme_som`-post: `Change { art:'fjernSammeSom', relationId }` (`redaktionWrite.ts:271`; RPC `red_fjern_samme_som`) → dry-run/LIVE via `submitChange`, præcis som Bekræft/Afvis.
- [ ] **3.6** Ekspansion i audit-listen genbruger `KandidatSammenligning` (Fase 2) — én komponent, to indgange.
- [ ] **3.7** Kør tests + typecheck — ingen regressioner.

## Fase 4 — Kan vente (udskudt, ikke i denne omgang)

- [ ] **4.1** Server-side match-view (skala-fix for `fetchMatchPersoner`): fact→conclusion→assertion → ét interval + titel + bog-ref pr. person. Kræver `schema.sql`+`db-migrations.sql`+`db-rls.sql`+`db-verify.sql` + bruger-godkendt prod-apply-gate.
- [ ] **4.2** Audit for `ikke_samme_som`-fortrydelse (write-arten `fjernIkkeSammeSom` findes allerede, `redaktionWrite.ts`).
- [ ] **4.3** Deterministisk score-rekomputering vist i audit-listen for ALLE historiske beslutninger (udvidelse af 3.3).

## Alternativer overvejet og forkastet

1. **Eager-hent alt (inkl. narrativer) for alle kandidater og render fuldt straks.** Forkastet: 1700 personer × fuld prosa sprænger net/hukommelse og er spild — redaktøren åbner kun få kandidater ad gangen. To-trins lazy-flow giver samme information ved behov.

2. **Genbrug den offentlige `fetchPersonDetail`/`DetailPanel` for hver side.** Forkastet: den offentlige sti kører `collapseSameAs` (folder netop de dubletter vi skal *sammenligne*) og er RLS-filtreret (skjuler `staged`/privat). Redaktionen skal have det *ufoldede, ufiltrerede* datasæt — derfor bygger `SammenlignUdgaver` allerede sit eget `rawDb` (linje 81-90). Vi skal blive på redaktions-læsestien.

3. **En dedikeret Postgres-RPC der returnerer en komplet sammenlignings-pakke.** Forkastet for v1: ny DB-overflade betyder `schema.sql`+`db-migrations.sql`+`db-rls.sql`+`db-verify.sql` og et bruger-godkendt prod-apply-gate (jf. samme-som-planens Fase A). At komponere eksisterende, testede klient-fetches er langt lavere risiko. Revurderes som view ved skala (Fase 4).

4. **Gem score-snapshot i DB ved Bekræft (til audit).** Forkastet: unødig skema-ændring. Scoren kan rekomputeres deterministisk fra matcher-kernen (`scorePair` er ren). Vigtig subtilitet at respektere: matcheren er injektiv + top-K (`assignTiers`, `matchUdgaver.ts:175`), så et *allerede bekræftet* par kan være faldet ud af `matchUdgaver`-outputtet. Audit-visningen skal derfor kalde `scorePair` direkte på de to `MatchFrame`s (via `buildMatchFrame`), ikke lede i arbejdslistens par.

5. **Læg sammenligningen ind i person-editoren (`Redaktion.tsx`s relations-sektion).** Forkastet: den per-person enkelt-link-flow eksisterer allerede (2026-07-02-planen, Task 7). Brugerens behov er *batch* tværudgave-triage — en anden arbejdsgang, som `SammenlignUdgaver` er det rette hjem for. De to kan dele `KandidatSammenligning`-komponenten.

## Kritiske filer for implementering

- `web/src/components/SammenlignUdgaver.tsx`
- `web/src/data/redaktionRead.ts`
- `packages/core/src/matchUdgaver.ts`
- `web/src/data/sammenlign.ts`
- `web/src/data/redaktionWrite.ts`

## Verifikation

1. **Efter hver fase:** `packages/core`: `npm test` (matcher-kernens eksisterende tests skal forblive grønne — type-udvidelsen er additiv); `web`: `npx tsc -b` ren + `npm test` (husk lokal, ikke-committet `.env.local` — påkrævet af `supabase.ts` for at modulerne kan loade i test), ingen regressioner.
2. **Manuel redaktør-gennemgang mod kendte kandidat-par (kræver Supabase-adgang):**
   (a) Fase 1: find to samtidige navnefættre (fx to "Detlev"'er fra 1939 vs. 2018-20) i arbejdslisten → forvent at forældre-navne + linje/bog-nr + titel nu er synlige i rækkerne og faktisk skelner dem uden at åbne noget;
   (b) Fase 2: ekspandér en kandidat → forvent to-kolonne-panel med begge narrativer, familierelationer og embeder/godser; afvigende felter fremhævet; fold-advarsel synlig FØR Bekræft-knappen; Bekræft/Afvis virker fra panelet (dry-run → LIVE) identisk med i dag; verificér at narrativ IKKE hentes for uåbnede rækker (netværksfanen);
   (c) Fase 3: audit-oversigten viser de eksisterende ~176 bekræftede matches med navn/år/linje/bog-nr, hvem+hvornår fra `change_set`, og fold-status; søg/filtrér ("vis kun links der ikke folder endnu"); fortryd ét testlink → forvent at parret vender tilbage til de åbne kandidater efter `refresh`, og fold-preview opdateres.
3. **Ydelses-tjek:** arbejdslisten med ~1700 personer skal loade uden mærkbar forværring ift. i dag (kun små eager-felter tilføjet); panelekspansion må gerne tage et øjeblik første gang (lazy fetch) men skal være øjeblikkelig ved genåbning (cache pr. personId).
