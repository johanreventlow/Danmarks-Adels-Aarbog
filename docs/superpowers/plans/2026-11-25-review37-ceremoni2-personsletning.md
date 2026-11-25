# Review 37 ceremoni 2: personsletning (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Luk review 37's rester om personsletning (P3, P4, P9, P10, R37P11-1, R37P11-3) i én prod-DDL-ceremoni plus én web-PR-del.

**Architecture:** Alle DB-ændringer er `CREATE OR REPLACE` af tre eksisterende funktioner (`private.person_purge_kontrol`, `public.red_slet_person_helt`, `public.red_slet_person`) med uændrede signaturer, så ACL og klienter er upåvirkede. Endelige kroppe står i `schema.sql` (source of truth) og ordret i blokken `-- BEGIN review37-c2` sidst i `db-migrations.sql`. DDL'en køres i prod FØR merge (bagudkompatibel: gamle web-klienter virker mod ny DB). Web-delen giver mærkater og tvangsvalg.

**Tech Stack:** PostgreSQL (plpgsql/sql), bash-testscripts i `tests/sql/`, React + vitest i `web/`.

**Spec:** fundene i `docs/reviews/37-helhedsreview-kodebase-2026-11-19.md:185-192` og issue #397 (tjekliste-linjerne R37P11-1/-3, P3, P4, P9, P10). Afgørelser fra projektejeren 2026-11-25 nedenfor. Linjenumre i reviewet er forældede; navigér efter funktionsnavn.

## Projektejerens afgørelser (2026-11-25)

- **P9:** slet den virkningsløse `set_config('statement_timeout','30s',true)`. Loftet er redaktørens 8 s; 8 s-backloggen for store profiler består.
- **P10:** søg lige så bredt som nu (ingen recall-tab), men fund, der KUN er et tal, får egen `grund` og vises adskilt.
- **R37P11-3:** reglen består (knudepunkt blokerer »Slet helt«). Dialogen forklarer vejen (fjern koblingerne under »Samme person«), og `red_slet_person` låser hele samme_som-gruppen mod kapløbet.

## Global Constraints

