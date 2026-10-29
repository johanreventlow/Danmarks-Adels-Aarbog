# Trin 6a: 1939's klausuler og kildetekst-revision — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's 584 helposter får klausuler i prod gennem den fælles writer. En generel kildetekst-revision med
forældelse, drifttjek over alle bindingstyper og genkørselskontrakt bygges og bevises på en kopi af prod.

**Architecture:**
- **Basen (PR 1):** én helpost-regel, valgfri profilnøgler (`text_form`, `helpost_observation_kind`),
  tekstversioner på helpostens observation med klausulsæt bundet til version, en ny writer-operation
  `source_text_revision` og S4-åbning med `key_version 2`.
- **Scripts (PR 2):** 1939-segmenteringsregler, `raw`-ankring og revisionsmanifestet.
- **Prod:** ceremoni A (DDL) og ceremoni B (1939-klausuler). Revisionen øves kun på en stand-in.

**Tech Stack:** PostgreSQL 17 / plpgsql (`schema.sql`, `db-migrations.sql`, `db-verify.sql`), psql-testfiler i
`tests/sql/`, Python 3 + pytest (`.claude/skills/daa-extract/scripts/`), R (DBI/RPostgres) til eksport,
GitHub Actions (`.github/workflows/ci.yml`).

**Spec:** `docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md` (læs §2-§8 før hver
task; tal og navne nedenfor er derfra).

## Global Constraints

- `schema.sql` er source of truth. Hver DB-ændring står både i `schema.sql` og som en idempotent blok i
  `db-migrations.sql`. Blokken skal kunne køres to gange (CI gør det).
- Ingen editionsnavngivne funktioner, tabeller eller operationer. Editionsdata ligger kun i profiler (JSON og
  `reimport_writer_profile`-rækker).
- 2018-20 er uændret: eksisterende `reimport_writer_profile.profile_sha256`, manifester og klausul-writerens
  adfærd på enkelt-anker-poster er byte- og adfærdsidentiske.
- Nye `writer_config`-nøgler er valgfri med default: `text_form` = `folded_projection@anywhere` og
  `helpost_observation_kind` = `person_post`. Tilladte `text_form`-værdier: `raw`, `folded_projection@anywhere`,
  `folded_projection@page_header`.
- Fejlkoder (præcis tekst):
  - Helpost-reglen: `RECORD_HELPOST_AMBIGUOUS`, `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE`.
  - `raw`-kontrollen: `CLAUSE_EVIDENCE_RAW_OFFSET_MISMATCH`.
  - Revisionen: `TEXT_REVISION_BINDING_SET_DRIFT`, `TEXT_REVISION_KEY_SET_DRIFT`, `TEXT_REVISION_SPAN_MISMATCH`,
    `TEXT_REVISION_NOOP`, `TEXT_REVISION_TARGET_TYPE_UNSUPPORTED`, `TEXT_REVISION_BASE_DRIFT`.
- Forældelsens grundlag hedder præcis `source_text_revision` (`decision_evidence->>'basis'`).
- Persondata:
  - Intet script eller output viser posttekst. Målinger skriver antal, nøgler og hashes til fil.
  - `work*/`-mapper sendes aldrig til en model, og Codex-søgninger udelukker `work*/` i selve kommandoen.
- Commits: Conventional Commits med dansk beskrivelse, uden Claude-attribution, men med `Claude-Session`-linjen.
  Ét commit pr. task. Ingen push uden projektejerens ja; PR'er oprettes som draft.
- Prod: kun fra projektejerens shell, med `--jeg-mener-det` og GO-kode. Prods `statement_timeout` er 2 min. Stand-in
  øves med `ALTER DATABASE … SET statement_timeout='2min'`.
- Lokal verifikation før push: hele det berørte CI-job køres lokalt (pg-jobbet og python-jobbet), ikke kun egne
  testfiler. `test_clause_readers.py` er repo-vid.

## Review Focus

1. **2018-20 må ikke flytte sig.** Den seedede 2018-20-klausulprofils `profile_sha256` er uændret efter migrationen,
   og et `clause_evidence`-element for en 2018-20-post bygget før og efter er byte-identisk. Testes i Task 2 og
   Task 10.
2. **Revision af en post med flere klausulsæt** (4 af de 10 har sæt 2): kun det *aktuelle* sæt forældes og
   erstattes. Fortolkninger, der kun citerer et ældre, allerede `erstattet` sæt, røres ikke. Testes i Task 5.
3. **Allerede afgjorte fortolkninger:**
   - `rejected` og `superseded` springes over; `unresolved` forældes.
   - En nøgle med flere versioner forældes én gang, fra sin aktuelle version.
   - Testes i Task 4.
4. **Ukendt bindingstype:** en promotion med `target_type` uden for `assertion` og `family` på en fortolkning, der
   ville blive forældet, giver `TEXT_REVISION_TARGET_TYPE_UNSUPPORTED`, før noget skrives. Testes i Task 4.
5. **Kanttilfælde i rå 1939-tekst:**
   - Helpost, der begynder med whitespace (214 af 584).
   - Sidemarkør som første eller sidste linje.
   - To markører i én post.
   - Markør efter `;` efterfulgt af små bogstaver (ingen split).
   - Ingen gap-brud og fuld dækning. Testes i Task 9.

---

## PR 1 — database (gren `feat/trin6a-db` fra `docs/trin6a-spec`)

