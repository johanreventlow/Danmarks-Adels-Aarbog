# Trin 4 · dagsværk 4.1c: writer-operationen `clause_evidence` — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skriv 4.1b's klausul-ledger ind i databasen gennem #153's generelle writer som en ny, hash-bundet elementoperation `clause_evidence`, med maskinelle startdispositioner, og bevis det på alle 591 2018-20-records i en restore uden kanonisk delta.

**Architecture:** Én ny privat writer-funktion `private.write_clause_evidence` + offentlig wrapper `public.red_apply_reimport_clause_evidence`, udvidelse af writerens lukkede nøglesæt (`expected_counts.clause_evidence`, præfiks `clause-evidence:`, `reimport_event.operation`), en tredje profiltype i `reimport_profile.py`, en manifest-builder fra ledger-artefaktet, R-klientens dispatch, en læse-kun preview og en R-integrationstest. Fortrydelse ved restore (spec §4.1.5).

**Tech Stack:** PostgreSQL 17 (plpgsql, SECURITY DEFINER), psql-SQL-tests, Python 3 (manifest), R + DBI/RPostgres (apply-klient, preview, integrationstest), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §4.1.4-4.1.6 og §3.

## Global Constraints

- Forudsætter 4.1a (skema) og 4.1b (ledger-artefakt + profilversion med GO) merget/anvendt.
- `schema.sql` = source of truth; `db-migrations.sql` idempotent (køres to gange i CI); alle funktionskroppe byte-identiske de to steder.
- Writerens eksisterende autorisationsformer (149a: 2 nøgler; 149b: 3 nøgler) skal fortsat validere uændret; regressionstest er obligatorisk (spec fund 8).
- Payload bærer **ingen tekst**; klausulteksten udskæres fra helposten i databasen og hash-verificeres. Offsets i payload er helpost-relative; databasen er rendition-absolut.
- Ekstern nøgle for en klausul er `(source_record_key, ordinal, verbatim_sha256)`; UUID'er forlader aldrig databasen i manifester.
- Ingen prod-mutation; rigtig kørsel i restore. `umask 077`, `PGTZ=UTC`, `DAA_REIMPORT_ACTOR_ID` sat for `apply_reimport.R` også i dry-run.
- Ny public `red_*`-RPC skal klassificeres i **fem** ACL-lister (spec fund 8), ellers fejler `EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED` / db-verify.
- Commits: ét pr. task, dansk Conventional Commit, ingen push. Gren `feat/148-clause-evidence-writer`.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, #148.
2. **Værdikædeled:** `klausulobservationer` i databasen, under helposten, med dispositionsledger.
3. **Generel/profil/legacy:** generel motor (writer-op, R-dispatch, manifest-builder) + 2018-20 writer-profil (`daa-2018-20-clause-evidence-v1`).
4. **Redaktionel værdi:** klausuler bliver adresserbare som belæg; dispositionsregnskabet pr. record kan aflæses.
5. **Bevis:** 591 elementer anvendt i restore; antal klausul-rækker = ledgerens `record_text`+`structural_header`; dispositionsfordeling som ledgerens flag; neutralitets- og `anon`-hashes uændrede; replay `already_applied`; 149b's legacy-suite fortsat grøn; 149a/149b-autorisationsformer valideres uændret.
6. **Erstatter:** intet; tilføjer den databasevej, `clause_ledger` manglede.

## Filoversigt

