# Trin 6b: 1939's identitet — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's 555 helposter med publiceret narrativbinding får en persona i prod gennem den fælles writer (ceremoni
B). Når 6c's runner har lagt navn og årstal som fortolkninger, får de 553 nye ikke-staged en identitet bundet til C3's
binding, kontrolleret af generatoren (ceremoni C).

**Architecture:**
- **Basen (PR 1):**
  - to nye elementoperationer i reimport-writeren: `publication_persona` (B) og `publication_identity` (C);
  - en ny strukturel oprindelse `publication_binding` i `private.decide_source_persona_identity`;
  - én SQL-klassifikator for kontrollens udfald, som writeren, arket og kalibreringen alle bruger;
  - webkø-filter og redaktørvagt for personas, der venter på kontrol;
  - årstalsreserve fra `date_raw` i generatorens input;
  - en dedikeret fortrydelse for C (B fortrydes ved restore af dumpet, fordi personas er append-only).
- **Scripts (PR 2):** generatoren udskriver hvert klyngemedlems egen score; kalibrering mod 2018-20; B's manifest
  og målingen; C's kortark og manifest.
- **Prod:** ceremoni A (DDL) og B (personas) nu. Ceremoni C er beskrevet her, men **blokeret**, indtil 6c's runner
  har kørt i prod (spec §4.3, §5).

**Tech Stack:** PostgreSQL 17 / plpgsql (`schema.sql`, `db-migrations.sql`, `db-verify.sql`), psql-testfiler i
`tests/sql/`, R-samtidighedstests i `tests/integration/`, TypeScript + vitest (`packages/identity-candidates`),
Python 3 + pytest (`.claude/skills/daa-extract/scripts/`), GitHub Actions (`.github/workflows/ci.yml`).

**Spec:** `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` (godkendt 2026-10-31). Læs §2-§7 før hver
task; tal og navne nedenfor er derfra. Planen præciserer fire punkter i specen (§4.2 id'er og kø, §4.3 pkt. 4,
§4.3.1 S/F/U); de er rettet i specen i samme commit som planen.

## Global Constraints

- `schema.sql` er source of truth. Hver DB-ændring står både i `schema.sql` og som en idempotent blok i
  `db-migrations.sql`. Blokken skal kunne køres to gange (CI gør det). Første blok hedder
  `-- ===== trin 6b: publication-operationer =====`; alle 6b-blokke ligger efter den, sidst i filen.
- Ingen editionsnavngivne funktioner, tabeller eller operationer. Editionsdata ligger kun i profilrækker og manifester.
- 2018-20 er uændret: eksisterende `reimport_writer_profile.profile_sha256`, 2018-20's identiteter og 5a's
  kalibrering mod de 587 (top1/top3/tier-tal) er uændrede eller bedre.
- Navne (præcis tekst):
  - operationer: `publication_persona`, `publication_identity`;
  - `expected_counts`-nøgler: `publication_personas`, `publication_identities`;
  - elementprefixer: `publication-persona:<source_record_key>`, `publication-identity:<source_persona_id>`;
  - oprindelse: `publication_binding`; `evidence.authority` = `narrative_record_publication`;
  - udfald: `enig`, `svag`, `uenig`, `navnefaelle`, `ingen_kandidat`;
  - F-grund: `publication_binding_disputed`; U-grund: `unknown`;
  - profil: `daa-1939-publication-v1` (kilde 3), én profil for begge operationer;
  - persona-nøgle: `'1939:' || source_record.record_key`.
- Fejlkoder (præcis tekst):
  - B: `PUBLICATION_PERSONA_PAYLOAD_INVALID`, `PUBLICATION_PERSONA_RECORD_MISSING`,
    `PUBLICATION_PERSONA_MENTION_DRIFT`, `PUBLICATION_PERSONA_BINDING_DRIFT`, `PUBLICATION_PERSONA_SUBJECT_INVALID`,
    `PUBLICATION_PERSONA_EXISTS`; helpost-fejl er 6a's `RECORD_HELPOST_AMBIGUOUS` /
    `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE` uændret.
  - C: `PUBLICATION_IDENTITY_PAYLOAD_INVALID`, `PUBLICATION_IDENTITY_RUN_STALE`,
    `PUBLICATION_IDENTITY_BINDING_DRIFT`, `PUBLICATION_IDENTITY_OUTCOME_MISMATCH`,
    `PUBLICATION_IDENTITY_SAMPLE_MISMATCH`, `PUBLICATION_IDENTITY_INPUT_DRIFT`; versionskonflikt er kernens `EVIDENCE_IDENTITY_VERSION_CONFLICT`.
  - Kernen: `PUBLICATION_BINDING_ORIGIN_INVALID`. Klassifikatoren: `PUBLICATION_CONTROL_CONFIG_MISSING`.
  - Køvagten: `IDENTITY_AWAITING_PUBLICATION_CONTROL`.
  - Fortrydelse: `PUBLICATION_REVERSAL_VERSION_DRIFT`; øvrige som
    `REIMPORT_WRITER_REVERSAL_INVALID`.
  - Arket: `PUBLICATION_SHEET_TOO_MANY_CARDS` (over 90 kort), `PUBLICATION_SAMPLE_FAILED` (F eller U i stikprøven).
- Id'er: indholds-id med `private.content_uuid('source-persona', {source_id, persona_key})` og
  `DETERMINISTIC_ID_COLLISION`-fangst som i `private.write_relation_persona` (schema.sql:16208).
- Persondata:
  - Intet script eller output i repoet viser posttekst eller navne. Målinger, manifester og rapporter rummer kun antal,
    id'er, nøgler og hashes.
  - Kortarket og detaljedumpet har navne; de ligger kun under `~/.private/6b/` (0600), og ingen agent læser dem.
  - `work*/`-mapper bruges ikke af 6b. Codex- og søgekommandoer udelukker `work*/` i selve kommandoen.
- Commits: Conventional Commits med dansk beskrivelse, uden Claude-attribution, men med `Claude-Session`-linjen.
  Ét commit pr. task. Ingen push uden projektejerens ja; PR'er oprettes som draft.
- Prod: kun fra projektejerens shell med `--jeg-mener-det` og GO-kode. Prods `statement_timeout` er 2 min; stand-ins
  øves med `ALTER DATABASE … SET statement_timeout='2min'`, ICU-locale og `ANALYZE` efter restore.
- Lokal verifikation før push: hele det berørte CI-job køres lokalt (pg-jobbene, node-jobbet for
  `@daa/identity-candidates`, python-jobbet), ikke kun egne testfiler.

## Review Focus

1. **En record med to aktive bindinger, eller en `withdrawn` + en `published`:** B kræver præcis én `published`
   `narrative_record_publication` og afviser ellers med `PUBLICATION_PERSONA_BINDING_DRIFT`. En `withdrawn` ved
   siden af én `published` er tilladt. Testes i Task 2.
