# 1939 v50 — resten af genimporten: prioriteret programplan

> **For agentic workers:** Dette er programplanen for de resterende faser.
> Hver fase A-D er sit eget delsystem og SKAL have sit eget detaljerede
> taskplan-dokument (superpowers:writing-plans) før implementering, som
> alle tidligere faser i dette program har haft. Fase-planerne eksekveres
> med superpowers:subagent-driven-development eller executing-plans.

**Mål:** Få hele det menneskeverificerede grænse-/Calamari-arbejde ind i
produktionsdatabasen: fuldt kilderegnskab, erstatning af de fejlbehæftede
narrativer (med OCR-afbrydnings-normalisering), promovering af verificerede
strukturerede fakta og oprydning af staged-backloggen.

**Arkitektur:** Genbruger det deployede v50-maskineri (privat evidenslag,
`red_apply_1939_v50_source_evidence`, `red_upsert_narrativ`,
`red_publicer_narrative_record`, autorisations-/batch-kontrakten) med nye
hash-låste manifester pr. fase. Ingen nye tabeller; nye behov = nye
manifest-/faktatyper (invariant 2).

**Tech stack:** Python (manifest-byggere + tests i
`.claude/skills/daa-extract/scripts/`), R/DBI (writers + rehearsals),
PostgreSQL 17 lokalt til rehearsal, Supabase prod via psql/MCP.

**Spec:** `docs/superpowers/specs/2026-08-02-evidensbaseret-genimport-og-multislaegt-design.md`
+ kilderegnskabet i `docs/superpowers/reviews/1939-v50-import-preview.md`
(592 source records; 543 mappede, 41 ægte nye, 3 pensionerede, 6 strukturelle,
2 krydsreferencer; narrativer: 478 ændrede / 65 uændrede / 3 pensionerede).

## Globale begrænsninger (gælder alle faser)

- **Prod-gate pr. fase:** ny umiddelbar backup (0600 + SHA-256) → rehearsal
  mod frisk produktionsækvivalent restore m. byte-identiske
  før/efter-baselines → eksplicit brugergodkendelse m. eksakte hashes →
  én apply, ingen retry. `get_advisors(security)` efter enhver DDL.
- **Verbatim er uforanderligt:** rendition (`daa-1939-calamari-r6-clean`,
  SHA `020123a3…`), spans og `citat_tekst` er byte-eksakte og må ALDRIG
  normaliseres. Kun `narrative.tekst` (formidlingslaget) må transformeres.
- **Påstande overskrives aldrig** (invariant 1): rettelser = nye
  assertions + nye konklusioner; narrativ-erstatning sker via det
  versionerede `red_upsert_narrativ`-spor, så gammel tekst bevares.
- **`load_daa.R` røres ikke og kaldes ikke.**
- **Supabase MCP `execute_sql` er read-only** — skrivninger via
  `apply_migration` (DDL) eller hash-låste psql-scripts (data).
- Manifester bygges deterministisk (ingen tidsstempler/tilfældighed i
  indholdet; `PYTHONHASHSEED`-uafhængighed bevises som i task 25).
- work/-artefakter indeholder PII-frit 1939-materiale men committes aldrig.

---

## Prioriteret rækkefølge og begrundelse

| Fase | Leverance | Hvorfor denne plads |
|---|---|---|
| **A** | Kilderegnskab 592/592 i prod (source-only) | Fundament: narrativ-bindinger og fakta-citationer skal pege på source records, der findes i prod. Nul kanonisk risiko. |
| **B** | 577 narrativer erstattet m. Calamari-tekst **inkl. ombrydnings-normalisering** + publiceret provenance | Programmets oprindelige formål (de fejlbehæftede tekster). Dewrap foldes ind HER: én skrivning + én review i stedet for to. |
| **C** | **C0 først:** 41 fejlklassificerede records kobles (løser de 23 gamle tekster); derefter strukturerede fakta promoveret/kø-lagt + ægtefællerne | C0 er billig og synlig for læsere; resten kræver A's records til citations og er redaktionelt tungest, kan tages i skiver. |
| **D** | 96 staged afgjort (publicér/pensionér/samme_som) | Uafhængig af B-C, men genbruger A's identitetsbillede; lavest hast. |
| **E** | Konsolidering: push, draft-PR, docs, oprydning | Løbende efter hver fase; afsluttes til sidst. |

