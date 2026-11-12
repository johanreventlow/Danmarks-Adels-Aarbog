# Review 36 — Helhedsreview af kodebasen (best practice, gentagelser, effektivitet, performance)

**Dato:** 2026-11-12 · **Commit:** `2ac193a9` (main) · **Worktree:** `daa-kodereview`, gren `chore/kodereview-helhed`
**Scope:** Hele kodebasen som samlet værk: `web/`, `mobile/`, `packages/*`, DB-laget (`schema.sql`, `db-rls.sql`,
`db-migrations.sql`, `tests/sql`), Python/R-pipelinen (`.claude/skills/*/scripts`, `R/`, `tools/`), tests og CI.
**Ikke dækket:** UX (review 26), roadmap-prioritering, indholdet af `data/` og PII-mapper.
**Status:** Kun review — **ingen rettelser er lavet**. Alt nedenfor er beslutningsgrundlag, ikke en plan.

## Metode

- Mekanisk forscanning (størrelser, dublerede funktionsnavne, web↔mobil-diff, SQL-dubletter) → hotspot-liste.
- 5 parallelle read-only reviewere (Fable 5.2): web · mobil+deling · `packages/core`/feed + dataindlæsning · DB · pipeline/tests/CI.
- Et uafhængigt Codex-review samme dag (projektejerens; `/private/tmp/daa-helhedsreview-2026-11-12.md`), flettet ind.
- Hovedsessionen har selv åbnet `fil:linje` for de vigtigste fund.

**Bevismærker:** **R** = reproduceret ved at køre den faktiske kode (Codex) · **V** = verificeret i koden af hovedsessionen ·
**S** = statisk fund fra én reviewer, ikke eftertjekket · **K** = kompleksitetsargument, ikke målt.
**Kilde:** F = Fable-reviewer · C = Codex · **F+C** = fundet uafhængigt af begge (stærkeste signal).
**Kendthed:** NY · KENDT (åben) · DELVIST (delvist løst tidligere).

Ingen af tallene er målt mod prod i dette review. Prod er lille (~1.811 personer, ~7.200 fakta), så de fleste
performance-fund er **skaleringsfund**: de koster lidt i dag og bliver afgørende ved foreningens samlede data (skøn 10–50×).

---

## 0. Samlet vurdering — i hverdagssprog

**Fundamentet er godt; samlingen er det svage led.** De rene kernefunktioner (`packages/core`, `packages/feed`), den
fejl-lukkede GDPR-synlighed i databasen, hash-bindingen af menneskets godkendelser og de mange målrettede tests er solide
og skal bevares. Problemerne ligger der, hvor delene er sat sammen over et halvt år:

1. **Et lille antal reelle korrekthedsfejl** — steder hvor koden kan vise forkerte data, miste en rettelse eller melde
   "grønt" for noget der fejlede. De er få, afgrænsede og billige at lukke. De bør gå før al oprydning.
2. **Samme ting er skrevet mange gange.** ~21 datamoduler findes i både web og mobil og er gledet fra hinanden (med
   konkrete fejl til følge); 121 rollegates er skrevet ind i hver SQL-funktion; hver Python-/R-fil har sin egen kopi
   af hjælpere til hashing, privat filskrivning og DB-forbindelse — med forskellige sikkerhedsregler.
3. **Migrationsmodellen vokser for evigt.** `db-migrations.sql` er gået fra 6.000 til 35.000 linjer på tre måneder;
   mindst 199 funktionskroppe er forældede kopier, og CI's paritetstjek dækker 62 af ~400 funktioner. Der er allerede
   én funktion, hvor en frisk base og en migreret base opfører sig forskelligt.
4. **Læsestien er bygget til 1.800 personer.** Hele grafen hentes til klienten i sider uden fast rækkefølge; den
   offentlige læsning genberegner et integritetsbevis (SHA-256) pr. række; RLS kalder en funktion pr. række. Det holder
   i dag (med enkelte allerede målte timeouts), men ikke ved 10–50×.

**Anbefaling:** Luk korrekthedsfejlene først (bølge 1, mest S-indsats). Lav derefter de billige værn, der forhindrer at
ting glider (bølge 2). Den store strukturelle konsolidering (bølge 3) og skaleringsarbejdet (bølge 4) kræver
beslutninger fra projektejeren og bør kobles til roadmappet — ikke en samlet omskrivning.

---

## 1. Top-12 — gør først

Rangeret efter (risiko for forkerte data eller tabt arbejde) ÷ indsats.