2. **Bindingspersonens egen klyngepartner scorer lige med eller højere end den selv:** udfaldet bliver `svag` med
   grunden `partner_hoejere`, aldrig `enig` (spec §4.5). Klassifikatoren bruger bindingspersonens egen
   `member_scores`-post og ser partnerne som konkurrenter. Testes i Task 5, Task 9 og Task 10.
3. **En `web_detail`-afgørelse mellem B og C:** `red_afgoer_source_persona` afviser med
   `IDENTITY_AWAITING_PUBLICATION_CONTROL`. Lykkes en afgørelse alligevel (fx før A), afviser C elementet med
   `EVIDENCE_IDENTITY_VERSION_CONFLICT`, og manifestbyggeren lister personaen som disposition. Testes i Task 3 og 6.
4. **En af de 8 v50-records i B's manifest:** afvises med `PUBLICATION_PERSONA_EXISTS`, fordi en persona for kilden
   allerede har en mention i helposten, selv om dens nøgle har en anden form. Testes i Task 2.
5. **Helpost med flere forankringer** (235 af 584): B finder helposten med `private.record_helpost_observation`, ikke
   med »præcis én forankring«. En helpost, hvor reglen giver `ambiguous` eller `outside`, afvises med 6a's kode.
   Testes i Task 2.

---

## PR 1 — database (gren `feat/trin6b-db` fra `docs/trin6b-spec`)

### Task 1: Registrering af de to operationer og profilen

**Files:**
- Modify: `schema.sql`:
  - `reimport_event_operation_check` (ca. linje 3625): tilføj de to operationer;
  - `private.validate_reimport_authorization_payload` (ca. linje 3791): de to `expected_counts`-nøgler, de to
    elementprefixer, tællinger pr. prefix; den tilladte nøgleantal-mængde `NOT IN (2..10)` udvides til `(2..12)`;
  - `public.red_finalize_reimport` (ca. linje 5182): to `CASE`-arme efter mønstret for `source_text_revision`;
  - seed af `reimport_writer_profile`-rækken `daa-1939-publication-v1`: `writer_config` er en kopi af
    `daa-1939-clause-evidence-v1`'s med `run_key_prefix` `reimport-publication:` og `extractor_version`
    `publication-v1`.
- Modify: `db-migrations.sql`: første 6b-blok med `PERFORM private.ensure_reimport_operations(ARRAY['publication_persona','publication_identity'])`
  (mønster `db-migrations.sql:27342`), de to funktioner og profilrækken (`ON CONFLICT DO NOTHING`).
- Create: `tests/sql/test-publication-registration.sql`.
- Modify: `.github/workflows/ci.yml`: kør testen efter `schema.sql` og efter `db-migrations.sql` (to gange), også i
  `writer_1939`-varianten, som 6a's `test-record-helpost.sql`.

**Interfaces:**
- Produces: operationerne kan autoriseres og finaliseres; profilen `daa-1939-publication-v1` findes for kilde 3.

- [ ] **Step 1: Skriv testen** (`BEGIN … ROLLBACK`):
  - `validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_personas":2}', {to elementer med prefix publication-persona:})` lykkes;
  - én for mange eller forkert prefix giver `REIMPORT_WRITER_AUTHORIZATION_INVALID`;
  - en batch med to `publication_persona`-events finaliseres med `{"…","publication_personas":2}`, og med 1 forventet
    giver den `REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH`;
  - profilrækken findes, og 2018-20-profilernes `profile_sha256` er uændrede (sammenlign med en hårdkodet liste
    taget fra `main` før ændringen).
- [ ] **Step 2:** Kør mod en base med `schema.sql`. Forventet: fejl.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4:** Kør mod frisk `schema.sql` og mod `db-migrations.sql` kørt to gange. Forventet: `OK`.
- [ ] **Step 5:** Commit `feat(db): registrér publication-operationerne og 1939-profilen`.

### Task 2: Writeren `publication_persona` (ceremoni B)

**Files:**
- Modify: `schema.sql`: `private.write_publication_persona(p_batch_id uuid, p_element_id text, p_payload jsonb)` og
  `public.red_apply_reimport_publication_persona(…)` efter `write_relation_persona`; REVOKE/GRANT som
  `red_apply_reimport_relation_persona`.
- Modify: `db-verify.sql`: wrapperen i `v_authenticated`-listen (ca. linje 2946).
- Modify: `db-migrations.sql` (6b-blokken).
- Create: `tests/sql/test-publication-persona.sql`, `tests/integration/test-publication-persona-concurrency.R`
  (mønster `tests/integration/test-narrative-record-concurrency.R`).
- Modify: `.github/workflows/ci.yml`.

**Interfaces:**
- Consumes: Task 1; 6a's `private.record_helpost_observation(record_id, helpost_kind)`.
- Produces:
  - payloadens lukkede nøglesæt (sorteret): `binding_id`, `binding_status`, `mention_id`, `mention_text_sha256`,
    `person_id`, `persona_key`, `source_id`, `source_record_key`. `binding_status` skal være `published`;
  - kvittering (returværdi og `reimport_event.payload->'result_receipt'`): `source_persona_id`, `mention_id`,
    `binding_id`, `person_id`; `reimport_event.canonical_person_id` = `person_id`.

Rækkefølgen i writeren er bindende:
1. kontrakt, `require_reimport_open_batch`, `require_reimport_writer_editor`, `lock_reimport_writer`, delt
   `daa-identity-candidates:<source>`-lås (som `write_relation_persona`), autorisationen (payload = autoriseret
   element), payloadform og `p_element_id = 'publication-persona:' || source_record_key`, `persona_key =
   '1939:' || source_record_key`;
2. **lås** `source_record … FOR UPDATE`, derefter recordens `narrative_record_publication`-rækker `FOR UPDATE`
   (i `id`-orden);
3. helposten: `record_helpost_observation(record, 'person')`; præcis én `source_mention` i den observation, med
   `id = mention_id` og `sha256(verbatim_text) = mention_text_sha256`, ellers `PUBLICATION_PERSONA_MENTION_DRIFT`;
4. præcis én `published` binding, med `id = binding_id`; narrativet er `subjekt_type='person'`, `subjekt_id =
   person_id`, `source_id` = batchens; ellers `PUBLICATION_PERSONA_BINDING_DRIFT`;
5. personen har præcis én `person_external_id` for kilden, ellers `PUBLICATION_PERSONA_SUBJECT_INVALID`;
6. ingen `source_persona` for kilden har en `source_persona_mention` på en mention i helpost-observationen, og
   ingen persona har nøglen, ellers `PUBLICATION_PERSONA_EXISTS`;