**Beslutning om ombrydning (brugerens spørgsmål):** normaliseringen lægges i
fase B, ikke som efterfølgende pas. Begrundelse: de 478 ændrede narrativer
skal alligevel skrives om — at dewrappe bagefter ville betyde 577 narrativer
skrevet og reviewet to gange. De 8 allerede publicerede narrativer (person
1846-1853, i dag rå OCR-ombrudte) medtages i fase B's batch, så alle 577 får
samme tekstnorm i én operation.

---

## Fase A: Kilderegnskab for de eksisterende poster

**Leverance:** Prod indeholder alle 592 source records med byte-ankre i
Calamari-renditionen (i dag: 243). Nul kanonisk delta.

**Indhold — detaljeret i
`2026-08-18-1939-v50-fase-a-kilderegnskab.md`:**
1. Ny deterministisk manifest-bygger for de **584** endnu ikke skrevne
   records (592 minus de 8 person-creates): span + verbatim (byte-verificeret
   mod Calamari) + sideudledning fra `###`-markørerne + `canonical_target`
   -person-id via database-preview'ets `person_anchors.matched`.
   **Ingen DDL og ingen personaer/identiteter** — persona-laget for
   eksisterende personer er flyttet til fase C, hvor
   `red_decide_source_persona_identity`-maskineriet bor.
2. Ny batch gennem den eksisterende authorize→begin→source_evidence→finalize-
   kontrakt uændret. `person_creates=0`, `canonical_delta=0`.
3. Rehearsal (frisk prod-restore EFTER cutover, byte-identiske baselines,
   dry-run + committed + replay) → GO-pakke → [godkendelse] → backup +
   apply → read-only efterkontrol (592 records i alt — 349 nye + 235
   eksisterende claim-nøgler beriget med helpost-occurrence — 897 ankre,
   personaer fortsat 8, kanoniske tællinger uændrede).

**Gate:** brugergodkendelse med manifest-SHA + backup-SHA før apply.

## Fase B: Narrativ-erstatning + ombrydnings-normalisering

**Leverance:** Alle 577 1939-narrativer har evidensbaseret tekst fra
Calamari-spans, ombrydningsfri, med publiceret record-provenance; gamle
tekster bevaret i versionshistorikken.

### Dewrap-transformens kontrakt (fastlægges nu, testes i fase-planen)

Ren, deterministisk funktion `dewrap_narrative_v1(raw: str, corpus: str) -> (str, list[Flag])`:

1. **Afsnit bevares:** `\n\n+` → `\n\n` (tomme linjer = ægte afsnitsskel).
2. **Blød ombrydning:** enkelt `\n` (uden foranstående bindestreg) → ét
   mellemrum; dobbelte mellemrum kollapses aldrig ud over det indførte.
3. **Bindestreg ved linjeskift** (`X-\nY`):
   - `Y` starter med **lille** bogstav → orddeling: sammentræk til `XY`
     («sammen-\ntrækkes» → «sammentrækkes»).
   - `Y` starter med **stort** bogstav → kompositum-kandidat (navne som
     «Reventlow-\nCriminil»): behold bindestregen, fjern kun linjeskiftet
     → `X-Y`.
   - **Korpus-tiebreak:** findes `XY` ubrudt andetsteds i Calamari-korpuset
     men `X-Y` gør ikke, vælges `XY` (og omvendt) uanset versaler.
   - **Uafklaret versal** (begge/ingen former i korpus + stort
     begyndelsesbogstav er eneste signal): behold `X-Y` **og** flag
     (`hyphen_ambiguous`) — fail-closed, aldrig et stille gæt.
   - **Ubevist småbogstavs-sammentrækning** (reviewfund: 168/584 merges
     havde hverken `XY` eller `X-Y` i korpus — heraf mindst én reel
     OCR-korruption, «kar-og» → «karog» hvor bogen har «kar. og»):
     sammentrækningen udføres fortsat som default, men flages
     (`hyphen_unproven`) så reviewarket viser alle 168 med kontekst til
     menneskeligt veto pr. tilfælde. Degenererede tilfælde (ikke
     bogstav-løb på begge sider — talintervaller, forkortelses-punktummer,
     †-nabo): behold bindestregen, fjern KUN linjeskiftet (aldrig et råt
     `\n` i slutteksten), flag `hyphen_ambiguous`.
