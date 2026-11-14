# Fuld personsletning — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En redaktør kan slette én personprofil helt fra Redaktion — efter en forhåndsvisning — uden at noget indhold om personen bliver tilbage.

**Architecture:** Et datadrevet sletteinventar (`private.person_purge_sted`) beskriver hvert sted, en person kan efterlade spor, og bruges af forhåndsvisning, sletning, tælling og en katalogvagt. Sletningen skriver de præcise rækker i et transaktionslokalt manifest; append-only-triggerne tillader DELETE kun for manifestets rækker på en eksplicit tilladelsesliste uden bogtabeller. Klienten sletter Storage-filer efter commit (som medie-udrensningen); den eksisterende janitor rydder forladte filer.

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql, psql-testscripts i CI, React/TypeScript + vitest i `web/`.

**Spec:** `docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md` (godkendt 2026-11-14). Læs specen før hver task; §-henvisninger nedenfor peger dertil.

## Global Constraints

- `schema.sql` er source of truth; hver ændring spejles idempotent i en ny blok sidst i `db-migrations.sql` (markør `-- Fuld personsletning (2026-11-14)`) og grants i `db-rls.sql`. Migrationen skal kunne køres to gange.
- Alle nye funktioner: `SECURITY DEFINER`, `SET search_path = pg_catalog, public, private`, `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` før eventuel `GRANT EXECUTE … TO authenticated` (kun de to public-RPC'er).
- Rollegaten `current_rolle() = 'redaktion'` er første sætning i begge public-RPC'er, før enhver læsning (V7, ingen eksistens-oracle).
- Bogens lag slettes aldrig: `private.source_record`, `source_occurrence`, `source_observation`, `source_observation_text`, `source_mention`, `source_rendition`, `extraction_run`, `source_persona`, `source_persona_mention`, `source_persona_placement*`, `interpretation`, `interpretation_party` (§3, §6.2).
- Ingen `DISABLE TRIGGER`, ingen `session_replication_role`, ingen ændring af TRUNCATE-triggere. UPDATE i append-only-tabeller forbliver forbudt, undtagen `narrative_legacy_publication.latest_event_id := NULL` for manifestets rækker (§6.2).
- Sletningen opretter ingen `change_set`/`change_event` og afviser, hvis `app.change_set_id` er sat (§6.1, K2).
- Låserækkefølge (§6.12): delt advisory på narrative-kontrakten → rollegate → `samme_som_mutation` + `guard_identity_mutation_snapshot` → `FOR UPDATE` source/external-id → `lock_identity_people` → `lock_family_rows` → kildelåsen `daa-identity-candidates:<source>`.
- Ny oprindelse i `private.decide_source_persona_identity`: `'person_purge'`, kun `decision_status='rejected'`, `p_canonical_person_id IS NULL`, evidence præcis `{"reason":"not_a_person"}` (§6.9).
- Fejlkoder (præfiks `PURGE_`): `PURGE_FREMMED_CHANGE_SET`, `PURGE_PREVIEW_AENDRET`, `PURGE_BLOKERET`, `PURGE_FINDES_IKKE`.
- Ingen PII i testoutput, commits eller logs; testpersoner er syntetiske med negative id'er som i `db-verify.sql` (fx `-987654611`).
- Prod skrives kun af projektejeren i egen shell via runner med `--jeg-mener-det --go <8hex>`.
- **Rettelse til specen §6.7 (Ruling):** ingen udbakke-tabel. Klienten sletter filerne efter commit som `executeUdrens` (`web/src/data/mediaUdrens.ts`); fejlede filer er forældreløse, fail-closed usynlige og fanges af `R/media-janitor.R` kategori b. Begrundelse: mekanismen findes og er testet; en udbakke gentager den. Specen opdateres i Task 9.

## Review Focus

1. **En person med spor i en tabel, inventaret ikke kender** (ny tabel efter planen) — forventet: katalogvagten fejler i CI, ikke en stille rest. Test i Task 1 (`vagt_ukendt_kolonne`).
2. **Manifestet for én transaktion bruges af en anden** (to samtidige sletninger, eller en anden session med samme person) — forventet: DELETE afvises. Test i Task 2 (`manifest_anden_backend`) og Task 8 (samtidighed).
3. **Forhåndsvisning med uændret antal men andre rækker** (fx et faktum slettet og et andet oprettet) — forventet: `PURGE_PREVIEW_AENDRET`. Test i Task 4.
4. **Fortrydelse af et bevaret fælles sæt efter sletningen** — forventet: fejler lukket eller genskaber intet af den slettede. Test i Task 6.
5. **Sletning af personen med højeste id** — forventet: næste nye person/narrativ/familie får ikke samme id. Test i Task 7.

---

## Filstruktur

| Fil | Ansvar |
|---|---|
| `schema.sql` (ny sektion »FULD PERSONSLETNING« lige efter `red_slet_person_preview`) | inventartabel, manifest, triggerhjælper, preview, sletning, oprindelse `person_purge` |
| `db-migrations.sql` (ny blok sidst) | samme, idempotent |
| `db-rls.sql` | REVOKE/GRANT for de nye objekter |
| `db-verify.sql` | asserts: manifest tomt, tilladelsesliste uden bogtabel, låserækkefølge, ingen `max(id)+1` |
| `tests/sql/fixtures/person-purge.sql` | syntetisk person med spor på alle inventarsteder + naboer |
| `tests/sql/test-person-purge.sql` | SQL-testene (Task 1-7) |
| `tests/sql/test-person-purge.sh` | frisk base + opgradering fra base-commit, byte-ens funktionskroppe/ACL, samtidighed |
| `.github/workflows/ci.yml` | nyt trin i jobbet med `test-6e2-*` |
| `web/src/data/personPurge.ts` (+ `__tests__`) | preview-læsning og klient-orkestrering (DB først, Storage bagefter) |
| `web/src/components/SletHeltDialog.tsx` (+ test) | knap, forhåndsvisning, bekræftelse med id + navn |
| `web/src/Redaktion.tsx` | tilslutning af dialogen ved personens slette-handling |
| `docs/runbooks/personsletning-prod.md` | prod-ceremoni og første brug (1791) |

---

### Task 1: Sletteinventaret og katalogvagten

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`
- Create: `tests/sql/test-person-purge.sql`, `tests/sql/test-person-purge.sh`, `tests/sql/fixtures/person-purge.sql`
- Modify: `.github/workflows/ci.yml` (trin efter »Koordinat-RPC · signaturændring …«: `bash tests/sql/test-person-purge.sh ciperson_purge 81d36706`)

**Interfaces:**
- Produces: tabel `private.person_purge_sted(sted text PRIMARY KEY, tabel regclass NOT NULL, pk_cols text[] NOT NULL, vaelg_sql text NOT NULL, fase int NOT NULL, append_only boolean NOT NULL, kategori text NOT NULL CHECK (kategori IN ('kerne','formidling','journal','log','identitet','promotion','familie','historik')), kan_ikke_forekomme text)`. `vaelg_sql` er en SELECT med `$1::bigint` = person-id, der returnerer én kolonne `pk jsonb` (rækkens pk som objekt). `fase` = sletteorden (lavest først).
- Produces: `private.person_purge_raekker(p_person_id bigint) RETURNS TABLE(sted text, tabel regclass, pk jsonb)` — kører alle `vaelg_sql` (læse-kun).
- Produces: `private.person_purge_kandidatkolonner() RETURNS TABLE(tabel regclass, kolonne text, art text)` — katalogscan: FK mod `public.person(id)`, kolonnepar `*_type`/`*_id` hvor typen kan være `'person'`, og jsonb-kolonner med kendte nøgler (`person_id`, `canonical_person_id`, `candidate_person_id`, `partner_ids`).

- [ ] **Step 1: Skriv de fejlende tests** i `tests/sql/test-person-purge.sql` (DO-blokke, `RAISE EXCEPTION` ved fejl, `RAISE NOTICE 'OK <navn>'` ved succes):
  - `inventar_daekker_katalog`: hver række i `person_purge_kandidatkolonner()` matches af mindst ét inventarsted (samme tabel); fejl lister de umatchede.
  - `vagt_ukendt_kolonne`: opret midlertidig tabel `public.tmp_purge_vagt(id int, person_id bigint REFERENCES public.person(id))`, assert at vagten nu fejler med tabellens navn; drop tabellen.
  - `inventar_ingen_bogtabel`: ingen række har `tabel` i Global Constraints' bogliste.
  - `fixture_daekker_inventar`: efter `\i tests/sql/fixtures/person-purge.sql` returnerer `person_purge_raekker(-987654700)` mindst én række for hvert sted, hvor `kan_ikke_forekomme IS NULL`.
- [ ] **Step 2: Kør og se dem fejle:** `bash tests/sql/test-person-purge.sh t_purge_t1` → FAIL `relation "private.person_purge_sted" does not exist`.
- [ ] **Step 3: Implementér** tabel, de to funktioner og inventarets rækker for alle steder S1-S58 fra kortlægningen (`scratchpad/purge/kortlaegning.md` medfølger i briefen) plus `identity_control_parent_event` (M5). Hvert sted, der ikke kan forekomme for en person, får en `kan_ikke_forekomme`-begrundelse. Byg fixturen: person `-987654700` (»Testperson Purge«) med spor på alle øvrige steder, en ægtefælle `-987654701`, et barn `-987654702`, en `samme_som`-nabo `-987654703`, og en tredjeperson `-987654704` uden forbindelse.
- [ ] **Step 4: Kør igen:** samme kommando → `OK inventar_daekker_katalog` … `OK fixture_daekker_inventar`, `FRISK_OK`, `UPGRADE_OK`.
- [ ] **Step 5: Commit** `feat(sletning): sletteinventar og katalogvagt for personspor`.

### Task 2: Manifest og kontrolleret løft af append-only (K1)

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`

**Interfaces:**
- Consumes: `private.person_purge_sted` (Task 1).
- Produces: tabel `private.person_purge_manifest(xid xid8 NOT NULL, backend_pid int NOT NULL, person_id bigint NOT NULL, tabel regclass NOT NULL, pk jsonb NOT NULL, PRIMARY KEY (xid, backend_pid, tabel, pk))`, RLS on, ingen grants.
- Produces: `private.person_purge_tilladt(p_tabel regclass, p_row jsonb) RETURNS boolean` — sand kun hvis (`pg_current_xact_id()`, `pg_backend_pid()`, `p_tabel`, rækkens pk) står i manifestet **og** `p_tabel` er på tilladelseslisten (en konstant `ARRAY[...]::regclass[]` i funktionen, uden bogtabeller) **og** en eventuel typet person-kolonne (`canonical_person_id`, `candidate_person_id`, `person_id`) i `p_row` er lig manifestets `person_id`.
- Modifies: DELETE-grenen i `private.reject_evidence_mutation`, `reject_interpretation_predicate_mutation`, `reject_narrative_publication_event_mutation`, `reject_narrative_record_cutover_receipt_mutation`, `reject_reimport_case_event_mutation`, `reject_reimport_writer_mutation` og øvrige append-only-funktioner, som inventarets `append_only`-steder bruger: `IF TG_OP='DELETE' AND private.person_purge_tilladt(TG_RELID::regclass, to_jsonb(OLD)) THEN RETURN OLD; END IF;` før den eksisterende afvisning. UPDATE-grenen: kun `narrative_legacy_publication` med `NEW.latest_event_id IS NULL` og øvrige kolonner uændrede.

- [ ] **Step 1: Tests:**
  - `manifest_uden_raekke_afvises`: DELETE af en fixtures publication-event uden manifest → samme fejl som i dag.
  - `manifest_tillader_egen_raekke`: indsæt manifestrække for rækken i samme transaktion → DELETE lykkes (ROLLBACK bagefter).
  - `manifest_anden_person_afvises`: manifestrække med `person_id=-987654704` for en række, hvis `canonical_person_id=-987654700` → afvises.
  - `manifest_anden_backend`: manifestrække med `backend_pid = pg_backend_pid()+1` → afvises.
  - `bogtabel_altid_afvist`: manifestrække for en `source_record`-række → DELETE afvises.
  - `update_stadig_forbudt`: UPDATE af en publication-event med manifest → afvises.
  - `trigger_enabled`: alle append-only-triggere har `tgenabled <> 'D'`.
- [ ] **Step 2: Kør** `bash tests/sql/test-person-purge.sh t_purge_t2` → FAIL.
- [ ] **Step 3: Implementér** manifest, `person_purge_tilladt` og triggerændringerne.
- [ ] **Step 4: Kør** → alle `OK`.
- [ ] **Step 5: Commit** `feat(sletning): manifest og snævert løft af append-only`.

### Task 3: Oprindelsen `person_purge` i identitetskernen (K4)

**Files:** `schema.sql`, `db-migrations.sql`, `tests/sql/test-person-purge.sql`

**Interfaces:**
- Modifies: `private.decide_source_persona_identity` — ny gren `ELSIF p_origin='person_purge'`: kræver `p_decision_status='rejected'`, `p_canonical_person_id IS NULL`, `p_evidence = '{"reason":"not_a_person"}'::jsonb`, ellers `EVIDENCE_PERSON_PURGE_SHAPE`. Gyldig kun når `current_setting('app.person_purge_xid', true) = pg_current_xact_id()::text` (sat af Task 5's funktion).
- Modifies: `red_source_persona_queue` viser `evidence->>'reason'` = `not_a_person` som »ikke en person« (kun label i svaret; ingen strukturændring).

- [ ] **Step 1: Tests:** `purge_oprindelse_form` (forkert evidence/status/person-id → `EVIDENCE_PERSON_PURGE_SHAPE`); `purge_oprindelse_kun_i_sletning` (uden `app.person_purge_xid` → afvises); `purge_afgoerelse_spaerrer_genoprettelse` (efter en `person_purge`-afgørelse v1 afviser `person_create` og `relation_person_create` personaen).
- [ ] **Step 2: Kør** → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** → `OK`.
- [ ] **Step 5: Commit** `feat(sletning): identitetsoprindelsen person_purge (»ikke en person«)`.

### Task 4: Forhåndsvisningen

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`

**Interfaces:**
- Consumes: `private.person_purge_raekker` (Task 1).
- Produces: `public.red_slet_person_helt_preview(p_person_id bigint) RETURNS jsonb` med nøglerne: `person_id`, `navn` (visningsnavn), `steder` (objekt sted → sorteret liste af pk), `familier_slettes`, `familier_bevares`, `vielser_staar` (fact-id'er), `samme_som_komponent` (person-id'er), `forældes` (`{narrativer:[…], bindinger:[…]}`, §6.5), `storage` (`[{bucket, sti}]`), `blokeringer` (liste af `{art, detalje}` med art ∈ `link_i_tekst`, `anden_promotion`, `aaben_koersel`, `samme_som_knudepunkt`), `levende_bruger` (boolean), `sha256` (over alt det øvrige, kanonisk jsonb-tekst).
- Produces: `private.person_purge_familieplan(p_person_id bigint) RETURNS TABLE(family_id bigint, handling text)` — `slet` når der efter sletningen er ≤1 partner og 0 børn, ellers `bevar` (§6.4).

- [ ] **Step 1: Tests** (hver blokering oprettes i testens egen transaktion og rulles tilbage, så fixturen forbliver sletbar i Task 5):
  - `preview_rollegate_foerst`: som anon og som medlem → `Kun redaktion` også for et ikke-eksisterende id (ingen forskel i fejl).
  - `preview_familier`: fixturens dubletfamilie (personen + ægtefælle, ingen børn) i `familier_slettes`; familie med barnet i `familier_bevares`, og dens vielse i `vielser_staar`.
  - `preview_blokering_link`: `[[person:-987654700|Testperson Purge]]` i hhv. tredjepersonens `narrative`, `story.tekst`, `entity_description.tekst`, `haendelse.klausul`, `suggestion` → én `link_i_tekst` pr. kolonne (skannet med `parse_mentions`).
  - `preview_blokering_knudepunkt`: to naboer forbundet kun gennem personen → `samme_som_knudepunkt`; én nabo → ingen blokering.
  - `preview_blokering_promotion`: ægtefællens `relation.marriage`-fortolkning er promoveret til den dubletfamilie, der skal slettes → `anden_promotion`.
  - `preview_blokering_aaben_koersel`: en uforseglet identitetskontrolkørsel, der omfatter personens persona → `aaben_koersel`; efter forsegling ingen blokering.
  - `preview_hash_stabil`: to kald → samme `sha256`; slet ét faktum og opret et andet (samme antal) → anden `sha256`.
- [ ] **Step 2: Kør** → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** → `OK`.
- [ ] **Step 5: Commit** `feat(sletning): forhåndsvisning med id-mængder, blokeringer og hash`.

### Task 5: Sletningen — kerne, familier, logs, identitet og promotions

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `tests/sql/test-person-purge.sql`

**Interfaces:**
- Consumes: Task 1-4.
- Produces: `public.red_slet_person_helt(p_person_id bigint, p_preview_sha256 text) RETURNS jsonb` → `{"slettet": <person_id>, "storage": [{bucket, sti}], "personas_afvist": <antal>}`.
- Forløb: rollegate → afvis ved sat `app.change_set_id` (`PURGE_FREMMED_CHANGE_SET`) → låse i Global Constraints' orden → genberegn preview, sammenlign hash (`PURGE_PREVIEW_AENDRET`), afvis ved blokeringer (`PURGE_BLOKERET: <art>`) → sæt `app.person_purge_xid` → skriv manifestet ud fra `person_purge_raekker` + familieplanens rækker → `UPDATE narrative_legacy_publication SET latest_event_id=NULL` for manifestets → DELETE pr. `fase` → for hver persona, hvis nuværende afgørelse pegede på personen: hele strømmen slettet via manifestet, derefter `decide_source_persona_identity(…, 'rejected', NULL, '{"reason":"not_a_person"}', 'person_purge')` med `expected_version` = 0 → tøm manifestet → nulstil `app.person_purge_xid`.
- Den præcise sletteorden (`fase`) skrives i inventaret i Task 1 og justeres her; cirklerne `interpretation_promotion` ← `relation_reopen`/`text_revision_reconciliation` og event ↔ `narrative_legacy_publication` løses i den rækkefølge.

- [ ] **Step 1: Tests:**
  - `purge_toemmer_alt`: efter sletning af `-987654700` returnerer `person_purge_raekker(-987654700)` 0 rækker, og en tælling svarende til `scratchpad/purge/count.sql` er 0 (bortset fra id i andres `change_event`).
  - `purge_andre_uaendrede`: sha256 over alle rækker for `-987654701..-987654704` (via `person_purge_raekker` for hver + deres `person`-rækker) er ens før og efter, bortset fra de forventede familieled og `samme_som`-kanter.
  - `purge_manifest_tomt`: `private.person_purge_manifest` er tom efter commit.
  - `purge_persona_ikke_en_person`: personens persona har nu præcis én event: v1, `rejected`, oprindelse `person_purge`, uden person-id.
  - `purge_andres_identitetsevent`: tredjepersonens persona havde v1 accepteret → `-987654700`, v2 accepteret → `-987654704`; efter sletningen findes kun v2, personaen peger stadig på `-987654704`, og `red_source_persona_history` returnerer uden fejl.
  - `purge_fremmed_saet`: med `app.change_set_id` sat → `PURGE_FREMMED_CHANGE_SET`, intet slettet.
  - `purge_blokeret`: link i tredjepersons tekst → `PURGE_BLOKERET: link_i_tekst`, intet slettet.
  - `purge_hash_aendret`: preview, derefter nyt faktum på personen, derefter sletning med gammel hash → `PURGE_PREVIEW_AENDRET`.
  - `purge_delt_medie`: medie koblet til personen og tredjepersonen bevares med fil; kun koblingen er væk; mediet ikke i `storage`.
- [ ] **Step 2: Kør** → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** → `OK`.
- [ ] **Step 5: Commit** `feat(sletning): red_slet_person_helt sletter personen uden rest`.

### Task 6: Historik på eventniveau og ingen egen historik (K2, K3)

**Files:** `schema.sql`, `db-migrations.sql`, inventarets `historik`-steder, `tests/sql/test-person-purge.sql`

**Interfaces:**
- Consumes: Task 5's forløb (historikken slettes sidst, efter manifestet er brugt).
- Regler (§6.3a): slet `change_event`-rækker, hvis `row_pk` er en af de slettede rækker; slet `change_set` kun når (a) ingen events tilbage, (b) ingen indgående FK, og (c) det havde events, der blev slettet nu, eller det er et fortryd-sæt (`reverterer_id`) for et sæt, der slettes; fortryd-sæt før deres mål.

- [ ] **Step 1: Tests** (fixturen skal indeholde: `red_opret_person`-sæt med navn i summary + dets fortryd-sæt; et `red_opret_union`-sæt med personen som subjekt og ægtefællens events; et fortryd-sæt for et bevaret sæt; et fælles sæt med en publication-event-FK):
  - `historik_ingen_ny`: antal `change_set`/`change_event` efter sletningen = før minus de slettede; ingen ny række (max(id) uændret).
  - `historik_navn_vaek`: ingen `change_set.summary` indeholder `'Testperson Purge'`.
  - `historik_faelles_bevaret`: union-sættet findes med ægtefællens events og uden personens.
  - `historik_fortryd_for_bevaret_urort`: fortryd-sættet for det bevarede sæt findes stadig.
  - `fortryd_efter_sletning`: `red_fortryd_change_set(<fælles sæt>)` og med `p_force=true` → enten fejl, eller ingen række med person-id `-987654700` eller den slettede familie genskabt.
- [ ] **Step 2: Kør** → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** → `OK`.
- [ ] **Step 5: Commit** `feat(sletning): historik slettes på eventniveau; sletningen logger intet`.

### Task 7: Id-genbrug og db-verify-asserts (V6, M4)

**Files:** `schema.sql` (`red_fortryd_change_set`'s fallback ved l. 9558), `db-migrations.sql`, `db-verify.sql`, `tests/sql/test-person-purge.sql`

- [ ] **Step 1: Tests:**
  - `id_genbruges_ikke`: opret syntetisk person med højeste id, slet helt, opret ny person, ny familie, nyt narrativ → ingen af dem får de slettede id'er.
  - db-verify (kør `tests/sql/run-db-verify-disposable.sql` i `test-person-purge.sh` efter en sletning) skal være grøn og indeholde asserts: `PURGE_MANIFEST_IKKE_TOMT`, `PURGE_TILLADELSESLISTE_BOGTABEL`, `IDENTITY_WRITER_LOCK_ORDER_DRIFT` også for `red_slet_person_helt(bigint,text)` (tilføj til listen ved db-verify l. 1758-1767), `ID_MAX_PLUS_ONE_ALLOCATOR` (ingen aktiv skrivefunktion indeholder `max(id)+1`/`coalesce(max(id),0)+1`, undtagen dokumenterede døde v1-veje på en navngiven liste).
- [ ] **Step 2: Kør** → FAIL.
- [ ] **Step 3: Implementér:** fallbacken bruger sekvensen (`nextval`) i stedet for `max+1`; asserts i `db-verify.sql`.
- [ ] **Step 4: Kør** → `OK` + db-verify grøn.
- [ ] **Step 5: Commit** `fix(sletning): ingen id-genbrug efter sletning; db-verify-vagter`.

### Task 8: Samtidighed og opgraderingsharness (V7)

**Files:** `tests/sql/test-person-purge.sh`

- [ ] **Step 1: Tilføj** til harnessen, efter de eksisterende trin: (a) to samtidige `red_slet_person_helt` for samme person (baggrunds-psql med `pg_sleep` i et låst øjeblik, som `test-control-model-v2.sh`) → én lykkes, den anden får `PURGE_FINDES_IKKE` eller `PURGE_PREVIEW_AENDRET`; (b) sletning mod en samtidig `red_afgoer_source_persona` på personens persona → serialiseret, ingen dødlås ud over `lock_timeout`; (c) opgradering fra base-commit `81d36706`: migrationen to gange, byte-ens funktionskroppe og ACL for alle nye/ændrede funktioner mellem frisk og opgraderet base.
- [ ] **Step 2: Kør** `bash tests/sql/test-person-purge.sh t_purge_t8` → `SAMTIDIG_OK`, `UPGRADE_OK`.
- [ ] **Step 3: Commit** `test(sletning): samtidighed og opgradering fra prods skema`.

### Task 9: Redaktion — knap, dialog og Storage

**Files:**
- Create: `web/src/data/personPurge.ts`, `web/src/data/__tests__/personPurge.test.ts`, `web/src/components/SletHeltDialog.tsx`, `web/src/components/__tests__/SletHeltDialog.test.tsx`
- Modify: `web/src/data/redaktionWrite.ts` (ny `art: 'sletPersonHelt'` → `{ fn: 'red_slet_person_helt', args: { p_person_id, p_preview_sha256 } }`), `web/src/Redaktion.tsx` (knap ved den eksisterende slette-handling, l. ~899-904), `docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md` §6.7 (rulingen fra Global Constraints)

**Interfaces:**
- Produces: `fetchSletHeltPreview(personId: string): Promise<SletHeltPreview>` (camelCase-spejl af Task 4's jsonb); `executeSletHelt(opts: { personId: string; sha256: string; dryRun: boolean; role?: string }, deps: { submit: SubmitFn; removeObjects: RemoveFn }): Promise<{ kind: 'dry-run' | 'completed'; storageAdvarsel?: string }>` — samme kontrakt som `executeUdrens`.
- `SletHeltDialog` props: `{ personId: string; onLukket(): void; onSlettet(): void }`. Viser navn + id, steder med antal, familier der slettes/bevares, blokeringer (knappen deaktiveret ved blokering), og et tekstfelt; »Slet helt« aktiveres kun, når feltet = personens id. Tekst: »Slet helt (kan ikke fortrydes)«. Siger, at det er den rå profil, ikke den sammenfoldede.

- [ ] **Step 1: Tests (vitest):** `executeSletHelt` respekterer `dryRun` (submit kaldt med `dryRun:true`, removeObjects ikke kaldt — obligatorisk regressionstest pr. ny skrivevej, PR #72); Storage-fejl giver `storageAdvarsel`, ikke fejl; dialogen: knap deaktiveret ved blokering, ved forkert id og aktiv ved korrekt id; navnet vises.
- [ ] **Step 2: Kør** `npm run test -w web -- personPurge SletHeltDialog` → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør** `npm run test -w web` og `npm run build -w web` → grøn.
- [ ] **Step 5: Commit** `feat(redaktion): »Slet helt« med forhåndsvisning og bekræftelse`.

### Task 10: Generalprøve, runner og runbook

**Files:** Create `docs/runbooks/personsletning-prod.md`; runneren `~/.private/5ab-overfoersel/42-personsletning.sh` skrives af hovedsessionen (aldrig en subagent; `~/.private` er forbudt for subagenter).

- [ ] **Step 1:** Restore det seneste prod-dump til `daa5ab_ddl_standin_<14 cifre>_purge` med `ANALYZE` (planner-statistik); kør `db-migrations.sql` to gange og `db-rls.sql`.
- [ ] **Step 2:** Som redaktør på kopien: preview og sletning af 1791; mål tid for begge (krav: under `authenticated`-rollens `statement_timeout`); kør `count.sql` for 1791 → 0 overalt bortset fra id i andres historik; hash over alle ikke-slettede rækker i berørte tabeller før/efter ens; manifest tomt; ingen ny historikrække.
- [ ] **Step 3:** Hele `db-verify.sql` grøn på kopien efter sletningen.
- [ ] **Step 4:** Runbook: GO-koder, dump før, `apply-ddl`, `maal`, `fortryd-ddl` (fortryd fjerner de nye funktioner/tabeller og genskaber de gamle triggerfunktionskroppe fra snapshot), derefter projektejerens sletning af 1791 i Redaktion og færdigbevisets tjek (spec §7).
- [ ] **Step 5: Commit** `docs(sletning): runbook og generalprøvetal`.