7. `extraction_run` som i `migrate_legacy_narrative_record` (profilens `run_key_prefix` + manifest-sha);
8. `source_persona` (indholds-id) og `source_persona_mention(persona, mention_id, 'primary', 1)`. **Ingen identitet.**
9. `reimport_event`.

- [ ] **Step 1: Skriv tests.** Fixture: kilde, rendition, records med helpost og underforekomster (genbrug mønstret i
  `tests/sql/test-record-helpost.sql`), narrativ med publiceret binding, person med én `person_external_id`.
  - `happy_path`: persona med forventet indholds-id og nøgle, én `primary`-mention, ingen
    `source_persona_identity`-række, kvitteringen stemmer;
  - `multi_anchor`: helpost + to underforekomster → lykkes på helpostens mention;
  - `helpost_ambiguous` og `helpost_outside` → 6a's koder;
  - `mention_drift`: forkert tekst-hash → `PUBLICATION_PERSONA_MENTION_DRIFT`;
  - `binding_drift`: binding er `draft`; to `published` (direkte indsat i fixturen); forkert `binding_id` → alle
    `PUBLICATION_PERSONA_BINDING_DRIFT`. `withdrawn` + én `published` → lykkes;
  - `subject_two_external_ids` → `PUBLICATION_PERSONA_SUBJECT_INVALID`;
  - `existing_v50_persona`: en persona med nøgle `X-anden-form` og mention i helposten → `PUBLICATION_PERSONA_EXISTS`;
  - `narrative_state_unchanged`: `private.narrative_publication_state(person, source, record_key)` er byte-ens før og
    efter (6b laver ingen placements);
  - `full_chain`: authorize → begin → apply → finalize med `publication_personas` = 2; replay af samme manifest
    giver den eksisterende batch, som 6a's runner forventer (`already_applied`).
  - Samtidighed (R, to sessioner): to batches med samme record. A tager recordlåsen og venter på en
    advisory-barriere; B blokerer. Når A committer, fejler B med `PUBLICATION_PERSONA_EXISTS`.
- [ ] **Step 2:** Kør. Forventet: fejl.
- [ ] **Step 3: Implementér** efter rækkefølgen ovenfor.
- [ ] **Step 4:** Kør testene og `db-verify.sql`. Forventet: `OK`.
- [ ] **Step 5:** Commit `feat(db): writer-operation publication_persona — persona på publiceret helpost uden identitet`.

### Task 3: Personas, der venter på kontrol: kø og redaktørvagt

**Files:**
- Modify: `schema.sql`:
  - ny `private.persona_awaiting_control(p_persona uuid) RETURNS boolean` (`STABLE SECURITY DEFINER`, revoked);
  - `red_source_persona_queue` (ca. linje 9568): `AND NOT private.persona_awaiting_control(persona.id)`;
  - `red_afgoer_source_persona` (ca. linje 9742): efter kildelåsen, `IF private.persona_awaiting_control(...)
    THEN RAISE EXCEPTION 'IDENTITY_AWAITING_PUBLICATION_CONTROL'`.
- Modify: `db-migrations.sql`. Create: `tests/sql/test-persona-awaiting-control.sql`. Modify: `ci.yml`.

**Interfaces:**
- Produces: `persona_awaiting_control` er sand, præcis når:
  - personaen har ingen `source_persona_identity`-række;
  - et `publication_persona`-event i en batch, der ikke er `reversed`, har `payload->'result_receipt'->>
    'source_persona_id'` = personaen (eventet, ikke `created_run_id`: kørslen kan genbruges på tværs af batches med
    samme manifest, Codex plan-r1 fund 10);
  - ingen `finalized` batch har et `publication_identity`-event med `payload->>'persona_batch_id'` = eventets batch.

  Ellers er den falsk. Alle andre personas er upåvirkede.

- [ ] **Step 1: Skriv testen:**
  - persona fra en B-batch er skjult i køen (`p_status` NULL og `proposed`), og `red_afgoer_source_persona` afviser
    `same` og `unresolved` med `IDENTITY_AWAITING_PUBLICATION_CONTROL`;
  - en 2018-20-lignende persona uden identitet er stadig synlig og kan afgøres;
  - efter en finaliseret C-batch, der navngiver B-batchen, er en persona uden identitet (de 2 staged) synlig igen som
    `proposed`;
  - køens kolonner og orden er ellers uændrede (sammenlign med en kørsel uden B-personas).
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (`OK`) mod `schema.sql` og migrations ×2.
- [ ] **Step 5:** Commit `feat(db): personas fra en publiceringsbatch venter på kontrol — skjult i køen og spærret for afgørelse`.

### Task 4: Årstalsreserve fra `date_raw` i generatorens input

**Files:**
- Modify: `schema.sql`: `private.identity_candidate_input` (ca. linje 9902). Rør ikke `red_match_personer` (bruges af
  matcher-fladen).
- Modify: `db-migrations.sql`. Modify: `tests/sql/test-identity-candidates.sql`.

**Interfaces:**
- Produces:
  - reserven er **tilvalgt i `input_spec`**: nøglen `year_fallback` med eneste værdi `date_raw-v1` er tilladt i begge
    tilstande. Uden nøglen er inputtet byte-ens med i dag, så eksisterende kandidat- og 5b-kontrolkørsler, der
    genberegner deres hash (`red_register_identity_control_run`, `control_input_list_sha256`), ikke driver (Codex
    plan-r1 fund 9);
  - med nøglen får en påstand i `input->'persons'->'assertions'` med `date_min IS NULL AND date_max IS NULL` og præcis
    ét forskelligt årstal i `public.assertion.date_raw` (regex `\m(1[0-9]{3}|20[0-9]{2})\M`) værdierne
    `date_min = 'YYYY-01-01'`, `date_max = 'YYYY-12-31'` og nøglen `date_origin = 'date_raw'`. Andre påstande er
    byte-ens. Tilføjelsen sker før sorteringen af arrays;
  - `export-input.sql` får en variabel `year_fallback` (tom = uden).

- [ ] **Step 1: Udvid testen** med påstande med `date_raw`:
  - `'1750'` → 1750;
  - `'c. 1750'` → 1750;
  - `'12. Marts 1750'` → 1750;
  - `'1750 el. 1751'` → ingen;
  - `'17..'` → ingen;
  - en påstand med `date_min` sat → uændret.
  - Assertér også, at `input_sha256` er deterministisk over to kald, at inputtet **uden** `year_fallback` er byte-ens
    med en hash taget før ændringen, og at en ukendt værdi (`date_raw-v2`) giver `IDENTITY_CANDIDATE_INPUT_SPEC_INVALID`.
  - Kør `tests/sql/test-identity-control-run.sql` uændret: en forseglet 5b-kørsel har samme status før og efter.
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (`OK`).
- [ ] **Step 5:** Commit `feat(db): årstal fra date_raw som reserve i identitetsgeneratorens input`.