| # | Fund | Konsekvens | Bevis | Kilde | Indsats |
|---|---|---|---|---|---|
| 1 | Hændelses-loaderen skriver til prod **som standard** (K1) | Én kommando uden flag ændrer prod og låser `haendelse` | V | F | S |
| 2 | Evidens-runneren melder **grønt** for ugyldigt modelsvar (K2) | En fejlet udtrækning ligner en post uden fakta, og caches | R+V | C | S |
| 3 | Redaktionen kan vise **person A's data under person B** (K3) | Redaktøren kan rette den forkerte persons påstand | V | F+C | S |
| 4 | Databasefejl vises som **"ingen data"** i redaktion og læserflade (K4) | Redaktør kan oprette dublet; læser mister link | V | F+C | S–M |
| 5 | Fortrydelse kan **overskrive en samtidig nyere rettelse** (K5) | Tabt redaktørarbejde trods `p_force=false` | V | C | M |
| 6 | To portrætter kan begge blive primære; begrundelse forældet (K6) | Forkert portræt; review 34's afvisning hviler på kode, der er ændret | V | C | S |
| 7 | Sidehentning uden fast rækkefølge og med tavst loft (K7) | Person/slægtskabskant kan mangle eller stå dobbelt | V | F (×3) | S |
| 8 | Kronologisk vagt læser rå datotekst og dropper slægtskabskanter (K8) | "Er vi i familie?" kan svare nej til en forbindelse i basen | V | F | S→M |
| 9 | Matcheren kan smide den bedste kandidat væk før rangering (K9) | Rigtig 1939↔2018-match vises ikke | R+V | C | S |
| 10 | Privat-fil-skrivning overskriver udfyldte ark stille (K10) | Menneskets svar i et ark kan tabes ved genkørsel af `render` | V | F+C | S–M |
| 11 | 69 af 133 Python-testfiler og 13 af 131 SQL-tests kører ikke i CI (D3) | `validate.py` m.fl. kan gå i stykker uden rød PR | V | F | S |
| 12 | `schema.sql` og migrationen er gledet fra hinanden for `narrative_record_state` (D1) | Frisk base og prod låser forskellige rækker | V | F+C | S |

---

## 2. Korrekthed og redaktionel sikkerhed (K)

### K1 · `load_haendelser.R` skriver til prod som standard — NY · V · F
- **Hvor:** `.claude/skills/daa-haendelser/scripts/load_haendelser.R:9` (`DRY_RUN <- "--dry-run" %in% argv`), `:49`
  (`LOCK TABLE haendelse IN SHARE ROW EXCLUSIVE MODE`), `:122-143` (én `dbExecute` pr. række).
- **Konsekvens:** Alle andre prod-skrivere kræver `--jeg-mener-det` eller har dry-run som standard. Denne gør det
  modsatte. Hver genkørsel sender også ét kald pr. hændelse — inkl. uændrede — under tabellås.
- **Forslag:** Kræv `--jeg-mener-det` som de øvrige; lad `plan_merge` springe uændrede rækker over; skriv via midlertidig
  tabel + tre mængde-statements. Markering-bevarelsen (`feed_status`) skal bestå.

### K2 · Evidens-runneren gør ugyldige modelsvar til grønne resultater — NY · R+V · C
- **Hvor:** `.claude/skills/daa-extract/scripts/evidence_runner.py:154-155` (ikke-sekvens → tom iteration),
  `:663-671` (`afviste and not gyldige` er falsk når begge er tomme → `cache.put` + `"green"`).
- **Konsekvens:** `claims: null`, en streng eller et objekt giver `([], [])` → posten caches og meldes grøn uden fakta.
  Den strenge validator ville have afvist (`RUNNER_CLAIMS_INVALID`), men omgås.
- **Forslag:** Tjek container-typen før opdeling; bevar den bevidst gyldige tomme liste. Negative tests for både
  nyt modelsvar og cachegenbrug.

### K3 · Redaktionen: dobbelt-hentning og kapløb ved personskift — NY · V · F+C
- **Hvor:** `web/src/Redaktion.tsx:548-565` (`loadPerson` = `useCallback([model])`), `:607-609`; mobil
  `mobile/src/app/redaktion/person/[id].tsx:109-135,161`.
- **Konsekvens:** (a) Når modellen lander efter personlisten, hentes hele personpakken igen (~13 kald), og igangværende
  redigering (`editingAssert`, `addingFact`, `storyEditor`) nulstilles. (b) Ingen af de syv `fetchX(id).then(setX)` har
  vagt mod forældede svar: vælg A, så B, lad A svare sidst → A's evidens står under B, og handlinger på de viste
  assertion-id'er rammer A. De nyere effekter i samme fil har vagten (`aktiv` `:491-506`, `alive` `:2558`).
- **Forslag:** Gør `loadPerson` uafhængig af `model`; én "seneste person-id/generation"-vagt; test A→B med omvendt
  svarrækkefølge.

### K4 · Fejl præsenteres som tomme data — DELVIST · V · F+C
- **Hvor:** 14 steder med `const { data } = await supabase…` uden `error`-tjek, bl.a. `web/src/data/redaktionRead.ts:134-151`,
  `:182`, `:236-248`, `:284`, `:941`; `web/src/data/media.ts:302-311`; `web/src/data/public.ts:190-198`; mobil
  `mobile/src/data/redaktionRead.ts:166-190`. Plus `safe()` i `web/src/data/public.ts:20-28`.
- **Konsekvens:** Fejler et opslag (RLS, timeout, pauset base), ser redaktøren en person uden påstande og kan oprette en
  dublet. På læsersiden returnerer `safe()` `[]` ved fejl → `if (!estates)` henter aldrig igen, og
  `web/src/Folgesvend.tsx:146-151` omdirigerer `/estate/<id>` til `/estates`. `.catch`-grenene på `:143,:155,:156` er uopnåelige.