4. **Ordenstals-strip (brugerkrav 2026-08-18):** efter indledende
   whitespace-trim fjernes et ledende søskende-ordenstal på formen
   `^\d{1,2}\.\s+` («1. Sybille Malvina Lonny…» → «Sybille Malvina
   Lonny…»). Nummereringen er allerede bevaret strukturelt (record-nøgler,
   identitetsregister, verbatim), så det er rent formidlingslag. Empirisk
   målt på 551-scopet: 499 entydige strips, 50 uden ordenstal (probander,
   røres ikke), 2 tvetydige OCR-varianter («7 Heinrich…» uden punktum;
   «2) Greve Conrad…» med parentes) → flages til menneskeligt reviewark,
   strippes ALDRIG ved gæt.
5. **Sidemarkører (fundet ved implementering):** 73 af de 551 spans
   krydser en sidegrænse og indeholder rendition-markørblokken
   `\n*### PAGE \d{4} ###\n*`. Blokken fjernes og erstattes af ÉT blødt
   linjeskift, FØR afsnits- og bindestregreglerne kører — så en orddeling
   hen over sidevendingen genindtræder i normal bindestreg-logik, og
   prosa der fortsætter over siden bliver til ét mellemrum (bogens
   sætning fortsætter; de blanke linjer omkring markøren er
   rendition-struktur, ikke afsnit). Slutteksten må ikke indeholde
   `### PAGE`. Empirisk assert: præcis 73 markør-fjernelser på 551-scopet.
6. Ingen andre ændringer: tegnsætning, stavning, «ø/æ/å», OCR-fejl m.v.
   røres ikke (det er evidens, ikke redaktion).
7. **Slutinvariianter:** slutteksten indeholder aldrig `### PAGE`, aldrig
   et enligt `\n` (kun `\n\n`-afsnitsskel — webben renderer `\n` som
   linjeskift), og trailing whitespace trimmes (`rstrip`; 293 rå spans
   sluttede på whitespace uden visningsværdi). Diff-klassekontrollen får
   `trailing_trim` som tilladt klasse.
8. Funktionen er versioneret (`narrative_norm_v1` = dewrap +
   ordenstals-strip + markør-fjernelse + slutinvariianter); manifestet
   registrerer pr. narrativ både rå span-SHA
   og normaliseret SHA, så transformationen kan genberegnes og efterprøves
   byte-eksakt.

Testkrav i fase-planen: eksempeldrevne enhedstests for hvert af punkterne
1-4 (inkl. «Reventlow-\nCriminil», orddeling over sidegrænse, flag-vejen)
plus en korpus-regression: transformér alle 577 spans, assert 0 utilsigtede
tegnændringer ud over linjeskift/bindestreg-reglerne (diff-klassekontrol).

### Skrivevejen

1. Manifest: 577 operationer (478 ændrede + 65 «uændrede» der nu dewrappes +
   8 nye personers + de resterende afgjort i kilderegnskabet), hver med
   narrative_id/person, source_record, span, rå og dewrapped tekst-SHA.
2. **Menneskelig gate før skrivning:** diff-rapport (gammel kanonisk tekst ↔
   ny dewrapped tekst) + bindestregs-reviewarket fra transformen. Stikprøve
   godkendes af brugeren; uafklarede bindestreger afgøres eller udskydes
   eksplicit (udskudt = behold `X-Y`).
3. Writer: pr. narrativ `red_upsert_narrativ` (source-nøglet, versioneret) +
   binding-oprettelse/publicering via `red_publicer_narrative_record`
   (draft→published-vejen er allerede hærdet). De 8 eksisterende bindinger
   beholdes — kun narrativ-teksten opdateres for dem.
4. Rehearsal → backup → GO-pakke → én apply → efterkontrol: 577 publicerede
   bindinger, alle narrativ-SHA'er = manifestets dewrapped SHA'er,
   versionshistorik indeholder de gamle tekster, nul delta på
   person/fact/relation-tællinger.

## Fase C: Promovering af strukturerede fakta

**Leverance:** Literal-verificerede påstande er kildebundne kanoniske data;
resten ligger i en redaktionel kø med kildespan.