### Task 5: Oprindelsen `publication_binding`, klassifikatoren og stikprøven

**Files:**
- Modify: `schema.sql`:
  - `private.decide_source_persona_identity` (ca. linje 9416): ny `ELSIF p_origin='publication_binding'`-gren og lås
    af målpersonen som i dag;
  - ny `private.publication_control_outcome(p_persona uuid, p_run uuid, p_person bigint) RETURNS jsonb`;
  - ny `private.publication_control_in_sample(p_persona uuid, p_run uuid) RETURNS boolean`;
  - nye `public.red_publication_control(p_candidate_run_id uuid) RETURNS jsonb` og
    `public.red_publication_control_details(p_candidate_run_id uuid) RETURNS jsonb` (redaktion; GRANT `authenticated`;
    i `db-verify.sql`'s liste).
- Modify: `db-migrations.sql`. Create: `tests/sql/test-publication-control.sql`. Modify: `tests/sql/test-identity-decision.sql`
  (`ukendt`-løkken får `publication_binding`-tilfældene). Modify: `ci.yml`.

**Interfaces:**
- Kernens krav for `publication_binding` (alle, ellers `PUBLICATION_BINDING_ORIGIN_INVALID`):
  - `accepted`, forventet version 0, ingen `basis`, `evidence.authority='narrative_record_publication'`;
  - `evidence.binding_id` peger på en `published` binding, hvis narrativ har `subjekt_id = p_canonical_person_id`;
  - personen har præcis én `person_external_id` for personaens kilde;
  - personaens `primary`-mention ligger i den observation, `private.record_helpost_status(bindingens record,
    observationens kind)` giver som `ok`;
  - ingen anden persona for kilden har en mention i den observation.
- Klassifikatoren læser de gemte kandidater for `(p_run, p_persona)` og kørslens `config` (`autoCutoff`,
  `controlMargin`, `topK`; mangler `controlMargin`, eller er `topK` < 2, kastes `PUBLICATION_CONTROL_CONFIG_MISSING`).
  Alle sammenligninger bruger de **uafrundede** `score_raw`-værdier fra `member_scores` (Task 9); lighed er `=` på
  dem (Codex plan-r1 fund 7):
  - **egen post:** `member_scores`-posten med `person_id = p_person` i en af personaens kandidatrækker. Egen score og
    egne signaler er den posts. Findes ingen: `ingen_kandidat`;
  - **konkurrent:** højeste `score_raw` blandt alle **andre** `member_scores`-poster for personaen, både i andre
    kandidatrækker (andre klynger) og i egen række (egne klyngepartnere). Uden konkurrent er marginen uendelig. Med
    `topK` ≥ 2 ligger den bedste anden klynge altid i de gemte rækker, når egen række er rang 1;
  - en anden klynges post > egen: `uenig`; lig egen: `navnefaelle`;
  - en egen klyngepartner > egen eller lig egen: `svag` (kortet viser grunden `partner_hoejere`). Specen §4.5:
    scorer partneren højere end bindingspersonen selv, bliver det et kort (Codex plan-r1 fund 6);
  - egen ≥ `autoCutoff`, mindst ét af `birth`/`death` i egne signaler og egen − konkurrent ≥ `controlMargin`: `enig`;
  - ellers `svag`.
  - Funktionen returnerer `jsonb` `{outcome, reason, own_score, competitor_score, competitor_person_id}`; writeren
    sammenligner kun `outcome`.
- Stikprøven: blandt `enig`-personas, som et `publication_persona`-event har skrevet (ikke de 8 v50-personas), de 20
  med lavest `sha256('publication-sample-v1:'||input_sha256||':'||config_sha256||':'||persona_key)` (`COLLATE "C"`);
  færre end 20 enige → alle. Populationen afhænger ikke af identitetsversion, så den flytter sig ikke, mens C skriver
  (Codex plan-r1 fund 2).
- `red_publication_control(run)` returnerer for hver persona i kørslen: `source_persona_id`, `identity_version`,
  `binding_id`, `binding_status`, `person_id` (bindingens), `outcome`, `reason`, `in_sample` og et ikke-staged-flag.
  Ingen tekst. Bindingen findes fra personaens `primary`-mention → recordens helpost → `published` binding.
- `red_publication_control_details(run)` returnerer til kortarket, kun til `~/.private/6b/`:
  - for bindingspersonen og alle personer i konkurrerende klynger: navn, leveår fra visningscachen, titel og
    postreference (record_label);
  - personaens `proposed` navn, fødsel og død;
  - opslaget går direkte på person-id'erne, uafhængigt af repræsentantvalg og af, om `buildScored` filtrerede
    bindingspersonen bort (Codex plan-r1 fund 8).

- [ ] **Step 1: Skriv tests:**
  - kernen: hver ugyldig variant (forkert status, version 1, `basis`, forkert autoritet, `draft`-binding, en anden
    person, to `person_external_id`, mention uden for helposten, en anden persona i helposten) giver
    `PUBLICATION_BINDING_ORIGIN_INVALID`; den gyldige lykkes; `reversal` til `superseded` virker bagefter;
  - klassifikatoren med syntetiske kandidatrækker:
    - (a) egen 0,95 med `birth`, ingen konkurrent → `enig`;
    - (b) samme uden årstal → `svag`;
    - (c) konkurrent 0,97 → `uenig`;
    - (d) konkurrent lig egen → `navnefaelle`;
    - (e) personen findes ikke → `ingen_kandidat`;
    - (f) **klyngepartneren 0,99 i samme række, egen 0,70** → `svag`, grund `partner_hoejere` (Review Focus 2);
    - (f2) klyngepartneren 0,99, egen 0,95 med årstal, ingen anden klynge → `svag`, grund `partner_hoejere`;
    - (g) margin lige under `controlMargin` → `svag`;
    - (g2) `score_raw` 0,89996 (afrundet 0,9) med `autoCutoff` 0,9 → ikke `enig`;
    - (h) `config` uden `controlMargin`, eller `topK` 1 → `PUBLICATION_CONTROL_CONFIG_MISSING`;
  - stikprøven er deterministisk, har højst 20 og kun `enig`. Med 25 enige: den er den samme før og efter, at 10 af
    dem har fået identitet.
  - `red_publication_control_details` giver bindingspersonens data, også når bindingspersonen ikke er
    repræsentant, og ved `ingen_kandidat`.
- Modify også: `.claude/skills/daa-extract/scripts/test_identity_guard_static.py`. Oprindelseslisten får
  `publication_binding`, og allowlisten over kernens kaldere får `private.write_publication_identity` (med `human` og
  `publication_binding`) og `public.red_reverse_reimport_publication` (med `reversal`). Migrationsantallet tælles
  efter Task 3's gendefinition af `red_afgoer_source_persona`. Henvisning: decisions 2026-10-31 (Codex plan-r1 fund
  11).
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (`OK`).
- [ ] **Step 5:** Commit `feat(db): oprindelsen publication_binding og én klassifikator for publiceringskontrollen`.