- Signaturer uændrede: `person_purge_kontrol(bigint,jsonb) RETURNS TABLE(sted text,tabel text,pk jsonb,grund text)`, `red_slet_person_helt(bigint,text) RETURNS jsonb`, `red_slet_person(bigint) RETURNS void`. Ingen nye funktioner, ingen GRANT-ændringer, ingen `db-rls.sql`-ændring.
- `grund`-værdier: `'fritekst'` = navnetræf (uændret betydning for navn), ny `'kun_id'` = kun et id-tal (P's eller en families) uden navnetræf. Én række pr. (sted, tabel, pk) fra tekst-scanningen; navn vinder over tal.
- P3's nye kilder søges for navn **og** id-tal som resten (projektejeren 25/11, ændret under udførelsen); rene tal bliver `kun_id`.
- Preview-hashen ændres af P3/P10 → åbne forhåndsvisninger fejler lukket (`PURGE_PREVIEW_AENDRET`) og skal hentes igen. Det er accepteret.
- Låseorden i `red_slet_person` uændret bortset fra, at `private.lock_identity_people` får hele gruppen i stedet for `ARRAY[p_person_id]` (samme kald-sted, efter `samme_som_mutation`-advisory og guard).
- Tidsgate: preview og execute for den største profil skal holde sig under 8 s med margin (mål: preview ≤ 4 s) på stand-in efter `ANALYZE`. Stand-in-tid er ikke prod-tid; prods tal måles efter DDL med læse-kald.
- `work_presens*/` må aldrig læses. `~/.private/` røres kun af parent-sessionen. Drop aldrig en database, du ikke selv har oprettet i samme script.
- Commit-politik for subagenter: do NOT commit; parent-sessionen ejer commits (Conventional Commits, dansk, ingen Claude-attribution).

## Review Focus

1. Et navn, der også står i P's egne rækker (som slettes), må ikke give kontrolrækker: `NOT EXISTS plan … handling='slet'` skal gælde de nye kilder. Test i Task 3.
2. Tom eller `NULL` `visning_navn`: nye kilder må ikke matche alt (`position('' IN x)=1`). Test i Task 3.
3. En tekst med både navn og P's id må give præcis én række med `grund='fritekst'`, ikke to. Test i Task 2.
4. Den fortrydelige sletning af P, mens et gruppemedlem Q's rækkelås holdes, skal vente (ikke lykkes på et forældet billede). Test i Task 4.
5. Gammel web-klient mod ny DB: ukendt `grund` vises rå (`purgeLabels[k.grund] ?? k.grund`), intet kaster. Ingen ny test; bekræftet ved læsning af `SletHeltDialog.tsx:163`.

---

### Task 1: P9 — fjern den virkningsløse tidsgrænse

**Files:**
- Modify: `schema.sql` (i `public.red_slet_person_helt`, linjen `PERFORM set_config('statement_timeout','30s',true);`, ca. 25013)
- Test: `tests/sql/test-person-purge.sql` (ny assert sidst i filen)

- [ ] **Step 1: Skriv den fejlende assert** i `test-person-purge.sql`: `pg_get_functiondef('public.red_slet_person_helt(bigint,text)'::regprocedure)` indeholder ikke `statement_timeout` (label `p9_ingen_statement_timeout`), og indeholder stadig `set_config('lock_timeout','5s',true)` (label `p9_lock_timeout_bevaret`). Følg filens eksisterende assert-stil.
- [ ] **Step 2:** `bash tests/sql/test-person-purge.sh lokal_c2_purge` → FAIL på `p9_ingen_statement_timeout`.
- [ ] **Step 3:** Slet linjen; erstat med en kommentar: tidsgrænsen er kalderens rolle-`statement_timeout` (redaktør 8 s via PostgREST), sat før funktionen starter, så en `set_config` her virker ikke (review 37 P9).
- [ ] **Step 4:** `grep -rn "30s\|30 s" docs/runbooks/personsletning-prod.md docs/superpowers/plans/personsletning/ db-verify.sql tests/sql/ | grep -i -E "timeout|i alt"`. Ret udsagn om »30 s i alt« til 8 s. Kør testen igen → PASS.

### Task 2: P10 — rene tal får egen grund

**Files:**
- Modify: `schema.sql` i `private.person_purge_kontrol`, slut-SELECT'en på `tekster` (`SELECT DISTINCT t.sted,t.tabel,t.pk,'fritekst'::text FROM tekster t CROSS JOIN tokens CROSS JOIN navn WHERE (t.tekst COLLATE "C" ~ tokens.rx OR …`)
- Test: `tests/sql/test-person-purge.sql`

**Interfaces:**
- Produces: `grund ∈ {'fritekst','kun_id','laast_familiefoto','bevaret_evidens','bevaret_summary'}` fra kontrollisten. Task 3 bygger videre på samme slut-SELECT; Task 5 viser mærkaterne.

- [ ] **Step 1: Fejlende tests** (syntetiske fixtures i filens eksisterende stil; P har et navn og et id < 2100 i testbasen, ellers vælg en anden fixture-tekst, der rummer P's id som rent tal):
  - en bevaret `note` på en anden persons fakta, der kun rummer P's id som tal (fx `'Nævnt i 1873'` hvor 1873 = P's id) → præcis én kontrolrække med `grund='kun_id'` (`p10_kun_tal`)
  - en bevaret note med P's navn → `grund='fritekst'` (`p10_navn`)
  - en bevaret note med både navn og id → præcis én række, `grund='fritekst'` (`p10_navn_vinder`)
- [ ] **Step 2:** Kør `test-person-purge.sh` → FAIL på de tre.
- [ ] **Step 3:** Omskriv slut-SELECT'en: beregn pr. tekstrække `navn_hit` (nuværende to `position`-tjek) og `id_hit` (`~ tokens.rx`); behold rækker med `navn_hit OR id_hit`; `grund = CASE WHEN navn_hit THEN 'fritekst' ELSE 'kun_id' END`. `NOT EXISTS plan … 'slet'` uændret. Sortering i preview er uændret (`person_purge_preview_fra_plan`).
- [ ] **Step 4:** Opdatér gyldne forventninger/hashes i `test-person-purge.sql`/`.sh`, som ændres af den nye `grund` (kun dem; forklar hver i commit-teksten). Kør → PASS.

### Task 3: P3 — kontrollisten søger navnet i flere tekster

**Files:**
- Modify: `schema.sql` i `private.person_purge_kontrol` (CTE `tekster` + slut-SELECT fra Task 2)
- Test: `tests/sql/test-person-purge.sql`, `tests/sql/measure-person-purge.sql` (kun brug)

**Interfaces:**
- Consumes: Task 2's `navn_hit`/`id_hit`-form.
- Produces: kolonnen `kun_navn boolean` på hver `tekster`-gren (`false` for alle eksisterende grene, `true` for de nye), så `id_hit` kun tæller når `NOT kun_navn`.

- [ ] **Step 1: Fejlende tests**, hver med P's navn i teksten på en ANDEN entitet, som sletningen bevarer → kontrolrække med `grund='fritekst'`:
  - `story` (titel eller tekst) på en anden person (`p3_story`)
  - `entity_description.tekst` på en anden entitet (`p3_entity_description`)
  - `assertion.vaerdi_tekst` på en anden persons faktum (`p3_assertion`)
  - `citation.citat_tekst` på en anden persons påstand (`p3_citation`)
  - samme fire, men kun med P's id som tal → INGEN række fra de nye grene (`p3_kun_navn`)
  - P's EGEN story/beskrivelse med navnet (slettes af planen) → ingen række (`p3_egne_slettes`)
  - P uden `visning_navn` (NULL eller '') → de nye grene giver ingen rækker (`p3_tomt_navn`)
- [ ] **Step 2:** Kør → FAIL.
- [ ] **Step 3:** Tilføj fire grene til `tekster` med `sted='S58'`, `kun_navn=true`: `public.story` (`concat_ws(' ',titel,tekst)`), `public.entity_description` (`tekst`), `public.assertion` (`vaerdi_tekst`) og `public.citation` (`citat_tekst`) — de to sidste UDEN for de eksisterende fam_keep-scopede S38b-grene (udelad rækker, som S38b-grenene allerede dækker, så samme pk ikke står under to steder). Slut-SELECT: `id_hit` kræver `NOT t.kun_navn`.
- [ ] **Step 4:** Kør → PASS. Kør også `bash tests/sql/test-person-purge-concurrent.sh lokal_c2_conc` → PASS (uændret adfærd).
- [ ] **Step 5: Tidsgate (parent-sessionen, stand-in):** mål preview og execute (i rullet-tilbage transaktion) for den største profil før og efter, med `measure-person-purge.sql`, efter `ANALYZE`. Krav: preview ≤ 4 s. Overskrides det → stop og rapportér (fx indeks eller `LATERAL`, jf. memory om kvadratiske CTE'er), ingen kvikfix.

### Task 4: R37P11-3 — lås hele samme_som-gruppen ved den fortrydelige sletning

**Files:**
- Modify: `schema.sql` i `red_slet_person` (kaldet `PERFORM private.lock_identity_people(ARRAY[p_person_id]);` og kommentaren lige under)
- Test: `tests/sql/test-person-purge-concurrent.sh` (nyt scenarie i filens eksisterende stil med baggrunds-psql og `application_name`-ventetjek)

- [ ] **Step 1: Fejlende scenarie `r37p11_3_gruppelaas`:** P og Q er samme_som (offentlige). Session W: `BEGIN; UPDATE person SET privat=true WHERE id=Q; SELECT pg_sleep(…)` (holdes åben). Session D (redaktør-JWT som filens øvrige scenarier, `SET lock_timeout='1s'`): `red_slet_person(P)` → skal fejle med `55P03` (venter på Q). Før rettelsen lykkes D.
- [ ] **Step 2:** Kør → FAIL (D lykkes).
- [ ] **Step 3:** Beregn gruppen (rekursivt over `relation` med `rolle='samme_som'`, person↔person, samme form som `public.person_gruppe_skjult`) EFTER advisory-låsen `samme_som_mutation` (kanterne er da stabile), og kald `private.lock_identity_people(<gruppe inkl. P>)`. Opdatér kommentaren: gruppemedlemmerne er låst, så `red_set_privat` og andre skrivere af `privat`/`levende` på et medlem venter.
- [ ] **Step 4:** Kør scenariet + hele `test-person-purge-concurrent.sh` + `tests/sql/test-review37-d9-laaseorden.sql` (via dets runner i CI-jobbet) → PASS, ingen deadlock.

### Task 5: Web — mærkater, vejvisning, tvangsvalg og flere rækker

**Files:**
- Modify: `web/src/components/SletHeltDialog.tsx` (`purgeLabels`, gruppering af »Til kontrol«)
- Modify: `web/src/components/SlettedePersoner.tsx`, `web/src/data/redaktionRead.ts` (`fetchSlettedePersoner`), og det sted, der leverer `fortryd`-prop'en (find med `grep -rn "SlettedePersoner" web/src`)
- Test: `web/src/components/__tests__/SletHeltDialog.test.tsx`, `web/src/components/__tests__/SlettedePersoner.test.tsx`

**Interfaces:**
- Consumes: `grund`-værdierne fra Task 2; blokeringen `samme_som_knudepunkt` (uændret).
- Produces: `fortryd: (r: SlettetPerson, opts?: { force?: boolean }) => Promise<{ dryRun: boolean }>`; `fetchSlettedePersoner(limit: number)` (uændret signatur, kaldes med stigende limit).

- [ ] **Step 1: Fejlende tests:**
  - `purgeLabels` har tekster for `fritekst` (»Teksten nævner profilens navn«), `kun_id` (»Teksten rummer profilens eller en families id som tal — ofte et årstal«) og `bevaret_summary` (»Et bevaret ændringssæts beskrivelse kan nævne profilen«); `kun_id`-rækker står i en særskilt, sammenklappet gruppe under »Til kontrol« med antal i overskriften
  - `samme_som_knudepunkt` viser: »Profilen er knudepunkt for andre profiler. Fjern først koblingerne under »Samme person« på profilens redigeringsside, og hent så en ny forhåndsvisning.«
  - SlettedePersoner: en fortryd-fejl, hvor `erFortrydKonflikt(msg)` er sand, viser forklaring + knappen »Fortryd alligevel (overskriver nyere ændringer)«, som kalder `fortryd(r, { force: true })`
  - SlettedePersoner: med 100 rækker vises »Vis flere«, som henter med limit 200 (trin à 100, højst 500 = DB'ens loft); ved 500 står »Viser de 500 nyeste«
- [ ] **Step 2:** `npm run test -w web -- SletHeltDialog SlettedePersoner` → FAIL.
- [ ] **Step 3:** Implementér. Tvangsvalget genbruger mønstret fra `web/src/Redaktion.tsx:866` (`'konflikt'` → force).
- [ ] **Step 4:** `npm run test -w web` og `npm run build -w web` → PASS. e2e lokalt: `PLAYWRIGHT_PORT=5293 VITE_SUPABASE_URL=https://e2e.invalid VITE_SUPABASE_ANON_KEY=e2e-dummy npx playwright test` (i `web/`); notér resultatet til PR'en.

### Task 6: R37P11-1 påstand 1 og P4 — bevis eller luk

Kodelæsning 25/11 tyder på, at begge allerede er løst: fortrydelses-sæt har ingen events (`red_fortryd_change_set` nulstiller `app.change_set_id`; `log_change` logger intet), så en fortrydelse af en fortrydelse er en no-op og personen står tilbage; og `person_purge_historik` dækker siden b4e27c73 (20/11, P1+P2) story- og relationshistorik med familie-subjekt i Fam_c.

**Files:**
- Test: `tests/sql/test-review37-p11-kaldere.sql` (påstand 1), `tests/sql/test-person-purge.sql` (P4)

- [ ] **Step 1:** Test `r37p11_1_fortryd_af_fortryd`: `red_slet_person(P)` → `red_fortryd_change_set(S)` → `red_fortryd_change_set(F1)`: P findes, `red_slettede_personer` lister ikke S; en ny `red_slet_person(P)` listes.
- [ ] **Step 2:** Test `p4_tidligere_familierelation`: en relation familie(Fam_c)→ejendom oprettes og fortrydes før sletningen af P; efter `red_slet_person_helt` findes ingen `change_event` med den relations id (story-varianten dækkes allerede af fixture `h` ved `test-person-purge.sql:3818`).
- [ ] **Step 3:** Kør begge. PASS → fundene lukkes med testene som bevis. FAIL → stop og rapportér til parent (ingen rettelse uden ny afgørelse).

### Task 7: Ceremoniblok, opgraderingstest, CI og dokumentation (parent-sessionen)

**Files:**
- Modify: `db-migrations.sql` (ny blok sidst: `-- BEGIN review37-c2` … `-- END review37-c2` med de tre endelige funktionskroppe ordret fra `schema.sql`)
- Create: `tests/sql/test-review37-c2-upgrade.sh` (efter `test-review37-c1-upgrade.sh`, uden db-rls-DO-blok; base-commit `90fa6fff` = main efter c1 = prods SQL)
- Modify: `.github/workflows/ci.yml` (c1-trinnet → c2-trinnet), `tests/ikke-i-ci.txt` (pensionér c1-testen med målt grund)
- Modify: `docs/decisions.md` (P9, P10, R37P11-3 + lukning af P4/R37P11-1 påstand 1 med testnavne), issue #397 tjekliste
- Create: `~/.private/review37-c2/prod.zsh` + `standin.zsh` (fra c1-skabelonerne; facit sammenligner ikke red_*-kalderet, jf. blindgyden kontrakt v1/v2)

- [ ] **Step 1:** Upgrade-testen: kataloget efter blokken på 90fa6fff-basen = frisk `schema.sql`; to kørsler ændrer intet; fuld `db-verify.sql` grøn.
- [ ] **Step 2:** Kør hele CI-jobbet for personsletning lokalt (`ci_jobs_lokalt.py`), tjek exit-kode.
- [ ] **Step 3:** Generalprøve på stand-in fra projektejerens shell; tjek `origin/main` for parallelle DB-ændringer før push og før prod-DDL.
- [ ] **Step 4:** PR `[MERGE IKKE – prod-DDL først]`, draft. Prod-DDL i projektejerens shell → `get_advisors` → merge efter ja.