### Task 1: Helpost-reglen

**Files:**
- Modify: `schema.sql` (ny sektion efter `private.source_record_anchor_current`, ca. linje 836)
- Modify: `db-migrations.sql` (ny blok sidst: `-- ===== trin 6a: helpost-regel =====`)
- Create: `tests/sql/test-record-helpost.sql`
- Modify: `.github/workflows/ci.yml` (kør testen i pg-jobbet efter `schema.sql` og efter `db-migrations.sql`, samme
  sted som `test-clause-evidence-writer.sql`)

**Interfaces:**
- Produces:
  - `private.record_helpost_status(p_record_id uuid, p_helpost_kind text) RETURNS TABLE(observation_id uuid,
    occurrence_id uuid, status text)`, hvor `status` ∈ {`ok`, `none`, `ambiguous`, `outside`} og der er præcis én
    række.
  - `private.record_helpost_observation(p_record_id uuid, p_helpost_kind text) RETURNS uuid`: returnerer
    `observation_id` ved `ok`. Ved `none` eller `ambiguous` rejses `RECORD_HELPOST_AMBIGUOUS`, ved `outside`
    `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE`.
  - Begge er `STABLE SECURITY DEFINER`, `REVOKE ALL FROM PUBLIC,anon,authenticated,service_role`.

- [ ] **Step 1: Skriv testen.** Fixture i én transaktion (`BEGIN … ROLLBACK`) efter mønstret i
  `tests/sql/test-clause-evidence-schema.sql`. Fire records under kilde 3 med rendition, run og forekomster:
  - (a) ét anker, top-observation `person` → `ok`;
  - (b) helpost `person` [100,500) + to underforekomster `fact` [120,200) og `marriage` [300,450) → `ok` med
    helpostens id;
  - (c) som (b), men `fact` [480,520) → `outside`;
  - (d) to accepterede `person`-forekomster → `ambiguous`;
  - (e) kun `structural_context` → `none`.
  - Assertér også at `record_helpost_observation` rejser den rigtige kode for (c), (d) og (e).
  - Og at en 2018-20-lignende record med `person_post` og kind `person_post` giver `ok`, mens kind `person` giver
    `none`.
- [ ] **Step 2:** `psql -v ON_ERROR_STOP=1 -d <lokal testbase med schema.sql> -f tests/sql/test-record-helpost.sql`.
  Forventet: fejl, fordi funktionen ikke findes.
- [ ] **Step 3: Implementér.** Forekomster for recorden med accepteret `source_record_anchor_current`, hvis eneste
  top-observation har `observation_kind = p_helpost_kind`, er kandidater. Er der præcis én kandidat, tjekkes alle
  øvrige accepterede forekomster for samme record: `char_from >= helpost.char_from AND char_to <= helpost.char_to`.
- [ ] **Step 4:** Kør testen mod en frisk base med `schema.sql` og mod en base bygget med `db-migrations.sql` kørt
  to gange. Forventet: `PASS` (testfilens egen `RAISE NOTICE 'OK'`-mønster).
- [ ] **Step 5:** Commit `feat(db): helpost-regel for records med flere forekomster`.

### Task 2: Valgfri profilnøgler, `raw`-kontrol og klausul-writeren på helpost-reglen

**Files:**
- Modify: `schema.sql`:
  - `private.validate_reimport_writer_config` (ca. linje 3473);
  - `private.clause_write_prepare` (ca. linje 4094);
  - `private.clause_write_set` (ca. linje 4190).
- Modify: `db-migrations.sql`, samme blok som Task 1 eller en ny `-- ===== trin 6a: klausul-writer =====`.
- Modify: `tests/sql/test-clause-evidence-writer.sql`.

**Interfaces:**
- Consumes: `private.record_helpost_observation(uuid,text)` (Task 1).
- Produces:
  - `private.writer_config_text_form(p_writer_config jsonb) RETURNS text`: værdien eller
    `'folded_projection@anywhere'`.
  - `private.writer_config_helpost_kind(p_writer_config jsonb) RETURNS text`: værdien eller `'person_post'`.
  - `clause_write_prepare`'s returnerede ctx får nøglen `text_form`.
- Seeder `reimport_writer_profile`-rækken for `daa-1939-clause-evidence-v1` med `source_id` 3, `profile_version`
  `clause-evidence-v1` og et `writer_config` med:
  - `rendition_key` `daa-1939-calamari-r6-clean`, `rendition_kind` `ocr_text`, `rendition_metadata`
    `{"edition":"1939"}`;
  - `run_key_prefix` `reimport-clause-evidence-1939:`, `schema_version` `clause-evidence-manifest-v1`,
    `extractor_version` `clause-evidence-v1`, `observation_extraction_method` `clause_segment_v1`;
  - `citation_label_template` `DAA 1939 side {page_from}`, `text_form` `raw`, `helpost_observation_kind`
    `person`.
  - Rækken skrives med `WHERE EXISTS(SELECT 1 FROM public.source WHERE id=3)` og `ON CONFLICT DO NOTHING`, efter
    mønstret ved `schema.sql:3644`.