### Task 6: Writeren `publication_identity` (ceremoni C)

**Files:**
- Modify: `schema.sql`: `private.write_publication_identity(…)` og `public.red_apply_reimport_publication_identity(…)`;
  `public.red_finalize_reimport` (inputdriften nedenfor);
  REVOKE/GRANT og `db-verify.sql`-liste som Task 2.
- Modify: `db-migrations.sql`. Create: `tests/sql/test-publication-identity.sql`,
  `tests/integration/test-publication-identity-concurrency.R`. Modify: `ci.yml`.

**Interfaces:**
- Consumes: Task 3 (`persona_awaiting_control`), Task 5 (kernen, klassifikatoren, stikprøven).
- Payloadens lukkede nøglesæt: `answer` (`null`|`S`|`F`|`U`), `binding_id`, `binding_status`, `candidate_run_id`,
  `candidates_sha256`, `expected_identity_version` (0), `outcome`, `person_id`, `persona_batch_id`, `rows_sha256`,
  `same_as_hint_person_id` (`null` eller tal; kun ved `S`), `sheet_line`, `sheet_sha256`, `source_persona_id`.
  Arkfelterne er `null` præcis når `answer` er `null`.
- Udfald og svar:
  - `enig` uden for stikprøven: `answer` null → `publication_binding`;
  - `enig` i stikprøven: `answer='S'` → `publication_binding`, med arkfelterne i evidensen; `F`/`U` afvises (arket
    stopper før, Task 12);
  - de øvrige fire udfald: `answer` påkrævet:
    - `S` → kernen med `human`, `basis='human_sheet'`, `sheet_sha256`, `rows_sha256`, `line`, eventuelt
      `same_as_hint_person_id`;
    - `F` → `unresolved` med `reason='publication_binding_disputed'`;
    - `U` → `unresolved` med `reason='unknown'`.

  *Afgjort i planen:* writeren kalder kernen med `human` direkte. `red_afgoer_source_persona` kan ikke sætte `reason`,
  og den afviser personas, der venter på kontrol (Task 3). Writeren bliver dermed den anden serverkalder af `human`
  ud over `red_afgoer_source_persona` (5a §4.2); det noteres i `docs/decisions.md` i plancommit'en.
- Rækkefølgen er bindende:
  1. kontrakt, batch, redaktør, writerlås, **eksklusiv** `daa-identity-candidates:<source>`-lås (ingen ny
     kandidatkørsel kan komme imellem), autorisation, payloadform, element-id;
  2. `candidate_run_id` er kildens seneste kørsel, og dens `candidates_sha256` er payloadens, ellers
     `PUBLICATION_IDENTITY_RUN_STALE`; `persona_batch_id` er en `finalized` batch, hvis `publication_persona`-event
     skrev personaen;
  3. **lås** i denne orden: bindingens `source_record … FOR UPDATE` (record først, som publiceringswriterne i
     `private.narrative_record_state(…, true)`, så C og en samtidig tilbagetrækning serialiseres på recorden, Codex
     plan-r1 fund 3), derefter `source_persona … FOR UPDATE`, derefter bindingen `FOR UPDATE`. Kernen låser selv
     identitetsrækken og personen (`lock_family_rows`). Writeren låser ikke i anden rækkefølge;
  4. **for alle svar og oprindelser** (Codex plan-r1 fund 5):
     - personaens `primary`-mention ligger i recordens helpost (`record_helpost_status(record, kind)` = `ok`);
     - bindingen er recordens eneste `published` binding med `id = binding_id`;
     - subjektet er `person_id`.

     Ellers `PUBLICATION_IDENTITY_BINDING_DRIFT`;
  5. `publication_control_outcome(persona, run, person_id) = outcome`, ellers `PUBLICATION_IDENTITY_OUTCOME_MISMATCH`;
     `publication_control_in_sample` stemmer med `answer`'s tilstedeværelse ved `enig`, ellers
     `PUBLICATION_IDENTITY_SAMPLE_MISMATCH`;
  6. kernen med `expected_identity_version` (konflikt giver kernens kode);
  7. `reimport_event` med kvittering `identity_version`, `origin`, `decision_status`.
- **Inputdrift** (Codex plan-r1 fund 4): `red_finalize_reimport` genberegner for en batch med
  `publication_identity`-events `identity_candidate_input(kørslens source_id, kørslens input_spec)` og sammenligner med
  kørslens `input_sha256`; afvigelse giver `PUBLICATION_IDENTITY_INPUT_DRIFT`. Runneren kører alle apply-kald og
  finalize i **én transaktion**, så en drift ruller hele C tilbage. Én genberegning pr. batch, ikke pr. element.

- [ ] **Step 1: Skriv tests** (fixture: B-batch fra Task 2, kandidatkørsel registreret med `red_record_identity_candidates`
  og `config.controlMargin`):
  - hvert af de fem udfald med hvert tilladt svar giver forventet status, oprindelse og evidens;
  - forkert `outcome` → `OUTCOME_MISMATCH`;
  - stikprøve-`enig` uden `S` eller ikke-stikprøve med `S` → `SAMPLE_MISMATCH`;
  - ny kandidatkørsel efter manifestet → `RUN_STALE`;
  - bindingen trukket tilbage efter manifestet → `BINDING_DRIFT`;
  - identitet allerede version 1 → `EVIDENCE_IDENTITY_VERSION_CONFLICT`;
  - krydsning: to gyldige B-personas med hver sin binding; en payload med persona 1 og binding 2 afvises for
    `S`, `F`, `U` og `enig` med `BINDING_DRIFT`;
  - en `proposed` `person.name`-fortolkning ændres efter kandidatkørslen → finalize giver
    `PUBLICATION_IDENTITY_INPUT_DRIFT`, og intet er skrevet efter rollback;
  - fuld kæde med `publication_identities` = n og finalize; bagefter er `persona_awaiting_control` falsk for B's
    personas;
  - `narrative_publication_state` for recorden er byte-ens før og efter.
  - Samtidighed (R): C mod en tilbagetrækning (`red_tilbagetraek_person_narrative_record`) af samme record i to
    sessioner, begge rækkefølger: ingen deadlock; den sidste fejler med `BINDING_DRIFT` eller `NARRATIVE_RECORD_STATE_STALE`.
  - Samtidighed (R): C holder den eksklusive kildelås og venter; `red_record_identity_candidates` i en anden session
    blokerer, og når C committer, lykkes kørslen. Omvendt rækkefølge giver C `RUN_STALE`.
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (`OK`).
- [ ] **Step 5:** Commit `feat(db): writer-operation publication_identity med efterprøvet afgørelsesmængde`.