- Modify: `schema.sql` (`validate_reimport_authorization_payload` 2582-2608; `reimport_event`-CHECK 2442; `red_finalize_reimport` 2962-2975; `red_reimport_batch_result` 3036-3060; ny funktion efter `red_apply_reimport_legacy_migration` 2956-2960; REVOKE/GRANT 3541/3543)
- Modify: `db-migrations.sql` (ny blok før `$public_red_revoke$`, samt tilføj RPC'en til `v_authenticated` i den blok)
- Modify: `db-rls.sql` (REVOKE private fn; REVOKE+GRANT public RPC i de eksisterende lister ~1179-1200)
- Modify: `db-verify.sql` (`$reimport_event_operation_check_verify$` skal også kræve `clause_evidence`; `$public_red_acl_verify$` `v_authenticated`; ny verify-blok)
- Modify: `tests/sql/test-reimport-writer.sql` (signaturlister linje 15-25 og `$acl_parity$` 100-135)
- Modify: `tests/sql/inspect-reimport-writer-catalog.sql` (funktionsnavne)
- Create: `tests/sql/test-clause-evidence-writer.sql`
- Modify: `.claude/skills/daa-extract/scripts/reimport_profile.py`, `test_reimport_profile.py`
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json`
- Create: `.claude/skills/daa-extract/scripts/build_clause_evidence_manifest.py`, `test_build_clause_evidence_manifest.py`
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_clause_evidence_preview.R`
- Create: `tests/integration/test-reimport-clause-evidence.R`
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `docs/changelog.md`

---

### Task 1: SQL-kontrakttest for writer-operationen (fejler først)

**Files:**
- Create: `tests/sql/test-clause-evidence-writer.sql`

**Interfaces:**
- Consumes: `public.red_authorize_reimport(...)`, `red_begin_reimport`, `red_apply_reimport_source_evidence`, `red_finalize_reimport`, `red_reimport_batch_result` (eksisterende), fixture-mønstret fra `tests/sql/test-reimport-legacy-migration.sql` linje 97-160.
- Produces: kontrakten for `public.red_apply_reimport_clause_evidence(uuid,text,jsonb) RETURNS jsonb` og fejltokens `REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID`, `REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`, `CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT`, `CLAUSE_EVIDENCE_GAP_INVALID`, `CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH`, `CLAUSE_EVIDENCE_ORDINAL_INVALID`.

- [ ] **Step 1: Skriv testen**

```sql
-- #148 4.1c: clause_evidence — autorisationsform, writer, dispositioner, replay, regression.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'CLAUSE_WRITER_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'CLAUSE_WRITER_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture: 149a-lignende source_evidence-batch for én record med kendt tekst.
CREATE FUNCTION pg_temp.se_fixture(p_key text, p_text text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := 148100 + abs(hashtext(p_key)) % 100000; v_profile text := 'fixture-se-'||p_key; v_sha text; v_config jsonb; v_actor uuid;
  v_msha text := encode(extensions.digest('manifest-se:'||p_key,'sha256'),'hex'); v_psha text := encode(extensions.digest('preview-se:'||p_key,'sha256'),'hex');
  v_auth uuid; v_batch uuid; v_payload jsonb;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES(v_source,'Fixture '||p_key,'synthetic','1900','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','fixture-v1',
    'observation_extraction_method','deterministic_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-source-evidence:','schema_version','source-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(v_source,v_profile,'source-evidence-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_payload:=jsonb_build_object('source_record_key',p_key,'source_id',v_source,'category','person_post','disposition','retain_source_only',
    'rendition_content_sha256',repeat('c',64),'source_span',jsonb_build_object('char_from',100,'char_to',100+char_length(p_text)),
    'page_evidence',jsonb_build_object('page_from',10,'page_to',10),'verbatim_text',p_text,
    'verbatim_sha256',encode(extensions.digest(p_text,'sha256'),'hex'),'anchor_method','deterministic-segment','segment_version','fixture');
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,'{"person_creates":0,"source_evidence":1}'::jsonb,jsonb_build_object('source-evidence:'||p_key,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:'||p_key,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN jsonb_build_object('source_id',v_source,'actor',v_actor,'record_key',p_key,'text',p_text,
    'parent_sha256',encode(extensions.digest(p_text,'sha256'),'hex'));
END $$;

-- Klausul-payload for teksten 'Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie Delta.' (to klausuler, ét mellemrum).
CREATE FUNCTION pg_temp.ce_payload(p_fx jsonb, p_clauses jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('source_record_key',p_fx->>'record_key','rendition_content_sha256',repeat('c',64),
    'parent_verbatim_sha256',p_fx->>'parent_sha256','clause_rules_version','clause-rules-fixture-v1','segmenter_version','clause_segment.py@v1',
    'ledger_sha256',repeat('d',64),'gap_charset',jsonb_build_array(' '),'clauses',p_clauses)
$$;
CREATE FUNCTION pg_temp.ce_clauses(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('ordinal',1,'char_from',0,'char_to',29,'classification','record_text','flags','[]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,1,29),'sha256'),'hex')),
    jsonb_build_object('ordinal',2,'char_from',30,'char_to',char_length(p_text),'classification','record_text','flags','["uncertain_marker"]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,31),'sha256'),'hex')))
$$;

-- Kør én clause_evidence-batch med ét element og vilkårlig payload.
CREATE FUNCTION pg_temp.ce_apply(p_fx jsonb, p_payload jsonb, p_element_key text, p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_profile text := 'fixture-ce-'||(p_fx->>'record_key'); v_config jsonb; v_sha text; v_auth uuid; v_batch uuid; v_result jsonb;
  v_msha text := encode(extensions.digest(p_nonce,'sha256'),'hex');
BEGIN
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','clause-evidence-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-clause-evidence:','schema_version','clause-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES((p_fx->>'source_id')::bigint,v_profile,'clause-evidence-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('9',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,v_profile,v_sha,'{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb,
    jsonb_build_object('clause-evidence:'||p_element_key,p_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('9',64));
  v_result:=public.red_apply_reimport_clause_evidence(v_batch,'clause-evidence:'||p_element_key,p_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth,'manifest_sha256',v_msha);
END $$;

DO $t1_authorization_forms$
BEGIN
  -- Regression (spec fund 8): 149a og 149b's former valideres uændret.
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":1}'::jsonb, jsonb_build_object('source-evidence:k','{}'::jsonb));
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb, jsonb_build_object('legacy-migration:k','{}'::jsonb));
  -- Ny form.
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_evidence":2}'::jsonb, jsonb_build_object('clause-evidence:a','{}'::jsonb,'clause-evidence:b','{}'::jsonb));
  -- Ukendt nøgle og præfiks afvises fortsat.
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"noget_andet":1}'::jsonb, jsonb_build_object('noget-andet:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb, jsonb_build_object('source-evidence:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 't1 authorization forms OK';
END $t1_authorization_forms$;

DO $t2_happy_path_and_replay$
DECLARE fx jsonb; r jsonb; v_text text := 'Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie Delta.'; v_n integer; v_disp text[]; v_auth uuid; v_batch uuid; v_res jsonb;
BEGIN
  fx := pg_temp.se_fixture('CE1', v_text);
  r := pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text)), 'CE1', 'ce1-nonce');
  IF (r->>'clauses')::int<>2 THEN RAISE EXCEPTION 'T2_CLAUSE_COUNT: %', r; END IF;
  SELECT count(*) INTO v_n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition rd ON rd.id=o.rendition_id
   WHERE rd.source_id=(fx->>'source_id')::bigint AND ob.observation_kind='clause';
  IF v_n<>2 THEN RAISE EXCEPTION 'T2_CLAUSE_ROWS: %', v_n; END IF;
  -- Absolutte offsets: helposten starter ved 100.
  IF NOT EXISTS (SELECT 1 FROM private.source_observation WHERE observation_kind='clause' AND clause_ordinal=1 AND char_from=100 AND char_to=129 AND page_from=10 AND page_to=10) THEN RAISE EXCEPTION 'T2_ABSOLUTE_OFFSETS'; END IF;
  SELECT array_agg(d.disposition ORDER BY ob.clause_ordinal) INTO v_disp FROM private.clause_disposition_current d JOIN private.source_observation ob ON ob.id=d.observation_id WHERE ob.observation_kind='clause' AND ob.extraction_run_id IN (SELECT id FROM private.extraction_run WHERE source_id=(fx->>'source_id')::bigint AND run_key LIKE 'reimport-clause-evidence:%');
  IF v_disp<>ARRAY['afventer_fortolkning','maskinelt_flagget'] THEN RAISE EXCEPTION 'T2_DISPOSITIONS: %', v_disp; END IF;
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='clause_evidence')<>1 THEN RAISE EXCEPTION 'T2_EVENT_MISSING'; END IF;
  IF (SELECT observed_counts FROM private.reimport_batch WHERE id=(r->>'batch_id')::uuid)<>'{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb THEN RAISE EXCEPTION 'T2_OBSERVED_COUNTS'; END IF;
  -- Replay: samme manifest/preview/profil → already_applied (samme batch-id fra red_begin_reimport).
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(r->>'manifest_sha256',repeat('9',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source_id')::bigint,'fixture-ce-CE1',(SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id=(fx->>'source_id')::bigint AND profile_id='fixture-ce-CE1'),
    '{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb,jsonb_build_object('clause-evidence:CE1',pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text))),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,r->>'manifest_sha256',repeat('9',64));
  IF v_batch<>(r->>'batch_id')::uuid THEN RAISE EXCEPTION 'T2_REPLAY_NEW_BATCH'; END IF;
  v_res:=public.red_reimport_batch_result(v_auth,v_batch);
  IF v_res->>'status'<>'finalized' THEN RAISE EXCEPTION 'T2_REPLAY_RESULT: %', v_res; END IF;
  RESET role;
  RAISE NOTICE 't2 happy path and replay OK';
END $t2_happy_path_and_replay$;

DO $t3_rejections$
DECLARE fx jsonb; v_text text := 'Echo Foxtrot, f. 1811, d. 1870. Gift 1840 m. Golf Hotel Ida.'; p jsonb; c jsonb;
BEGIN
  fx := pg_temp.se_fixture('CE2', v_text);
  c := pg_temp.ce_clauses(v_text);
  -- Forkert parent-hash (helposten er ændret siden ledgeren blev bygget).
  p := pg_temp.ce_payload(fx, c) || jsonb_build_object('parent_verbatim_sha256',repeat('e',64));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n1'),'CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT');
  -- Klausulhash matcher ikke udsnittet.
  p := pg_temp.ce_payload(fx, jsonb_set(c,'{0,verbatim_sha256}',to_jsonb(repeat('f',64))));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n2'),'CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH');
  -- Mellemrum indeholder ikke-hvidlistet tegn (klausul 2 starter ved 31 → tegn 30 = 'G' bliver "gap").
  p := pg_temp.ce_payload(fx, jsonb_set(jsonb_set(c,'{1,char_from}','31'),'{1,verbatim_sha256}',to_jsonb(encode(extensions.digest(substr(v_text,32),'sha256'),'hex'))));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n3'),'CLAUSE_EVIDENCE_GAP_INVALID');
  -- Ordinal-hul.
  p := pg_temp.ce_payload(fx, jsonb_set(c,'{1,ordinal}','3'));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n4'),'CLAUSE_EVIDENCE_ORDINAL_INVALID');
  -- Manglende nøgle i payload.
  p := pg_temp.ce_payload(fx, c) - 'gap_charset';
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n5'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID');
  -- Element-id ≠ clause-evidence:<record_key>.
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,pg_temp.ce_payload(fx,c),'ANDEN','n6'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID');
  -- Gyldig apply, derefter dublet under samme helpost afvises.
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, c), 'CE2', 'n7');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,pg_temp.ce_payload(fx,c),'CE2','n8'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS');
  RAISE NOTICE 't3 rejections OK';
END $t3_rejections$;

DO $t4_acl$
BEGIN
  IF NOT has_function_privilege('authenticated','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_clause_evidence(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'T4_ACL_INVALID';
  END IF;
  RAISE NOTICE 't4 acl OK';
END $t4_acl$;

ROLLBACK;
```

Bemærk til t3's gap-case: `substr(v_text,31)` er 1-indekseret i SQL og svarer til helpost-relativ `char_from=30`; ved at flytte klausul 2 til 31 bliver tegnet på indeks 30 (`G`) et "mellemrum", som ikke er i `gap_charset`.

- [ ] **Step 2: Kør og se den fejle**

Base som i plan 4.1a Task 2 Step 2 (writer_1939-ækvivalent, med 4.1a's DDL):

```bash
psql -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-writer.sql
```

Forventet: FAIL i `t1` (`REIMPORT_WRITER_AUTHORIZATION_INVALID` for den nye form).

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add tests/sql/test-clause-evidence-writer.sql
git commit -m "test(db): kontrakttest for writer-operationen clause_evidence (#148 4.1c) — fejler før DDL"
```

---

### Task 2: Writerens lukkede mængder + ny elementoperation i `schema.sql`

**Files:**
- Modify: `schema.sql` linje 2442 (CHECK), 2582-2608 (`validate_reimport_authorization_payload`), 2962-2975 (`red_finalize_reimport`), 3036-3060 (`red_reimport_batch_result`), ny funktion efter linje 2960, REVOKE/GRANT 3541/3543.

**Interfaces:**
- Produces: `private.write_clause_evidence(p_batch_id uuid, p_element_id text, p_payload jsonb) RETURNS jsonb` og `public.red_apply_reimport_clause_evidence(uuid,text,jsonb) RETURNS jsonb`; returværdi `{"clauses": n, "parent_observation_id": uuid, "run_id": uuid}`.

- [ ] **Step 1: Udvid de lukkede mængder**

1. Linje 2442: `CHECK(operation IN ('source_evidence','person_create','legacy_migration','clause_evidence','canonical_delta','reversal','activation'))`.
2. `validate_reimport_authorization_payload`: tilføj `v_clause_evidence bigint;`; udvid nøgletjekket til at tillade `clause_evidence` på samme måde som `legacy_migrations` (numerisk, `^[0-9]+$`); nøgleantal `NOT IN (2,3,4)`; nøgleliste `NOT IN ('person_creates','source_evidence','legacy_migrations','clause_evidence')`; `v_clause_evidence:=coalesce((p_expected_counts->>'clause_evidence')::bigint,0);`; summen `v_person_creates+v_source_evidence+v_legacy_migrations+v_clause_evidence`; præfiks-regexen får `AND element.key !~ '^clause-evidence:.+$'`; og en ny linje `OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements) key WHERE key ~ '^clause-evidence:.+$')<>v_clause_evidence`.
3. `red_finalize_reimport`: efter `legacy_migrations`-CASE'n tilføj `|| CASE WHEN v_batch.expected_counts ? 'clause_evidence' THEN jsonb_build_object('clause_evidence',count(*) FILTER(WHERE operation='clause_evidence')) ELSE '{}'::jsonb END`.
4. `red_reimport_batch_result`: spejl 2. (nøgler, `NOT IN (2,3,4)`, `v_expected_clause_evidence`, sum, præfiks `^clause-evidence:`, og `event.operation IN ('person_create','source_evidence','legacy_migration','clause_evidence')`).

- [ ] **Step 2: Skriv writer-funktionen**

Indsæt efter `public.red_apply_reimport_legacy_migration` (linje 2960):

```sql
-- #148 4.1c: klausul-observationer under en helpost fra en hash-bundet ledger.
-- Payload bærer ingen tekst; udsnit og hashes verificeres mod helposten i basen.
CREATE FUNCTION private.write_clause_evidence(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_batch private.reimport_batch%ROWTYPE; v_auth private.reimport_authorization%ROWTYPE; v_profile private.reimport_writer_profile%ROWTYPE;
  v_record private.source_record%ROWTYPE; v_occurrence private.source_record_occurrence%ROWTYPE; v_parent private.source_observation%ROWTYPE;
  v_run uuid; v_clause jsonb; v_expected_ordinal integer := 0; v_prev_end integer := 0; v_from integer; v_to integer; v_gap text; v_text text;
  v_gap_chars text[]; v_obs uuid; v_count integer := 0; v_disposition text; v_run_key text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED'; END IF;
  v_batch:=private.require_reimport_open_batch(p_batch_id);
  PERFORM private.require_reimport_writer_editor();
  PERFORM private.lock_reimport_writer(v_batch.source_id,v_batch.profile_id);
  SELECT * INTO v_auth FROM private.reimport_authorization WHERE id=v_batch.authorization_id;
  SELECT * INTO v_profile FROM private.reimport_writer_profile WHERE source_id=v_batch.source_id AND profile_id=v_batch.profile_id AND profile_sha256=v_batch.profile_sha256;
  IF NOT FOUND OR NOT v_auth.authorized_elements ? p_element_id OR v_auth.authorized_elements->p_element_id IS DISTINCT FROM p_payload THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED';
  END IF;
  IF jsonb_typeof(p_payload)<>'object'
     OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(p_payload) k)
        <> ARRAY['clause_rules_version','clauses','gap_charset','ledger_sha256','parent_verbatim_sha256','rendition_content_sha256','segmenter_version','source_record_key']
     OR p_element_id<>'clause-evidence:'||coalesce(p_payload->>'source_record_key','')
     OR coalesce(p_payload->>'rendition_content_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(p_payload->>'parent_verbatim_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(p_payload->>'ledger_sha256','') !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(coalesce(p_payload->>'clause_rules_version','')),'') IS NULL
     OR nullif(btrim(coalesce(p_payload->>'segmenter_version','')),'') IS NULL
     OR jsonb_typeof(p_payload->'gap_charset')<>'array' OR jsonb_array_length(p_payload->'gap_charset')=0
     OR jsonb_typeof(p_payload->'clauses')<>'array' OR jsonb_array_length(p_payload->'clauses')=0 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID';
  END IF;
  SELECT array_agg(value) INTO v_gap_chars FROM jsonb_array_elements_text(p_payload->'gap_charset');
  SELECT * INTO v_record FROM private.source_record WHERE source_id=v_batch.source_id AND record_key=p_payload->>'source_record_key' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_RECORD_MISSING'; END IF;
  IF (SELECT count(*) FROM private.source_record_anchor_current a WHERE a.source_record_id=v_record.id AND a.decision_status='accepted')<>1 THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_ANCHOR_AMBIGUOUS';
  END IF;
  SELECT o.* INTO v_occurrence FROM private.source_record_anchor_current a JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
   WHERE a.source_record_id=v_record.id AND a.decision_status='accepted';
  IF NOT EXISTS (SELECT 1 FROM private.source_rendition r WHERE r.id=v_occurrence.rendition_id AND r.content_sha256=p_payload->>'rendition_content_sha256') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RENDITION_DRIFT';
  END IF;
  -- Præcis én helpost under forekomsten; radlås mod samtidige klausul-writes (spec 4.1.4).
  IF (SELECT count(*) FROM private.source_observation ob WHERE ob.occurrence_id=v_occurrence.id AND ob.parent_observation_id IS NULL)<>1 THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_PARENT_AMBIGUOUS';
  END IF;
  SELECT * INTO v_parent FROM private.source_observation ob WHERE ob.occurrence_id=v_occurrence.id AND ob.parent_observation_id IS NULL FOR UPDATE;
  IF encode(digest(v_parent.verbatim_text,'sha256'),'hex')<>p_payload->>'parent_verbatim_sha256' THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM private.source_observation WHERE parent_observation_id=v_parent.id) THEN RAISE EXCEPTION 'REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS'; END IF;
  v_run_key:=(v_profile.writer_config->>'run_key_prefix')||v_batch.manifest_sha256;
  INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_batch.source_id,v_run_key,v_profile.writer_config->>'schema_version',v_profile.writer_config->>'extractor_version',v_profile.profile_version,v_batch.manifest_sha256,
         jsonb_build_object('batch_id',p_batch_id,'profile_sha256',v_batch.profile_sha256)) ON CONFLICT(source_id,run_key) DO NOTHING;
  SELECT id INTO v_run FROM private.extraction_run WHERE source_id=v_batch.source_id AND run_key=v_run_key;
  FOR v_clause IN SELECT value FROM jsonb_array_elements(p_payload->'clauses') LOOP
    v_expected_ordinal:=v_expected_ordinal+1;
    IF jsonb_typeof(v_clause)<>'object' OR (v_clause->>'ordinal')::int IS DISTINCT FROM v_expected_ordinal THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_ORDINAL_INVALID'; END IF;
    v_from:=(v_clause->>'char_from')::int; v_to:=(v_clause->>'char_to')::int;
    IF v_from IS NULL OR v_to IS NULL OR v_from<v_prev_end OR v_to<=v_from OR v_to>char_length(v_parent.verbatim_text)
       OR coalesce(v_clause->>'verbatim_sha256','') !~ '^[0-9a-f]{64}$' OR jsonb_typeof(v_clause->'flags')<>'array'
       OR NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='clause_classification' AND code=v_clause->>'classification') THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID';
    END IF;
    v_gap:=substr(v_parent.verbatim_text, v_prev_end+1, v_from-v_prev_end);
    IF v_gap<>'' AND EXISTS (SELECT 1 FROM regexp_split_to_table(v_gap,'') ch WHERE NOT (ch = ANY(v_gap_chars))) THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_GAP_INVALID'; END IF;
    v_text:=substr(v_parent.verbatim_text, v_from+1, v_to-v_from);
    IF encode(digest(v_text,'sha256'),'hex')<>v_clause->>'verbatim_sha256' THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH'; END IF;
    INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
      parent_observation_id,clause_ordinal,clause_classification,clause_flags)
    VALUES(v_occurrence.id,'clause',v_parent.page_from,v_parent.page_to,v_parent.char_from+v_from,v_parent.char_from+v_to,v_text,v_parent.quality_status,
      (v_profile.writer_config->>'observation_extraction_method')||':'||(p_payload->>'clause_rules_version'),v_run,
      v_parent.id,v_expected_ordinal,v_clause->>'classification',v_clause->'flags') RETURNING id INTO v_obs;
    v_disposition:=CASE WHEN v_clause->>'classification'='structural_header' THEN 'strukturel'
                        WHEN jsonb_array_length(v_clause->'flags')>0 THEN 'maskinelt_flagget'
                        ELSE 'afventer_fortolkning' END;
    INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
    VALUES(v_obs,1,v_disposition,'machine',jsonb_build_object('batch_id',p_batch_id,'element_id',p_element_id,'manifest_sha256',v_batch.manifest_sha256,'clause_rules_version',p_payload->>'clause_rules_version'));
    v_prev_end:=v_to; v_count:=v_count+1;
  END LOOP;
  v_gap:=substr(v_parent.verbatim_text, v_prev_end+1);
  IF v_gap<>'' AND EXISTS (SELECT 1 FROM regexp_split_to_table(v_gap,'') ch WHERE NOT (ch = ANY(v_gap_chars))) THEN RAISE EXCEPTION 'CLAUSE_EVIDENCE_GAP_INVALID'; END IF;
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES(p_batch_id,p_element_id,'clause_evidence',v_record.record_key,p_payload||jsonb_build_object('parent_observation_id',v_parent.id,'run_id',v_run,'clauses_written',v_count),
         encode(digest((p_payload||jsonb_build_object('clauses_written',v_count))::text,'sha256'),'hex'));
  RETURN jsonb_build_object('clauses',v_count,'parent_observation_id',v_parent.id,'run_id',v_run);