- [ ] **Step 1: Skriv tests** i `test-clause-evidence-writer.sql`:
  - `test_2018_profile_hash_unchanged`: den seedede 2018-20-profilrækkes `profile_sha256` er lig
    `private.reimport_canonical_json_sha256(writer_config)` og lig konstanten fra den nuværende
    `daa-2018-20-clause-evidence-v1.json`.
  - `test_writer_config_rejects_unknown_text_form`: `text_form = 'folded'` giver CHECK-fejl.
  - `test_1939_three_anchor_record_gets_clauses`: en fixture som Task 1 (b) med en `raw`-profil skriver klausuler
    under helposten.
  - `test_raw_offset_mismatch_rejected`: et klausul-element med `rendition_char_from = helpost.char_from +
    post_char_from + 1` giver `CLAUSE_EVIDENCE_RAW_OFFSET_MISMATCH`.
  - `test_single_anchor_2018_unchanged`: den eksisterende 2018-20-sti er uændret (eksisterende assertions
    består).
- [ ] **Step 2:** Kør. Forventet: de nye tests fejler.
- [ ] **Step 3: Implementér.**
  - Valideringen tillader de to valgfri nøgler med lukkede værdisæt.
  - `clause_write_prepare` erstatter `count(*)<>1` på ankre og top-observationer med
    `record_helpost_observation(v_record.id, writer_config_helpost_kind(v_profile.writer_config))`.
  - `clause_write_set` håndhæver ved `text_form = 'raw'`, at `rendition_char_from = parent.char_from +
    char_from` og `rendition_char_to = parent.char_from + char_to`.
- [ ] **Step 4:** Kør testfilen mod `schema.sql`-base og mod migrationsbase (to gange). Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(db): klausul-writer på helpost-regel og rå tekstform`.

### Task 3: Tekstversioner og klausulsæt bundet til version

**Files:**
- Modify: `schema.sql`:
  - `private.source_observation_text` (ca. linje 568): nye nullable kolonner;
  - `ALTER TABLE private.source_observation` (ca. linje 633): `parent_text_id`;
  - `private.validate_clause_observation` (ca. linje 655-725);
  - `private.validate_clause_set_seq` (ca. linje 15392).
- Modify: `db-migrations.sql`.
- Modify: `db-verify.sql`: den eksisterende `source_observation_text`-indsættelse (ca. linje 2440) skal fortsat
  passere; tilføj en assertion for de nye kolonner.
- Create: `tests/sql/test-source-text-version.sql`.

**Interfaces:**
- Produces:
  - Kolonner på `private.source_observation_text`: `extraction_run_id uuid NULL REFERENCES
    private.extraction_run(id)`, `method text NULL`, `evidence jsonb NULL CHECK (evidence IS NULL OR
    jsonb_typeof(evidence)='object')`.
  - `private.source_observation.parent_text_id uuid NULL REFERENCES private.source_observation_text(id)`.
    Kun klausuler må have den; for andre rejses `EVIDENCE_CLAUSE_PARENT_FORBIDDEN`.
  - `private.helpost_text_current(p_observation_id uuid) RETURNS TABLE(text_id uuid, verbatim_text text)`:
    foretrukket version (`source_observation_text_current` med `is_preferred`), ellers `(NULL, basistekst)`.
    `STABLE SECURITY DEFINER`, revoked.

- [ ] **Step 1: Skriv tests:**
  - `test_clause_on_text_version_validates_against_version`: en klausul med `parent_text_id` skåret af
    versionens tekst accepteres. Den samme klausul uden `parent_text_id` giver `EVIDENCE_CLAUSE_TEXT_MISMATCH`.
  - `test_text_version_of_other_observation_rejected`: `parent_text_id`, der tilhører en anden observation, giver
    `EVIDENCE_CLAUSE_PARENT_TEXT_INVALID`.
  - `test_mixed_text_in_set_rejected`: to klausuler i samme sæt med forskellig `parent_text_id` giver
    `EVIDENCE_CLAUSE_SET_TEXT_MIXED`.
  - `test_helpost_text_current`: uden versioner returneres basisteksten, med en foretrukken version returneres den.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3: Implementér.** `validate_clause_observation` bruger versionens tekst, når `parent_text_id` er sat:
  `post_char_to`-grænsen og delstrengskontrollen. `validate_clause_set_seq` kræver samme `parent_text_id` inden for
  ét sæt (`IS NOT DISTINCT FROM` mod en eksisterende række i sættet).
- [ ] **Step 4:** Kør testen og `tests/sql/run-db-verify-disposable.sql`. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(db): tekstversioner af helposten og klausulsæt bundet til version`.

### Task 4: Afhængighedsmængde og forældelse

**Files:**
- Modify: `schema.sql`: ny sektion efter `private.assertion_binding_current` (ca. linje 18300).
- Modify: `db-migrations.sql`.
- Create: `tests/sql/test-text-revision-dependencies.sql`.