### Task 7: Fortrydelse af C

`source_persona` og `source_persona_mention` er append-only (`private.reject_evidence_mutation`, schema.sql:1098-1108).
B kan derfor ikke fortrydes med en writer. B fortrydes ved **restore af B-dumpet** i det deklarerede vindue, som 6a's
ceremoni B (Codex plan-r1 fund 1; spec §6 og §8 pkt. 9 rettet i samme commit). Denne task bygger kun C's fortrydelse.

**Files:**
- Modify: `schema.sql`: ny `public.red_reverse_reimport_publication(p_batch_id uuid, p_authorization_id uuid) RETURNS
  jsonb`. Autorisationen kommer fra den eksisterende `red_authorize_reimport_reversal`. Grants som
  `red_reverse_reimport`. `red_reverse_reimport` røres ikke; den kræver `activated` og kender kun `person_create`.
- Modify: `db-migrations.sql`, `db-verify.sql`. Create: `tests/sql/test-publication-reversal.sql`. Modify: `ci.yml`.

**Interfaces:**
- Batchen skal være `finalized` og må kun have `publication_identity`-events; ellers `REIMPORT_WRITER_REVERSAL_INVALID`.
  Autorisationskontrollerne er som i `record_reimport_legacy_reversal` (schema.sql:5608).
- Pr. event, i persona-id-orden under `FOR UPDATE`: er personaens aktuelle identitetsversion ikke eventets version,
  afvises hele fortrydelsen med `PUBLICATION_REVERSAL_VERSION_DRIFT`. Ellers kaldes kernen med `reversal` →
  `superseded` (`reversed_batch_id`).
- Batchen bliver `reversed`, og der skrives et `reversal`-event. Personaerne venter derefter igen på kontrol: Task 3's
  betingelse kræver en `finalized` C-batch, og en `reversed` tæller ikke.

- [ ] **Step 1: Skriv tests:**
  - C → identiteterne er `superseded`, version 2, og `persona_awaiting_control` er falsk (de har en identitetsrække);
  - C efter en senere menneskelig afgørelse → `VERSION_DRIFT`;
  - en B-batch → `REVERSAL_INVALID`;
  - en anden fortrydelse af samme batch → `REVERSAL_INVALID`.
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (`OK`).
- [ ] **Step 5:** Commit `feat(db): fortrydelse af publication_identity-batches med versionsvagt`.

### Task 8: PR 1 samlet

- [ ] **Step 1:** Hele pg-jobbenes testliste lokalt mod frisk `schema.sql` og mod `db-migrations.sql` ×2, `db-verify.sql`
  og `db-rls.sql`. Forventet: alt grønt.
- [ ] **Step 2:** Opgraderingstest (memory `signaturaendring-kraever-opgraderingstest`): migrationsblokken på en
  stand-in af prod (`6am2`) to gange, derefter `db-verify.sql`. Forventet: grønt; 2018-20-profilernes sha uændret.
- [ ] **Step 3:** Commit kun, hvis noget blev rettet: `fix(db): …`.

## PR 2 — generator og scripts (gren `feat/trin6b-scripts` fra `feat/trin6b-db`)

### Task 9: Generatoren udskriver hvert klyngemedlems egen score

**Files:**
- Modify: `packages/identity-candidates/src/rank.ts`, `src/cli.ts`; Modify: `src/__tests__/rank.test.ts`.

**Interfaces:**
- `Candidate.basis.member_scores: Array<{ person_id: number; score_raw: number; signals: string[] }>` på **hver**
  kandidatrække: for en klynge alle medlemmer, der overlevede `buildScored`, med deres egen **uafrundede** score og
  egne signaler; for en enkeltperson én post. Opsamles før sammenfoldningen i `rank.ts:45-62`. Rang,
  `score`, `tier` og øvrige `basis`-felter er uændrede.
- CLI: `--control-margin <x>` (valgfri, i (0,1)) lægges i `config.controlMargin`; `config.autoCutoff` og `config.topK`
  findes allerede via `rankConfig`/CLI. `--year-fallback date_raw-v1` sendes videre til `export-input.sql` (Task 4). `GENERATOR_VERSION` = `identity-candidates-1.2`.

- [ ] **Step 1: Tests:**
  - en klynge {A 0,99 med årstal, B 0,70 uden} giver én række med score 0,99 og `member_scores` for begge med egne
    værdier;
  - en enkeltperson har én post;
  - rang, tier og `cluster_members` er byte-ens med 1.1 på eksisterende fixtures (bortset fra det nye felt);
  - `--control-margin` når ind i `config`.
- [ ] **Step 2-4:** `npm run test -w @daa/identity-candidates` (fejl) → implementér → (grøn); `npm run typecheck -w
  @daa/identity-candidates`.
- [ ] **Step 5:** Commit `feat(identity-candidates): hvert klyngemedlems egen score i kandidatgrundlaget`.

### Task 10: Kalibrering mod 2018-20 og årstalsdækning

**Files:**
- Create: `packages/identity-candidates/sql/calibrate-publication-control.sql` (læse-kun mod en stand-in, hvor
  kandidaterne er registreret).
- Create: `docs/evidensbaseret-genimport/identitet-6b-kalibrering.md` (kun tal).

- [ ] **Step 1:** På en frisk stand-in med PR 1 anvendt: generatoren for kilde 1 i `list`-tilstand over de 587 kendte
  (`sql/export-truth.sql`), `--top-k 5`, registreret med `red_record_identity_candidates`, én kørsel pr.
  gitterværdi for `controlMargin` ∈ {0,02, 0,05, 0,08, 0,10, 0,15, 0,20}, med `--year-fallback date_raw-v1`.
- [ ] **Step 2:** Pr. gitterværdi med `publication_control_outcome`:
  - **rigtige:** antal `enig`, når bindingspersonen er facit;
  - **forkerte:** antal `enig`, når bindingspersonen er en hvilken som helst anden kandidatperson i top 5 uden for
    facits klynge (kontrafaktisk);
  - **forkerte med forkert klynge:** som før, men med en syntetisk `samme_som` mellem den forkerte bindingsperson og
    facit, lagt i en kopi af inputtet. Udfaldet må heller ikke her blive `enig` (Codex plan-r1 fund 6).
- [ ] **Step 3: Valget.** `controlMargin` er den mindste gitterværdi med 0 forkerte, plus ét trin. Er ingen værdi fri
  for fejl: stop og tag det op med projektejeren. Kortantallet indgår ikke i valget (spec §4.3 pkt. 7).
- [ ] **Step 4:** 5a's `calibrate` på kørslen med den valgte værdi. Forventet: top1, top3 og tier-tal som 5a-beviset
  eller bedre (årstalsreserven kan kun tilføje årstal).