- **Forslag:** Flyt `orThrow` (fra review 27 R1) til `@daa/core` og brug den overalt i redaktionens læselag; lad `safe`
  skelne fejl fra tomt. Tolerant fravalg af ekstra feed-indhold kan forblive en dokumenteret undtagelse.

### K5 · Generisk fortrydelse: tjek-så-skriv uden rækkelås — NY · V · C
- **Hvor:** `schema.sql:9411-9425` (sammenligner `_version_current_row` med forventet tilstand, skriver bagefter);
  `_version_current_row` læser uden `FOR UPDATE` (`:9252-9258`); `_version_upsert_row` opdaterer på PK uden betingelse.
- **Konsekvens:** T1 kontrollerer B; T2 gemmer C; T1 genskaber A → C er tabt, selv uden `force`. Låsen på `change_set`
  blokerer ikke almindelige redigeringer.
- **Forslag:** Lås berørte rækker (`FOR UPDATE`, fast rækkefølge) før verifikation, eller atomisk sammenlign-og-opdatér.
  Test med to sessioner (projektet har mønstret fra writer-låsetesten).

### K6 · Portrætvalg: to primære mulige; kommentarens bevis holder ikke længere — NY · V · C
- **Hvor:** `schema.sql:8944-8947` (kommentar: "verificeret umuligt" pga. `begin_change_set`'s `max(id)+1`),
  `:8958-8965` (ryd-så-sæt). `begin_change_set` bruger nu IDENTITY (`:9184-9187`) — kollisionen, der serialiserede, findes ikke.
- **Konsekvens:** To samtidige valg, når ingen er primær, kan begge sætte `primaer`. Review 34 M1 blev afvist på et
  grundlag, der senere er ændret (jf. erfaringen "latent er ikke harmløst").
- **Forslag:** Partielt unikt indeks (højst ét `primaer` pr. person) + lås pr. person; ret kommentaren; medtag fortrydelsesvejen.

### K7 · `getAll`: offset-sider uden `ORDER BY` og tavst loft — KENDT (F-07) · V · F (web, mobil, core)
- **Hvor:** `packages/core/src/getAll.ts:13-21` (`for (i < 400)`, ingen fejl ved loft); kald uden `.order` i
  `web/src/data/model.ts:63-64`, `web/src/data/presens.ts:38`, `web/src/data/redaktionRead.ts:40`, `mobile/src/data/load.ts:209-213` m.fl. (49 kald i web).
- **Konsekvens:** `person` (2 sider) og `family_member` (3 sider) er allerede over én side. Postgres lover ingen fast
  rækkefølge mellem to `LIMIT/OFFSET`-kald → en række kan mangle eller stå dobbelt ved samtidig skrivning. Filens egen
  kommentar (`model.ts:170-172`) siger, at `.order('id')` er nødvendig. F-07's straksværn er stadig ikke indført.
- **Forslag:** Lad `getAll` kaste ved loftet; `.order` på entydig nøgle for de store tabeller; deduplikér på nøgle.

### K8 · Kronologisk vagt dropper slægtskabskanter på rå datotekst — NY · V · F
- **Hvor:** `packages/core/src/buildModel.ts:23-30` (dropper kant hvis barn født > forælders død + 1);
  `packages/core/src/fields.ts:4-8` (`parseYear` = første 3-4-cifrede tal, ignorerer kvalifikator); `visning_foedt/doed`
  er `coalesce(date_raw, vaerdi_tekst)`.
- **Konsekvens:** Forælder "† efter 1650", barn født 1660 → kanten forsvinder lydløst. "Er vi i familie?" kan svare
  "ingen forbindelse" for noget, der står i basen. Strider mod invariant 5 (fuzzy datoer) og 7 (vis usikkerhed). Samme
  tal bruges i `collapseSameAs`' validering. Antal ramte kanter i prod er ikke målt.
- **Forslag:** (1, S) Tæl/log droppede kanter og spring vagten over ved kvalifikator. (2, M) Lever `date_min/date_max`
  til modellen og drop kun ved beviselig modstrid.

### K9 · Matcherens top-K bruger en anden score end slutrangeringen — NY · R+V · C
- **Hvor:** `packages/core/src/matchUdgaver.ts:189-195` (beskærer med `scorePair`), `:211-216` (`assignTiers` bruger
  `scorePairEvidens` når `evidensNormaliseret`); aktiveret i `web/src/components/SammenlignUdgaver.tsx:227`.
- **Konsekvens:** Reproduceret: kandidaten der ville få score 1,0/auto forsvinder ved `topK=10`.
  `packages/identity-candidates/src/rank.ts:16-19` omgår allerede problemet lokalt.
- **Forslag:** Brug den endelige score før beskæring.

### K10 · Privat filskrivning: mindst fem varianter, nogle overskriver stille — NY · V · F+C
- **Hvor:** `S/spouse_exception_sheet.py:126-130` (`O_TRUNC` uden `O_EXCL`, chmod bagefter; importeres af seks ark-scripts);
  `S/transfer_ddl.py:36-39` (`_write_new` med `O_TRUNC`); skriv-så-chmod i `S/identity_decision_sheet.py:158,175`,
  `S/identity_control_sheet.py:221,237`, `S/interpretation_decision_sheet.py:194-208,230`, m.fl.;
  `S/evidence_runner.py:523-525` (cache skrives direkte til endeligt navn → trunkeret fil ved afbrydelse stopper
  genkørsel, `:508-512`). Bedste variant: `S/build_narrative_revision_manifest.py:103-117`. (`S/` = `.claude/skills/daa-extract/scripts/`.)
- **Konsekvens:** `render` til samme sti som et udfyldt ark overskriver menneskets svar uden advarsel (ægteskab, barn,
  forælder, ordinal, placement, lineage); kø-arket nægter. Kortvarigt umask-læsbare private filer.
- **Forslag:** Ét `private_io.py` med `write_private_new` (nægter eksisterende), `write_private_replace` (atomisk,
  `O_NOFOLLOW`, `os.replace`) og `check_private_path` (i dag kopieret tre steder). Hvert kaldested vælger bevidst.

### Mindre korrekthedsfund
- **K11 · Mobil: logout-kapløb genopretter redaktionsmodel** — `mobile/src/store/useStore.ts:375-386` (R, C). Mobil er dev-only.
- **K12 · Web↔mobil-drift med adfærdsforskel** (V, F):
  - `p_source_id ?? 1` (`mobile/src/data/redaktionWrite.ts:248`) mod `?? null` (`web/src/data/redaktionWrite.ts:363`). Samme handling rammer forskellige narrativ-rækker.
  - Mobil mangler web-rettelsen `svageKandidater` (`mobile/src/data/sammenlign.ts:25`).
  - Mobilens "Sammenlign udgaver" mangler linjeudelukkelsen (`udenforMatchning`) og bruger 5× `getAll` i stedet for RPC'en `red_match_personer`.
- **K13 · Bogstavelig NUL-byte i kildekode** — `mobile/src/lib/feedMedia.ts:76` (V). Git og grep ser filen som binær, så
  ændringer er usynlige i PR-diffs. Én linjes rettelse.
- **K14 · Genindlæsning efter skrivning via 700 ms-timer** — `web/src/Redaktion.tsx:2508` (V). Langsommere skrivning
  (prod er målt 2,5–4,5× lokalt) viser gammel tilstand. Brug `await`.
- **K15 · Rå `Number()` på id'er** (S, F): 5 kopier af id-parseren og flere steder med `Number()` → `NaN` → `null` sendes til RPC.
- **K16 · Slægtskabsmotoren** (S, F): `parentsByChild` kender kun barnets første familie, mens træet viser alle
  (`buildModel.ts:61-71`); "alle linjer" udelukker en fjernere fælles ane med uafhængig vej (`relationship.ts:80-85`);
  dansk sortering placerer mellemrum efter Å (`collation.ts:15`), så "Annalise" kommer før "Anna Sophie".

---

## 3. Performance og skalering (P)

Rangeret efter, hvornår det bider. "Nu" = koster mærkbart ved dagens data.

| # | Fund | Hvornår | Bevis | Indsats |
|---|---|---|---|---|
| P1 | Persondetaljen hentes 3× ved dybt link (~30 kald i stedet for ~10) | Nu | V | S |
| P2 | Koordinat-RPC'en offset-pagineres → hele beregningen køres pr. side (1,2–1,4 s pr. kørsel) | Nu (2×), kvadratisk ved vækst | V+K | S–M |
| P3 | Forsiden henter alle biografier i ét kald (13 s målt mod 3 s grænse) og igen ved hver tilbagevenden | Nu (KENDT, decisions.md:312) | V | M |
| P4 | Redaktørkoden (24 filer, ~9.700 linjer) ligger i læsernes startpakke | Nu | V | S |
| P5 | Kontraktversion slås op serielt før hver personvisning; v1-læseren vedligeholdes stadig | Nu (én rundtur) | S | S (+M) |
| P6 | Manglende indeks `conclusion.valgt_assertion_id` → seq scan pr. slettet påstand | Fortryd/slet af import: M×N | V | S |
| P7 | Offentlig læsning genberegner integritetsbevis (SHA-256) pr. række — ét mønster tre steder | Nu (KENDT), værre ved vækst | S+K | L (første skridt S–M) |
| P8 | `person`-RLS kalder DEFINER-funktion pr. række, ikke inlinet; offset genscanner | ~n²/2000 kald ved fuld hentning | S+K | S–M + måling |
| P9 | Hele grafen hentes til klienten (~20 MB `person`-JSON ved 50×) | 50× | K | L |
| P10 | `.in()`-lister uden opdeling → URL-længdefejl; opdelte kald kører serielt; hjælperen kopieret 6× | 10–50× | S+K | S |
| P11 | Feed-rækkefølge O(n²) (`filter`+`splice`+`indexOf`), kommentar lover O(n log n) | 50×; ~3 s ved n=50.000 (syntetisk) | V+K | M |
| P12 | Nærmeste fælles aner O(C²·A) | Sammengiftede slægter; 1,1 s ved C=2.047 (syntetisk) | V+K | S |
| P13 | Dansk sortering kalder `toUpperCase` pr. tegn pr. sammenligning, ved hvert tastetryk | 90.000 navne: 3,3 s → 0,36 s med nøgle | S+K | S |
| P14 | Pipeline: ledger genvalideres pr. record (≈2·N·L); klausulindeks genbygges pr. claim; sandbox-test før cacheopslag | Batchkørsler | S | S–M |
| P15 | `SammenlignUdgaver` genberegner hele kandidatberegningen ved hvert klik | Umålt | S | M |
| P16 | Mobil: alle biografier ved koldstart; fuld genindlæsning efter hver medieændring | Dev-only | S | M |

**Detaljer til de vigtigste:**

- **P1** `web/src/Folgesvend.tsx:174-188`: effekten afhænger af `[focusId, model, detailForsoeg]` og har ingen
  `if (!model)`-vagt. Geo-svaret laver et nyt model-objekt (`:317`), så effekten kører (a) før modellen findes, hvor
  `manglerBogNummer` fejlagtigt er sand, (b) når modellen lander og (c) når geo lander. Panelet blinker hver gang.
  Samme mønster i `fetchEstateOwners` (`:159-165`). *Forslag:* vent på modellen; hold geo i egen state eller afhæng af stabile delfelter.
- **P2** `web/src/data/model.ts:70` og `mobile/src/data/load.ts:219` kalder `getAll(() => rpc('public_person_source_coordinates'))`.
  RPC'en er `plpgsql RETURN QUERY` (`schema.sql:3334`), så hele resultatet beregnes før `.range()` skærer ud. Fundet af
  tre reviewere uafhængigt. *Forslag:* ét samlet svar eller keyset-parameter; markér i `getAll`, at RPC'er ikke må offset-pagineres.
- **P6** `schema.sql:3616` (FK uden indeks; eneste indeks er `ix_conclusion_target` `:6795`). Triggeren
  `trg_regen_from_assertion` (`:6476`) og FK-tjekket ved hver `DELETE FROM assertion` scanner hele `conclusion`;
  `red_reverse_reimport` sletter i løkke (`:5792`). Ét `CREATE INDEX` i schema + migration.
- **P7/P8** er kendte og kræver beslutning (jf. `docs/decisions.md:265-268`, `:3490-3494`). Forslag til retning:
  flyt integritetsbeviset fra læsetid til skrivetid via en **fejl-lukket** projektionstabel (manglende række = skjult),
  med en `db-verify`-assert der beviser projektion = genberegning. For `person`-RLS: rent kolonneprædikat + assert om
  ækvivalens med `person_offentlig`, men **mål først** — projektet har tidligere droppet en RLS-omlægning uden målt gevinst.
- **P9** er det store skaleringsvalg: et versioneret, komprimeret øjebliksbillede af den anon-synlige graf (ETag) og
  senere slægtskab som server-RPC (`SECURITY INVOKER`, så levende personer ikke lækker som mellemled). Høj GDPR-risiko → egen spec.

---

## 4. Gentagelser og struktur (G)

### G1 · Web↔mobil: datalaget er kopieret, ikke delt — DELVIST (review 27 #2) · V · F+C
- **Fakta:** `packages/core` og `packages/feed` bruges som tiltænkt til ren domænelogik (54 web- og 34 mobil-filer
  importerer `@daa/core`). Men **datalaget** (Supabase-hentning, RPC-bygning, mapping) blev ikke flyttet med: ~21
  moduler findes i begge apps (`redaktionRead.ts` 1.553/1.312 linjer med 719 identiske; `redaktionWrite.ts` 463
  identiske; `presens.ts`, `story.ts`, `livsdato.ts`, `haendelser.ts`, `sammenlign.ts` …). Siden 1/8: 85 commits i
  `web/src`, 10 i `mobile/src` — rettelser når ikke mobil (se K12).
- **Rod:** web har en ikke-nullbar `supabase`-singleton, mobil en nullbar. Derfor er mange fetchere kopieret med
  `if (!supabase) return []` som eneste forskel.
- **Forslag (trinvis):**
  1. **Rent og identisk → `@daa/core`** (meget lav risiko): `sammenlign.ts`, `mediaPaths.ts`, én `parsePostgresBigintId`,
     én `getAllIn`, `compareParentOrder` + rækker→graf via udvidet `buildFamilyGraph` (i dag tre udgaver, KENDT F-21),
     bio-gruppering, presens-formattere, `orThrow`. Fra web: `joinEvidence`, `buildForaeldreSlot`, `buildTidslinje`,
     `mapFamilieRows`, `klassificerMedie` m.fl. Ca. 8 dobbelte testfiler bliver til én.
  2. **Fetchere med injiceret klient** → ny `packages/data` (supabase-js som peer-afhængighed, så core forbliver
     afhængighedsfri). Mobil har allerede mønstret (`fetchLivsdatoRows(sb)`). **Kræver beslutning** (ny permanent pakke).
  3. **Én delt `buildRpcCall`** (skrivevej — højest risiko; kræver afgørelse pr. ændringsart).
  4. **Lad være:** UI-komponenter, upload/storage-I/O, auth, `types.ts`.
- Hvis mobil forbliver dev-only længe, er trin 1 + K12 + K13 det meste af gevinsten.

### G2 · `Redaktion.tsx`: én funktion på ~2.280 linjer — NY · V · F
- **Hvor:** `web/src/Redaktion.tsx:204-2486` (`Arbejdsbord`): ~75 `useState`, 24 indre `renderX()`, 438 inline
  `style={{`, 78 hårdkodede farver, 67 `<div onClick>` mod 12 `<button>` (ikke tastaturtilgængelige).
- **Forslag:** Samme snit som lykkedes i `Folgesvend.tsx` (1.326 → 580 linjer): hooks først (`useMediaEditor`,
  `usePersonRecord`, `useKvalitetsark`), derefter `renderX` → komponenter, og en `Knap`-primitiv. Gøres naturligt i
  forbindelse med webredesignets fase for redaktionen. K3 er en direkte følge af størrelsen.

### G3 · SQL: rollegate, kontraktlås og label-blokke kopieret — NY · V · F
- 65× `IF current_rolle() <> 'redaktion'` (121 rollegates i 8 varianter; tre varianter er uenige om, hvorvidt en
  manglende bruger afvises eksplicit). Blokken "advisory-lås + `narrative_record_contract_version()<>2`" står 33 gange.
  Binding→record-label-blokken er kopieret mellem `public_family_sources` og `public_person_facts`.
- **Forslag:** `private.require_redaktion(fejlkode)` (returnerer aktør-id), `private.require_narrative_contract(version, fejlkode)`.
  Indfør gradvist, når en funktion alligevel røres; fejlkoden som parameter, fordi testene matcher på tekst.

### G4 · Pipeline: hjælpere kopieret i stedet for delt — NY · V · F
- **DB-forbindelse (R):** ~45 scripts bygger hver sin forbindelse med fem forskellige SSL-regler. 11 ikke-frosne
  scripts sætter ingen `sslmode` (libpq-standard `prefer`); 9 sætter `disable`, når `PGDATABASE` er sat, uden at tjekke
  værten (`S/apply_phase_a_1939_v50.R:54-57`). `env_or` er defineret 22×, `connection_factory` 10×.
  **Forslag:** én `daa_connect(mode = "prod"|"local")`: prod altid `require`, local kun ved lokal vært; sætter
  `request.jwt.claim.sub` ét sted. Frosne filer røres ikke.
- **Ark og hashing (Python):** `render_sheet`/`parse_sheet` i 10 filer; `decision_sheet_core.py` deler kun 32 linjer.
  SQL-citering 4 steder (kun én afviser NUL); kanonisk JSON 8×; `_sha` betyder fire forskellige ting i 19 filer;
  identitets-/rækkefølgetjek findes i hærdet og uhærdet udgave.
  **Forslag:** udvid `decision_sheet_core` — men **lås først med golden-tests, at output er byte-identisk**, ellers
  brydes hash-bundne godkendelser.
- **Pakning:** ingen `conftest.py`/`pytest.ini`; `sys.path.insert` i 42 filer. En `pytest.ini` med `pythonpath` gør
  testkrogene overflødige (CLI-scripts beholder deres, pga. `python -I`).

### G5 · Død og afsluttet kode ligger fladt blandt levende — KENDT (D-31, 1c-07) · S · F
- `.claude/skills/daa-extract/scripts/` har 461 filer i ét niveau. `*_1939_v50*`: 69 kodefiler (22.464 linjer) + 48
  testfiler; 68 af 98 1939-filer har ingen reference udefra. 19 `fix_*.sql` (prod-kørt i oktober).
- Rod: `db-migrations-c3-identity.sql` (selvstoppende, 1.328 døde linjer), `db-rollback-fase2/3.sql`,
  `db-rollback-foraeldrefamilie.sql`, `db-backfill-foraeldrefamilie.sql` (juli), `supabase_load.R` (historisk).
  `R/update-1939-narratives.R` og `R/update-2018-narratives.R` er spærrede kopier.
- `packages/core/src/index.ts` eksporterer alt (`export *` ×25); bl.a. `geoSelectors`-funktioner, `findSlaegtsrod`,
  `entityDescriptions.ts` og `chooseNext`/`weightedDrawIndex` (feed) bruges kun af tests.
- **Forslag:** Flyt til `scripts/arkiv/1939-v50/` og `docs/arkiv/sql/` efter det eksisterende `arkiv/README.md`-mønster;
  ret wrappere, inventory-test og SKILL.md i samme commit. **Ingen sletning** — mål og vis indhold først (Hård regel 6).

---

## 5. Drift, CI og migrationsmodel (D)

### D1 · Paritetsgaten dækker 62 af ~400 funktioner, og der er reel drift — DELVIST (F-04, B9) · V · F+C
- `.github/workflows/ci.yml:419-420` (hardkodet `-eq 62`); `tests/sql/inspect-5ab-function-parity.sql`.
- **Drift:** `private.narrative_record_state` har et ekstra `JOIN public.source … slags='DAA-udgave'` i
  `db-migrations.sql:14005-14010`, som mangler i `schema.sql:14978-14983` (siden 2026-08-29; begge filer har kun én
  definition). Hvilken version prod kører, er ikke tjekket i dette review. Desuden er 15 funktioner håndskrevet to gange
  med kosmetiske forskelle, og `private.ensure_reimport_operations` findes kun på migrerede baser.
- **Forslag:** Én generisk katalogsammenligning (alle funktioner: definition, DEFINER, config, grants; kolonner,
  indekser, triggere, politikker) mellem "kun schema" og "schema + migrationer", med en kort eksplicit undtagelsesliste.
  Ensret de 15 kosmetiske dubletter først. **Afgør `narrative_record_state` med en prod-læsning før noget rettes.**

### D2 · Migrationsmodellen: filen vokser for evigt og genafspiller sin historie — KENDT (F-04, B9/1b-05) · S · F+C
- `db-migrations.sql`: 6.229 linjer (2/8) → 15.793 (3/9) → 27.321 (30/10) → 35.162 (12/11). 634 funktionsdefinitioner,
  mindst 199 forældede (~11.300 linjer). `red_finalize_reimport` står 10 gange. Egen `BEGIN/COMMIT` midt i filen.
  `entitet_offentlig` holdes i hånd i to filer. Samme grant står tre steder. Prod-deploys kører allerede "fra markør X
  til slut" — altså nummererede migrationer uden protokol.
- **Forslag (ingen værktøjsskift, ren psql):**
  1. Genskabelig kode (funktioner, views, triggere, politikker, grants) defineres **kun** i schema-filerne og lægges på
     idempotent ved hvert deploy.
  2. Engangsmigrationer (tabel-DDL, data) som nummererede filer + lille protokoltabel (id, sha256, tidspunkt) — passer
     til de eksisterende sha-bundne ceremonier.
  3. Nulpunkt: når prod er verificeret på et commit, arkiveres den nuværende fil som historik.
  4. D1's generiske gate er forudsætningen og laves først.
- **Hensyn:** funktion brugt i CHECK-constraint (`db-migrations.sql:12874`), `5a-cutover`-udsnittet CI klipper med
  `sed`, opgraderingstesten bundet til `2d6aabf:schema.sql`, og at kontrakt-v1-grenene ikke er døde (frisk base starter i v1).
  Allerede besluttet som "særskilt beslutning efter trin 6" — dette review giver tallene til den.

### D3 · Tests der ikke kører i CI — DELVIST (review 35 P6, D-33) · V · F
- 69 af 133 Python-testfiler (31.974 linjer) står uden for den hardkodede liste i `ci.yml:159`, bl.a. `test_validate.py`
  (skill'ens blokerende trin), `test_clause_ledger.py`, `test_source_record_ledger.py`, `test_identitetsregister.py`.
  13 af 131 `tests/sql`-filer nås ikke; `tests/integration/test-reimport-writer.R` nævnes ikke.
- **Forslag:** Vend listen: pytest over hele mappen med en kort udelukkelsesliste (der krymper med G5). Lad CI fejle,
  hvis en `tests/sql/test-*`-fil hverken køres eller står på en "køres ikke"-liste. **Kør hele suiten lokalt først** — der
  kan være røde tests.

### D4 · CI genopbygger samme base mange gange — NY · S · F
- `schema.sql` (21k linjer) indlæses 22 gange i `ci.yml`; narrativ-jobbet kører samme femtrins-opskrift 4 gange
  (`ci.yml:722-767`); 9 Python-testmoduler bygger 11 baser med samme tuple.
- **Forslag:** Skabelonbase pr. opskrift + `createdb -T` (mønstret findes i `tests/sql/test-placement-ceremoni.sh:101`);
  delt session-fixture i `conftest.py`. Rør ikke de bevidst forskellige opskrifter. Mål ét skema-load i en CI-log først.

### D5 · R-pakker er ulåste — NY · S · F
- Ingen `renv.lock`/`DESCRIPTION`; `jsonlite` og `digest` indgår i hash-bundne manifester. En ny pakkeversion kan ændre
  JSON-formatering og dermed hashes uden kodeændring. Cache kun i ét af fire R-jobs.
- **Forslag:** dateret RSPM-snapshot i `setup-r`; genbrug cache-trinnet.

### D6 · Dokumentation siger "PWA-først", men web har hverken manifest eller service worker — NY · S · F
- `web/index.html`, `web/vite.config.ts`. Enten ret CLAUDE.md eller notér som udskudt.

---

## 6. Foreslået rækkefølge (bølger)

**Bølge 1 — korrekthed, billigt (alle S):** K1, K2, K3, K4, K6, K7, K9, K13, K14, P6 + K8 trin 1 (tæl/log) + K12.
Hver er afgrænset, har en tydelig test og kan committes atomisk. K5 (fortryd-lås) er M og kræver en to-sessions-test.

**Bølge 2 — værn mod at ting glider (S–M):** D1 (generisk paritetsgate; først afgør `narrative_record_state` mod prod),
D3 (alle tests i CI), K10 (`private_io.py`), G4 `daa_connect`, P1, P2, P4, P5-cachen.

**Bølge 3 — struktur (M–L, kræver beslutninger):** G1 trin 1 → (beslutning) trin 2–3; G2 sammen med webredesignet; G3
gradvist; G5 arkivering; D2 migrationsmodel efter trin 6; D4 CI-skabeloner.

**Bølge 4 — skalering (L, kræver spec):** P7 projektionstabel, P8 person-RLS (mål først), P9 graf-øjebliksbillede,
P3 biografier pr. vindue, P10–P13 algoritmer. Prioritér efter, hvornår foreningens samlede data faktisk kommer.

Importrelaterede punkter (K2, K10, P14, G4, G5) skal ved en plan kobles til roadmapmål, værdikædeled og færdigbevis jf.
`docs/evidensbaseret-genimport/` — dette review ændrer ikke roadmappet (aktivt mål: trin 6e).

## 7. Beslutninger, der ligger hos projektejeren

1. **`packages/data`** — ny permanent pakke til delte fetchere med injiceret klient (G1 trin 2)? Kræver linje i `decisions.md`.
2. **Mobilens fremtid** — forbliver den dev-only længe, er G1 trin 2–3 ikke umagen værd endnu.
3. **Migrationsmodel** (D2) — tidspunkt og nulpunkt; allerede noteret som "efter trin 6".
4. **Kontrakt v1** — skal v1-læserne i web/mobil/core fjernes, nu prod har været på v2 siden 6/9 (P5)?
5. **Integritetsbevis ved skrivning** (P7) — projektionstabel på GDPR-fladen kræver spec og fejl-lukket design.
6. **Kronologisk vagt** (K8 trin 2) — hvilken regel skal gælde for kvalificerede/fuzzy datoer?

## 8. Det, der er godt og skal bevares

- **Ren kerne** i `packages/core`/`feed` uden runtime-afhængigheder; tid og tilfældighed samlet ét sted; seedet,
  deterministisk feed med ét GDPR-lukkepunkt (`kunSikkertDoede`).
- **`collapseSameAs` + preflight:** konflikter går i karantæne, valideringen kører til fast punkt; preflight låst til
  den fulde beregning af en ækvivalenstest. **Usikkerhed vises** i slægtskabsfinderen (svageste led, `usikker`).
- **Fejl-lukket synlighed i DB:** `entitet_offentlig` med `else false`, `family_offentlig` som DEFINER for ikke at fejle
  åbent; allow-listen for `red_*` (tilbagekald alt, tildel navngivne signaturer); eksplicit `search_path` på alle
  funktioner; `(select current_rolle())` som InitPlan.
- **Hash-binding af menneskets godkendelse, dry-run som standard** (`S/apply_reimport.R`), `S/arkiv/README.md`-mønstret,
  selvstoppende historiske filer — **centralisér, svæk ikke**.
- **Pipeline kun på standardbiblioteket** (eneste tredjepart: pytest); CI-kommentarer der forklarer hvorfor
  (minutbudget, `paths-ignore`); CI's dobbeltkørsel af migrationer og begge katalogrækkefølger.
- **Nyere web-mønstre:** ren `map`/`build` adskilt fra tynd `fetch`; vagter mod forældede svar (`alive`/`aktiv`);
  `submitChange` → `describeCall` som eneste skrivevej; Følgesvend-opdelingen; navngiven degradering pr. tabel i `loadModel`.

## 9. Dækning og begrænsninger

- **Læst grundigt:** web-dataindlæsning og `Folgesvend`/dele af `Redaktion`; mobil `load.ts`/`useStore.ts` og
  web↔mobil-diffs af ~15 par; `packages/core` (relationship, buildModel, collapseSameAs, tree, getAll, collation, matchUdgaver)
  og `packages/feed` (order, pool, stream, score); `db-rls.sql` (politikker), kernetabeller og udvalgte læse-RPC'er i
  `schema.sql`; `ci.yml`; `load_haendelser.R`, `apply_reimport.R`, `decision_sheet_core.py`, `evidence_runner.py` (Codex).
- **Maskinelt analyseret:** alle SQL-funktionsdefinitioner (navn, krop-hash, dubletter, drift); alle ikke-test
  Python-funktioner grupperet på krop; alle R-`dbConnect`/`sslmode`; testfiler mod `ci.yml`.
- **Skimmet/sprunget over:** store web-komponenter (`SammenlignUdgaver`, `MediaDetaljeOverlay`, `OcrKildepanel`,
  `PresensView`), mobilens øvrige skærme, `db-verify.sql` (kun struktur), de store ceremoni-writere, `tools/`,
  `R/tng-qa`, `R/geo-enrich`, 1939-familiens indre, alle UI-komponentpar.
- **Ikke gjort:** ingen tests, `tsc`, build eller bundle-måling (ingen `node_modules` i worktree'en); ingen DB-forbindelse,
  `EXPLAIN` eller HTTP-måling. Syntetiske mikromålinger (P11–P13) er af løkkeformen, ikke projektdata. Codex
  reproducerede K2, K9 og K11 med den faktiske kode i hukommelsen.
- **Kendthed** er tjekket mod review 27, fundament-reviewet 2026-07-16, review 35 og 2026-10-27-reviewet; den åbne
  backlog i `docs/decisions.md` er kun nøgleordssøgt.