1. **C0 (de 41 »ægte nye« records — fejlklassifikation; TAGES FØRST):**
   Fase B efterlod 23 narrativer med gammel tekst. Undersøgelse 2026-08-19
   viste at årsagen ikke er manglende tekst, men en manglende KOBLING:
   fx person 1299 (Ferdinand Einar Julius Gottlieb) har i prod netop den
   tekst, som kilderecord `record-82f49e95…` (side 574-575) dækker — men
   recorden blev i identitetsgennemgangen klassificeret
   `accepted_genuinely_new_source_record` / `person_creation: forbidden`
   uden baseline-tilknytning, så personen kom aldrig i fase B's scope.
   Leverance: gennemgå alle 41 »ægte nye« records mod eksisterende
   personer (tekstlighed mod prods narrativer er et stærkt signal —
   eksakt eller næsten-eksakt match afslører fejlklassifikationen);
   hver record ender enten (a) mappet til en eksisterende person →
   optages i en fase B-efterkørsel (samme writer, nyt lille manifest),
   (b) bekræftet ægte ny → personoprettelse som i task 25, eller
   (c) dokumenteret som alias/dublet → afgøres i C3.
   De 6 strukturelle og 2 krydsreference-records er IKKE i denne
   gennemgang (de skal med rette ikke kobles til personer).
   Bemærk: OCR-fejl i teksten (fx «Gottlie b» med indsat mellemrum) er
   redaktionelt arbejde, ikke normalisering — de rettes i redaktørfladen,
   ikke af denne fase.
2. **C1 (mekanisk):** 1.078 literal facts + 212 literal marriages →
   kildebundne assertions/citations der bekræfter de eksisterende
   konklusioner (ingen konklusionsændring — kun evidens-tilknytning).
   Manifest + writer efter fase A-mønstret.
3. **C2 (redaktionel):** 92+56 ikke-literal, 38+38 uden span, 81 børne-/
   strukturrelationer og de 305 allerede parkerede → reviewark pr. klasse
   med span-kontekst; afgørelser materialiseres som nye manifester i
   skiver. Ingen deadline — køen er selve leverancen.
4. **C3 (ægtefællerne — de 644 narrativ-løse personer):** Prod-måling
   2026-08-18: alle 644 er `partner`-rolle (gift-ind, skabt af loaderen fra
   »g.m. …«-klausuler; ingen er forældre/børn), 331 fra 2018-20 og 313 fra
   1939, 465 allerede `samme_som`-matchet på tværs af udgaverne, 179
   umatchede (103/76 pr. kilde), heraf 115 i unioner hvor probanden ER
   matchet — de er primære dublet-kandidater. Leverancer:
   - Ægteskabs-records (fase C1) giver ægtefællerne source personas +
     identitetsafgørelser mod de eksisterende partner-rækker, så de 644
     bliver evidensbårne i stedet for loader-artefakter.
   - Match-review af de 115 kandidater (genbrug værktøjet fra
     tværudgave-matchningen, PR #90-#96): hver af de 179 ender enten
     `samme_som`-linket eller dokumenteret som ægte én-udgave-ægtefælle.
   - Ægtefællers forældre (»datter af N.N.«) findes i dag kun i prosaen;
     de materialiseres KUN via C2's relations-kø, hvis en klausul bærer
     dem — ingen ny personoprettelse uden positiv source-validering.

## Fase D: Staged-backlog (96 personer)

**Leverance:** 0 uafklarede staged-personer fra de gamle loads.

De 96 deler sig præcist i 51 med 1939-narrativ (probander) og 45
narrativ-løse ægtefæller — de 45 er delmængde af fase C3's 644 og afgøres
med samme identitetsgrundlag.

1. Klassificér de 96 (51 m. 1939-narrativ) mod kilderegnskabet: dublet →
   `samme_som` + pensionering (jf. 2026-08-16-planen om duplicate
   retirement), reel → publicér via `red_publicer_udgave`-sporet, hverken →
   dokumenteret pensionering.
2. Samme gate-mønster; cutover af nye offentlige personer kræver egen
   godkendelse som i dag.

## Fase E: Konsolidering (løbende + afslutning)

- Push af `feat/evidensbaseret-genimport` + draft-PR (git-gate: kræver ja).
- `docs/changelog.md` + `docs/database-current-state.md` afstemmes efter
  hver prod-fase (som 2026-08-18-posten).
- Oprydning: lokale rehearsal-databaser droppes (kræver ja), forældede
  work/-mellemprodukter arkiveres.

---

## Definition of done (programmet)

1. 592/592 source records m. ankre i prod; 577 narrativer ombrydningsfri,
   evidensbaserede og provenance-publicerede; gamle tekster i historik.
2. Alle literal-påstande kildebundne; alle øvrige i dokumenteret kø.
3. 0 uafklarede staged; backlog-memoerne opdateret.
4. Hver prod-skrivning har backup + rehearsal-rapport + GO-pakke i work/.