**Interfaces:**
- Produces:
  - `private.text_revision_dependents(p_parent_observation_id uuid) RETURNS TABLE(interpretation_key uuid,
    current_id uuid, current_status text)`: aktuelle versioner af nøgler, hvis aktuelle version har et link til en
    klausul i helpostens *aktuelle* sæt, og hvis status ∉ {`rejected`,`superseded`}.
  - `private.text_revision_binding_set(p_interpretation_keys uuid[]) RETURNS TABLE(promotion_id uuid, target_type
    text, interpretation_key uuid, target_id text)`: kun *gældende* bindinger.
    - `assertion`: `private.assertion_binding_current(p.id)`.
    - `family`: `cur.id = p.interpretation_id AND cur.status='accepted' AND
      private.relation_binding_state_sha256(p.interpretation_id) = p.evidence->>'state_sha256'`.
    - Findes en promotion med anden `target_type` for nøglerne, rejses `TEXT_REVISION_TARGET_TYPE_UNSUPPORTED`.
  - `private.supersede_for_text_revision(p_interpretation_keys uuid[], p_actor uuid, p_actor_name text, p_evidence
    jsonb) RETURNS integer`: indsætter pr. nøgle en ny version med `status='superseded'`, `supersedes_id` = aktuel,
    `decision_evidence = p_evidence || {'basis':'source_text_revision'}` og samme audit-felter som
    `red_decide_interpretation`. Den kopierer alle `interpretation_observation`-links fra den aktuelle version og
    returnerer antal.

- [ ] **Step 1: Skriv tests:**
  - `test_dependents_skip_rejected_and_superseded`
  - `test_dependents_include_unresolved`
  - `test_dependents_only_current_set`: en nøgle, der kun citerer et `erstattet` sæt 1, er ikke med.
  - `test_binding_set_assertion_and_family`: en fixture med én gældende assertion-promotion, én gældende
    family-promotion og én family-promotion med forældet `state_sha256`. Resultatet er præcis de to første.
  - `test_binding_set_unknown_target_type_raises`
  - `test_supersede_copies_links_and_sets_basis`: den nye version har samme link-mængde, og `decision_evidence->>
    'basis'` er `source_text_revision`. `assertion_binding_current` er false efter.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3: Implementér.** Før indsættelse låses nøglernes aktuelle rækker i `interpretation_key`-orden (`FOR
  UPDATE`). Status-overgangen tillades kun gennem denne funktion. `red_decide_interpretation` er uændret.
- [ ] **Step 4:** Kør. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(db): afhængighedsmængde og forældelse ved kildetekst-revision`.

### Task 5: Writer-operationen `source_text_revision`

**Files:**
- Modify: `schema.sql`:
  - ny `private.write_source_text_revision` og `public.red_apply_reimport_source_text_revision` efter
    `write_clause_revision` (ca. linje 4312);
  - `private.validate_reimport_authorization_payload` (ca. linje 3689): `expected_counts.source_text_revision`.
- Modify: `db-migrations.sql`: blok med `PERFORM private.ensure_reimport_operations(ARRAY['source_text_revision'])`
  efter mønstret ved `db-migrations.sql:18038`.
- Create: `tests/sql/test-source-text-revision.sql`.
- Modify: `.github/workflows/ci.yml`.

**Interfaces:**
- Consumes: Task 1-4 og `private.clause_write_prepare` / `private.clause_write_set`.
- Produces:
  - `public.red_apply_reimport_source_text_revision(p_batch_id uuid, p_element_id text, p_payload jsonb) RETURNS
    jsonb`. GRANT til `authenticated`, ellers revoked.
  - Payloadens lukkede nøglesæt: `source_record_key`, `rendition_content_sha256`, `projection_rule`,
    `before_text_sha256`, `verbatim_text`, `after_text_sha256`, `replaces_clause_set_seq`,
    `replaces_clause_set_sha256`, `clause_rules_version`, `segmenter_version`, `ledger_sha256`, `gap_charset`,
    `clauses`, `expected_superseded_keys` (sorteret array af uuid-strenge), `expected_binding_loss` (sorteret array
    af `{promotion_id, target_type}`).
  - Kvittering (returværdi og `reimport_event.payload`-tillæg): `text_id`, `clause_set_seq`, `superseded_keys`,
    `binding_loss` (`promotion_id`, `target_type`, `interpretation_key`, `target_id`), `parties_dropped`
    (`interpretation_party_current`-rækker for de forældede nøgler før forældelsen), `personas_on_old_set`
    (persona-id'er, hvis mention ligger på en klausul i det gamle sæt), `before_clause_set_sha256` og
    `after_clause_set_sha256`.

Rækkefølgen i writeren (spec §4.4) er bindende:
1. prepare;
2. tekst og kontroller;
3. afhængigheder, drift og bindingsmængde;
4. `source_observation_text`-række (foretrukken, proveniens);
5. `supersede_for_text_revision`;
6. nyt sæt via `clause_write_set` med `parent_text_id`;
7. `erstattet` på det gamle sæt;
8. `SET CONSTRAINTS … IMMEDIATE`;
9. `reimport_event`.

- [ ] **Step 1: Skriv tests** med en 2018-20-lignende fixture: en post med fortolkninger, én assertion-binding og
  én family-binding.
  - `test_revision_happy_path`:
    - én tekstversion med samme spænd og rendition;
    - nyt sæt `seq+1` med `parent_text_id`;
    - gamle klausuler `erstattet`;
    - nøglerne `superseded`;
    - kvitteringens `binding_loss` er lig `expected_binding_loss`;
    - `helpost_text_current` returnerer den nye tekst.
  - `test_revision_binding_drift_assertion` og `test_revision_binding_drift_family`: én ekstra eller manglende
    binding i den forventede mængde giver `TEXT_REVISION_BINDING_SET_DRIFT`, og intet er skrevet.
  - `test_revision_key_drift`: giver `TEXT_REVISION_KEY_SET_DRIFT`.
  - `test_revision_noop`: `after_text_sha256 = before_text_sha256` giver `TEXT_REVISION_NOOP`.
  - `test_revision_base_drift`: forkert `before_text_sha256` eller forkert `replaces_clause_set_sha256` giver
    `TEXT_REVISION_BASE_DRIFT`.
  - `test_revision_span_mismatch`: payloaden bærer intet spænd. Writeren sætter selv tekstversionens
    `rendition_id`, `char_from` og `char_to` fra helpost-observationen. En `rendition_content_sha256`, der ikke er
    observationens renditions, giver `TEXT_REVISION_SPAN_MISMATCH`. At teksten er projektionen af netop det spænd,
    bevises på manifest-siden (Task 12), fordi basen ikke har renditionsteksten.
  - `test_revision_narrative_state_unchanged`: `private.narrative_publication_state(person, source, record_key)`
    hashes før og efter, og de er ens.
  - `test_revision_multi_set_post`: en post med sæt 1 (`erstattet`, en nøgle citerer kun den) og sæt 2 (aktuelt).
    Kun sæt 2-nøgler forældes.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3: Implementér** efter rækkefølgen ovenfor. Brug `clause_write_prepare(…, 'source_text_revision')`,
  udvidet med operationen og dens nøglesæt. Writeren læser og hasher den nuværende tekst via
  `helpost_text_current`.
- [ ] **Step 4:** Kør testen og hele pg-jobbets testliste lokalt. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(db): writer-operation for kildetekst-revision med forældelse og drifttjek`.