- [ ] **Step 5:** Årstalsdækning for de 563 bundne 1939-personer: antal med mindst ét år i matcherens frames før og efter
  Task 4. Notér begge tal.
- [ ] **Step 6:** Skriv beviset og commit `docs(genimport): kalibrering af publiceringskontrollen mod 2018-20`.
  Værdien indsættes i Global Constraints som `controlMargin = <x>` i samme commit.

### Task 11: B's manifest og målingen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/publication_persona_manifest.sql` (læse-kun; kun id'er, nøgler og hashes).
- Create: `.claude/skills/daa-extract/scripts/maal_trin6b.sql`.
- Create: `.claude/skills/daa-extract/scripts/tests/test_publication_persona_manifest.py` (kører SQL'en mod en lokal
  fixturebase, som de øvrige SQL-scripttests).
- Modify: `.github/workflows/ci.yml`: python-jobbets eksplicitte filliste (ca. linje 145) får testfilen (Codex plan-r1
  fund 12).

**Interfaces:**
- Manifestet: `{elements: {"publication-persona:<key>": payload}, expected_counts: {person_creates:0, source_evidence:0,
  publication_personas:n}, dispositions: [{record_key|person_id, label}]}`. Elementrækkefølge `COLLATE "C"`.
  Etiketter:
  - `allerede_persona` (de 8);
  - `ingen_helpost` (8);
  - `ingen_postbinding` (21 helposter uden binding);
  - `staged_ikke_offentlig` (2; de får persona i B, etiketten gælder C);
  - `ingen_bundet_narrativ` (13 personer).

  *Afgjort i planen:* `opret_benet` / `c3_uafklaret` (spec §4.6) bruges kun, hvis C0's `[NY]`-klassifikation kan
  forespørges i basen. Step 1 undersøger det. Ellers får alle 21 `ingen_postbinding`, og runbooken angiver
  fordelingen 16/5 fra #160's nøgleliste.
- `maal_trin6b.sql` udskriver én linje `T6B_MAAL tilstand=<foer|a|b|c> personas_k3=… identiteter_k3=… afventer=…
  k1_personas=… k1_identiteter=… k1_hash=…`. `k1_hash` er en hash over kilde 1's persona- og identitetsrækker.
  Tilstanden afledes af operationer og batches.

- [ ] **Step 1:** Undersøg, om `[NY]` kan forespørges: C0/C3-tabeller, `reimport_case_*` og `record_kind`. Notér
  svaret i runbooken (Task 13).
- [ ] **Step 2: Test** mod fixturen fra Task 2: manifestet har ét element pr. bundet helpost uden persona, de rigtige
  dispositioner og stabil hash over to kørsler; `maal` giver `foer` → `b` efter apply.
- [ ] **Step 3-4:** Implementér → kør pytest for mappen (hele python-jobbet lokalt).
- [ ] **Step 5:** Commit `feat(scripts): manifest og måling for 1939's personas (trin 6b)`.

### Task 12: C's kortark og manifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/publication_identity_sheet.py` (mønster `identity_queue_sheet.py`,
  inklusive `check_private_path` og `_write_new`).
- Create: `.claude/skills/daa-extract/scripts/tests/test_publication_identity_sheet.py`.
- Modify: `.github/workflows/ci.yml`: python-jobbets filliste får testfilen.

**Interfaces:**
- `render --control <red_publication_control-json> --details <red_publication_control_details-json> --out <ark>`:
  - ét kort pr. persona med udfald ≠ `enig` og pr. stikprøvepersona;
  - kortene for stikprøven blandes ind i de øvrige uden at vise udfaldet;
  - kortet viser bindingens person og op til 3 konkurrerende klynger med navn, leveår, titel og postreference;
    bindingspersonens egen score står adskilt fra klyngens;
  - token-linje `P <persona-id> <version> : _ # `, hvor `_` er `S`, `S <person-id>` (S + manglende `samme_som`),
    `F` eller `U`;
  - over 90 kort → `PUBLICATION_SHEET_TOO_MANY_CARDS`;
  - højst 30 kort pr. fil (`…-1.txt`, `…-2.txt`, `…-3.txt`), hver med egen hash.
- `manifest --control … --sheets <filer> --approved-sha256 <liste> --persona-batch <uuid> --out <manifest>`:
  - hashkontrol pr. ark;
  - F eller U på en stikprøvelinje → `PUBLICATION_SAMPLE_FAILED`;
  - ellers ét element pr. ikke-staged ny persona i kontrolmængden (de 553) efter payloadformen i Task 6;
  - de 8 eksisterende og de 2 staged som dispositioner;
  - `rows_sha256` = sha256 af `--control`-filens bytes.
  - Udskriver kun antal og hashes.

- [ ] **Step 1: Tests** med syntetisk control- og detaljedata:
  - kortantal og blanding er deterministiske;
  - 91 kort → fejl;
  - en ændret arkbyte → hashfejl;
  - F på en stikprøvelinje → `PUBLICATION_SAMPLE_FAILED`;
  - manifestets elementer har præcis Task 6's nøglesæt;
  - `S 123` giver `same_as_hint_person_id` 123;
  - stier uden for `--private-root` og i git afvises.
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør (grøn; hele python-jobbet).
- [ ] **Step 5:** Commit `feat(scripts): kortark og manifest for 1939's identitetskontrol (trin 6b)`.

## Øvelse og prod for A og B

### Task 13: Runbook og stand-in-øvelse af A og B

**Files:**
- Create: `docs/runbooks/trin6b-prod.md` (mønster `docs/runbooks/trin6a-prod.md`: forløb, varighed, stoppunkter,
  fortrydelse pr. fase efter spec §6).
- Create (privat): `~/.private/6b/` med runner `26-trin6b.sh` (`maal`, `go-a`, `dump`, `apply-a`, `manifest`, `go-b`,
  `apply-b`) og `26-trin6b-b.R` (dry-run, authorize som `service_role`, apply, replay), via 5c-2's
  `lib.zsh`/`koer.zsh`.

- [ ] **Step 1:** Frisk stand-in fra seneste prod-dump (ICU, 2 min, `ANALYZE`). Ceremoni A → `T6B_APPLY_A_OK` og målingen
  `a`; 2018-20's `k1_hash` uændret. Notér varigheder.
- [ ] **Step 2:** Manifest → forventet 555 elementer og dispositionerne fra spec §4.6 (8/8/21/2/13). Afviger tallene:
  stop og forklar før videre.
- [ ] **Step 3:** Ceremoni B → `T6B_APPLY_B_OK personas=555 identiteter=0`, replay giver `already_applied`, og
  målingen er `b`. Kontrollér:
  - `count(*)` af personas med `primary`-mention i hver sin helpost er 555, og 0 records har to personas;
  - `narrative_publication_state`-hash for de 563 er uændret;
  - køen viser ingen af de 555;
  - `k1_hash` er uændret.