END $$;

CREATE FUNCTION public.red_apply_reimport_clause_evidence(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  RETURN private.write_clause_evidence(p_batch_id,p_element_id,p_payload);
END $$;
```

Tilføj `public.red_apply_reimport_clause_evidence(uuid,text,jsonb)` til REVOKE-listen (linje 3541) og GRANT-listen til `authenticated` (linje 3543), og `private.write_clause_evidence(uuid,text,jsonb)` til den nærmeste REVOKE-liste for private writer-funktioner i `schema.sql` (søg `REVOKE ALL ON FUNCTION private.ensure_reimport_source_evidence`).

- [ ] **Step 3: Kør Task 1's test og de eksisterende writer-suiter**

```bash
# frisk base som i 4.1a Task 2 Step 2, derefter:
psql -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-writer.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

Forventet: `t1…t4 OK`; `test-reimport-writer.sql` fejler nu på ACL-paritet, fordi den nye RPC ikke står i dens liste — det rettes i Task 3, ikke ved at fjerne RPC'en.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add schema.sql
git commit -m "feat(db): elementoperationen clause_evidence i den generelle writer (#148 4.1c)"
```

---

### Task 3: Migration, ACL-lister, db-verify, testlister

**Files:**
- Modify: `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, `tests/sql/test-reimport-writer.sql`, `tests/sql/inspect-reimport-writer-catalog.sql`

- [ ] **Step 1: Migration**

I 4.1c-blokken (før `$public_red_revoke$`): (a) gentag `$lm_operation_check$`-mønstret fra `db-migrations.sql:16519-16532` med den nye værdiliste og navnet `$ce_operation_check$`; (b) `CREATE OR REPLACE FUNCTION` for `validate_reimport_authorization_payload`, `red_finalize_reimport`, `red_reimport_batch_result`, `private.write_clause_evidence` og `public.red_apply_reimport_clause_evidence` med kroppene ordret fra `schema.sql`; (c) REVOKE/GRANT for de to nye funktioner; (d) i `$public_red_revoke$`-blokkens `v_authenticated`-array tilføj `'public.red_apply_reimport_clause_evidence(uuid,text,jsonb)'::regprocedure` (alfabetisk plads).

- [ ] **Step 2: `db-rls.sql`**

Tilføj `private.write_clause_evidence(uuid,text,jsonb)` til REVOKE-listen for private reimport-funktioner (~1170-1178), og `public.red_apply_reimport_clause_evidence(uuid,text,jsonb)` både i REVOKE-listen (~1179-1189) og i GRANT-listen til `authenticated` (~1194-1200).

- [ ] **Step 3: `db-verify.sql`**

1. I `$reimport_event_operation_check_verify$`: `IF v_count<>1 OR v_definition NOT LIKE '%legacy_migration%' OR v_definition NOT LIKE '%clause_evidence%' THEN`.
2. I `$public_red_acl_verify$`'s `v_authenticated`: tilføj `'public.red_apply_reimport_clause_evidence(uuid,text,jsonb)'::regprocedure`.
3. Ny blok:

```sql
DO $clause_evidence_writer_verify$
BEGIN
  IF to_regprocedure('private.write_clause_evidence(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_clause_evidence(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_WRITER_MISSING';
  END IF;
  IF has_function_privilege('authenticated','private.write_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_WRITER_ACL_INVALID';
  END IF;
  IF pg_get_functiondef('private.validate_reimport_authorization_payload(jsonb,jsonb)'::regprocedure) NOT LIKE '%clause-evidence:%' THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_AUTHORIZATION_FORM_MISSING';
  END IF;
  RAISE NOTICE 'OK: #148 clause_evidence-writer, ACL og autorisationsform';
END $clause_evidence_writer_verify$;
```

- [ ] **Step 4: Testlister**

- `tests/sql/test-reimport-writer.sql`: tilføj `'public.red_apply_reimport_clause_evidence(uuid,text,jsonb)'` til RPC-listen (linje ~15-25) og til `$acl_parity$`-arrayet (forventet `authenticated=true`, `service_role=false`, samme som `red_apply_reimport_legacy_migration`), og `'private.write_clause_evidence(uuid,text,jsonb)'` med `false/false`.
- `tests/sql/inspect-reimport-writer-catalog.sql`: tilføj `'red_apply_reimport_clause_evidence'` (public) og `'write_clause_evidence'` (private) til navnelisterne.

- [ ] **Step 5: Kør alle tre stier + db-verify**

```bash
# migreret sti (to gange), frisk sti, og frisk+migration — som i plan 4.1a Task 3 Step 2-3,
# derefter for hver base:
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-writer.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
```

Forventet: alt grønt; `OK: #148 clause_evidence-writer …`.

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-reimport-writer.sql tests/sql/inspect-reimport-writer-catalog.sql
git commit -m "chore(db): migration, ACL-lister og verify for clause_evidence (#148 4.1c)"
```

---

### Task 4: Profiltype og manifest-builder (Python)

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/reimport_profile.py`, `test_reimport_profile.py`
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json`
- Create: `.claude/skills/daa-extract/scripts/build_clause_evidence_manifest.py`, `test_build_clause_evidence_manifest.py`
- Modify: `.github/workflows/ci.yml` (pytest-listen på linje 103)

**Interfaces:**
- `reimport_profile.load_profile` accepterer `profile_schema_version = "reimport-clause-evidence-profile-v1"` med nøgler `{profile_schema_version, source_id, profile_id, profile_version, writer_config, raw_text_sha256, clause_rules_version, segmenter_version, expected_counts}` hvor `expected_counts = {person_creates: 0, source_evidence: 0, clause_evidence: N>0}`.
- `build_clause_evidence_manifest.py --profile <fil> --ledger <clause-ledger-v1.json> --output <fil>` producerer et manifest med `source`, `expected_counts {source_evidence:0, person_creates:0, canonical_delta:0, clause_evidence:N}`, `operations[]` (`element_id: clause-evidence:<key>`, `dependency_class: clause_evidence`, payload præcis som writerens 8 nøgler) og `manifest_content_sha256`.

- [ ] **Step 1: Profil-fil**

```json
{
  "profile_schema_version": "reimport-clause-evidence-profile-v1",
  "source_id": 1,
  "profile_id": "daa-2018-20-clause-evidence-v1",
  "profile_version": "clause-evidence-v1",
  "writer_config": {
    "citation_label_template": "DAA 2018-20 side {page_from}",
    "extractor_version": "clause-evidence-v1",
    "observation_extraction_method": "clause_segment_v1",
    "rendition_key": "daa-2018-20-pdftotext-r1",
    "rendition_kind": "pdf_text_layer",
    "rendition_metadata": {
      "edition": "2018-20",
      "pdf_sha256": "3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a",
      "pdftotext_version": "26.07.0"
    },
    "run_key_prefix": "reimport-clause-evidence:",
    "schema_version": "clause-evidence-manifest-v1"
  },
  "raw_text_sha256": "2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563",
  "clause_rules_version": "<clause_rules.version fra 4.1b's GO'ede profilversion>",
  "segmenter_version": "clause_segment.py@v1",
  "expected_counts": {"person_creates": 0, "source_evidence": 0, "clause_evidence": 591}
}
```

`clause_rules_version` udfyldes med den faktiske, GO'ede værdi fra `extraction-profiles.json` (ingen pladsholder må blive stående; `reimport_profile._assert_no_placeholder` afviser `<…>`).

- [ ] **Step 2: Fejlende profil-tests**

Tilføj til `test_reimport_profile.py` (følg filens eksisterende mønster for `tmp_path`-profiler):

```python
def test_clause_evidence_profile_validates(tmp_path):
    profile = json.loads((REPO / ".claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json").read_text())
    loaded = reimport_profile.load_profile(REPO / ".claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json")
    assert loaded["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "clause_evidence": 591}
    assert loaded["profile_sha256"]
    broken = dict(profile); broken["expected_counts"] = {"person_creates": 0, "source_evidence": 1, "clause_evidence": 591}
    path = tmp_path / "p.json"; path.write_text(json.dumps(broken))
    with pytest.raises(reimport_profile.ProfileError, match="PROFILE_EXPECTED_COUNTS_INVALID"):
        reimport_profile.load_profile(path)
```

- [ ] **Step 3: Implementér profiltypen**

I `reimport_profile.py`:

```python
CLAUSE_PROFILE_SCHEMA_VERSION = "reimport-clause-evidence-profile-v1"
CLAUSE_PROFILE_KEYS = {"profile_schema_version", "source_id", "profile_id", "profile_version", "writer_config",
                       "raw_text_sha256", "clause_rules_version", "segmenter_version", "expected_counts"}
CLAUSE_EXPECTED_COUNTS_KEYS = {"person_creates", "source_evidence", "clause_evidence"}


def _validate_clause_evidence_profile(profile: dict[str, Any]) -> None:
    if set(profile) != CLAUSE_PROFILE_KEYS:
        _fail("PROFILE_KEYS_INVALID")
    if not _positive_int(profile["source_id"]) or not _text(profile["profile_id"]) or not _text(profile["profile_version"]) \
            or not _text(profile["clause_rules_version"]) or not _text(profile["segmenter_version"]):
        _fail("PROFILE_FIELD_SET_INVALID")
    if not isinstance(profile["raw_text_sha256"], str) or not HASH_RE.match(profile["raw_text_sha256"]):
        _fail("PROFILE_MEASURED_HASH_INVALID")
    counts = profile["expected_counts"]
    if not isinstance(counts, dict) or set(counts) != CLAUSE_EXPECTED_COUNTS_KEYS \
            or counts["person_creates"] != 0 or counts["source_evidence"] != 0 or not _positive_int(counts["clause_evidence"]):
        _fail("PROFILE_EXPECTED_COUNTS_INVALID")
    _assert_collation_stable(profile["writer_config"])
    config = profile["writer_config"]
    metadata = config.get("rendition_metadata") if isinstance(config, dict) else None
    if not isinstance(metadata, dict) or not isinstance(metadata.get("pdf_sha256"), str) or not HASH_RE.match(metadata["pdf_sha256"]):
        _fail("PROFILE_MEASURED_HASH_INVALID")
    _validate_writer_config(config, metadata["pdf_sha256"])
```

og i `load_profile`: `elif profile.get("profile_schema_version") == CLAUSE_PROFILE_SCHEMA_VERSION: _validate_clause_evidence_profile(profile)`.

- [ ] **Step 4: Manifest-builder + test**

Test (`test_build_clause_evidence_manifest.py`): bygger et syntetisk ledger med to records (2 + 1 klausuler), kalder `build_manifest(profile, ledger)` og asserterer: 2 operations sorteret på `record_key` (`COLLATE "C"`-ækvivalent: Python-bytesortering), `element_id == "clause-evidence:<key>"`, payload-nøgler præcis de 8, `expected_counts["clause_evidence"] == 2`, ingen `verbatim_text` i output, `LEDGER_COUNT_MISMATCH` når profilen forventer 3, og `LEDGER_RULES_VERSION_MISMATCH` når `clause_rules_version` afviger.

Implementation:

```python
#!/usr/bin/env python3
"""Byg clause_evidence-manifest fra 4.1b's ledger-artefakt (#148 4.1c). Ingen tekst i output."""
from __future__ import annotations
import argparse, hashlib, json, sys
from pathlib import Path
from typing import Any

class BuildError(ValueError): ...
def _fail(code: str) -> None: raise BuildError(code)

def build_manifest(profile: dict[str, Any], ledger: dict[str, Any]) -> dict[str, Any]:
    if ledger.get("schema_version") != "clause-ledger-v1": _fail("LEDGER_SCHEMA_INVALID")
    if ledger.get("rules_version") != profile["clause_rules_version"]: _fail("LEDGER_RULES_VERSION_MISMATCH")
    if ledger.get("segmenter_version") != profile["segmenter_version"]: _fail("LEDGER_SEGMENTER_VERSION_MISMATCH")
    gap_charset = ledger.get("gap_charset") or [" "]
    operations, seen = [], set()
    for rec in sorted(ledger["records"], key=lambda r: r["record_key"].encode("utf-8")):
        key = rec["record_key"]
        if key in seen: _fail("LEDGER_RECORD_KEY_DUPLICATE")
        seen.add(key)
        clauses = [{"ordinal": c["ordinal"], "char_from": c["char_from"], "char_to": c["char_to"],
                    "classification": c["classification"], "flags": list(c["flags"]), "verbatim_sha256": c["verbatim_sha256"]}
                   for c in sorted(rec["clauses"], key=lambda c: c["ordinal"])]
        if [c["ordinal"] for c in clauses] != list(range(1, len(clauses) + 1)): _fail("LEDGER_ORDINALS_INVALID")
        if not clauses: _fail("LEDGER_RECORD_WITHOUT_CLAUSES")
        operations.append({"element_id": f"clause-evidence:{key}", "dependency_class": "clause_evidence",
                           "source_record_key": key, "rendition_content_sha256": rec["rendition_content_sha256"],
                           "parent_verbatim_sha256": rec["parent_verbatim_sha256"], "clause_rules_version": rec["rules_version"],
                           "segmenter_version": ledger["segmenter_version"], "ledger_sha256": rec["ledger_sha256"],
                           "gap_charset": gap_charset, "clauses": clauses})
    if len(operations) != profile["expected_counts"]["clause_evidence"]: _fail("LEDGER_COUNT_MISMATCH")
    manifest = {"source": {"id": profile["source_id"], "profile_id": profile["profile_id"], "profile_sha256": profile["profile_sha256"]},
                "expected_counts": {"source_evidence": 0, "person_creates": 0, "canonical_delta": 0, "clause_evidence": len(operations)},
                "operations": operations}
    manifest["manifest_content_sha256"] = hashlib.sha256(json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return manifest

def main() -> None:
    parser = argparse.ArgumentParser()
    for flag in ("--profile", "--ledger", "--output"): parser.add_argument(flag, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from reimport_profile import load_profile
    profile = load_profile(Path(args.profile))
    ledger = json.loads(Path(args.ledger).read_text(encoding="utf-8"))
    out = Path(args.output)
    if out.exists(): _fail("CLAUSE_EVIDENCE_OUTPUT_EXISTS")
    out.write_text(json.dumps(build_manifest(profile, ledger), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if __name__ == "__main__": main()
```

Bemærk: `gap_charset` skal komme fra ledger-artefaktet; udvid 4.1b's `build_clause_ledger.py` til at skrive `"gap_charset": rules["gap_charset"]` i ledgerens topniveau (én linje), så manifestet er hash-bundet til profilens frosne tegnsæt.

- [ ] **Step 5: Kør tests, tilføj til CI, commit**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_reimport_profile.py .claude/skills/daa-extract/scripts/test_build_clause_evidence_manifest.py .claude/skills/daa-extract/scripts/test_build_clause_ledger.py -q
```

Tilføj `test_build_clause_evidence_manifest.py` til pytest-listen i `ci.yml` (linje 103).

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/reimport_profile.py .claude/skills/daa-extract/scripts/test_reimport_profile.py .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json .claude/skills/daa-extract/scripts/build_clause_evidence_manifest.py .claude/skills/daa-extract/scripts/test_build_clause_evidence_manifest.py .claude/skills/daa-extract/scripts/build_clause_ledger.py .github/workflows/ci.yml
git commit -m "feat(evidens): clause_evidence-profil og manifest-builder fra klausul-ledger (#148 4.1c)"
```

---

### Task 5: R-klient, preview og integrationstest

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` (`validate_reimport_manifest` 20-68, `reimport_writer_expected_counts` 81-85, `execute_reimport` 181-190, gateway 258-272)
- Create: `.claude/skills/daa-extract/scripts/export_clause_evidence_preview.R`
- Create: `tests/integration/test-reimport-clause-evidence.R`
- Modify: `.github/workflows/ci.yml` (writer_1939-jobbet: nyt trin efter "Legacy migration writer integration (149b)")

- [ ] **Step 1: Skriv integrationstesten (fejler først)**

Følg `tests/integration/test-reimport-legacy-migration.R` linje 1-95 ordret for opsætning (nonce, aktør, source, source-evidence-profil, `authorize`, en source_evidence-batch med én afdød record D1 med tekst `"Alfa <run_key> Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie."`). Derefter:

```r
# ---- clause_evidence: manifest fra en syntetisk ledger ---------------------------
ce_profile_id <- paste0(profile_id, "-ce")
ce_config <- sub('"run_key_prefix":"reimport-source-evidence:"', '"run_key_prefix":"reimport-clause-evidence:"',
  sub('"schema_version":"source-evidence-manifest-v1"', '"schema_version":"clause-evidence-manifest-v1"',
  sub('"observation_extraction_method":"deterministic_segment_v1"', '"observation_extraction_method":"clause_segment_v1"', writer_config)))
ce_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(ce_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'clause-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, ce_profile_id, ce_sha, ce_config))
sha_text <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
c1 <- substr(text_dead, 1L, 29L); c2 <- substr(text_dead, 31L, nchar(text_dead))
clauses <- list(
  list(ordinal = 1L, char_from = 0L, char_to = 29L, classification = "record_text", flags = list(), verbatim_sha256 = sha_text(c1)),
  list(ordinal = 2L, char_from = 30L, char_to = nchar(text_dead), classification = "record_text", flags = list(), verbatim_sha256 = sha_text(c2)))
manifest_ce <- list(
  manifest_content_sha256 = run_hash("manifest-ce"),
  source = list(id = source_id, profile_id = ce_profile_id, profile_sha256 = ce_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, clause_evidence = 1L),
  operations = list(list(element_id = paste0("clause-evidence:", key_dead), dependency_class = "clause_evidence",
    source_record_key = key_dead, rendition_content_sha256 = sha("c"), parent_verbatim_sha256 = sha_text(text_dead),
    clause_rules_version = "clause-rules-fixture-v1", segmenter_version = "clause_segment.py@v1",
    ledger_sha256 = sha("d"), gap_charset = list(" "), clauses = clauses)))
validate_reimport_manifest(manifest_ce)
preview_sha_ce <- run_hash("preview-ce")
before <- q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]]
dry <- execute_reimport(manifest_ce, preview_sha_ce, "dry-run", env_gateway(), NULL)
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
  q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]] == before)
applied <- execute_reimport(manifest_ce, preview_sha_ce, "apply", env_gateway(), list(id = authorize(manifest_ce, preview_sha_ce)))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
stopifnot(q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]] == before + 2L)
stopifnot(count1("SELECT count(*) FROM private.clause_disposition_current d JOIN private.source_observation o ON o.id=d.observation_id WHERE o.observation_kind='clause' AND d.disposition='afventer_fortolkning'") >= 2L)
replay <- execute_reimport(manifest_ce, preview_sha_ce, "apply", env_gateway(), list(id = authorize(manifest_ce, preview_sha_ce)))
stopifnot(identical(replay$status, "already_applied"))
cat("clause_evidence integration OK\n")
```

- [ ] **Step 2: Kør og se den fejle**

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=clause_schema_test
Rscript tests/integration/test-reimport-clause-evidence.R
```

Forventet: FAIL med `REIMPORT_MANIFEST_COUNTS_INVALID` (R-klienten kender ikke `clause_evidence`).

- [ ] **Step 3: Udvid R-klienten**

I `validate_reimport_manifest`:
- `base_counts` uændret; tillad nøglemængderne `base`, `base+legacy_migrations`, `base+clause_evidence` (ikke begge samtidig):

```r
  allowed_sets <- list(base_counts, c(base_counts, "legacy_migrations"), c(base_counts, "clause_evidence"))
  if (!is.list(manifest$expected_counts) ||
      !any(vapply(allowed_sets, function(s) identical(sort(count_names), sort(s)), logical(1))) || ...
```
- `dependency_class %in% c("source_evidence", "person_create", "legacy_migration", "clause_evidence")`.
- Tællinger: samme mønster som `legacy_migrations` for `clause_evidence` (`has_clause_evidence_ops`; nøglen skal findes, hvis der er operationer, og tælle rigtigt).

I `reimport_writer_expected_counts`: `intersect(c("person_creates", "source_evidence", "legacy_migrations", "clause_evidence"), ...)`.

I `execute_reimport`-loopet: `else if (identical(operation$dependency_class, "clause_evidence")) { call("clause_evidence", batch_id, operation$element_id, payload) }`.

I gatewayen (efter `legacy_migration = {...}`):

```r
      clause_evidence = {
        result <- query("SELECT public.red_apply_reimport_clause_evidence($1,$2,$3::jsonb)::text AS value", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))$value[[1L]]
        jsonlite::fromJSON(result, simplifyVector = FALSE)
      },
```

Vigtigt om JSON-serialisering: `flags = list()` skal blive `[]`, ikke `{}`; `jsonlite::toJSON(list(), auto_unbox=TRUE)` giver `[]`. `gap_charset = list(" ")` giver `[" "]`. Payloaden skal serialiseres **identisk** i `red_authorize_reimport` (`reimport_authorized_payloads`) og i apply-kaldet, ellers `REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED`; det er allerede sådan for de andre operationer, fordi begge går gennem samme `toJSON`.

- [ ] **Step 4: Preview-script**

`export_clause_evidence_preview.R` — kopiér `export_reimport_preview.R`'s CLI/hash/READ ONLY-ramme (linje 1-45) og byg outputtet af:

```r
preview <- list(
  preview_schema_version = "clause-evidence-preview-v1",
  manifest_content_sha256 = manifest$manifest_content_sha256, manifest_bytes_sha256 = manifest_bytes_sha256,
  narrative_record_contract_version = query("SELECT public.narrative_record_contract_version() v")$v[[1L]],
  source = preview_source_state(query, manifest),
  expected_counts = reimport_writer_expected_counts(manifest),
  before_counts = list(
    helposts = query("SELECT count(*) n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1 AND ob.parent_observation_id IS NULL", list(manifest$source$id))$n[[1L]],
    clauses = query("SELECT count(*) n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1 AND ob.observation_kind='clause'", list(manifest$source$id))$n[[1L]]),
  record_key_coverage = preview_record_key_coverage(query, manifest),
  canonical_baseline_sha256 = preview_canonical_baseline(query),
  database_write_authorized = FALSE, production_authorized = FALSE)
```

(`preview_source_state`, `preview_record_key_coverage`, `preview_canonical_baseline` findes i `export_reimport_preview_helpers.R`.) Skriv output med `file.create` + `Sys.chmod(...,"0600")` som eksportscriptet, og print kun tal.

- [ ] **Step 5: Kør integrationstesten + CI-trin**

```bash
Rscript tests/integration/test-reimport-clause-evidence.R
```

Forventet: `clause_evidence integration OK`. Tilføj i `ci.yml` (writer_1939-jobbet, efter 149b-integrationstrinnet, samme `env:` som det):

```yaml
      - name: Clause evidence writer SQL (#148 4.1c)
        env: { PGPASSWORD: postgres }
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-writer.sql
      - name: Clause evidence writer integration (#148 4.1c)
        env: { PGHOST: localhost, PGPORT: "5432", PGUSER: postgres, PGPASSWORD: postgres, PGDATABASE: writer_1939 }
        run: Rscript tests/integration/test-reimport-clause-evidence.R
```

Brug præcis de env-nøgler, 149b-trinnet bruger.

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/apply_reimport_helpers.R .claude/skills/daa-extract/scripts/export_clause_evidence_preview.R tests/integration/test-reimport-clause-evidence.R .github/workflows/ci.yml
git commit -m "feat(evidens): R-klient, preview og integrationstest for clause_evidence (#148 4.1c)"
```

---

### Task 6: Rigtig kørsel — 591 records i restore

**Files:**
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` (afsnit 4.1c), `docs/changelog.md`
- Modify: `docs/runbooks/clause-evidence-reimport-rehearsal.md` (Create; kort, peger på `legacy-migration-reimport-rehearsal.md` for restore-trinnene)

Forudsætning: restore `$DB` med 4.1a-migration og 4.1c-migration anvendt (`db-migrations.sql` to gange + `db-rls.sql`), 4.1b's ledger-artefakt `$ART/ledger/clause-ledger-v1.json`, projektejerens redaktionsprofil-UUID `$ACTOR_UUID` (findes i `public.profiles` i restoren), `PGTZ=UTC`, `umask 077`.

- [ ] **Step 1: Profilrække + manifest + preview**

```bash
set -euo pipefail; umask 077; export PGTZ=UTC PGDATABASE="$DB"
P=.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-clause-evidence-v1.json
PROFILE_SHA=$(cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -c "import json,sys;from reimport_profile import load_profile;print(load_profile(sys.argv[1])['profile_sha256'])" "$OLDPWD/$P")
psql -X -v ON_ERROR_STOP=1 -v cfg="$(python3 -c "import json;print(json.dumps(json.load(open('$P'))['writer_config'],ensure_ascii=False,separators=(',',':'),sort_keys=True))")" -c \
 "INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(1,'daa-2018-20-clause-evidence-v1','clause-evidence-v1',private.reimport_canonical_json_sha256(:'cfg'::jsonb),:'cfg'::jsonb)"
psql -X -Atc "SELECT profile_sha256='$PROFILE_SHA' FROM private.reimport_writer_profile WHERE profile_id='daa-2018-20-clause-evidence-v1'"   # t
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 build_clause_evidence_manifest.py --profile "$OLDPWD/$P" --ledger "$ART/ledger/clause-ledger-v1.json" --output "$ART/clause-evidence-manifest-v1.json"
cd -
MANIFEST_BYTES_SHA=$(shasum -a 256 "$ART/clause-evidence-manifest-v1.json" | cut -d' ' -f1)
Rscript .claude/skills/daa-extract/scripts/export_clause_evidence_preview.R --profile "$P" --manifest "$ART/clause-evidence-manifest-v1.json" --manifest-sha256 "$MANIFEST_BYTES_SHA" --output "$ART/clause-evidence-preview-v1.json"
PREVIEW_SHA=$(shasum -a 256 "$ART/clause-evidence-preview-v1.json" | cut -d' ' -f1)
```

Forventet i preview: `before_counts.helposts=591`, `before_counts.clauses=0`, `record_key_coverage` 591/591/0/0, `canonical_baseline_sha256` noteret.

- [ ] **Step 2: Dry-run, autorisation, apply**

```bash
DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" Rscript .claude/skills/daa-extract/scripts/apply_reimport.R --manifest "$ART/clause-evidence-manifest-v1.json" --manifest-sha256 "$MANIFEST_BYTES_SHA" --preview-sha256 "$PREVIEW_SHA" --dry-run
# Autorisation: generér 0600 SQL-fil med expected_counts + authorized_elements fra manifestet (samme mønster som 149b §3.6):
/usr/bin/python3 - "$ART/clause-evidence-manifest-v1.json" "$ART/authorize-ce.sql" "$ACTOR_UUID" "$PREVIEW_SHA" "$PROFILE_SHA" <<'PY'
import json,sys,os
m=json.load(open(sys.argv[1])); actor,preview,psha=sys.argv[3:6]
els={op["element_id"]:{k:v for k,v in op.items() if k not in ("element_id","dependency_class")} for op in m["operations"]}
counts={k:v for k,v in m["expected_counts"].items() if k!="canonical_delta"}
q=lambda s: "'"+s.replace("'","''")+"'"
sql=f"""BEGIN; SET LOCAL ROLE service_role; SELECT set_config('request.jwt.claim.sub',{q(actor)},true);
SELECT public.red_authorize_reimport({q(m['manifest_content_sha256'])},{q(preview)},jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
 {m['source']['id']},{q(m['source']['profile_id'])},{q(psha)},{q(json.dumps(counts,separators=(',',':')))}::jsonb,{q(json.dumps(els,ensure_ascii=False,separators=(',',':')))}::jsonb,gen_random_uuid(),clock_timestamp()+interval '15 minutes') AS id \\gset
COMMIT; \\echo :id
"""
fd=os.open(sys.argv[2],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,sql.encode()); os.close(fd)
PY
AUTH_ID=$(psql -X -v ON_ERROR_STOP=1 -At -f "$ART/authorize-ce.sql" | tail -1)
printf '{"id":"%s"}' "$AUTH_ID" > "$ART/authorization-ce.json"; chmod 600 "$ART/authorization-ce.json"
DAA_REIMPORT_ACTOR_ID="$ACTOR_UUID" Rscript .claude/skills/daa-extract/scripts/apply_reimport.R --manifest "$ART/clause-evidence-manifest-v1.json" --manifest-sha256 "$MANIFEST_BYTES_SHA" --preview-sha256 "$PREVIEW_SHA" --apply --authorization "$ART/authorization-ce.json"
```

Forventet: dry-run `finalized/committed=false`; apply `finalized/committed=true`.

- [ ] **Step 3: Verifikation (kun tal)**

```bash
psql -X -At <<'SQL'
SELECT (SELECT count(*) FROM private.source_observation WHERE observation_kind='clause') AS clauses,
       (SELECT count(*) FROM private.reimport_event WHERE operation='clause_evidence') AS elements,
       (SELECT jsonb_object_agg(disposition,n) FROM (SELECT disposition,count(*) n FROM private.clause_disposition_current GROUP BY 1) x) AS dispositions,
       (SELECT count(*) FROM private.source_observation c JOIN private.source_observation p ON p.id=c.parent_observation_id WHERE c.observation_kind='clause' AND (c.char_from<p.char_from OR c.char_to>p.char_to)) AS span_violations;
SQL
```

Forventet: `clauses` = ledger-summaryets `clauses.total`; `elements=591`; dispositionsfordeling = ledgerens flag-/klassifikationsfordeling; `span_violations=0`. Kør derefter previewet igen mod basen og sammenlign `canonical_baseline_sha256` (skal være identisk med før) samt `anon`-hashes efter samme opskrift som 149b-runbookens §4. Kør til sidst `tests/sql/test-reimport-legacy-migration.sql` mod restoren (ruller tilbage) og gentag apply-kommandoen for at bevise `already_applied`.

- [ ] **Step 4: Rapport, runbook, changelog, commit**

Tilføj afsnittet "Dagsværk 4.1c" til rehearsal-rapporten med tabellen fra Step 3 plus manifest-/preview-/profil-hashes og `canonical_baseline_sha256` før/efter. Skriv `docs/runbooks/clause-evidence-reimport-rehearsal.md` som en kort opskrift (Step 1-3 ovenfor, med henvisning til `legacy-migration-reimport-rehearsal.md` §2 for restore og §4 for hash-opskriften). Changelog-post: "#148 4.1c: 591 records' klausuler skrevet i restore; nul kanonisk delta; ingen prod-mutation".

```bash
git branch --show-current
git add docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md docs/runbooks/clause-evidence-reimport-rehearsal.md docs/changelog.md
git commit -m "docs(genimport): 4.1c clause_evidence anvendt på alle 591 records i restore (#148)"
```

---

## Selvreview-checkliste

- [ ] Fem ACL-lister opdateret: `schema.sql` REVOKE/GRANT, `db-rls.sql`, `db-migrations.sql` `$public_red_revoke$`, `db-verify.sql` `$public_red_acl_verify$`, `tests/sql/test-reimport-writer.sql` `$acl_parity$` (+ katalog-inspect).
- [ ] 149a-/149b-autorisationsformer valideres uændret (t1 i Task 1).
- [ ] Ingen tekst i manifest, preview, autorisations-SQL eller rapport.
- [ ] Fortrydelse: kun restore; projektejerens særskilte kvittering for `clause_evidence` er noteret som gate før et eventuelt prod-GO (spec §4.1.5).