### Task 6: Genkørselskontrakt: S4-åbning og `key_version 2`

**Files:**
- Modify: `schema.sql`: `private.write_interpretation_proposal` (ca. linje 4500-4620) og ny
  `private.interpretation_proposal_key_material_v2` ved siden af v1 (ca. linje 4409).
- Modify: `db-migrations.sql`.
- Modify: `tests/sql/test-interpretation-proposal.sql`.

**Interfaces:**
- Produces:
  - `private.interpretation_proposal_key_material_v2(p_source_id bigint, p_record_key text, p_predicate text,
    p_cited_clauses jsonb, p_value jsonb, p_text_sha256 text) RETURNS text`: som v1 med `'key_version',2` og
    `'text_sha256',p_text_sha256`.
  - v1's signatur og krop er uændrede.
- Regler:
  - S4 tillader et nyt forslag for recorden, hvis alle fortolkningsnøgler skabt af tidligere
    `interpretation_proposal`-events for recorden har aktuel status `superseded` med `decision_evidence->>'basis' =
    'source_text_revision'`.
  - Nøglen bruger v2 med hashen af `helpost_text_current(...).verbatim_text`, når helposten har en foretrukken
    tekstversion. Ellers bruges v1.
  - Writerens helpost-valg ændres *ikke* her; det sker i 6c.

- [ ] **Step 1: Skriv tests:**
  - `test_s4_still_blocks_unrevised_post`
  - `test_s4_opens_after_text_revision`: genbrug Task 5's fixture. Forslaget med samme ordinal og værdi accepteres,
    og dets `interpretation_key` ≠ den forældede.
  - `test_s4_blocks_if_any_key_not_superseded_by_revision`: én nøgle `rejected` i stedet giver
    `REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`.
  - `test_key_v1_unchanged`: et kendt v1-input giver samme streng som før.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** Kør. Forventet: `PASS`. Tilføj en opgraderingstest i
  `tests/sql/evidence-hardening-pre-migration.sql`-mønstret: en base med prods gamle funktionskrop, migreret, giver
  samme v1-nøgle for et kendt input (memory: signaturændring kræver opgraderingstest).
- [ ] **Step 5:** Commit `feat(db): genkørsel efter kildetekst-revision (S4-åbning, nøgle v2)`.

### Task 7: Læsere af helposttekst i basen

**Files:**
- Create: `docs/superpowers/reviews/6a-helpost-tekstlaesere.md`: inventaret.
- Modify: `schema.sql` / `db-migrations.sql`: de DB-læsere, inventaret flytter.

**Interfaces:**
- Consumes: `private.helpost_text_current(uuid)` (Task 3).

- [ ] **Step 1: Byg inventaret.**
  - Søg: `git grep -n "verbatim_text" -- schema.sql ':!work*'`, `git grep -ln "verbatim_text" --
    '.claude/skills/daa-extract/scripts' ':!work*'` og `export_legacy_migration_candidates_helpers.R`.
  - Klassificér hver forekomst som én af: helpost (observation), helpost (forekomst), klausul, mention, andet.
  - For hver helpost-læser: flyt til `helpost_text_current` eller begrund binding til basisteksten. Kendte (spec
    §4.4): `clause_write_prepare`, `clause_write_set`, `validate_clause_observation`, `clause_set_sha256`,
    `write_interpretation_proposal`, `migrate_legacy_narrative_record`, `red_source_persona_detail`,
    `relation_persona_v3_input`, `clause_evidence_projection.sql`, `interpretation_proposal_projection.sql`,
    `export_43b_runner_input.R` og 149b-komparatoren.
- [ ] **Step 2:** Skriv en test pr. flyttet DB-læser i `tests/sql/test-source-text-revision.sql`: efter en revision
  ser læseren den nye tekst. Kør. Forventet: fejl.