- [ ] **Step 4: Fortrydelsesøvelse:** restore af B-dumpet (taget i tilstand `a`) på stand-in'en, `db-rls.sql` bagefter →
  målingen er `a`, og `k1_hash` er uændret. Kør B igen → `b` (samme manifest, ny batch).
- [ ] **Step 5:** Commit runbooken `docs(runbooks): trin 6b ceremoni A og B`.

### Task 14: Codex-diffreview, prod A og B, status

- [ ] **Step 1:** Codex-runde på diffen af PR 1 + PR 2 (`gpt-6.1-sol`, read-only, søgekommandoer med `--glob '!work*/**'`);
  Opus afvejer fundene (nødvendig / forenkl / kendt begrænsning / afvis). Det er B13's anden og sidste runde.
- [ ] **Step 2:** Projektejerens ja → push og draft-PR'er. PR 1 merges før PR 2. Slutøvelse (Task 13 Step 1-3) på `main`.
- [ ] **Step 3:** Ceremoni A og B i prod fra projektejerens shell efter runbooken; bagefter `NOTIFY pgrst` og
  `get_advisors(security)` (forventet nye fund: højst de nye `red_*`-wrappere, som de øvrige).
- [ ] **Step 4:** Opdatér `status.md` (1939 »Identitet«: personas i prod, identitet venter på 6c's runner),
  `docs/database-current-state.md` og `docs/changelog.md`. Commit `docs(status): 1939's personas i prod (trin 6b, ceremoni B)`.

## Ceremoni C — blokeret til 6c's runner har kørt i prod

Forudsætninger, der skal stå i 6c's delspec og være opfyldt (spec §5):
- runnerens input kobler persona og record gennem den primære mention;
- eksport og forslagswriter vælger helposten efter 6a's helpost-regel;
- de tilladte poster vælges med hele gaten (afdød, ikke privat, ikke staged);
- rækkefølgen er runner → 6b C → promotion.

### Task 15: Stand-in-øvelse af C

- [ ] **Step 1:** Stand-in efter 6c's runner-øvelse: kontrollér, at de 561 ikke-staged personas har `proposed`
  `person.name` og at mindst `person.birth` eller `person.death` findes for de fleste (notér antal).
- [ ] **Step 2:** Generatoren for kilde 3 i `list`-tilstand over de 561, `--top-k 5 --control-margin <Task 10> --year-fallback date_raw-v1`,
  registreret med `red_record_identity_candidates`. `red_publication_control` → fordelingen af udfald, stikprøven på
  20 og kortantallet. Over 90 kort: stop (spec §4.3 pkt. 6).
- [ ] **Step 3:** Ark (øvelse: projektejeren udfylder et øvelsesark, eller alle kort `U` som teknisk prøve; notér hvad),
  manifest, apply og finalize. Kontrollér:
  - spec §7's færdigbevis-tal;
  - `persona_awaiting_control` er falsk for alle 555;
  - de 2 staged er synlige som `proposed`;
  - de 8 eksisterende er urørte;
  - `narrative_publication_state` for de 563 er uændret.
- [ ] **Step 4:** Fortrydelsesøvelse af C → `superseded` og version 2; derefter apply igen på en frisk kopi.
- [ ] **Step 5:** Udvid runbooken med ceremoni C (`go-c`, `control`, `render`, `manifest-c`, `apply-c`, `reverse-c`). Commit
  `docs(runbooks): trin 6b ceremoni C`.

### Task 16: Prod C og status

- [ ] **Step 1:** Generatoren mod prod (læs input, registrér kandidater) og `red_publication_control`; arket bygges under
  `~/.private/6b/` og udfyldes af projektejeren; hashene bindes i GO-koden.
- [ ] **Step 2:** `apply-c --jeg-mener-det --go <kode>`; `maal` → `c`.
- [ ] **Step 3:** Kontrolrapporten (kun tal): udfald, stikprøve, S/F/U, antal F og hvad projektejeren gjorde med deres
  publicering, dispositioner.
- [ ] **Step 4:** `status.md`: 1939 »Identitet« → `produktionsverificeret` med dato; `database-current-state.md`;
  `changelog.md`. Commit `docs(status): 1939's identitet i prod (trin 6b)`.

---

## Reviewlog

### Codex-runde på spec+plan (2026-10-31, `gpt-6.1-sol`, B13-runden): NO-GO, 12 fund

Afvejning (Opus):

| # | Alvor | Fund | Afvejning | Indarbejdet |
|---|---|---|---|---|
| 1 | BLOCKER | B-fortrydelsen kan ikke slette append-only personas | nødvendig; bekræftet (schema.sql:1098-1108) | Task 7 kun C; B ved restore (Task 13); spec §6, §8 pkt. 9 |
| 2 | HIGH | Stikprøven flytter sig, mens C skriver | nødvendig | Task 5: populationen er B-skrevne `enig`, uafhængig af version |
| 3 | HIGH | Låseinversion mellem C og publiceringswriteren | kendt begrænsning i den beskrevne form: publiceringswriteren låser recorden først, så der er ingen cyklus, når C også gør; ordenen er nu eksplicit | Task 6 trin 3 + tosessionstest |
| 4 | HIGH | C ser ikke ændret kandidatinput | nødvendig | Task 6: finalize genberegner inputtet; apply+finalize i én transaktion |
| 5 | HIGH | `human`-grenen kobler ikke persona og binding | nødvendig | Task 6 trin 4 for alle svar + krydsningstest |
| 6 | HIGH | En bedre klyngepartner skjules | nødvendig (spec §4.5 siger kort) | Task 5: partner ≥ egen → `svag`; Task 10: negativ kontrol med forkert klynge |
| 7 | HIGH | Afrunding og top-K gør udfaldet uefterprøveligt | nødvendig | Task 9 `score_raw`; Task 5 `topK` ≥ 2 og lighed på rå værdier |
| 8 | HIGH | Kortarket mangler bindingspersonens data | nødvendig | Task 5 `red_publication_control_details`; Task 12 |
| 9 | HIGH | Årstalsreserven ændrer 5b's forseglede kontrolgrundlag | nødvendig | Task 4: tilvalgt i `input_spec`; spec §4.4 |
| 10 | HIGH | B → fortryd → B genbruger kørslens batch-id | forenkl: B fortrydes nu ved restore; køfilteret bygger desuden på eventets kvittering | Task 3 |
| 11 | MEDIUM | 5a's statiske guard mangler | nødvendig | Task 5 (`test_identity_guard_static.py`) |
| 12 | MEDIUM | Nye Python-tests kommer ikke med i CI | nødvendig | Task 11, Task 12 |