- [ ] **Step 3:** Flyt DB-læserne.
- [ ] **Step 4:** Kør hele pg-jobbet lokalt. Forventet: `PASS`.
- [ ] **Step 5:** Commit `refactor(db): helpost-tekst læses gennem én funktion`.

### Task 8: PR 1 samlet

- [ ] **Step 1:** Opgraderingstest: restore prods skema (fra den seneste stand-in) til en ny lokal base, kør
  `db-migrations.sql` to gange og kør alle nye testfiler. Forventet: `PASS`.
- [ ] **Step 2:** `db-verify.sql` via `tests/sql/run-db-verify-disposable.sql`. Forventet: `PASS`.
- [ ] **Step 3:** Kør hele CI-jobbet `pg` lokalt (alle psql-linjer i `ci.yml`). Forventet: grøn.
- [ ] **Step 4:** Commit eventuelle rettelser. Push og draft-PR først efter projektejerens ja.

---

## PR 2 — scripts og profiler (gren `feat/trin6a-scripts`)

### Task 9: 1939-segmenteringsregler

**Files:**
- Modify:
  - `.claude/skills/daa-extract/scripts/clause_segment.py` (`_split_points`, `segment_clauses`);
  - `.claude/skills/daa-extract/scripts/evidence_extract.py` (regel-validering ca. linje 83 og 125);
  - `.claude/skills/daa-extract/references/extraction-profiles.json` (profil `daa-1939-v1` → version `1.1.0`).
- Test:
  - `.claude/skills/daa-extract/scripts/test_clause_segment.py`;
  - `.claude/skills/daa-extract/scripts/test_evidence_extract.py`.

**Interfaces:**
- Valgfri regelnøgler: `page_marker_pattern` (regex for én hel linje) og `possible_layout_line_pattern`. Uden
  nøglerne er adfærden uændret.
- Nye flag: `page_marker_in_clause` og `possible_layout_line`.
- `daa-1939-v1` får nøglerne `clause_rules` (`version` `clause-rules-1939-v1`, ellers v3 +
  `gap_charset [" ","\n"]`, terminatorerne `". "`, `"; "`, `".\n"` og `";\n"`, `page_marker_pattern
  ^###\s*PAGE\s+\d+\s*###\s*$` og `possible_layout_line_pattern` = `PAGE_NOISE_1939_RE`'s mønster), `text_form`
  `raw` og `helpost_observation_kind` `person`.

- [ ] **Step 1: Skriv tests** med syntetiske tekster (ingen bogtekst):
  - `test_newline_terminator_splits`: `"f. 1700.\nGift m. X."` giver to klausuler.
  - `test_page_marker_mid_sentence_stays_in_clause`: `"boede i Ro-\n\n### PAGE 0036 ###\nstock † 1700."` giver én
    klausul med flaget `page_marker_in_clause`.
  - `test_page_marker_after_terminator_splits_before_marker`: `"† 1726.\n\n### PAGE 0036 ###\nGift m. X."` giver to
    klausuler; den anden begynder med `### PAGE` og har flaget.
  - `test_page_marker_after_semicolon_lowercase_no_split`
  - `test_two_markers_one_post`
  - `test_leading_whitespace_post_full_coverage`: summen af spans dækker hele teksten, og gaps indeholder kun
    `gap_charset`.
  - `test_possible_layout_line_flagged`: `"…\n1726.\n…"` flagges, men forsvinder ikke.
  - `test_2018_rules_unchanged`: et eksisterende fixture-output er byte-identisk.
- [ ] **Step 2:** `pytest .claude/skills/daa-extract/scripts/test_clause_segment.py -q`. Forventet: fejl.
- [ ] **Step 3:** Implementér. I `_split_points` sker følgende efter whitespace-spring: matcher linjen ved
  `next_start` `page_marker_pattern`, hoppes linjen og efterfølgende whitespace over, *kun* når næste tegn
  vurderes. Splitpunktet bliver ved `next_start`.
- [ ] **Step 4: Forkortelseslisten.**
  - Kør den tørre kørsel (§2.2) mod en lokal eksport (Task 11's eksport, `--helpost-kind person`) i en 0700-mappe
    uden `work`-komponent.
  - Tag tokens med ≥3 forekomster fra `unknown_abbreviation_tokens`, som er forkortelser (ikke ordenstal eller
    initialer, der dækkes af mønstrene), ind i `non_terminal_abbreviations`.
  - Notér før/efter-tal for flag i testfilens docstring (kun antal).
- [ ] **Step 5:** Kør pytest for hele scripts-mappen. Forventet: `PASS`.
- [ ] **Step 6:** Commit `feat(daa-extract): 1939-klausulregler med sidemarkør og linjeskift`.

### Task 10: `raw`-ankring, profilvalidering og 1939-klausulprofil

**Files:**
- Modify:
  - `.claude/skills/daa-extract/scripts/build_clause_evidence_manifest.py` (`_operations`, `_anchor`);
  - `.claude/skills/daa-extract/scripts/reimport_profile.py` (`WRITER_CONFIG_KEYS` ca. linje 43 og validering ca.
    linje 147-160);
  - `.claude/skills/daa-extract/scripts/clause_ledger.py` (summary: »ingen helpost«).
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-1939-clause-evidence-v1.json`
  (`expected_counts.clause_evidence` 584; `writer_config` identisk med Task 2's seedede række).
- Test:
  - `.claude/skills/daa-extract/scripts/test_build_clause_evidence_manifest.py`;
  - `.claude/skills/daa-extract/scripts/test_reimport_profile.py` (opret, hvis den ikke findes).

**Interfaces:**
- `reimport_profile.load_profile` accepterer de valgfri nøgler `text_form` og `helpost_observation_kind`.
  `rendition_metadata` kræver `edition`. `pdf_sha256` og `pdftotext_version` kræves kun, når `rendition_kind ==
  'pdf_text_layer'`.
- `build_clause_evidence_manifest`:
  - Ved `text_form == 'raw'` er projektionen identitet: `projected = rendition`, `offsets = range(len)`, og
    `rendition_projection_sha256 = sha256(rendition)`.
  - Ankret kræver `sha256(rendition[pcf:pct]) == parent_verbatim_sha256`.

- [ ] **Step 1: Skriv tests:**
  - `test_raw_manifest_offsets_are_identity`
  - `test_raw_anchor_hash_mismatch_fails`
  - `test_2018_manifest_byte_identical`: byg 2018-20-manifestet fra testfixturen før og efter; sha256 er ens.
  - `test_1939_profile_hash_matches_db_seed`: profilens `profile_sha256` er lig den kanoniske sha af
    `writer_config`, og strengen er kopieret i Task 2's migration.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** Kør pytest for hele scripts-mappen. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(daa-extract): rå tekstform i klausul-manifestet og 1939-profil`.

### Task 11: Eksporten vælger helposten i basen

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/export_clause_source_texts.R`.
- Test: `tests/integration/test-reimport-clause-evidence.R` (udvid).

**Interfaces:**
- Consumes: `private.record_helpost_status(uuid,text)` (Task 1).
- Nyt obligatorisk flag `--helpost-kind`.
- Eksporten returnerer én række pr. record med `status='ok'` (tekst plus `text_id` fra `helpost_text_current`).
  Indeksfilen får en `no_helpost`-liste med `record_key` og status for resten.
- `ambiguous` og `outside` stopper eksporten (`EXPORT_HELPOST_INVALID`). `none` tælles.

- [ ] **Step 1: Skriv test** mod en lokal fixture-base med Task 1's former: 3 `ok`-rækker og 1 i `no_helpost`. En
  `outside`-record giver `EXPORT_HELPOST_INVALID`.
- [ ] **Step 2:** Kør `Rscript tests/integration/test-reimport-clause-evidence.R`. Forventet: fejl.
- [ ] **Step 3:** Implementér. Behold `REPEATABLE READ READ ONLY` og `ROLLBACK`.
- [ ] **Step 4:** Kør igen og kør `pytest …/test_clause_readers.py`. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(daa-extract): klausuleksport vælger helpost via basens regel`.

### Task 12: Revisionsmanifestet

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_source_text_revision_manifest.py`.
- Create: `.claude/skills/daa-extract/scripts/source_text_revision_dependencies.sql` (læse-kun). Den returnerer pr.
  record `before_text_sha256`, aktuelt sæt og sæt-sha, `expected_superseded_keys` (via
  `private.text_revision_dependents`) og `expected_binding_loss` (via `private.text_revision_binding_set`). Ingen
  tekst.
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-source-text-revision-v1.json`
  (`source_id` 1; `text_form` `folded_projection@page_header`; `expected_counts.source_text_revision` 10).
- Modify: `.claude/skills/daa-extract/scripts/test_clause_readers.py` (ALLOWED + begrundelse for de nye filer).
- Test: `.claude/skills/daa-extract/scripts/test_build_source_text_revision_manifest.py`.

**Interfaces:**
- CLI: `--profile --rendition --texts --dependencies --output`.
- Den nye tekst er `segment.py`'s post-tekst for recorden under segmentprofilen `2018-20-v2` (støjregel
  `page_header`).
- **Forudsætninger** (fejler lukket):
  - v1-postteksten (`2018-20`) for recorden har sha lig `before_text_sha256` (`TEXT_REVISION_V1_MISMATCH`);
  - v2-postens spænd er lig helpostens `char_from` og `char_to` (`TEXT_REVISION_SPAN_MISMATCH`);
  - v2-teksten ≠ v1-teksten.
- En record, der fejler spænd-forudsætningen, kommer i manifestets `dispositions` med koden `span_outside` og ikke
  i operationerne. Det gælder I-84.
- Klausulerne til payloaden segmenteres med `clause-rules-2018-20-v3` på den nye tekst. Ankringen sker med
  `project_rendition(noise_rule='page_header')`.

- [ ] **Step 1: Skriv tests** med syntetisk rendition og to poster:
  - `test_same_span_revision_emitted`
  - `test_span_outside_goes_to_dispositions`
  - `test_v1_mismatch_fails`
  - `test_no_text_in_index_output`: indeksfilen indeholder ingen `verbatim_text`.
  - `test_expected_sets_sorted_and_copied`
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** Kør pytest for hele mappen. Forventet: `PASS`.
- [ ] **Step 5:** Commit `feat(daa-extract): manifest for kildetekst-revision`.

### Task 13: Script-læsere af helposttekst

**Files:** de script-læsere, Task 7's inventar har markeret til flytning: `export_43b_runner_input.R`,
`clause_evidence_projection.sql`, `interpretation_proposal_projection.sql`,
`export_legacy_migration_candidates_helpers.R` / `build_legacy_migration_manifest.py`.

- [ ] **Step 1:** Pr. fil: en test, der efter en revision i en lokal fixture-base ser den nye tekst (R-integration
  eller pytest efter filens eksisterende testmønster). Kør. Forventet: fejl.
- [ ] **Step 2:** Flyt læseren til `private.helpost_text_current`.
- [ ] **Step 3:** Kør hele python- og R-jobbet lokalt (`Rscript run-tests.R` og pytest). Forventet: `PASS`.
- [ ] **Step 4:** Commit `refactor(daa-extract): helpost-tekst læses gennem basens funktion`.

---

## Øvelse og prod

### Task 14: Stand-in-øvelse af ceremoni A og B

**Files:**
- Create: `docs/runbooks/trin6a-prod.md`. Ceremoni A følger `docs/runbooks/5c2-b11-prod.md`. Ceremoni B følger
  `docs/runbooks/clause-evidence-prod-apply.md` med 1939-profilen.
- Create (privat, uden for repo): `~/.private/6a/` med `maal`, `go`, `dump` og `apply` efter `~/.private/5c2/`.

- [ ] **Step 1:**
  - Opret en stand-in fra det seneste prod-dump: ICU-locale (memory `prod-icu-lokale-baser-libc`), `ALTER
    DATABASE … SET statement_timeout='2min'` og `ANALYZE` efter restore.
  - Kør ceremoni A. Forventet: `DDL_6A_OK`, varighed noteret.
  - Mål forholdet mellem prod og stand-in på én fælles læseforespørgsel før og efter.
- [ ] **Step 2: Byg 1939-manifestet** fra eksporten (`--helpost-kind person`) og `work_1939_stamtavle/`-renditionen
  (hash `020123a3…6da37`). Forventet:
  - 584 operationer;
  - 8 i `no_helpost`;
  - 0 gap-brud.
- [ ] **Step 3: Røgtest.** 20 tilfældige poster med en seed noteret i runbooken, blandt posterne om personer død
  før 1800 (årstal i rå tekst < 1800 og `†`). Klausulgrænserne gennemses for oplagte fejlsnit. Fund: ret reglerne
  (Task 9), byg igen, gentag. Ingen tekst i noter; kun post-nøgle og fejltype.
- [ ] **Step 4: Ceremoni B** på stand-in'en (authorize → preflight → apply).
  - Forventet: `APPLY_OK`.
  - Kontrollér `count(DISTINCT parent_observation_id)` = 584 for kilde 3's klausuler og dispositionsfordelingen.
  - Kontrollér, at 2018-20's klausultal er uændret.
- [ ] **Step 5:** Commit runbooken `docs(runbooks): trin 6a ceremoni A og B`.

### Task 15: Stand-in-bevis for kildetekst-revisionen (anvendes ikke i prod)

**Files:**
- Create: `docs/evidensbaseret-genimport/kildetekst-revision-6a-bevis.md`.

- [ ] **Step 1:** På en ny stand-in med ceremoni A anvendt: kør `source_text_revision_dependencies.sql` for 2018-20's
  11 A6b-poster og byg manifestet. Forventet:
  - 10 operationer;
  - `dispositions` = `[I-84: span_outside]`;
  - forventede nøgler = 58 (ellers notér det målte tal og hvorfor);
  - `expected_binding_loss` = 16 (9 `assertion` og 7 `family`).
- [ ] **Step 2:** Før anvendelsen tages:
  - `narrative_publication_state`-hash for de 10;
  - `public_person_facts`-rækker for de berørte personer (antal pr. provenance);
  - `public_family_sources`-rækker for de 7 familier.
- [ ] **Step 3:** Anvend (ét kald pr. post med prods tidsgrænse). Forventet:
  - 10 kvitteringer, hvor `binding_loss`-foreningsmængden = de 16;
  - narrativ-hashene er uændrede;
  - 9 fakta er skiftet til »fra den oprindelige import«, og de 7 familiekilder er væk;
  - komparatoren gennem `helpost_text_current` viser ikke de 9 bundne poster som afvigende.
- [ ] **Step 4:** Genkørselsprøve på én post: et syntetisk forslag med samme ordinal og værdi accepteres med v2-nøgle
  (rulles tilbage).
- [ ] **Step 5:** Skriv beviset (kun antal og nøgler). Commit `docs(genimport): bevis for kildetekst-revision på
  stand-in`.

### Task 16: Codex-diffreview, prod og status

- [ ] **Step 1:** Codex-runde på diffen af PR 1 + PR 2 (`gpt-6.1-sol`, Opus dømmer fundene). Søgekommandoerne
  udelukker `work*/`.
- [ ] **Step 2:** Projektejerens ja → push og draft-PR'er. PR 1 merges før PR 2.
- [ ] **Step 3:** Ceremoni A og B i prod fra projektejerens shell efter `docs/runbooks/trin6a-prod.md`: dump med
  B1-disciplin og GO-koder. Bagefter `NOTIFY pgrst` og `get_advisors`.
- [ ] **Step 4:** Opdatér:
  - `status.md`: 1939-rækken »Klausuler« bliver `produktionsverificeret` med dato. Revisionen og genkørslen bliver
    `isoleret implementeret`.
  - `docs/database-current-state.md`.
  - `docs/changelog.md`.
  - Commit `docs(status): 1939-klausuler i prod (trin 6a)`.
