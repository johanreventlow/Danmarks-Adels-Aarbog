# Trin 5b, del 1 — ægtefællers identitet (#151) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ægtefæller i 2018-20 får en kildebundet persona og en afgjort identitet — maskinelt, når familien er entydig og en blind stikprøve er bestået, ellers af redaktøren — uden at åbne for lighedsmatch generelt.

**Architecture:** Et deterministisk Python-udtræk finder ægtefællens navn og år i den eksisterende ægteskabspåstand; en ny writer-operation (`relation_persona`) skriver persona, mention, år og relationsparter. 5a's kandidatgenerator får et familiesignal, og en ny serverstyret kontrolkørsel binder en blind stikprøve, som redaktøren afgør i 5a's token-ark. Først efter en bestået kørsel må en ny kerne-oprindelse (`family_corroboration`) acceptere de resterende entydige sager under rækkelåse.

**Tech Stack:** PostgreSQL (plpgsql i `schema.sql`/`db-migrations.sql`), Python 3.9 (`/usr/bin/python3`, pytest), TypeScript (`@daa/identity-candidates`, vitest), React (`web/`).

**Spec:** `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md` (godkendt 2026-10-06; §22 errata). Del 2 (`2026-10-06-trin5b-del2-binding.md`, skrives efter del 1) dækker strukturel binding, relationsafgørelser, nye personer, disposition og den samlede rapport.

## Global Constraints

- `schema.sql` er source of truth; `db-migrations.sql` er idempotent og køres to gange i CI (alt `CREATE OR REPLACE`/`IF NOT EXISTS`/`DROP … IF EXISTS`).
- Nye `public.red_*`-funktioner defineres i 5b-sektionen i `db-migrations.sql` **før** `DO $public_red_revoke$` (linje ~18629) og tilføjes `v_authenticated` dér, `db-verify.sql`'s `$public_red_acl_verify$`-liste og `db-rls.sql`'s allow-liste. Nye `private`-tabeller tilføjes `db-rls.sql`'s master-array (linje ~29).
- Writer-rammens funktioner er defineret flere gange i `db-migrations.sql`; **kun den sidste definition gælder** (`validate_reimport_authorization_payload` ~19529, `red_finalize_reimport` ~19567, `red_reimport_batch_result` ~19589). Ret dem dér og i `schema.sql` (3008, 3966, 3988) — aldrig ved at tilføje en ny, senere definition.
- Al deterministisk orden: `ORDER BY … COLLATE "C"`; hashes via `private.reimport_canonical_json_sha256`.
- Hovedpersonen er den eneste persona med en `primary`-mention på postens helpost-observation (spec §22.1) — aldrig en placering.
- Ingen værdier (navne, klausultekst, påstandsværdier, noter, aktør-uuid) i stdout, log, chat, repo eller commits. Scripts printer kun tal og hashes; filer med navne er 0600 under `~/.private/5b/` (mappe 0700).
- Python: `/usr/bin/python3` (3.9, har pytest). R: `R_ENVIRON_USER=/dev/null`. Web-tests: dummy `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`. Node: `env -u NODE_OPTIONS`.
- SQL-fixtures kalder private funktioner som ejer **før** `SET LOCAL ROLE authenticated`; dblink-kald i fixtures sker efter `RESET ROLE`.
- Commit pr. task, Conventional Commits på dansk, trailer `Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb`, ingen Claude-attribution.
- Hele CI-jobbet genafspilles lokalt (scratchpad `localci.py`, præfiks `ci5b_`) før push.
- **Frisk testbase** (samme trin som CI's job `evidence-promotion-db`, »Evidens-hardening på frisk schema-sti«) — kaldes `fresh <db>` i stepsene:
  ```bash
  fresh() { createdb "$1" && for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "$f" >/dev/null || return 1; done; }
  ```
  Writer-tests (contract v2) kører i CI-jobbet `writer-1939-v50-db`; lokalt hedder opskriften `fresh_v2 <db>`:
  ```bash
  fresh_v2() { fresh "$1" && psql -X -q -v ON_ERROR_STOP=1 -d "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null; }
  ```
  Kun baser med præfikset `ci5b_` oprettes og droppes.
- Arbejdsbaser: kun kopier (`createdb -T daa2018f_20261001133125 daa5b_<formål>_<ts>`); aldrig skrivning i `daa2018f_*` eller prod.

## Review Focus

1. **Hovedpersonen skifter identitet efter persona-oprettelsen** — kernen skal genkontrollere principalens *gældende* `accepted` identitet ved `family_corroboration` (Task 6, test `principal_ikke_accepteret`).
2. **Post med en parkeret ægteskabspåstand** — `count_mismatch` tæller alle ikke-afviste ægteskabspåstande i posten, også dem uden spouse-persona (Task 6, test `count_mismatch_med_parkeret`).
3. **To spouse-personas i samme post peger på samme partner** — den anden afvises (Task 6, test `dobbelt_maal`).
4. **Redaktøren skriver `P <id>` med rang-1-personens id på en stikprøvelinje** — tæller som afvigelse, ikke bestået (Task 5, test `p_token_er_afvigelse`).
5. **Ny kandidatkørsel efter forsegling** — evalueringen skriver `failed`, og bekræftelsen afvises (Task 5, test `kandidatkoersel_forældet`).

## File Structure

| Fil | Ansvar |
| --- | --- |
| `schema.sql`, `db-migrations.sql` | `interpretation_party`, relationsinput, `relation_persona`-writer, rammeudvidelser, familiekontekst, kontrolkørsel, kerne-oprindelse, bekræftelses-RPC, detalje-udvidelse |
| `db-rls.sql`, `db-verify.sql` | RLS master-array, allow-liste, ACL-drift og eksistens-asserts |
| `tests/sql/fixtures/relation-5b.sql` | delte pg_temp-fixtures (kilde, post, klausul, hovedperson, ægteskabspåstand, familie) |
| `tests/sql/test-relation-party.sql` | Task 1 |
| `tests/sql/test-relation-persona-writer.sql` | Task 2 |
| `tests/sql/test-relation-family-context.sql` | Task 4 |
| `tests/sql/test-identity-control-run.sql` | Task 5 |
| `tests/sql/test-family-corroboration.sql` | Task 6 |
| `.claude/skills/daa-extract/scripts/relation_persona_extract.py` (+ test) | Task 3: udtræk og manifest |
| `.claude/skills/daa-extract/scripts/identity_decision_sheet.py`, `identity_sheet_rows.sql`, `identity_control_rows.sql` (+ tests) | Task 5: blind stikprøve |
| `packages/identity-candidates/src/family.ts` (+ test), `rank.ts`, `cli.ts` | Task 4 |
| `web/src/data/sourcePersona.ts`, `web/src/components/KildepersonaKo.tsx` (+ tests) | Task 7 |
| `.github/workflows/ci.yml` | nye SQL-, pytest- og vitest-trin |

---

### Task 0: Forudsætninger og måling (intet skrives)

**Files:** ingen i repoet. Resultater (kun tal) i ledgeren.

- [ ] **Step 1: Bekræft udgangspunktet**

Run:
```bash
git -C .claude/worktrees/spec-5b log --oneline -1 origin/main
psql -X -At -d postgres -c "select datname from pg_database where datname='daa2018f_20261001133125'"
```
Expected: `origin/main` indeholder `796f603` (5a); basen findes.

- [ ] **Step 2: Opret målebasen**

Run:
```bash
TS=$(date +%Y%m%d%H%M%S); createdb -T daa2018f_20261001133125 daa5b_maal_$TS && echo daa5b_maal_$TS
```
Expected: navnet printes. Skriv det i ledgeren.

- [ ] **Step 3: Mål relationspåstandene (kun tal)**

Run (erstat `<db>`):
```bash
psql -X -At -d <db> <<'SQL'
WITH cur AS (SELECT * FROM private.interpretation_current WHERE source_id=1 AND predicate IN ('relation.marriage','relation.child','relation.parent')),
cl AS (SELECT cur.interpretation_key, cur.predicate, cur.value->>'raw' raw,
  count(io.observation_id) FILTER (WHERE io.evidence_role='supporting') n_sup,
  count(co.id) n_cur, min(co.verbatim_text) txt
  FROM cur LEFT JOIN private.interpretation_observation io ON io.interpretation_id=cur.id
  LEFT JOIN private.clause_observation_current co ON co.id=io.observation_id GROUP BY 1,2,3)
SELECT predicate,
  count(*) n,
  count(*) FILTER (WHERE n_sup=1 AND n_cur=1) en_gaeldende_klausul,
  count(*) FILTER (WHERE n_sup=1 AND n_cur=1 AND position(raw in txt)>0) ordret,
  count(*) FILTER (WHERE n_sup=1 AND n_cur=1 AND (length(txt)-length(replace(txt,raw,'')))/greatest(length(raw),1)>1) tvetydig
FROM cl GROUP BY 1 ORDER BY 1;
SQL
```
Expected: tre linjer; `relation.marriage` n=248. Skriv tallene i ledgeren.

- [ ] **Step 4: Mål familiegrundlaget (kun tal)**

Run:
```bash
psql -X -At -d <db> <<'SQL'
WITH principal AS (
  SELECT DISTINCT ON (o.occurrence_id) o.occurrence_id, spm.persona_id, i.canonical_person_id pid
    FROM private.source_observation o
    JOIN private.source_mention sm ON sm.observation_id=o.id
    JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
    JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id AND i.decision_status='accepted'
   WHERE o.parent_observation_id IS NULL),
m AS (SELECT co.occurrence_id, count(*) n_claims FROM private.interpretation_current ic
  JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting'
  JOIN private.clause_observation_current co ON co.id=io.observation_id
  WHERE ic.source_id=1 AND ic.predicate='relation.marriage' AND ic.status<>'rejected' GROUP BY 1),
f AS (SELECT p.occurrence_id, count(DISTINCT fm.family_id) n_fam,
  count(*) FILTER (WHERE fm.ordinal IS NULL) n_null_ord
  FROM principal p JOIN family_member fm ON fm.person_id=p.pid AND fm.rolle='partner' GROUP BY 1)
SELECT count(*) poster_med_aegteskab,
  count(*) FILTER (WHERE m.n_claims=coalesce(f.n_fam,0)) antal_passer,
  count(*) FILTER (WHERE m.n_claims<>coalesce(f.n_fam,0)) count_mismatch,
  count(*) FILTER (WHERE f.n_null_ord>0 AND f.n_fam>1) null_ordinal_flere_familier
FROM m LEFT JOIN f USING (occurrence_id);
SQL
```
Expected: én linje med fire tal; `poster_med_aegteskab` = 217. Skriv dem i ledgeren — de bestemmer arkets forventede størrelse (spec §7.3).

- [ ] **Step 5: Mål `family.id` og klausul-koordinaterne**

Run:
```bash
psql -X -At -d <db> -c "select is_identity from information_schema.columns where table_schema='public' and table_name='family' and column_name='id'" -c "select count(*) from private.clause_observation_current where post_char_from is null"
```
Expected: `YES` (prod-lignende; del 2 retter `schema.sql`), `0`.

- [ ] **Step 6: Ledger-linje**

Skriv `Task 0: complete (måling: <tal fra step 3-5>)` i ledgeren. Ingen commit (intet ændret i repoet). Målebasen beholdes til Task 3's prøvekørsel.

---

### Task 1: `interpretation_party` og delte fixtures

**Files:**
- Create: `tests/sql/fixtures/relation-5b.sql`, `tests/sql/test-relation-party.sql`
- Modify: `schema.sql` (efter `private.interpretation_observation`, ~linje 1256), `db-migrations.sql` (ny 5b-sektion lige efter 5a-sektionens sidste sætning og før `DO $public_red_revoke$`), `db-rls.sql:29`, `db-verify.sql` (ny blok `$relation_party_verify$` efter `$identity_candidate_verify$`), `.github/workflows/ci.yml` (fresh-schema-trinnet, efter `test-identity-detail.sql`)

**Interfaces:**
- Produces: tabellen `private.interpretation_party(interpretation_key uuid, party_role text, version int, source_persona_id uuid, marriage_ordinal int, post_offset int, origin text, origin_ref uuid, created_at timestamptz)`; viewet `private.interpretation_party_current`; fixture-funktionerne `pg_temp.f5b_actor(uuid)`, `pg_temp.f5b_source(bigint) RETURNS jsonb {run,rend}`, `pg_temp.f5b_post(bigint,jsonb,text,text,text[],bigint,uuid) RETURNS jsonb {record,occ,helpost,clauses[],principal}`, `pg_temp.f5b_claim(bigint,jsonb,text,uuid,text) RETURNS jsonb {id,key}`, `pg_temp.f5b_family(bigint,bigint,int) RETURNS bigint`.

- [ ] **Step 1: Skriv de delte fixtures**

`tests/sql/fixtures/relation-5b.sql`:
```sql
-- Trin 5b: delte fixtures. Indlæses med \ir fra testfilerne; alt oprettes i den kaldende
-- transaktion og rulles tilbage af testen. Kald dem som ejer, før SET LOCAL ROLE.
CREATE OR REPLACE FUNCTION pg_temp.f5b_actor(p_actor uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO auth.users(id,email) VALUES (p_actor,p_actor::text||'@5b.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,navn,email) VALUES (p_actor,'redaktion','5b fixture',p_actor::text||'@5b.invalid')
    ON CONFLICT DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION pg_temp.f5b_source(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=gen_random_uuid(); v_rend uuid:=gen_random_uuid();
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES (p_source,'DAA-udgave','5b fixture','synthetic',1900);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,p_source,'5b-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (v_rend,p_source,'5b-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}');
  RETURN jsonb_build_object('run',v_run,'rend',v_rend);
END $$;

-- Én post med helpost, ét klausulsæt og en hovedperson-persona (primary-mention på
-- helposten) med accepteret identitet til p_principal_person (via legacy-lignende
-- ejer-insert: fixturen skriver identitetsrækken direkte som ejer).
CREATE OR REPLACE FUNCTION pg_temp.f5b_post(p_source bigint,p_src jsonb,p_key text,p_text text,
  p_clauses text[],p_principal_person bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=(p_src->>'run')::uuid; v_rec uuid; v_occ uuid; v_help uuid; v_persona uuid; v_mention uuid;
  v_clause uuid; v_ids uuid[]:='{}'; v_pos int:=0; v_from int; i int;
BEGIN
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (p_source,p_key,'person_post',v_run) RETURNING id INTO v_rec;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES ((p_src->>'rend')::uuid,'occ-'||p_key,10,10,1000,1000+char_length(p_text),p_text,repeat('3',64),repeat('4',64),v_run)
    RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_rec,'accepted',jsonb_build_object('fixture','5b'),1,p_actor,'fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES (v_occ,'person_post',10,10,1000,1000+char_length(p_text),p_text,'clear','fixture',v_run) RETURNING id INTO v_help;
  FOR i IN 1..cardinality(p_clauses) LOOP
    v_from:=strpos(substr(p_text,v_pos+1),p_clauses[i])+v_pos-1;
    IF v_from<v_pos THEN RAISE EXCEPTION 'F5B_CLAUSE_NOT_IN_TEXT %',i; END IF;
    INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,
      post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq)
      VALUES (v_occ,'clause',10,10,1000+v_from,1000+v_from+char_length(p_clauses[i]),p_clauses[i],'clear',
        'clause_segment_v1',v_run,v_help,v_from,v_from+char_length(p_clauses[i]),i,'record_text','[]'::jsonb,1)
      RETURNING id INTO v_clause;
    v_ids:=v_ids||v_clause; v_pos:=v_from+char_length(p_clauses[i]);
  END LOOP;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_help,'person_post',0,char_length(p_text),p_text,v_run) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (p_source,p_key,v_run) RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'primary',1);
  IF p_principal_person IS NOT NULL THEN
    INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
      decided_by,decided_by_name,decided_at)
      VALUES (v_persona,p_principal_person,'accepted',1,'{"fixture":"5b"}',p_actor,'fixture',clock_timestamp());
  END IF;
  RETURN jsonb_build_object('record',v_rec,'occ',v_occ,'helpost',v_help,'clauses',to_jsonb(v_ids),'principal',v_persona,'key',p_key);
END $$;

-- En gældende relationspåstand (version 1, proposed) der citerer én klausul.
CREATE OR REPLACE FUNCTION pg_temp.f5b_claim(p_source bigint,p_src jsonb,p_predicate text,p_clause uuid,p_raw text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
    value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_id,v_key,1,p_source,NULL,'relation',p_predicate,jsonb_build_object('raw',p_raw,'normalized',p_raw),
      'fixture','model_inference',0.9,'proposed','fixture',(p_src->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_id,p_clause,'supporting',1);
  RETURN jsonb_build_object('id',v_id,'key',v_key);
END $$;

-- En familie med to partnere (ordinal ens for begge, som red_opret_union) eller én.
CREATE OR REPLACE FUNCTION pg_temp.f5b_family(p_a bigint,p_b bigint,p_ordinal int) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_fam bigint;
BEGIN
  INSERT INTO family(id,type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family),'vielse') RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_a,'partner',p_ordinal);
  IF p_b IS NOT NULL THEN
    INSERT INTO family_member(family_id,person_id,rolle,ordinal) VALUES (v_fam,p_b,'partner',p_ordinal);
  END IF;
  RETURN v_fam;
END $$;
```

- [ ] **Step 2: Skriv den fejlende test**

`tests/sql/test-relation-party.sql`:
```sql
-- Trin 5b, Task 1: interpretation_party — parter nøglet på interpretation_key.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $relation_party_surface$
DECLARE v_role text; v_state text;
BEGIN
  IF to_regclass('private.interpretation_party') IS NULL OR to_regclass('private.interpretation_party_current') IS NULL THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: tabel eller view mangler';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.interpretation_party'::regclass) THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: RLS er slået fra';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_state:=NULL;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I',v_role);
      PERFORM 1 FROM private.interpretation_party LIMIT 1;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    EXECUTE 'SET LOCAL ROLE NONE';
    IF v_state IS DISTINCT FROM '42501' THEN
      RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: % kunne læse (%)',v_role,v_state;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: interpretation_party har RLS og ingen API-adgang';
END $relation_party_surface$;

DO $relation_party_rules$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b101';
  s jsonb; p1 jsonb; p2 jsonb; c jsonb; c_child jsonb; v_spouse uuid; v_other uuid; v_err text; v_new uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5101,false,false,'5b'),(-5102,false,false,'5b');
  s:=pg_temp.f5b_source(-5101);
  p1:=pg_temp.f5b_post(-5101,s,'I-1','Anna Alfa, f. 1800. g. m. Bo Beta, f. 1801.',
       ARRAY['Anna Alfa, f. 1800.','g. m. Bo Beta, f. 1801.'],-5101,v_actor);
  p2:=pg_temp.f5b_post(-5101,s,'I-2','Carl Alfa, f. 1830. søn af Anna Alfa.',
       ARRAY['Carl Alfa, f. 1830.','søn af Anna Alfa.'],-5102,v_actor);
  c:=pg_temp.f5b_claim(-5101,s,'relation.marriage',(p1->'clauses'->>1)::uuid,'g. m. Bo Beta, f. 1801.');
  c_child:=pg_temp.f5b_claim(-5101,s,'relation.parent',(p2->'clauses'->>1)::uuid,'søn af Anna Alfa.');
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-5101,'I-1#spouse',(s->>'run')::uuid)
    RETURNING id INTO v_spouse;

  -- principal fra samme post: godkendt (version 1)
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p1->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
  -- forkert version afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'principal',3,(p1->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: versionsspring godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_VERSION_CONFLICT%' THEN RAISE; END IF;
  END;
  -- child-rolle på et ægteskab afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'child',1,(p2->>'principal')::uuid,NULL,'relation_decision',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: child på ægteskab godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_ROLE_INVALID%' THEN RAISE; END IF;
  END;
  -- principal fra en anden post afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'principal',2,(p2->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: fremmed principal godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_SCOPE_INVALID%' THEN RAISE; END IF;
  END;
  -- parent fra en anden post (dennes hovedperson) godkendt
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c_child->>'key')::uuid,'principal',1,(p2->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,origin,origin_ref)
    VALUES ((c_child->>'key')::uuid,'parent',1,(p1->>'principal')::uuid,'relation_decision',gen_random_uuid());
  -- spouse uden ordinal afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'spouse',1,v_spouse,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: spouse uden ordinal godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- append-only
  BEGIN
    UPDATE private.interpretation_party SET post_offset=0 WHERE interpretation_key=(c->>'key')::uuid;
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: UPDATE lykkedes';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_APPEND_ONLY:%' THEN RAISE; END IF;
  END;
  -- parterne følger fortolkningen gennem en ny version (nøglet på interpretation_key)
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_new:=red_decide_interpretation((c->>'id')::uuid,1,'unresolved','{"note":"5b party-test"}'::jsonb);
  RESET ROLE;
  IF (SELECT count(*) FROM private.interpretation_party_current pc
       JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
      WHERE ic.id=v_new)<>1 THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: parterne fulgte ikke den nye version';
  END IF;
  RAISE NOTICE 'OK: roller, version, rolleafhængigt post-scope, append-only og versionsoverlevelse';
END $relation_party_rules$;
ROLLBACK;
```

- [ ] **Step 3: Kør testen mod en frisk base og se den fejle**

Run:
```bash
fresh ci5b_t1 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t1 -f tests/sql/test-relation-party.sql
```
Expected: FAIL med `RELATION_PARTY_TEST_FAILED: tabel eller view mangler`.

- [ ] **Step 4: Implementér tabellen i `schema.sql`**

Indsæt efter `private.interpretation_observation`-tabellen:
```sql
-- Trin 5b (#151): relationens to ender. interpretation.source_persona_id kan kun bære
-- én persona; parterne nøgles på interpretation_key, så de følger fortolkningen
-- gennem red_decide_interpretation's nye versioner. Append-only og versioneret.
CREATE TABLE private.interpretation_party (
  interpretation_key uuid    NOT NULL,
  party_role         text    NOT NULL CHECK (party_role IN ('principal','spouse','child','parent')),
  version            integer NOT NULL CHECK (version>=1),
  source_persona_id  uuid    REFERENCES private.source_persona(id),
  marriage_ordinal   integer CHECK (marriage_ordinal IS NULL OR marriage_ordinal>=1),
  post_offset        integer CHECK (post_offset IS NULL OR post_offset>=0),
  origin             text    NOT NULL CHECK (origin IN ('relation_persona','relation_decision')),
  origin_ref         uuid    NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (interpretation_key,party_role,version),
  CONSTRAINT interpretation_party_ordinal_check CHECK (
    (party_role='spouse' AND (source_persona_id IS NULL OR marriage_ordinal IS NOT NULL))
    OR (party_role<>'spouse' AND marriage_ordinal IS NULL))
);

CREATE VIEW private.interpretation_party_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (interpretation_key,party_role) *
  FROM private.interpretation_party
 ORDER BY interpretation_key,party_role,version DESC;

CREATE FUNCTION private.validate_interpretation_party()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_interp private.interpretation%ROWTYPE; v_claim_occ uuid; v_persona_source bigint; v_prev integer;
BEGIN
  SELECT * INTO v_interp FROM private.interpretation_current WHERE interpretation_key=NEW.interpretation_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_PARTY_INTERPRETATION_UNKNOWN'; END IF;
  IF v_interp.predicate NOT IN ('relation.marriage','relation.child','relation.parent')
     OR (NEW.party_role='spouse' AND v_interp.predicate<>'relation.marriage')
     OR (NEW.party_role='child' AND v_interp.predicate<>'relation.child')
     OR (NEW.party_role='parent' AND v_interp.predicate<>'relation.parent') THEN
    RAISE EXCEPTION 'EVIDENCE_PARTY_ROLE_INVALID: % på %',NEW.party_role,v_interp.predicate;
  END IF;
  SELECT coalesce(max(version),0) INTO v_prev FROM private.interpretation_party
   WHERE interpretation_key=NEW.interpretation_key AND party_role=NEW.party_role;
  IF NEW.version<>v_prev+1 THEN RAISE EXCEPTION 'EVIDENCE_PARTY_VERSION_CONFLICT: forventet %',v_prev+1; END IF;
  IF NEW.source_persona_id IS NULL THEN RETURN NEW; END IF;
  SELECT source_id INTO v_persona_source FROM private.source_persona WHERE id=NEW.source_persona_id;
  IF v_persona_source IS DISTINCT FROM v_interp.source_id THEN RAISE EXCEPTION 'EVIDENCE_PARTY_SCOPE_INVALID: kilde'; END IF;
  SELECT o.occurrence_id INTO v_claim_occ FROM private.interpretation_observation io
    JOIN private.source_observation o ON o.id=io.observation_id
   WHERE io.interpretation_id=v_interp.id AND io.evidence_role='supporting' ORDER BY io.ordinal LIMIT 1;
  IF NEW.party_role='principal' THEN
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
                     JOIN private.source_observation o ON o.id=sm.observation_id
                    WHERE spm.persona_id=NEW.source_persona_id AND spm.mention_role='primary'
                      AND o.parent_observation_id IS NULL AND o.occurrence_id=v_claim_occ) THEN
      RAISE EXCEPTION 'EVIDENCE_PARTY_SCOPE_INVALID: principal';
    END IF;
  ELSIF NEW.party_role='spouse' THEN
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
                     JOIN private.source_observation o ON o.id=sm.observation_id
                    WHERE spm.persona_id=NEW.source_persona_id AND spm.mention_role='spouse' AND o.occurrence_id=v_claim_occ) THEN
      RAISE EXCEPTION 'EVIDENCE_PARTY_SCOPE_INVALID: spouse';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
                     JOIN private.source_observation o ON o.id=sm.observation_id
                    WHERE spm.persona_id=NEW.source_persona_id AND spm.mention_role='primary'
                      AND o.parent_observation_id IS NULL AND o.occurrence_id<>v_claim_occ) THEN
      RAISE EXCEPTION 'EVIDENCE_PARTY_SCOPE_INVALID: %',NEW.party_role;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_interpretation_party_validate BEFORE INSERT ON private.interpretation_party
  FOR EACH ROW EXECUTE FUNCTION private.validate_interpretation_party();
CREATE TRIGGER trg_interpretation_party_append_only BEFORE UPDATE OR DELETE ON private.interpretation_party
  FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
CREATE TRIGGER trg_interpretation_party_no_truncate BEFORE TRUNCATE ON private.interpretation_party
  FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation();
ALTER TABLE private.interpretation_party ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.interpretation_party FROM PUBLIC,anon,authenticated;
REVOKE ALL ON private.interpretation_party_current FROM PUBLIC,anon,authenticated;
```

- [ ] **Step 5: Spejl i `db-migrations.sql` (idempotent)**

Opret en ny sektion lige efter 5a-sektionens sidste sætning (før `DO $public_red_revoke$`), med overskriften:
```sql
-- ===================================================================================
-- Trin 5b (#151): relationsparter, relationspersonas, kontrolkørsel og family_corroboration.
-- Sektionen ligger FØR $public_red_revoke$ af samme grund som 5a's (nye red_*-navne castes dér).
-- ===================================================================================
```
og indsæt Step 4's DDL med `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE VIEW`, `CREATE OR REPLACE FUNCTION`, og triggerne som `DROP TRIGGER IF EXISTS … ; CREATE TRIGGER …`.

- [ ] **Step 6: RLS, verify og CI**

- `db-rls.sql:29`: tilføj `'interpretation_party'` til master-arrayet efter `'person_create_receipt'`.
- `db-verify.sql`: ny blok efter `$identity_candidate_verify$`:
```sql
DO $relation_party_verify$
BEGIN
  IF to_regclass('private.interpretation_party') IS NULL OR to_regclass('private.interpretation_party_current') IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_MISSING';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.interpretation_party'::regclass) THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_RLS_OFF';
  END IF;
  IF has_table_privilege('authenticated','private.interpretation_party','SELECT')
     OR has_table_privilege('anon','private.interpretation_party','SELECT') THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_GRANT';
  END IF;
END $relation_party_verify$;
```
- `.github/workflows/ci.yml`: i fresh-schema-trinnet efter `test-identity-detail.sql` tilføj `psql -v ON_ERROR_STOP=1 -f tests/sql/test-relation-party.sql`.

- [ ] **Step 7: Kør testen og se den bestå**

Run:
```bash
fresh ci5b_t1b && psql -X -v ON_ERROR_STOP=1 -d ci5b_t1b -f tests/sql/test-relation-party.sql \
  && psql -X -q -v ON_ERROR_STOP=1 -d ci5b_t1b -f tests/sql/run-db-verify-disposable.sql
```
Expected: `OK: interpretation_party har RLS og ingen API-adgang`, `OK: roller, version, rolleafhængigt post-scope, append-only og versionsoverlevelse`; `fresh` kører migrationerne to gange uden fejl, og db-verify består. Drop testbaserne (`dropdb ci5b_t1 ci5b_t1b` — kun `ci5b_`-baser).

- [ ] **Step 8: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/fixtures/relation-5b.sql tests/sql/test-relation-party.sql .github/workflows/ci.yml
git commit -m "feat(151): interpretation_party — relationens parter nøglet på interpretation_key

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 2: Relationsinput og writer-operationen `relation_persona`

**Files:**
- Create: `tests/sql/test-relation-persona-writer.sql`
- Modify: `schema.sql` (reimport_event-CHECK ~2868; validator 3008; finalize 3966; batch_result 3988 — begge `RETURN`; nye funktioner efter `red_apply_reimport_interpretation_proposal` ~3962), `db-migrations.sql` (5b-sektionen + de **sidste** definitioner af validator ~19529, finalize ~19567, batch_result ~19589), `db-migrations.sql` `v_authenticated` (~18632), `db-verify.sql` (`$public_red_acl_verify$`-listen), `db-rls.sql` (allow-listen), `.github/workflows/ci.yml` (job `writer-1939-v50-db`, efter `test-interpretation-proposal.sql`)

**Interfaces:**
- Consumes: `private.interpretation_party` (Task 1); `private.clause_observation_current`, `private.clause_set_sha256(uuid,int)`, `private.deterministic_uuid(text)`, writer-rammen.
- Produces:
  - `private.relation_marriage_ordinals(p_occurrence uuid) RETURNS TABLE(interpretation_key uuid, marriage_ordinal int, post_offset int)` — serverens ægteskabsnummer over **alle** ikke-afviste ægteskabspåstande i posten (bruges også af Task 6's kerne).
  - `private.relation_persona_input(p_source_id bigint) RETURNS jsonb` (array) og `red_relation_persona_input(p_source_id bigint) RETURNS jsonb {input_sha256,input}`.
  - `public.red_apply_reimport_relation_persona(p_batch_id uuid, p_element_id text, p_payload jsonb) RETURNS jsonb {result_receipt_sha256, spouse_source_persona_id}`.
  - Expected-count-nøglen `relation_personas` og elementpræfikset `relation-persona:`.
  - `private.relation_batch_results(p_batch_id uuid) RETURNS jsonb` (`{}` eller `{relation_results:[…]}`) og `private.relation_derived_counts(text,jsonb)`.
  - Receiptskema `relation-persona-receipt-v1` (spec §5.2.1).

- [ ] **Step 1: Skriv de fejlende tests**

Tilføj først to writer-hjælpere til `tests/sql/fixtures/relation-5b.sql` (de bruges også af Task 8):
```sql
CREATE OR REPLACE FUNCTION pg_temp.f5b_profile(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_cfg jsonb:='{"citation_label_template":"DAA 5b s. {page_from}","extractor_version":"5b","observation_extraction_method":"5b",
  "rendition_key":"5b","rendition_kind":"pdf_text_layer","rendition_metadata":{},"run_key_prefix":"5b","schema_version":"5b"}';
BEGIN
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (p_source,'relation-5b','relation-persona-v1',private.reimport_canonical_json_sha256(v_cfg),v_cfg);
  RETURN jsonb_build_object('profile_id','relation-5b','profile_sha256',private.reimport_canonical_json_sha256(v_cfg));
END $$;

-- Autoriserer og åbner en batch med de givne elementer. Kaldes som EJER (før SET LOCAL ROLE
-- authenticated) med aktørens claim sat — samme mønster som test-reimport-name-completion.sql:104-110.
-- red_authorize_reimport er kun tildelt service_role (schema.sql:4558); som authenticated fejler kaldet.
-- Databaseidentiteten er JSON-strengen, som schema.sql:3096 sammenligner med — ikke current_database().
CREATE OR REPLACE FUNCTION pg_temp.f5b_batch(p_source bigint,p_actor uuid,p_prof jsonb,p_elements jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_manifest text:=private.reimport_canonical_json_sha256(p_elements); v_auth uuid; v_batch uuid;
BEGIN
  IF current_user NOT IN (SELECT rolname FROM pg_roles WHERE rolsuper) THEN RAISE EXCEPTION 'F5B_BATCH_MUST_RUN_AS_OWNER'; END IF;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  v_auth:=public.red_authorize_reimport(v_manifest,v_manifest,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    p_source,p_prof->>'profile_id',
    p_prof->>'profile_sha256',jsonb_build_object('person_creates',0,'source_evidence',0,
    'relation_personas',(SELECT count(*) FROM jsonb_object_keys(p_elements))),p_elements,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  v_batch:=public.red_begin_reimport(v_auth,v_manifest,v_manifest);
  RETURN jsonb_build_object('auth',v_auth,'batch',v_batch);
END $$;
```

Derefter `tests/sql/test-relation-persona-writer.sql`:
```sql
-- Trin 5b, Task 2: relationsinput og writer-operationen relation_persona (contract v2).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $relation_persona_writer$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b201';
  s jsonb; p jsonb; prof jsonb; cm jsonb; cm2 jsonb; cc jsonb; b jsonb; r jsonb; v_in jsonb; e jsonb; e2 jsonb; ec jsonb;
  v_clause uuid; v_text text; v_raw text:='g. m. Bo Beta, f. 1801, d. 1870.'; v_raw2 text:='g. 2° m. Cia Ceta.';
  v_state text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5201,false,false,'5b');
  s:=pg_temp.f5b_source(-5201);
  v_text:='Anna Alfa, f. 1800. '||v_raw||' '||v_raw2||' Datter Dora.';
  p:=pg_temp.f5b_post(-5201,s,'II-7',v_text,ARRAY['Anna Alfa, f. 1800.',v_raw||' '||v_raw2,'Datter Dora.'],-5201,v_actor);
  v_clause:=(p->'clauses'->>1)::uuid;
  cm:=pg_temp.f5b_claim(-5201,s,'relation.marriage',v_clause,v_raw);
  cm2:=pg_temp.f5b_claim(-5201,s,'relation.marriage',v_clause,v_raw2);
  cc:=pg_temp.f5b_claim(-5201,s,'relation.child',(p->'clauses'->>2)::uuid,'Datter Dora.');
  prof:=pg_temp.f5b_profile(-5201);

  -- input: tre påstande, serverens ægteskabsnummer 1 og 2 i tekstrækkefølge
  v_in:=private.relation_persona_input(-5201);
  IF jsonb_array_length(v_in)<>3 THEN RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: input %',jsonb_array_length(v_in); END IF;
  IF (SELECT array_agg(o.marriage_ordinal ORDER BY o.post_offset) FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o)<>ARRAY[1,2] THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: ægteskabsnumre';
  END IF;

  e:=jsonb_build_object('birth_raw','1801','clause_observation_id',v_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw','1870',
    'interpretation_key',cm->>'key','interpretation_version',1,'marriage_ordinal',1,
    'name_from',6,'name_to',13,'post_offset',strpos(v_text,v_raw)-1,'predicate','relation.marriage',
    'profile','relation-persona-2018-20-v1','span_from',0,'span_to',char_length(v_raw));
  ec:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',(p->'clauses'->>2)::uuid,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',cc->>'key','interpretation_version',1,'marriage_ordinal',NULL,'name_from',NULL,'name_to',NULL,
    'post_offset',strpos(v_text,'Datter Dora.')-1,'predicate','relation.child','profile','relation-persona-2018-20-v1',
    'span_from',0,'span_to',char_length('Datter Dora.'));

  b:=pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm->>'key'),e,'relation-persona:'||(cc->>'key'),ec));
  SET LOCAL ROLE authenticated;
  -- ikke-autoriseret payload (ændret ordinal) afvises
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm->>'key'),e||'{"marriage_ordinal":2}');
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: uautoriseret payload';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED%' THEN RAISE; END IF;
  END;
  r:=public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm->>'key'),e);
  PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cc->>'key'),ec);
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  r:=public.red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  IF r->'person_id_map' IS NULL OR jsonb_array_length(r->'relation_results')<>1
     OR r->'relation_results'->0->'derived_counts'<>'{"mentions":1,"parties":3,"spouse_personas":1,"year_interpretations":2}' THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: batch_result %',r;
  END IF;
  -- Idempotens (spec §5.2, Codex plan-r1 fund 3): samme payload igen → writer-rammens replay returnerer
  -- den finaliserede batch; intet nyt skrives.
  IF (pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm->>'key'),e,'relation-persona:'||(cc->>'key'),ec))->>'batch')
     IS DISTINCT FROM b->>'batch'
     OR (SELECT count(*) FROM private.source_persona WHERE source_id=-5201 AND persona_key LIKE '%#rel-marriage-%')<>1 THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: replay';
  END IF;
  -- persona, mention og parter
  IF NOT EXISTS (SELECT 1 FROM private.source_persona WHERE persona_key='II-7#rel-marriage-'||(strpos(v_text,v_raw)-1)||'-'||char_length(v_raw))
     OR (SELECT count(*) FROM private.interpretation_party_current WHERE interpretation_key IN ((cm->>'key')::uuid,(cc->>'key')::uuid))<>3 THEN
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: rækker mangler';
  END IF;
  -- påstanden er nu ude af input; ny batch for samme påstand afvises
  IF jsonb_array_length(private.relation_persona_input(-5201))<>1 THEN RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: input efter'; END IF;
  -- forkert ordinal for 2. ægteskab afvises af serveren
  -- 'g. 2° m. ' er 9 tegn: navnet ligger på (len(v_raw)+1)+9 .. +17 i klausulen; kun ordinal er forkert.
  e2:=e||jsonb_build_object('interpretation_key',cm2->>'key','marriage_ordinal',1,
     'name_from',char_length(v_raw)+1+9,'name_to',char_length(v_raw)+1+17,'birth_raw',NULL,'death_raw',NULL,
     'post_offset',strpos(v_text,v_raw2)-1,'span_from',char_length(v_raw)+1,'span_to',char_length(v_raw)+1+char_length(v_raw2));
  b:=pg_temp.f5b_batch(-5201,v_actor,prof,jsonb_build_object('relation-persona:'||(cm2->>'key'),e2));
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(cm2->>'key'),e2);
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: forkert ordinal godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: input, serverens ægteskabsnummer, writer, receipt, finalize og resultatkort';
END $relation_persona_writer$;

-- Spændregler: ikke-ordret, tvetydigt og hovedperson uden accepteret identitet.
DO $relation_persona_negative$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b202';
  s jsonb; p jsonb; prof jsonb; c jsonb; b jsonb; e jsonb; v_text text:='Bent Bravo. g. m. Ea Echo. g. m. Ea Echo.';
  v_case text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-5202);
  p:=pg_temp.f5b_post(-5202,s,'III-1',v_text,ARRAY['Bent Bravo.','g. m. Ea Echo. g. m. Ea Echo.'],NULL,v_actor);
  c:=pg_temp.f5b_claim(-5202,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Ea Echo.');
  prof:=pg_temp.f5b_profile(-5202);
  e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',p->'clauses'->>1,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
    'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,'name_from',5,'name_to',13,
    'post_offset',12,'predicate','relation.marriage','profile','relation-persona-2018-20-v1','span_from',0,'span_to',14);
  b:=pg_temp.f5b_batch(-5202,v_actor,prof,jsonb_build_object('relation-persona:'||(c->>'key'),e));
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,'relation-persona:'||(c->>'key'),e);
    RAISE EXCEPTION 'RELATION_WRITER_TEST_FAILED: tvetydigt spænd godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: tvetydigt spænd afvises';
END $relation_persona_negative$;
ROLLBACK;
```

- [ ] **Step 2: Kør testen og se den fejle**

Run: `fresh_v2 ci5b_t2 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t2 -f tests/sql/test-relation-persona-writer.sql`
Expected: FAIL med `function private.relation_persona_input(integer) does not exist`.

- [ ] **Step 3: Ægteskabsnummer og input (schema.sql + 5b-sektionen)**

```sql
-- Trin 5b (#151): serverens ægteskabsnummer. Rang efter (post_offset, spændlængde,
-- interpretation_key) over ALLE ikke-afviste ægteskabspåstande i posten — også dem,
-- udtrækket parkerer — så numrene ikke flytter sig mellem kørsler (spec §5.1).
CREATE OR REPLACE FUNCTION private.relation_marriage_ordinals(p_occurrence uuid)
RETURNS TABLE(interpretation_key uuid, marriage_ordinal integer, post_offset integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  WITH m AS (
    SELECT ic.interpretation_key, ic.value->>'raw' AS raw,
           co.post_char_from+nullif(strpos(co.verbatim_text,ic.value->>'raw'),0)-1 AS post_offset
      FROM private.interpretation_current ic
      JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
      JOIN private.clause_observation_current co ON co.id=io.observation_id
     WHERE ic.predicate='relation.marriage' AND ic.status<>'rejected' AND co.occurrence_id=p_occurrence)
  SELECT m.interpretation_key,
         (row_number() OVER (ORDER BY m.post_offset NULLS LAST,char_length(m.raw),m.interpretation_key::text COLLATE "C"))::integer,
         m.post_offset
    FROM m;
$$;
REVOKE ALL ON FUNCTION private.relation_marriage_ordinals(uuid) FROM PUBLIC,anon,authenticated;

-- Udtrækkets input: gældende relationspåstande uden gældende parter, med den citerede
-- klausul læst udelukkende fra clause_observation_current (spec §5.1).
CREATE OR REPLACE FUNCTION private.relation_persona_input(p_source_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.record_key COLLATE "C",x.interpretation_key COLLATE "C"),'[]'::jsonb)
  FROM (
    SELECT ic.interpretation_key::text AS interpretation_key, ic.version AS interpretation_version, ic.predicate,
           ic.value->>'raw' AS raw, rec.record_key, rec.occurrence_id::text AS occurrence_id,
           (SELECT o.marriage_ordinal FROM private.relation_marriage_ordinals(rec.occurrence_id) o
             WHERE o.interpretation_key=ic.interpretation_key) AS marriage_ordinal,
           (SELECT count(*) FROM private.interpretation_observation io
             WHERE io.interpretation_id=ic.id AND io.evidence_role='supporting') AS supporting_count,
           coalesce((SELECT jsonb_agg(jsonb_build_object(
                'observation_id',co.id::text,'verbatim_text',co.verbatim_text,
                'post_char_from',co.post_char_from,'post_char_to',co.post_char_to,
                'clause_set_seq',coalesce(co.clause_set_seq,1),
                'clause_set_sha256',private.clause_set_sha256(co.parent_observation_id,coalesce(co.clause_set_seq,1)))
              ORDER BY co.clause_ordinal)
              FROM private.interpretation_observation io
              JOIN private.clause_observation_current co ON co.id=io.observation_id
             WHERE io.interpretation_id=ic.id AND io.evidence_role='supporting'),'[]'::jsonb) AS clauses
      FROM private.interpretation_current ic
      JOIN LATERAL (SELECT sr.record_key, o.occurrence_id FROM private.interpretation_observation io
                      JOIN private.source_observation o ON o.id=io.observation_id
                      JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
                      JOIN private.source_record sr ON sr.id=ac.source_record_id
                     WHERE io.interpretation_id=ic.id AND io.evidence_role='supporting'
                     ORDER BY io.ordinal LIMIT 1) rec ON true
     WHERE ic.source_id=p_source_id
       AND ic.predicate IN ('relation.marriage','relation.child','relation.parent')
       AND ic.status IN ('proposed','accepted')
       AND NOT EXISTS (SELECT 1 FROM private.interpretation_party_current pc
                        WHERE pc.interpretation_key=ic.interpretation_key AND pc.source_persona_id IS NOT NULL)
  ) x;
$$;
REVOKE ALL ON FUNCTION private.relation_persona_input(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION red_relation_persona_input(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_input jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v_input:=private.relation_persona_input(p_source_id);
  RETURN jsonb_build_object('input_sha256',private.reimport_canonical_json_sha256(v_input),'input',v_input);
END $$;
REVOKE ALL ON FUNCTION red_relation_persona_input(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_relation_persona_input(bigint) TO authenticated;
```

- [ ] **Step 4: Writeren (schema.sql + 5b-sektionen)**

```sql
CREATE OR REPLACE FUNCTION private.write_relation_persona(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE
  v_batch private.reimport_batch%ROWTYPE; v_auth private.reimport_authorization%ROWTYPE;
  v_interp private.interpretation%ROWTYPE; v_clause private.source_observation%ROWTYPE;
  v_record_key text; v_principal uuid; v_principal_n integer; v_spouse uuid; v_mention uuid; v_run uuid; v_run_key text;
  v_raw text; v_ordinal integer; v_year_ids uuid[]:='{}'; v_year_id uuid; v_pred text; v_year text; v_receipt jsonb;
  v_hash text; v_marriage boolean; v_from integer; v_to integer; v_name_from integer; v_name_to integer;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED'; END IF;
  v_batch:=private.require_reimport_open_batch(p_batch_id);
  PERFORM private.require_reimport_writer_editor();
  PERFORM private.lock_reimport_writer(v_batch.source_id,v_batch.profile_id);
  -- Nye personas ændrer kandidatinputtet: delt kildelås, så de eksklusive maskin-RPC'er
  -- (kandidatkørsel, kontrolregistrering, bekræftelse) aldrig løber samtidig med writeren.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_batch.source_id::text,0));
  SELECT * INTO v_auth FROM private.reimport_authorization WHERE id=v_batch.authorization_id;
  IF NOT FOUND OR NOT v_auth.authorized_elements ? p_element_id
     OR v_auth.authorized_elements->p_element_id IS DISTINCT FROM p_payload THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED';
  END IF;
  v_marriage:=p_payload->>'predicate'='relation.marriage';
  IF jsonb_typeof(p_payload)<>'object'
     OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(p_payload) k)
        <> ARRAY['birth_raw','clause_observation_id','clause_set_seq','clause_set_sha256','death_raw','interpretation_key',
                 'interpretation_version','marriage_ordinal','name_from','name_to','post_offset','predicate','profile',
                 'span_from','span_to']
     OR p_element_id<>'relation-persona:'||coalesce(p_payload->>'interpretation_key','')
     OR coalesce(p_payload->>'predicate','') NOT IN ('relation.marriage','relation.child','relation.parent')
     OR p_payload->>'profile' IS DISTINCT FROM 'relation-persona-2018-20-v1'
     OR coalesce(p_payload->>'clause_set_sha256','') !~ '^[0-9a-f]{64}$'
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['interpretation_version','clause_set_seq','post_offset','span_from','span_to']) k
                 WHERE jsonb_typeof(p_payload->k)<>'number' OR (p_payload->>k) !~ '^[0-9]+$')
     OR (v_marriage AND EXISTS (SELECT 1 FROM unnest(ARRAY['marriage_ordinal','name_from','name_to']) k
                                 WHERE jsonb_typeof(p_payload->k)<>'number' OR (p_payload->>k) !~ '^[0-9]+$'))
     OR (NOT v_marriage AND EXISTS (SELECT 1 FROM unnest(ARRAY['marriage_ordinal','name_from','name_to','birth_raw','death_raw']) k
                                     WHERE jsonb_typeof(p_payload->k)<>'null'))
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['birth_raw','death_raw']) k
                 WHERE jsonb_typeof(p_payload->k) NOT IN ('string','null')
                    OR (jsonb_typeof(p_payload->k)='string' AND p_payload->>k !~ '^[0-9]{4}$')) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_INVALID';
  END IF;
  v_from:=(p_payload->>'span_from')::integer; v_to:=(p_payload->>'span_to')::integer;

  SELECT * INTO v_interp FROM private.interpretation_current
   WHERE interpretation_key=(p_payload->>'interpretation_key')::uuid;
  IF NOT FOUND OR v_interp.source_id<>v_batch.source_id OR v_interp.version<>(p_payload->>'interpretation_version')::integer
     OR v_interp.predicate<>p_payload->>'predicate' OR v_interp.status NOT IN ('proposed','accepted') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_DRIFT';
  END IF;
  PERFORM 1 FROM private.interpretation WHERE id=v_interp.id FOR SHARE;
  IF EXISTS (SELECT 1 FROM private.interpretation_party_current
              WHERE interpretation_key=v_interp.interpretation_key AND source_persona_id IS NOT NULL) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_EXISTS';
  END IF;

  IF (SELECT count(*) FROM private.interpretation_observation
       WHERE interpretation_id=v_interp.id AND evidence_role='supporting')<>1 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_CLAUSE_INVALID';
  END IF;
  SELECT co.* INTO v_clause FROM private.clause_observation_current co
    JOIN private.interpretation_observation io
      ON io.observation_id=co.id AND io.interpretation_id=v_interp.id AND io.evidence_role='supporting'
   WHERE co.id=(p_payload->>'clause_observation_id')::uuid;
  IF NOT FOUND OR coalesce(v_clause.clause_set_seq,1)<>(p_payload->>'clause_set_seq')::integer
     OR private.clause_set_sha256(v_clause.parent_observation_id,coalesce(v_clause.clause_set_seq,1))
        IS DISTINCT FROM p_payload->>'clause_set_sha256' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_CLAUSE_INVALID';
  END IF;

  v_raw:=v_interp.value->>'raw';
  IF v_to-v_from<>char_length(v_raw)
     OR substr(v_clause.verbatim_text,v_from+1,v_to-v_from)<>v_raw
     OR (char_length(v_clause.verbatim_text)-char_length(replace(v_clause.verbatim_text,v_raw,'')))/char_length(v_raw)<>1
     OR (p_payload->>'post_offset')::integer<>v_clause.post_char_from+v_from THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID';
  END IF;

  -- Hovedpersonen (spec §22.1): eneste primary-mention på helposten, accepteret identitet.
  SELECT count(*),min(spm.persona_id::text)::uuid INTO v_principal_n,v_principal
    FROM private.source_mention sm
    JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
   WHERE sm.observation_id=v_clause.parent_observation_id;
  IF v_principal_n<>1 OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity
                                      WHERE source_persona_id=v_principal AND decision_status='accepted') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_PRINCIPAL_INVALID';
  END IF;
  SELECT sr.record_key INTO v_record_key FROM private.source_record_anchor_current ac
    JOIN private.source_record sr ON sr.id=ac.source_record_id
   WHERE ac.occurrence_id=v_clause.occurrence_id AND ac.decision_status='accepted';

  IF v_marriage THEN
    v_name_from:=(p_payload->>'name_from')::integer; v_name_to:=(p_payload->>'name_to')::integer;
    SELECT o.marriage_ordinal INTO v_ordinal FROM private.relation_marriage_ordinals(v_clause.occurrence_id) o
     WHERE o.interpretation_key=v_interp.interpretation_key;
    IF v_ordinal IS DISTINCT FROM (p_payload->>'marriage_ordinal')::integer
       OR v_name_from<v_from OR v_name_to>v_to OR v_name_to<=v_name_from THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_SPAN_INVALID';
    END IF;
  END IF;

  v_run_key:='relation-persona:'||(p_payload->>'profile')||':'||v_batch.manifest_sha256;
  INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES (v_batch.source_id,v_run_key,'relation-persona-v1',p_payload->>'profile',p_payload->>'profile',
          v_batch.manifest_sha256,jsonb_build_object('batch_id',p_batch_id))
  ON CONFLICT (source_id,run_key) DO NOTHING;
  SELECT id INTO v_run FROM private.extraction_run
   WHERE source_id=v_batch.source_id AND run_key=v_run_key AND schema_version='relation-persona-v1'
     AND input_sha256=v_batch.manifest_sha256 AND manifest=jsonb_build_object('batch_id',p_batch_id);
  IF v_run IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_RUN_DRIFT'; END IF;

  IF v_marriage THEN
    INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
      VALUES (v_batch.source_id,v_record_key||'#rel-marriage-'||(p_payload->>'post_offset')||'-'||char_length(v_raw),v_run)
      RETURNING id INTO v_spouse;
    INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES (v_clause.id,'person',v_name_from,v_name_to,
              substr(v_clause.verbatim_text,v_name_from+1,v_name_to-v_name_from),v_run)
      RETURNING id INTO v_mention;
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_spouse,v_mention,'spouse',1);
    FOREACH v_pred IN ARRAY ARRAY['person.birth','person.death'] LOOP
      v_year:=p_payload->>(CASE v_pred WHEN 'person.birth' THEN 'birth_raw' ELSE 'death_raw' END);
      CONTINUE WHEN v_year IS NULL;
      -- Året skal stå i ægtefællens eget segment (efter navnet, inden for spændet).
      IF strpos(substr(v_clause.verbatim_text,v_name_to+1,v_to-v_name_to),v_year)=0 THEN
        RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_YEAR_INVALID';
      END IF;
      v_year_id:=gen_random_uuid();
      INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
        predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
      VALUES (v_year_id,private.deterministic_uuid(jsonb_build_object('kind','relation-persona-year',
                'interpretation_key',v_interp.interpretation_key,'predicate',v_pred)::text),
              1,v_batch.source_id,v_spouse,'property',v_pred,to_jsonb(v_year),'relation-persona-v1',
              'deterministic',1,'proposed','relation-persona-v1',v_run);
      INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
        VALUES (v_year_id,v_clause.id,'supporting',1);
      v_year_ids:=v_year_ids||v_year_id;
    END LOOP;
  END IF;

  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
  VALUES (v_interp.interpretation_key,'principal',
          (SELECT coalesce(max(version),0)+1 FROM private.interpretation_party
            WHERE interpretation_key=v_interp.interpretation_key AND party_role='principal'),
          v_principal,(p_payload->>'post_offset')::integer,'relation_persona',p_batch_id);
  IF v_marriage THEN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,
      post_offset,origin,origin_ref)
    VALUES (v_interp.interpretation_key,'spouse',
            (SELECT coalesce(max(version),0)+1 FROM private.interpretation_party
              WHERE interpretation_key=v_interp.interpretation_key AND party_role='spouse'),
            v_spouse,v_ordinal,(p_payload->>'post_offset')::integer,'relation_persona',p_batch_id);
  END IF;

  v_receipt:=jsonb_build_object('schema','relation-persona-receipt-v1',
    'principal_source_persona_id',v_principal,'spouse_source_persona_id',v_spouse,'mention_id',v_mention,
    'year_interpretation_ids',coalesce((SELECT jsonb_agg(y::text ORDER BY y::text COLLATE "C") FROM unnest(v_year_ids) y),'[]'::jsonb),
    'party_keys',(SELECT jsonb_agg(jsonb_build_array(pc.interpretation_key::text,pc.party_role,pc.version)
                                   ORDER BY pc.party_role COLLATE "C")
                    FROM private.interpretation_party_current pc WHERE pc.interpretation_key=v_interp.interpretation_key));
  v_hash:=private.reimport_canonical_json_sha256(v_receipt);
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES (p_batch_id,p_element_id,'relation_persona',v_record_key,
          p_payload||jsonb_build_object('result_receipt',v_receipt),v_hash);
  RETURN jsonb_build_object('result_receipt_sha256',v_hash,'spouse_source_persona_id',v_spouse);
END $$;
REVOKE ALL ON FUNCTION private.write_relation_persona(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.red_apply_reimport_relation_persona(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  RETURN private.write_relation_persona(p_batch_id,p_element_id,p_payload);
END $$;
REVOKE ALL ON FUNCTION public.red_apply_reimport_relation_persona(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_apply_reimport_relation_persona(uuid,text,jsonb) TO authenticated;

-- Finalisering: receiptet læses fra payload->'result_receipt', hashen genberegnes, og hvert
-- id efterprøves mod databasen (spec §5.2.1). Prædikatbetinget: kun ægteskaber har ny persona.
CREATE OR REPLACE FUNCTION private.verify_relation_persona_receipts(p_batch_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE e private.reimport_event%ROWTYPE; r jsonb; v_run uuid; v_key uuid;
BEGIN
  SELECT er.id INTO v_run FROM private.extraction_run er JOIN private.reimport_batch b ON b.id=p_batch_id
   WHERE er.source_id=b.source_id AND er.schema_version='relation-persona-v1' AND er.input_sha256=b.manifest_sha256
     AND er.manifest=jsonb_build_object('batch_id',p_batch_id);
  FOR e IN SELECT * FROM private.reimport_event WHERE batch_id=p_batch_id AND operation='relation_persona' ORDER BY id LOOP
    r:=e.payload->'result_receipt'; v_key:=(e.payload->>'interpretation_key')::uuid;
    IF r IS NULL OR private.reimport_canonical_json_sha256(r)<>e.after_sha256
       OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(r) k)
          <>ARRAY['mention_id','party_keys','principal_source_persona_id','schema','spouse_source_persona_id','year_interpretation_ids']
       OR r->>'schema'<>'relation-persona-receipt-v1' OR jsonb_typeof(r->'year_interpretation_ids')<>'array'
       OR NOT EXISTS (SELECT 1 FROM private.interpretation_party pc
                       WHERE pc.interpretation_key=v_key AND pc.party_role='principal' AND pc.origin_ref=p_batch_id
                         AND pc.source_persona_id=(r->>'principal_source_persona_id')::uuid)
       OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity i
                       WHERE i.source_persona_id=(r->>'principal_source_persona_id')::uuid AND i.decision_status='accepted')
       -- party_keys = præcis de parter, batchen skrev for påstanden (Codex plan-r1 fund 4)
       OR r->'party_keys' IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array(pc.interpretation_key::text,pc.party_role,pc.version)
                                                   ORDER BY pc.party_role COLLATE "C")
                                              FROM private.interpretation_party pc
                                             WHERE pc.interpretation_key=v_key AND pc.origin_ref=p_batch_id) THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_RECEIPT_INVALID: %',e.element_id;
    END IF;
    IF e.payload->>'predicate'='relation.marriage' THEN
      IF NOT EXISTS (SELECT 1 FROM private.source_persona p WHERE p.id=(r->>'spouse_source_persona_id')::uuid AND p.created_run_id=v_run)
         OR NOT EXISTS (SELECT 1 FROM private.source_mention m WHERE m.id=(r->>'mention_id')::uuid AND m.created_run_id=v_run
                         AND m.observation_id=(e.payload->>'clause_observation_id')::uuid
                         AND m.char_from=(e.payload->>'name_from')::integer AND m.char_to=(e.payload->>'name_to')::integer)
         OR NOT EXISTS (SELECT 1 FROM private.interpretation_party pc
                         WHERE pc.interpretation_key=v_key AND pc.party_role='spouse' AND pc.origin_ref=p_batch_id
                           AND pc.source_persona_id=(r->>'spouse_source_persona_id')::uuid
                           AND pc.marriage_ordinal=(e.payload->>'marriage_ordinal')::integer)
         -- årene: præcis ét pr. ikke-NULL år i payloaden, og præcis alle runnens årfortolkninger for personaen,
         -- hver med rigtigt prædikat og citation af den autoriserede klausul (Codex plan-r1 fund 4)
         OR jsonb_array_length(r->'year_interpretation_ids')
            <>(e.payload->>'birth_raw' IS NOT NULL)::int+(e.payload->>'death_raw' IS NOT NULL)::int
         OR r->'year_interpretation_ids' IS DISTINCT FROM coalesce((SELECT jsonb_agg(i.id::text ORDER BY i.id::text COLLATE "C")
                                                                     FROM private.interpretation i
                                                                    WHERE i.extraction_run_id=v_run
                                                                      AND i.source_persona_id=(r->>'spouse_source_persona_id')::uuid),'[]'::jsonb)
         OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'year_interpretation_ids') y
                     WHERE NOT EXISTS (SELECT 1 FROM private.interpretation i
                                         JOIN private.interpretation_observation io ON io.interpretation_id=i.id
                                          AND io.observation_id=(e.payload->>'clause_observation_id')::uuid AND io.evidence_role='supporting'
                                        WHERE i.id=y::uuid AND i.predicate IN ('person.birth','person.death')
                                          AND i.status='proposed' AND i.version=1)) THEN
        RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_RECEIPT_INVALID: %',e.element_id;
      END IF;
    ELSIF jsonb_typeof(r->'spouse_source_persona_id')<>'null' OR jsonb_typeof(r->'mention_id')<>'null'
          OR r->'year_interpretation_ids'<>'[]'::jsonb THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_RECEIPT_INVALID: %',e.element_id;
    END IF;
  END LOOP;
  -- Batchglobal distinct-kontrol: hvert ny id i præcis ét receipt.
  IF EXISTS (SELECT 1 FROM (
       SELECT x FROM private.reimport_event e,
         LATERAL (SELECT e.payload->'result_receipt'->>'spouse_source_persona_id' x
                  UNION ALL SELECT e.payload->'result_receipt'->>'mention_id'
                  UNION ALL SELECT y FROM jsonb_array_elements_text(e.payload->'result_receipt'->'year_interpretation_ids') y) ids
        WHERE e.batch_id=p_batch_id AND e.operation='relation_persona' AND x IS NOT NULL
        GROUP BY x HAVING count(*)>1) d) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_RECEIPT_INVALID: dublet';
  END IF;
END $$;
REVOKE ALL ON FUNCTION private.verify_relation_persona_receipts(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.relation_derived_counts(p_operation text,p_receipts jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE p_operation
    WHEN 'relation_persona' THEN (SELECT jsonb_build_object(
      'spouse_personas',count(*) FILTER (WHERE r->>'spouse_source_persona_id' IS NOT NULL),
      'mentions',count(*) FILTER (WHERE r->>'mention_id' IS NOT NULL),
      'year_interpretations',coalesce(sum(jsonb_array_length(r->'year_interpretation_ids')),0),
      'parties',coalesce(sum(jsonb_array_length(r->'party_keys')),0)) FROM jsonb_array_elements(p_receipts) r)
    ELSE '{}'::jsonb END;
$$;

CREATE OR REPLACE FUNCTION private.relation_batch_results(p_batch_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  SELECT CASE WHEN count(*)=0 THEN '{}'::jsonb
              ELSE jsonb_build_object('relation_results',jsonb_agg(x.r ORDER BY x.r->>'operation' COLLATE "C")) END
    FROM (SELECT jsonb_build_object('operation',e.operation,'elements',count(*),
            'receipts_sha256',private.reimport_canonical_json_sha256(jsonb_agg(e.after_sha256 ORDER BY e.after_sha256 COLLATE "C")),
            'derived_counts',private.relation_derived_counts(e.operation,jsonb_agg(e.payload->'result_receipt' ORDER BY e.id))) AS r
            FROM private.reimport_event e
           WHERE e.batch_id=p_batch_id AND e.operation IN ('relation_persona','relation_person_create','relation_disposition')
           GROUP BY e.operation) x;
$$;
REVOKE ALL ON FUNCTION private.relation_batch_results(uuid) FROM PUBLIC,anon,authenticated;
```

- [ ] **Step 5: Udvid writer-rammen (schema.sql OG de sidste definitioner i db-migrations.sql)**

1. Operationsvokabularet: i `schema.sql:2868` tilføj `'relation_persona'` i `reimport_event_operation_check`-listen; i 5b-sektionen af `db-migrations.sql`:
   ```sql
   SELECT private.ensure_reimport_operations(ARRAY['relation_persona']);
   ```
2. `private.validate_reimport_authorization_payload` (schema.sql 3008 og db-migrations ~19529): erstat funktionens krop med samme logik plus én valgfri tæller. Konkret, i begge definitioner:
   - `DECLARE`: tilføj `v_relation_personas bigint;`
   - i første `IF`: tilføj
     `OR (p_expected_counts ? 'relation_personas' AND (jsonb_typeof(p_expected_counts->'relation_personas')<>'number' OR coalesce(p_expected_counts->>'relation_personas','') !~ '^[0-9]+$'))`,
     ret `NOT IN (2,3,4,5,6)` til `NOT IN (2,3,4,5,6,7)` og tilføj `'relation_personas'` i nøglelisten;
   - efter `v_clause_revisions:=…`: `v_relation_personas:=coalesce((p_expected_counts->>'relation_personas')::bigint,0);`
   - summen: `+v_relation_personas`;
   - præfiks-mønsteret: tilføj `AND element.key !~ '^relation-persona:.+$'`;
   - ny linje: `OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements) key WHERE key ~ '^relation-persona:.+$')<>v_relation_personas`.
3. `public.red_finalize_reimport` (schema.sql 3966 og db-migrations ~19567): tilføj efter `clause_revisions`-CASE'n
   ```sql
            || CASE WHEN v_batch.expected_counts ? 'relation_personas'
                    THEN jsonb_build_object('relation_personas',count(*) FILTER(WHERE operation='relation_persona')) ELSE '{}'::jsonb END
   ```
   og lige før `UPDATE private.reimport_batch SET status='finalized'…`:
   ```sql
     IF v_batch.expected_counts ? 'relation_personas' THEN PERFORM private.verify_relation_persona_receipts(p_batch_id); END IF;
   ```
4. `public.red_reimport_batch_result` (schema.sql 3988 og den SIDSTE definition i db-migrations ~19589) — funktionens egne afsluttende valideringer skal kende den nye tæller, ellers fejler første kald efter finalize med `REIMPORT_WRITER_BATCH_RESULT_INVALID` (schema.sql:4046-4075; Codex plan-r1 fund 7). I begge definitioner:
   - `DECLARE`: tilføj `v_expected_relation_personas bigint;`
   - i den store `IF v_batch.status<>'finalized' OR …`: tilføj
     `OR (v_batch.expected_counts ? 'relation_personas' AND (jsonb_typeof(v_batch.expected_counts->'relation_personas')<>'number' OR coalesce(v_batch.expected_counts->>'relation_personas','') !~ '^[0-9]+$'))`,
     ret `NOT IN (2,3,4,5,6)` til `NOT IN (2,3,4,5,6,7)` og tilføj `'relation_personas'` i nøglelisten `key NOT IN (…)`;
   - efter `v_expected_clause_revisions:=…`: `v_expected_relation_personas:=coalesce((v_batch.expected_counts->>'relation_personas')::bigint,0);`
   - summen `v_authorized_element_count<>(…)`: `+v_expected_relation_personas`;
   - præfiks-mønsteret: tilføj `AND item.key !~ '^relation-persona:'`;
   - event-operationslisten `event.operation IN (…)`: tilføj `'relation_persona'`;
   - begge `RETURN jsonb_build_object('batch_id',v_batch.id,'status',…,'person_id_map',…);` → `RETURN jsonb_build_object(…uændret…) || private.relation_batch_results(v_batch.id);` (`person_id_map` bevares; `relation_results` tilføjes kun, når batchen har relationshændelser).
5. Grants/ACL: tilføj `'red_relation_persona_input(bigint)'::regprocedure` og `'red_apply_reimport_relation_persona(uuid,text,jsonb)'::regprocedure` i `v_authenticated` (db-migrations ~18632), i `db-verify.sql`'s `$public_red_acl_verify$`-liste og i `db-rls.sql`'s allow-liste (samme stil som 5a's `red_identity_candidate_input`).
6. Statisk værn: i `.claude/skills/daa-extract/scripts/test_identity_guard_static.py` er intet at ændre her (kernen kaldes ikke).

- [ ] **Step 6: Kør testen og se den bestå**

Run: `fresh_v2 ci5b_t2b && psql -X -v ON_ERROR_STOP=1 -d ci5b_t2b -f tests/sql/test-relation-persona-writer.sql && psql -X -v ON_ERROR_STOP=1 -d ci5b_t2b -f tests/sql/test-interpretation-proposal.sql && psql -X -q -v ON_ERROR_STOP=1 -d ci5b_t2b -f tests/sql/run-db-verify-disposable.sql`
Expected: begge `OK`-noticer; den eksisterende proposal-test og db-verify består uændret (operationsvokabularet er udvidet, ikke indsnævret).

- [ ] **Step 7: CI og commit**

`.github/workflows/ci.yml`, job `writer-1939-v50-db`, efter trinnet »Fortolkningsforslag SQL (#147 4.4)«:
```yaml
      - name: Relationspersona-writer SQL (5b)
        env: {PGPASSWORD: postgres}
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-relation-persona-writer.sql
```
```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-relation-persona-writer.sql .github/workflows/ci.yml
git commit -m "feat(151): relationsinput og writer-operationen relation_persona med receipt

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 3: Deterministisk udtræk, manifest og apply-script

**Files:**
- Create: `.claude/skills/daa-extract/scripts/relation_persona_extract.py`, `.claude/skills/daa-extract/scripts/test_relation_persona_extract.py`, `.claude/skills/daa-extract/scripts/relation_persona_input.sql`, `.claude/skills/daa-extract/scripts/relation_persona_apply.sql`
- Modify: `.github/workflows/ci.yml` (job `python`: tilføj testfilen)

**Interfaces:**
- Consumes: `red_relation_persona_input(bigint)` og `red_apply_reimport_relation_persona` (Task 2).
- Produces: `extract_rows(rows: list[dict]) -> tuple[dict, dict]` = (manifest `{expected_counts, authorized_elements}`, stats `{elementer, parkeret: {grund: antal}, pr_praedikat}`); CLI `relation_persona_extract.py --input <0600-fil> --out <0600-fil>` der kun printer tal og hashes; profilkonstanten `PROFILE = "relation-persona-2018-20-v1"`.

- [ ] **Step 1: Skriv de fejlende tests (kun syntetiske eksempler)**

`.claude/skills/daa-extract/scripts/test_relation_persona_extract.py`:
```python
import json
import subprocess
import sys
from pathlib import Path

import relation_persona_extract as rpe

HERE = Path(__file__).parent
SHA = "a" * 64


def row(raw, text=None, predicate="relation.marriage", ordinal=1, key="k1", n_sup=1, post_from=100, record="I-1"):
    text = raw if text is None else text
    clauses = [] if n_sup == 0 else [{"observation_id": "o-" + key, "verbatim_text": text, "post_char_from": post_from,
                                      "post_char_to": post_from + len(text), "clause_set_seq": 1, "clause_set_sha256": SHA}]
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": predicate, "raw": raw,
            "record_key": record, "occurrence_id": "occ-" + record,
            "marriage_ordinal": ordinal if predicate == "relation.marriage" else None,
            "supporting_count": max(n_sup, 1) if n_sup else 1, "clauses": clauses}


def test_aegteskab_med_navn_og_aar():
    raw = "g. 1975 m. Bo Beta, f. 3.2.1950 i Kbh., d. 2001, d. af Carl Ceta."
    m, st = rpe.extract_rows([row(raw)])
    p = m["authorized_elements"]["relation-persona:k1"]
    assert raw[p["name_from"]:p["name_to"]] == "Bo Beta"
    assert (p["birth_raw"], p["death_raw"]) == ("1950", "2001")
    assert p["post_offset"] == 100 and p["span_from"] == 0 and p["span_to"] == len(raw)
    assert m["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "relation_personas": 1}
    assert st["elementer"] == 1


def test_aar_i_foraeldresegment_tages_ikke():
    raw = "g. m. Bo Beta, d. af Carl Ceta, f. 1900, d. 1960."
    p = rpe.extract_rows([row(raw)])[0]["authorized_elements"]["relation-persona:k1"]
    assert p["birth_raw"] is None and p["death_raw"] is None


def test_d_af_er_ikke_doed():
    raw = "g. m. Bo Beta, f. 1950, d. af Carl."
    p = rpe.extract_rows([row(raw)])[0]["authorized_elements"]["relation-persona:k1"]
    assert (p["birth_raw"], p["death_raw"]) == ("1950", None)


def test_barn_har_null_felter():
    p = rpe.extract_rows([row("Datter Dora.", predicate="relation.child")])[0]["authorized_elements"]["relation-persona:k1"]
    assert all(p[k] is None for k in ("marriage_ordinal", "name_from", "name_to", "birth_raw", "death_raw"))


def test_parkeringsgrunde():
    rows = [row("g. m. Bo Beta.", text="noget andet", key="a"),
            row("g. m. Bo Beta.", text="g. m. Bo Beta. g. m. Bo Beta.", key="b"),
            row("g. m. Bo Beta.", n_sup=0, key="c"),
            row("gift 1975.", key="d"),
            row("g. m. Bo Beta.", ordinal=None, key="e")]
    rows[2]["supporting_count"] = 2
    m, st = rpe.extract_rows(rows)
    assert m["authorized_elements"] == {}
    assert st["parkeret"] == {"ikke_ordret": 1, "tvetydigt_spaend": 1, "flere_klausuler": 1, "intet_navn": 1, "intet_nummer": 1}


def test_dubletter_parkeres_begge():
    a, b = row("g. m. Bo Beta.", key="a"), row("g. m. Bo Beta.", key="b")
    m, st = rpe.extract_rows([a, b])
    assert m["authorized_elements"] == {} and st["parkeret"] == {"dublet": 2}


def test_payload_noegler_er_writerens():
    p = rpe.extract_rows([row("g. m. Bo Beta.")])[0]["authorized_elements"]["relation-persona:k1"]
    assert sorted(p) == ["birth_raw", "clause_observation_id", "clause_set_seq", "clause_set_sha256", "death_raw",
                         "interpretation_key", "interpretation_version", "marriage_ordinal", "name_from", "name_to",
                         "post_offset", "predicate", "profile", "span_from", "span_to"]


def test_cli_printer_ingen_vaerdier(tmp_path):
    inp = tmp_path / "in.json"
    inp.write_text(json.dumps({"input_sha256": SHA, "input": [row("g. m. Hemmelig Navnesen, f. 1950.")]}))
    out = tmp_path / "out.json"
    r = subprocess.run([sys.executable, str(HERE / "relation_persona_extract.py"), "--input", str(inp), "--out", str(out)],
                       capture_output=True, text=True, check=True)
    first = r.stdout.splitlines()[0]
    assert "Hemmelig" not in r.stdout + r.stderr and "1950" not in first   # 2. linje er en hex-hash
    assert first.startswith("RELATION_EXTRACT_OK elementer=1")
    assert oct(out.stat().st_mode & 0o777) == "0o600"
```

- [ ] **Step 2: Kør testene og se dem fejle**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_relation_persona_extract.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'relation_persona_extract'`.

- [ ] **Step 3: Implementér udtrækket**

`.claude/skills/daa-extract/scripts/relation_persona_extract.py`:
```python
#!/usr/bin/env python3
"""Trin 5b: deterministisk udtræk af ægtefællens navn og år fra eksisterende relationspåstande.

Input er serverens (red_relation_persona_input). Output er writerens manifest. Ingen modelkald.
Scriptet printer kun tal og hashes; filerne indeholder navne og skrives 0600 under ~/.private/5b/."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

PROFILE = "relation-persona-2018-20-v1"
# Profilens markører (versioneret: ændres de, skal PROFILE have ny version).
NAME_START = re.compile(r"(?:^|\s)m\.\s+")                    # »… m. <navn>« (gift med)
NAME_END = re.compile(r",|;|\(|\s(?:f|d|s)\.\s|\.$|$")        # navnet slutter ved komma, parentes eller markør
PARENTS = re.compile(r"(?:\b[ds]\.\s+af\b|\bdatter af\b|\bsøn af\b)")
BIRTH = re.compile(r"\bf\.\s+[^,;()]*?\b(\d{4})\b")
DEATH = re.compile(r"(?:^|[\s,])d\.\s+(?!af\b)[^,;()]*?\b(\d{4})\b")
LETTER = re.compile(r"[A-Za-zÀ-ÿ]")


def _park(stats: Counter, reason: str) -> None:
    stats[reason] += 1


def _name(raw: str):
    m = NAME_START.search(raw)
    if not m:
        return None
    start = m.end()
    end_m = NAME_END.search(raw, start)
    end = end_m.start() if end_m else len(raw)
    name = raw[start:end].rstrip()
    if not LETTER.search(name) or len(name.split()) > 8:
        return None
    return start, start + len(name)


def _years(segment: str):
    cut = PARENTS.search(segment)
    own = segment[:cut.start()] if cut else segment
    births, deaths = BIRTH.findall(own), DEATH.findall(own)
    if len(births) > 1 or len(deaths) > 1:
        return "tvetydige_aar"
    return (births[0] if births else None, deaths[0] if deaths else None)


def extract_rows(rows: list[dict]) -> tuple[dict, dict]:
    parked: Counter = Counter()
    candidates: dict[str, dict] = {}
    for r in rows:
        clauses = r["clauses"]
        if r["supporting_count"] != 1:
            _park(parked, "flere_klausuler"); continue
        if len(clauses) != 1:
            _park(parked, "klausul_ikke_gaeldende"); continue
        c, raw = clauses[0], r["raw"]
        text = c["verbatim_text"]
        n = text.count(raw) if raw else 0
        if n == 0:
            _park(parked, "ikke_ordret"); continue
        if n > 1:
            _park(parked, "tvetydigt_spaend"); continue
        span_from = text.index(raw)
        payload = {"birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
                   "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
                   "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
                   "marriage_ordinal": None, "name_from": None, "name_to": None,
                   "post_offset": c["post_char_from"] + span_from, "predicate": r["predicate"], "profile": PROFILE,
                   "span_from": span_from, "span_to": span_from + len(raw)}
        if r["predicate"] == "relation.marriage":
            if r["marriage_ordinal"] is None:
                _park(parked, "intet_nummer"); continue
            nm = _name(raw)
            if nm is None:
                _park(parked, "intet_navn"); continue
            years = _years(raw[nm[1]:])
            if years == "tvetydige_aar":
                _park(parked, "tvetydige_aar"); continue
            payload.update(marriage_ordinal=r["marriage_ordinal"], name_from=span_from + nm[0], name_to=span_from + nm[1],
                           birth_raw=years[0], death_raw=years[1])
        candidates["relation-persona:" + r["interpretation_key"]] = payload
    # Uadskillelige dubletter (spec §5.1): samme post, prædikat, post_offset og spændlængde.
    groups: Counter = Counter()
    rec = {r["interpretation_key"]: r["record_key"] for r in rows}
    sig = {k: (rec[p["interpretation_key"]], p["predicate"], p["post_offset"], p["span_to"] - p["span_from"])
           for k, p in candidates.items()}
    groups.update(sig.values())
    elements = {}
    for k, p in candidates.items():
        if groups[sig[k]] > 1:
            _park(parked, "dublet")
        else:
            elements[k] = p
    manifest = {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
                "authorized_elements": dict(sorted(elements.items()))}
    per = Counter(p["predicate"] for p in elements.values())
    return manifest, {"elementer": len(elements), "parkeret": dict(sorted(parked.items())), "pr_praedikat": dict(sorted(per.items()))}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    data = json.loads(Path(a.input).read_text(encoding="utf-8"))
    manifest, stats = extract_rows(data["input"])
    manifest["input_sha256"] = data["input_sha256"]
    out = Path(a.out)
    body = json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode("utf-8")
    out.write_bytes(body); out.chmod(0o600)
    print(f"RELATION_EXTRACT_OK elementer={stats['elementer']} parkeret={json.dumps(stats['parkeret'])} "
          f"pr_praedikat={json.dumps(stats['pr_praedikat'])}")
    print(f"  manifest_fil_sha256 {hashlib.sha256(body).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Kør testene og se dem bestå**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_relation_persona_extract.py -q`
Expected: `8 passed`.

- [ ] **Step 5: Input- og apply-script (psql, kun tal i output)**

`.claude/skills/daa-extract/scripts/relation_persona_input.sql`:
```sql
-- Trin 5b: udtrækkets input. Output indeholder navne → 0600-fil under ~/.private/5b/.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_relation_persona_input(:source_id);
COMMIT;
```
`.claude/skills/daa-extract/scripts/relation_persona_apply.sql`:
```sql
-- Trin 5b: autorisér, åbn, skriv, finalisér én relation_persona-batch. Printer kun tal og hashes.
-- Variabler: actor, source_id, manifest_file. Profilen oprettes som ejer (idempotent).
\set ON_ERROR_STOP on
\set content `cat :manifest_file`
SELECT private.reimport_canonical_json_sha256((:'content'::jsonb)->'authorized_elements') AS m \gset
SELECT '{"citation_label_template":"DAA 2018-20 s. {page_from}","extractor_version":"relation-persona-v1","observation_extraction_method":"relation_persona_extract","rendition_key":"relation-persona","rendition_kind":"pdf_text_layer","rendition_metadata":{},"run_key_prefix":"relation-persona","schema_version":"relation-persona-v1"}'::jsonb AS cfg \gset
INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
VALUES (:source_id,'relation-persona-2018-20','relation-persona-v1',private.reimport_canonical_json_sha256(:'cfg'::jsonb),:'cfg'::jsonb)
ON CONFLICT (source_id,profile_id) DO NOTHING;
SELECT profile_sha256 AS profile_sha FROM private.reimport_writer_profile WHERE source_id=:source_id AND profile_id='relation-persona-2018-20' \gset
SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS dbid \gset
-- Autorisationen er kun tildelt service_role (schema.sql:4558) — egen transaktion, som i
-- docs/runbooks/legacy-migration-reimport-rehearsal.md §3.
BEGIN;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SELECT public.red_authorize_reimport(:'m',:'m',:'dbid',:source_id,'relation-persona-2018-20',:'profile_sha',
  (:'content'::jsonb)->'expected_counts',(:'content'::jsonb)->'authorized_elements',gen_random_uuid(),
  clock_timestamp()+interval '1 hour') AS auth \gset
COMMIT;
-- Begin, apply og finalize som authenticated redaktion.
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_begin_reimport(:'auth'::uuid,:'m',:'m') AS batch \gset
SELECT count(public.red_apply_reimport_relation_persona(:'batch'::uuid,e.key,e.value)) AS skrevet
  FROM jsonb_each((:'content'::jsonb)->'authorized_elements') e;
SELECT public.red_finalize_reimport(:'batch'::uuid)->'counts' AS counts;
SELECT r->'relation_results' AS relation_results FROM public.red_reimport_batch_result(:'auth'::uuid,:'batch'::uuid) r;
COMMIT;
SELECT 'manifest_sha256 '||:'m' AS manifest;
```

- [ ] **Step 6: Prøvekørsel på målebasen (Task 0) — kun tal**

Run (målebasen fra Task 0; `A` = en lokal redaktør-uuid fra basens `profiles` med rolle `redaktion`, aldrig printet):
```bash
umask 077; mkdir -p ~/.private/5b
A=$(psql -X -At -d <db> -c "select id from profiles where rolle='redaktion' order by id limit 1")
psql -X -At -q -d <db> -v actor="$A" -v source_id=1 -f .claude/skills/daa-extract/scripts/relation_persona_input.sql > ~/.private/5b/relation-input.json
/usr/bin/python3 .claude/skills/daa-extract/scripts/relation_persona_extract.py --input ~/.private/5b/relation-input.json --out ~/.private/5b/relation-manifest.json
```
Expected: `RELATION_EXTRACT_OK elementer=N parkeret={…} pr_praedikat={…}` — kun tal. Skriv tallene i ledgeren. Er `intet_navn` mere end 10 % af ægteskaberne, justér `NAME_START`/`NAME_END` ud fra **tællinger** (fx `psql -c "select count(*) … where value->>'raw' ~ '<mønster>'"`), bump `PROFILE` til `-v2`, ledger en `Ruling:` og kør igen. Læs aldrig filerne.

- [ ] **Step 7: CI og commit**

`.github/workflows/ci.yml`, job `python`: tilføj `test_relation_persona_extract.py` i pytest-listen (samme linje som `test_identity_decision_sheet.py`).
```bash
git add .claude/skills/daa-extract/scripts/relation_persona_extract.py .claude/skills/daa-extract/scripts/test_relation_persona_extract.py \
  .claude/skills/daa-extract/scripts/relation_persona_input.sql .claude/skills/daa-extract/scripts/relation_persona_apply.sql .github/workflows/ci.yml
git commit -m "feat(151): deterministisk udtræk af ægtefællers navn og år + apply-script

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 4: Familiekontekst på serveren og familiesignal i generatoren

**Files:**
- Create: `tests/sql/test-relation-family-context.sql`, `packages/identity-candidates/src/family.ts`, `packages/identity-candidates/src/__tests__/family.test.ts`
- Modify: `tests/sql/fixtures/relation-5b.sql` (ny `f5b_spouse`), `schema.sql` + 5b-sektionen (ny funktion, ny kolonne, `private.identity_candidate_input`, `red_record_identity_candidates` — erstattes på deres eksisterende plads i 5a-sektionen, ikke dubleret), `packages/identity-candidates/src/frames.ts`, `rank.ts`, `cli.ts`, `src/__tests__/rank.test.ts`, `.github/workflows/ci.yml` (fresh-trinnet)

**Interfaces:**
- Consumes: `interpretation_party_current` (Task 1), `private.relation_marriage_ordinals` (Task 2).
- Produces:
  - `private.persona_family_context(p_persona uuid) RETURNS jsonb` — `NULL` for personas der ikke er gældende `spouse`-part med accepteret principal; ellers `{principal_source_persona_id, principal_identity_version, principal_person_id, spouse_identity_version, marriage_ordinal, marriage_claims_in_post, families:[{family_id, ordinal, konfidens:[…], partners:[person_id…]}]}` (sorteret).
  - Kolonnen `private.source_persona_identity_candidate.family_context_sha256 text` (sat af serveren; NULL uden kontekst). Task 7's kerne genberegner den.
  - `identity_candidate_input`: personas får `family_context` (kun når ikke-NULL); top-niveau `same_as: [[a,b]…]` (sorteret).
  - TS: `evaluateFamily(ctx: FamilyContext): FamilyEval`, `clusterMap(pairs: Array<[number, number]>): Map<number, number>`, `RankOptions.families`, `RankOptions.clusters`, `RankOptions.familyNameMin` (default `0.9`); `Candidate.basis` får `family_partner`, `ordinal_match`, `corroboration_eligible`, `eligibility_reason`, `cluster_members`.

- [ ] **Step 1: Udvid fixtures med en ægtefælle-persona**

Tilføj til `tests/sql/fixtures/relation-5b.sql`:
```sql
-- En ægtefælle-persona som writeren ville skrive den (mention på klausulen, rolle spouse)
-- plus principal- og spouse-part. Bruges af Task 4-7's tests uden writer-rammen.
CREATE OR REPLACE FUNCTION pg_temp.f5b_spouse(p_source bigint,p_src jsonb,p_post jsonb,p_claim jsonb,p_clause uuid,
  p_name text,p_ordinal int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_text text; v_from int; v_persona uuid; v_mention uuid; v_ref uuid:=gen_random_uuid();
BEGIN
  SELECT verbatim_text INTO v_text FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_text,p_name)-1;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
    VALUES (p_source,(p_post->>'key')||'#rel-marriage-'||v_from||'-'||p_ordinal,(p_src->>'run')::uuid) RETURNING id INTO v_persona;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (p_clause,'person',v_from,v_from+char_length(p_name),p_name,(p_src->>'run')::uuid) RETURNING id INTO v_mention;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'spouse',1);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((p_claim->>'key')::uuid,'principal',1,(p_post->>'principal')::uuid,v_from,'relation_persona',v_ref);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,origin,origin_ref)
    VALUES ((p_claim->>'key')::uuid,'spouse',1,v_persona,p_ordinal,v_from,'relation_persona',v_ref);
  RETURN v_persona;
END $$;
```

- [ ] **Step 2: Skriv den fejlende SQL-test**

`tests/sql/test-relation-family-context.sql`:
```sql
-- Trin 5b, Task 4: familiekontekst og family_context_sha256 på kandidatrækken.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $relation_family_context$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b401';
  s jsonb; p jsonb; c jsonb; v_sp uuid; v_fam bigint; ctx jsonb; v_in jsonb; v_run uuid; v_hash text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES (-5401,false,false,'5b','Anna Alfa'),(-5402,false,false,'5b','Bo Beta');
  s:=pg_temp.f5b_source(-5401);
  p:=pg_temp.f5b_post(-5401,s,'IV-1','Anna Alfa. g. m. Bo Beta, f. 1801.',ARRAY['Anna Alfa.','g. m. Bo Beta, f. 1801.'],-5401,v_actor);
  c:=pg_temp.f5b_claim(-5401,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Bo Beta, f. 1801.');
  v_sp:=pg_temp.f5b_spouse(-5401,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  v_fam:=pg_temp.f5b_family(-5401,-5402,1);
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',-5402,'person',-5401,'samme_som');

  ctx:=private.persona_family_context(v_sp);
  IF ctx->>'principal_person_id'<>'-5401' OR (ctx->>'marriage_claims_in_post')::int<>1 OR (ctx->>'marriage_ordinal')::int<>1
     OR ctx->'families'->0->'partners'<>'[-5402]'::jsonb OR (ctx->'families'->0->>'family_id')::bigint<>v_fam THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: %',ctx;
  END IF;
  IF private.persona_family_context((p->>'principal')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: hovedpersonen fik kontekst';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5401,'{"mode":"undecided"}');
  IF jsonb_array_length(v_in->'input'->'personas')<>1
     OR v_in->'input'->'personas'->0->'family_context' IS NULL
     OR v_in->'input'->'same_as'<>'[[-5402,-5401]]'::jsonb THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: input %',v_in->'input'->'same_as';
  END IF;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5401,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    jsonb_build_array(jsonb_build_object('source_persona_id',v_sp,'candidate_person_id',-5402,'rank',1,'score',0.95,'tier','auto',
      'basis','{"signals":["name","family_partner"]}'::jsonb)));
  RESET ROLE;
  SELECT family_context_sha256 INTO v_hash FROM private.source_persona_identity_candidate WHERE run_id=v_run;
  IF v_hash IS DISTINCT FROM private.reimport_canonical_json_sha256(ctx) THEN
    RAISE EXCEPTION 'FAMILY_CONTEXT_TEST_FAILED: hash på kandidatrækken';
  END IF;
  RAISE NOTICE 'OK: familiekontekst, input med same_as og serverberegnet family_context_sha256';
END $relation_family_context$;
ROLLBACK;
```

- [ ] **Step 3: Kør og se den fejle**

Run: `fresh ci5b_t4 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t4 -f tests/sql/test-relation-family-context.sql`
Expected: FAIL — `function private.persona_family_context(uuid) does not exist`.

- [ ] **Step 4: Implementér SQL-delen**

1. Ny funktion (schema.sql efter `relation_marriage_ordinals`; 5b-sektionen):
```sql
CREATE OR REPLACE FUNCTION private.persona_family_context(p_persona uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  WITH sp AS (SELECT pc.interpretation_key,pc.marriage_ordinal FROM private.interpretation_party_current pc
               WHERE pc.source_persona_id=p_persona AND pc.party_role='spouse'),
  pr AS (SELECT pc.source_persona_id FROM private.interpretation_party_current pc JOIN sp USING (interpretation_key)
          WHERE pc.party_role='principal'),
  pid AS (SELECT i.canonical_person_id,i.version,i.source_persona_id FROM private.source_persona_identity i
            JOIN pr ON pr.source_persona_id=i.source_persona_id WHERE i.decision_status='accepted'),
  occ AS (SELECT o.occurrence_id FROM sp JOIN private.interpretation_current ic ON ic.interpretation_key=sp.interpretation_key
            JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
            JOIN private.source_observation o ON o.id=io.observation_id)
  SELECT CASE WHEN (SELECT count(*) FROM sp)<>1 OR (SELECT count(*) FROM pid)<>1 THEN NULL ELSE jsonb_build_object(
    'principal_source_persona_id',(SELECT source_persona_id FROM pid)::text,
    'principal_identity_version',(SELECT version FROM pid),
    'principal_person_id',(SELECT canonical_person_id FROM pid),
    'spouse_identity_version',coalesce((SELECT version FROM private.source_persona_identity WHERE source_persona_id=p_persona),0),
    'marriage_ordinal',(SELECT marriage_ordinal FROM sp),
    'marriage_claims_in_post',(SELECT count(*) FROM occ CROSS JOIN LATERAL private.relation_marriage_ordinals(occ.occurrence_id)),
    'families',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'family_id',fm.family_id,'ordinal',fm.ordinal,
        'konfidens',(SELECT coalesce(jsonb_agg(DISTINCT o.konfidens ORDER BY o.konfidens),'[]'::jsonb) FROM family_member o
                      WHERE o.family_id=fm.family_id AND o.rolle='partner' AND o.konfidens IS NOT NULL),
        'partners',(SELECT coalesce(jsonb_agg(o.person_id ORDER BY o.person_id),'[]'::jsonb) FROM family_member o
                     WHERE o.family_id=fm.family_id AND o.rolle='partner' AND o.person_id<>fm.person_id))
        ORDER BY fm.family_id)
       FROM family_member fm WHERE fm.person_id=(SELECT canonical_person_id FROM pid) AND fm.rolle='partner'),'[]'::jsonb)) END;
$$;
REVOKE ALL ON FUNCTION private.persona_family_context(uuid) FROM PUBLIC,anon,authenticated;
```
2. Kolonnen (schema.sql: i `CREATE TABLE private.source_persona_identity_candidate`; 5b-sektionen):
```sql
ALTER TABLE private.source_persona_identity_candidate ADD COLUMN IF NOT EXISTS family_context_sha256 text
  CONSTRAINT source_persona_identity_candidate_family_ctx_check CHECK (family_context_sha256 IS NULL OR family_context_sha256 ~ '^[0-9a-f]{64}$');
```
3. `private.identity_candidate_input` (schema.sql 8460 og 5a-sektionens definition i db-migrations — ret begge på stedet):
   - i den indre `SELECT … FROM private.source_persona p` tilføj kolonnen `fctx.fc AS family_context` og joinet
     `LEFT JOIN LATERAL (SELECT private.persona_family_context(p.id) AS fc) fctx ON true`;
   - aggregatet ændres fra `jsonb_agg(to_jsonb(x) ORDER BY …)` til
     ```sql
     jsonb_agg((to_jsonb(x)-'family_context')
               || CASE WHEN x.family_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('family_context',x.family_context) END
               ORDER BY x.source_persona_id COLLATE "C")
     ```
     så 5a-personas uden kontekst har præcis samme form som før;
   - returværdien bliver:
  RETURN jsonb_build_object('personas',v_personas,'persons',v_persons,
    'same_as',coalesce((SELECT jsonb_agg(jsonb_build_array(r.subjekt_id,r.objekt_id) ORDER BY r.subjekt_id,r.objekt_id)
                          FROM public.relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'),'[]'::jsonb));
```
4. `red_record_identity_candidates` (schema.sql 8582 og 5a-sektionen): kandidat-INSERT'en udvides:
```sql
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis,family_context_sha256)
  SELECT v_run,(c->>'source_persona_id')::uuid,(c->>'candidate_person_id')::bigint,(c->>'rank')::int,
         (c->>'score')::numeric,c->>'tier',c->'basis',
         (SELECT CASE WHEN fc IS NULL THEN NULL ELSE private.reimport_canonical_json_sha256(fc) END
            FROM private.persona_family_context((c->>'source_persona_id')::uuid) fc)
    FROM jsonb_array_elements(p_candidates) c;
```
5. CI: fresh-trinnet efter `test-relation-party.sql`: `psql -v ON_ERROR_STOP=1 -f tests/sql/test-relation-family-context.sql`.

- [ ] **Step 5: Kør SQL-testen og 5a's kandidattests**

Run: `fresh ci5b_t4b && for t in test-relation-family-context test-identity-candidates test-identity-decision test-identity-detail; do psql -X -v ON_ERROR_STOP=1 -d ci5b_t4b -f tests/sql/$t.sql || break; done`
Expected: `OK: familiekontekst …` og 5a's tre testfiler uændret grønne.

- [ ] **Step 6: Skriv de fejlende generator-tests**

`packages/identity-candidates/src/__tests__/family.test.ts`:
```ts
import { describe, expect, test } from 'vitest';
import type { MatchFrame } from '@daa/core';
import { clusterMap, evaluateFamily, type FamilyContext } from '../family';
import { rankCandidates } from '../rank';

const f = (id: string | number, nameKey: string): MatchFrame =>
  ({ id, nameKey, birthMin: null, birthMax: null, deathMin: null, deathMax: null, sex: 'ukendt' });
const ctx = (over: Partial<FamilyContext> = {}): FamilyContext => ({
  principal_person_id: 1, marriage_ordinal: 1, marriage_claims_in_post: 1,
  families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7] }], ...over,
});
const origins = new Map([['s1', { name: 'mention', birth: null, death: null }]]);

describe('evaluateFamily', () => {
  test('entydig familie', () => expect(evaluateFamily(ctx())).toMatchObject({ structureOk: true, target: 7, reason: 'ok' }));
  test('count_mismatch', () => expect(evaluateFamily(ctx({ marriage_claims_in_post: 2 })).reason).toBe('count_mismatch'));
  test('NULL-ordenstal ved flere familier', () => expect(evaluateFamily(ctx({ marriage_claims_in_post: 2,
    families: [{ family_id: 10, ordinal: null, konfidens: [], partners: [7] }, { family_id: 11, ordinal: 2, konfidens: [], partners: [8] }] })).reason)
    .toBe('ordinal_null'));
  test('ordenstal vælger familien', () => expect(evaluateFamily(ctx({ marriage_ordinal: 2, marriage_claims_in_post: 2,
    families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7] }, { family_id: 11, ordinal: 2, konfidens: [], partners: [8] }] })).target)
    .toBe(8));
  test('omstridt konfidens', () => expect(evaluateFamily(ctx({ families: [{ family_id: 10, ordinal: 1, konfidens: ['omstridt'], partners: [7] }] })).reason)
    .toBe('konfidens'));
  test('to partnere', () => expect(evaluateFamily(ctx({ families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7, 9] }] })).reason)
    .toBe('partner_count'));
});

describe('rankCandidates med familie', () => {
  test('familiepartneren står først og er egnet ved stærkt navn', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo beta'), f(7, 'bo beta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]) });
    expect(out[0]).toMatchObject({ candidate_person_id: 7, rank: 1 });
    expect(out[0].basis).toMatchObject({ family_partner: true, ordinal_match: true, corroboration_eligible: true });
  });
  test('svagt navn er ikke egnet', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(7, 'carl ceta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]) });
    expect(out.find((c) => c.candidate_person_id === 7)?.basis.corroboration_eligible ?? false).toBe(false);
  });
  test('samme_som-klynge slås sammen med familiepartneren som repræsentant', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo beta'), f(7, 'bo beta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]), clusters: clusterMap([[5, 7]]) });
    expect(out.map((c) => c.candidate_person_id)).toEqual([7]);
    expect(out[0].basis.cluster_members).toEqual([5, 7]);
  });
  test('samme_som-klynge uden familiepartner: laveste id, selv når det højere id scorer bedst', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo bxta'), f(7, 'bo beta')],
      { topK: 3, origins, clusters: clusterMap([[5, 7]]) });
    expect(out.map((c) => c.candidate_person_id)).toEqual([5]);
    expect(out[0].basis.cluster_members).toEqual([5, 7]);
  });
});
```

- [ ] **Step 7: Kør og se dem fejle**

Run: `env -u NODE_OPTIONS npm run test -w @daa/identity-candidates`
Expected: FAIL — `Cannot find module '../family'`.

- [ ] **Step 8: Implementér `family.ts` og udvid `rank.ts`, `frames.ts`, `cli.ts`**

`packages/identity-candidates/src/family.ts`:
```ts
export type FamilyContext = {
  principal_person_id: number; marriage_ordinal: number; marriage_claims_in_post: number;
  families: Array<{ family_id: number; ordinal: number | null; konfidens: string[]; partners: number[] }>;
};
export type FamilyEval = { partners: number[]; target: number | null; structureOk: boolean; reason: string; ordinalMatch: Set<number> };

// Spec §6.1/§6.2(b): samme strukturelle regler som kernen efterprøver. Generatorens svar er
// kun en sorteringshjælp — kernen genberegner det hele under rækkelåse.
export function evaluateFamily(ctx: FamilyContext): FamilyEval {
  const partners = [...new Set(ctx.families.flatMap((x) => x.partners))].sort((a, b) => a - b);
  const no = (reason: string): FamilyEval => ({ partners, target: null, structureOk: false, reason, ordinalMatch: new Set() });
  if (ctx.marriage_claims_in_post !== ctx.families.length) return no('count_mismatch');
  if (ctx.families.length > 1 && ctx.families.some((x) => x.ordinal == null)) return no('ordinal_null');
  const chosen = ctx.families.length === 1 ? ctx.families : ctx.families.filter((x) => x.ordinal === ctx.marriage_ordinal);
  if (chosen.length !== 1) return no('ordinal_no_match');
  const fam = chosen[0];
  if (fam.partners.length !== 1) return no('partner_count');
  if (fam.konfidens.some((k) => k === 'omstridt' || k === 'formodet')) return no('konfidens');
  return { partners, target: fam.partners[0], structureOk: true, reason: 'ok', ordinalMatch: new Set(fam.partners) };
}

// Union-find over samme_som-par; repræsentant = laveste id (rangeringen vælger den synlige).
export function clusterMap(pairs: Array<[number, number]>): Map<number, number> {
  const parent = new Map<number, number>();
  const find = (x: number): number => { const p = parent.get(x) ?? x; if (p === x) return x; const r = find(p); parent.set(x, r); return r; };
  for (const [a, b] of pairs) { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(Math.max(ra, rb), Math.min(ra, rb)); }
  const out = new Map<number, number>();
  for (const x of new Set(pairs.flat())) out.set(x, find(x));
  return out;
}
```
`rank.ts` — ændringer:
```ts
import { evaluateFamily, type FamilyContext } from './family';
export type Candidate = {
  source_persona_id: string; candidate_person_id: number; rank: number; score: number; tier: Tier;
  basis: { signals: string[]; name_origin: string; birth_origin: string | null; death_origin: string | null;
           family_partner?: boolean; ordinal_match?: boolean; corroboration_eligible?: boolean;
           eligibility_reason?: string; cluster_members?: number[] };
};
export type RankOptions = { topK: number; origins: Map<string, PersonaOrigin>; evidensNormaliseret?: boolean;
  families?: Map<string, FamilyContext>; clusters?: Map<number, number>; familyNameMin?: number };
```
og i løkken pr. persona, efter `const sorted = …` og før `margin`:
```ts
    const ctx = opts.families?.get(pid);
    const fam = ctx ? evaluateFamily(ctx) : null;
    let ordered = sorted;
    if (fam) {
      const inFam = new Set(fam.partners);
      ordered = [...sorted.filter((p) => inFam.has(Number(p.bId))), ...sorted.filter((p) => !inFam.has(Number(p.bId)))];
    }
    const members = new Map<number, number[]>();
    if (opts.clusters) {
      const seen = new Map<number, number>();
      ordered = ordered.filter((p) => {
        const id = Number(p.bId); const rep = opts.clusters!.get(id) ?? id;
        if (seen.has(rep)) { members.get(seen.get(rep)!)!.push(id); return false; }
        seen.set(rep, id); members.set(id, [id]); return true;
      });
      // Spec §6.1: repræsentanten er familiens partner, ellers laveste id — ikke den bedst scorede.
      // Pladsen (score, rang) bevares; kun id'et skiftes (Codex plan-r1 fund 6).
      const partnerSet = new Set(fam?.partners ?? []);
      ordered = ordered.map((p) => {
        const id = Number(p.bId); const ms = members.get(id)!;
        const repId = ms.find((m) => partnerSet.has(m)) ?? Math.min(...ms);
        if (repId === id) return p;
        members.delete(id); members.set(repId, ms);
        return { ...p, bId: repId };
      });
    }
```
erstat `sorted` med `ordered` i `margin` og `list`, og i `list.forEach` udvid tier og basis:
```ts
      const isPartner = fam ? fam.partners.includes(Number(p.bId)) : false;
      const eligible = Boolean(fam?.structureOk && i === 0 && fam.target === Number(p.bId) && p.nameSim >= (opts.familyNameMin ?? 0.9));
      const famTier: Tier = eligible ? 'auto' : tier === 'auto' ? 'review' : tier;
      const cl = (members.get(Number(p.bId)) ?? []).sort((a, b) => a - b);
      out.push({
        source_persona_id: pid, candidate_person_id: Number(p.bId), rank: i + 1, score: round4(Math.min(1, Math.max(0, p.s))),
        tier: fam ? famTier : tier,
        basis: { signals: [...signals, ...(isPartner ? ['family_partner'] : []), ...(fam?.ordinalMatch.has(Number(p.bId)) ? ['ordinal_match'] : [])],
                 name_origin: origin.name ?? 'unknown', birth_origin: origin.birth, death_origin: origin.death,
                 ...(fam ? { family_partner: isPartner, ordinal_match: fam.ordinalMatch.has(Number(p.bId)),
                             corroboration_eligible: eligible, eligibility_reason: eligible ? 'ok' : (fam.structureOk ? 'name_or_rank' : fam.reason) } : {}),
                 ...(cl.length > 1 ? { cluster_members: cl } : {}) },
      });
```
`frames.ts`: `PersonaExportRow` får `family_context?: FamilyContext` (import fra `./family`).
`cli.ts` (generate): efter `const persons = …`:
```ts
  const families = new Map(personaRows.filter((r) => r.family_context).map((r) => [r.source_persona_id, r.family_context!] as const));
  const clusters = clusterMap(((exp.input as { same_as?: Array<[number, number]> }).same_as ?? []));
  const familyNameMin = Number(arg('family-name-min', false) ?? 0.9);
  const candidates = rankCandidates(frames, persons, { topK, origins, evidensNormaliseret, families, clusters, familyNameMin });
```
og `run.config` får `familyNameMin`. Konsoloutput udvides med `egnede=${candidates.filter((c) => c.basis.corroboration_eligible).length}`. `GENERATOR_VERSION` bumpes til `'identity-candidates-1.1'`.

- [ ] **Step 9: Kør generator-testene, typecheck og se dem bestå**

Run: `env -u NODE_OPTIONS npm run test -w @daa/identity-candidates && env -u NODE_OPTIONS npm run typecheck -w @daa/identity-candidates`
Expected: alle tests grønne (5a's `rank.test.ts` uændret grøn — familie- og klyngefelterne er valgfrie), typecheck rc 0.

- [ ] **Step 10: Commit**

```bash
git add schema.sql db-migrations.sql tests/sql/fixtures/relation-5b.sql tests/sql/test-relation-family-context.sql \
  packages/identity-candidates/src .github/workflows/ci.yml
git commit -m "feat(151): familiekontekst og familiesignal i kandidatgeneratoren

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 5: Børn og forældre — strukturelle kandidater, rækkelåse og menneskelig afgørelse

**Files:**
- Create: `tests/sql/test-relation-decision.sql`
- Modify: `schema.sql` + 5b-sektionen, `db-migrations.sql` `v_authenticated`, `db-verify.sql` ACL-listen, `db-rls.sql` allow-listen, `.github/workflows/ci.yml` (fresh-trinnet)

**Interfaces:**
- Consumes: `interpretation_party` (Task 1), principal-parten skrevet af `relation_persona` (Task 2), `red_decide_interpretation(uuid,int,text,jsonb)` (eksisterende; kræver status `proposed`).
- Produces:
  - `private.relation_structural_candidates(p_interpretation_key uuid) RETURNS TABLE(family_id bigint, counterpart_persona_id uuid, counterpart_person_id bigint)` — kandidat-familier for `relation.child`/`relation.parent` blandt kildens hovedpersoner.
  - `private.lock_family_rows(p_person_ids bigint[]) RETURNS void` — spec §6.2's rækkelåse (person → familie → `family_member`, sorteret). Genbruges af Task 8.
  - `red_afgoer_relation_interpretation(p_interpretation_key uuid, p_expected_version integer, p_action text, p_family_id bigint, p_note text, p_context jsonb DEFAULT '{}') RETURNS integer` (ny version). `p_note` er med af samme grund som 5a's wrapper (afgørelser kræver en note). `U` → status `unresolved` (terminal for versionen, som trin 4).

- [ ] **Step 1: Skriv den fejlende test**

`tests/sql/test-relation-decision.sql`:
```sql
-- Trin 5b, Task 5: strukturelle kandidater og menneskelig afgørelse af relation.child/parent.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
DO $relation_decision$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b501';
  s jsonb; pa jsonb; pc jsonb; cc jsonb; cp jsonb; v_fam bigint; v_other bigint; v_ver int; v_n int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5501,false,false,'5b'),(-5502,false,false,'5b'),(-5503,false,false,'5b');
  s:=pg_temp.f5b_source(-5501);
  pa:=pg_temp.f5b_post(-5501,s,'V-1','Anna Alfa. Søn Carl.',ARRAY['Anna Alfa.','Søn Carl.'],-5501,v_actor);
  pc:=pg_temp.f5b_post(-5501,s,'V-2','Carl Alfa. søn af Anna.',ARRAY['Carl Alfa.','søn af Anna.'],-5502,v_actor);
  v_fam:=pg_temp.f5b_family(-5501,-5503,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5502,'barn');
  v_other:=pg_temp.f5b_family(-5503,NULL,2);
  cc:=pg_temp.f5b_claim(-5501,s,'relation.child',(pa->'clauses'->>1)::uuid,'Søn Carl.');
  cp:=pg_temp.f5b_claim(-5501,s,'relation.parent',(pc->'clauses'->>1)::uuid,'søn af Anna.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((cc->>'key')::uuid,'principal',1,(pa->>'principal')::uuid,11,'relation_persona',gen_random_uuid()),
           ((cp->>'key')::uuid,'principal',1,(pc->>'principal')::uuid,11,'relation_persona',gen_random_uuid());

  IF (SELECT array_agg(counterpart_person_id) FROM private.relation_structural_candidates((cc->>'key')::uuid))<>ARRAY[-5502]::bigint[]
     OR (SELECT array_agg(counterpart_person_id) FROM private.relation_structural_candidates((cp->>'key')::uuid))<>ARRAY[-5501]::bigint[] THEN
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: strukturelle kandidater';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  -- familie uden for kandidaterne afvises
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'same',v_other,'forkert familie','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: fremmed familie godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'RELATION_DECISION_FAMILY_INVALID%' THEN RAISE; END IF;
  END;
  -- forældet version afvises
  BEGIN
    PERFORM red_afgoer_relation_interpretation((cc->>'key')::uuid,2,'same',v_fam,'gammel','{}');
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: forkert version godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_INTERPRETATION_VERSION_CONFLICT%' THEN RAISE; END IF;
  END;
  v_ver:=red_afgoer_relation_interpretation((cc->>'key')::uuid,1,'same',v_fam,'barnet passer','{}');
  PERFORM red_afgoer_relation_interpretation((cp->>'key')::uuid,1,'unresolved',NULL,'kan ikke afgøre','{}');
  RESET ROLE;
  IF v_ver<>2 OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(cc->>'key')::uuid)<>'accepted'
     OR (SELECT decision_evidence->>'family_id' FROM private.interpretation_current WHERE interpretation_key=(cc->>'key')::uuid)<>v_fam::text
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(cc->>'key')::uuid
                     AND party_role='child' AND source_persona_id=(pc->>'principal')::uuid)
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(cp->>'key')::uuid)<>'unresolved'
     OR EXISTS (SELECT 1 FROM private.interpretation_party_current WHERE interpretation_key=(cp->>'key')::uuid AND party_role='parent') THEN
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: afgørelse eller part';
  END IF;
  RAISE NOTICE 'OK: strukturelle kandidater, familievalg, version, accept med modpart og U';
END $relation_decision$;

ROLLBACK;

-- Rækkelåsen: en samtidig family_member-indsættelse for personen venter (FK tager KEY SHARE).
-- Personen committes først, så dblink-forbindelsen ser den; den ryddes op til sidst.
INSERT INTO person(id,levende,privat,status) VALUES (-5591,false,false,'5b lock') ON CONFLICT (id) DO NOTHING;
CREATE EXTENSION IF NOT EXISTS dblink;
BEGIN;
DO $relation_lock$
DECLARE v_err text;
  -- Samme forbindelsesstreng som 5a's låsetest (test-identity-decision.sql:184): dblink bruger
  -- serverprocessens libpq-standarder, så port og socket skal angives eksplicit.
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM private.lock_family_rows(ARRAY[-5591]::bigint[]);
  BEGIN
    PERFORM dblink_connect('l5b',v_conn);
    PERFORM * FROM dblink('l5b','SET lock_timeout=''300ms''; INSERT INTO family(id,type) VALUES (-5591,''vielse''); '
      ||'INSERT INTO family_member(family_id,person_id,rolle) VALUES (-5591,-5591,''partner''); SELECT ''x''') AS t(x text);
    RAISE EXCEPTION 'RELATION_DECISION_TEST_FAILED: indsættelse ventede ikke';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    PERFORM dblink_disconnect('l5b');
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: personlåsen blokerer nye familiemedlemmer';
END $relation_lock$;
ROLLBACK;
DELETE FROM person WHERE id=-5591;
```

- [ ] **Step 2: Kør og se den fejle**

Run: `fresh ci5b_t5 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t5 -f tests/sql/test-relation-decision.sql`
Expected: FAIL — `function private.relation_structural_candidates(uuid) does not exist`.

- [ ] **Step 3: Implementér (schema.sql + 5b-sektionen)**

```sql
CREATE OR REPLACE FUNCTION private.lock_family_rows(p_person_ids bigint[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  -- Spec §6.2: personrækker → familier → medlemmer, alle sorteret. FOR UPDATE på personen
  -- blokerer nye family_member-rækker (FK-kontrollens FOR KEY SHARE) og red_slet_person.
  -- _tjek_partner_loft låser familien FØR FK-kontrollen tager personen; en samtidig
  -- partner-indsættelse i en af de låste familier kan derfor give deadlock. Postgres afbryder
  -- den ene transaktion (40P01) — fail-closed; kaldet gentages.
  PERFORM 1 FROM public.person WHERE id=ANY(p_person_ids) ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.family
   WHERE id IN (SELECT family_id FROM public.family_member WHERE person_id=ANY(p_person_ids))
   ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.family_member
   WHERE family_id IN (SELECT family_id FROM public.family_member WHERE person_id=ANY(p_person_ids))
   ORDER BY family_id,person_id,rolle FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION private.lock_family_rows(bigint[]) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.relation_structural_candidates(p_interpretation_key uuid)
RETURNS TABLE(family_id bigint, counterpart_persona_id uuid, counterpart_person_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  WITH ic AS (SELECT * FROM private.interpretation_current WHERE interpretation_key=p_interpretation_key),
  pr AS (SELECT i.canonical_person_id AS pid FROM private.interpretation_party_current pc
           JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
          WHERE pc.interpretation_key=p_interpretation_key AND pc.party_role='principal'),
  principals AS (
    SELECT spm.persona_id,i.canonical_person_id AS pid
      FROM private.source_persona sp
      JOIN private.source_persona_mention spm ON spm.persona_id=sp.id AND spm.mention_role='primary'
      JOIN private.source_mention sm ON sm.id=spm.mention_id
      JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
      JOIN private.source_persona_identity i ON i.source_persona_id=sp.id AND i.decision_status='accepted'
     WHERE sp.source_id=(SELECT source_id FROM ic))
  SELECT fm_p.family_id,pp.persona_id,pp.pid
    FROM ic CROSS JOIN pr
    JOIN public.family_member fm_p ON fm_p.person_id=pr.pid
    JOIN public.family_member fm_o ON fm_o.family_id=fm_p.family_id AND fm_o.person_id<>pr.pid
    JOIN principals pp ON pp.pid=fm_o.person_id
   WHERE (ic.predicate='relation.child' AND fm_p.rolle='partner' AND fm_o.rolle='barn')
      OR (ic.predicate='relation.parent' AND fm_p.rolle='barn' AND fm_o.rolle='partner')
   ORDER BY 1,3;
$$;
REVOKE ALL ON FUNCTION private.relation_structural_candidates(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION red_afgoer_relation_interpretation(
  p_interpretation_key uuid, p_expected_version integer, p_action text, p_family_id bigint,
  p_note text, p_context jsonb DEFAULT '{}'::jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_ctx jsonb:=coalesce(p_context,'{}'::jsonb); v_basis text; v_ic private.interpretation%ROWTYPE;
  v_role text; v_cand record; v_n integer; v_principal_pid bigint; v_evidence jsonb; v_new uuid;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v_basis:=coalesce(v_ctx->>'basis','web_detail');
  IF jsonb_typeof(v_ctx)<>'object'
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_ctx) k WHERE k NOT IN ('basis','sheet_sha256','rows_sha256','line'))
     OR p_action NOT IN ('same','unresolved') OR nullif(btrim(p_note),'') IS NULL
     OR (p_action='same' AND p_family_id IS NULL) OR (p_action<>'same' AND p_family_id IS NOT NULL)
     OR v_basis NOT IN ('web_detail','human_sheet')
     OR (v_basis='human_sheet' AND (coalesce(v_ctx->>'sheet_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'rows_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'line','') !~ '^[1-9][0-9]*$')) THEN
    RAISE EXCEPTION 'RELATION_DECISION_INVALID';
  END IF;
  SELECT * INTO v_ic FROM private.interpretation_current WHERE interpretation_key=p_interpretation_key;
  IF NOT FOUND OR v_ic.predicate NOT IN ('relation.child','relation.parent') THEN RAISE EXCEPTION 'RELATION_DECISION_INVALID'; END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_ic.source_id::text,0));
  v_role:=CASE v_ic.predicate WHEN 'relation.child' THEN 'child' ELSE 'parent' END;
  v_evidence:=jsonb_build_object('note',btrim(p_note),'action',p_action,'basis',v_basis,'method','relation-human-v1');
  IF v_basis='human_sheet' THEN
    v_evidence:=v_evidence||jsonb_build_object('sheet_sha256',v_ctx->>'sheet_sha256','rows_sha256',v_ctx->>'rows_sha256',
      'line',(v_ctx->>'line')::int);
  END IF;
  IF p_action='same' THEN
    SELECT i.canonical_person_id INTO v_principal_pid FROM private.interpretation_party_current pc
      JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
     WHERE pc.interpretation_key=p_interpretation_key AND pc.party_role='principal';
    IF v_principal_pid IS NULL THEN RAISE EXCEPTION 'RELATION_DECISION_PRINCIPAL_INVALID'; END IF;
    -- Rækkelåse (spec §6.2) før den sidste genberegning af kandidaterne.
    PERFORM private.lock_family_rows(ARRAY(SELECT DISTINCT x FROM unnest(ARRAY[v_principal_pid]||ARRAY(
      SELECT counterpart_person_id FROM private.relation_structural_candidates(p_interpretation_key))) x ORDER BY 1));
    SELECT count(*) INTO v_n FROM private.relation_structural_candidates(p_interpretation_key) c WHERE c.family_id=p_family_id;
    IF v_n<>1 THEN RAISE EXCEPTION 'RELATION_DECISION_FAMILY_INVALID'; END IF;
    SELECT * INTO v_cand FROM private.relation_structural_candidates(p_interpretation_key) c WHERE c.family_id=p_family_id;
    v_evidence:=v_evidence||jsonb_build_object('family_id',p_family_id,'counterpart_persona_id',v_cand.counterpart_persona_id);
    v_new:=public.red_decide_interpretation(v_ic.id,p_expected_version,'accepted',v_evidence);
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,origin,origin_ref)
    VALUES (p_interpretation_key,v_role,
            (SELECT coalesce(max(version),0)+1 FROM private.interpretation_party
              WHERE interpretation_key=p_interpretation_key AND party_role=v_role),
            v_cand.counterpart_persona_id,'relation_decision',v_new);
  ELSE
    v_new:=public.red_decide_interpretation(v_ic.id,p_expected_version,'unresolved',v_evidence);
  END IF;
  RETURN (SELECT version FROM private.interpretation WHERE id=v_new);
END $$;
REVOKE ALL ON FUNCTION red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb) TO authenticated;
```
Tilføj `'red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb)'::regprocedure` i `v_authenticated`, `$public_red_acl_verify$`-listen og `db-rls.sql`'s allow-liste. CI: fresh-trinnet efter `test-relation-family-context.sql`: `psql -v ON_ERROR_STOP=1 -f tests/sql/test-relation-decision.sql`.

- [ ] **Step 4: Kør og se den bestå**

Run: `fresh ci5b_t5b && psql -X -v ON_ERROR_STOP=1 -d ci5b_t5b -f tests/sql/test-relation-decision.sql`
Expected: `OK: strukturelle kandidater, familievalg, version, accept med modpart og U` og `OK: personlåsen blokerer nye familiemedlemmer`.

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-relation-decision.sql .github/workflows/ci.yml
git commit -m "feat(151): strukturelle kandidater, rækkelåse og menneskelig afgørelse af børn/forældre

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 6: Kontrolkørslen — serverens stikprøve, forsegling, status og stikprøveregler i afgørelses-RPC'erne

**Files:**
- Create: `tests/sql/test-identity-control-run.sql`
- Modify: `schema.sql` + 5b-sektionen (tre tabeller, fire funktioner; `red_afgoer_source_persona` og `red_afgoer_relation_interpretation` erstattes på deres plads), `db-rls.sql` (master-array + allow-liste), `db-verify.sql`, `db-migrations.sql` `v_authenticated`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: kandidatkørslen med `basis.corroboration_eligible` (Task 4), `persona_family_context` (Task 4), `relation_structural_candidates` (Task 5).
- Produces:
  - Tabeller `private.identity_control_run(id, source_id, candidate_run_id, identity_population_sha256, relation_population_sha256, input_list_sha256, created_by, created_at)`, `private.identity_control_sample(id, control_run_id, sample_kind, stratum, source_persona_id, interpretation_key, interpretation_version, identity_version, mapping jsonb {"1":"<id>",…} (højst pladserne 1–3), expected text)`, `private.identity_control_event(control_run_id, seq, status ∈ sealed|passed|failed, sheet_sha256, rows_sha256, reason, created_by, created_at)`.
  - `red_register_identity_control_run(p_candidate_run_id uuid) RETURNS uuid`
  - `red_identity_control_sample(p_control_run_id uuid) RETURNS jsonb` (kun id'er og mapping; ingen navne)
  - `red_seal_identity_control_run(p_control_run_id uuid, p_sheet_sha256 text, p_rows_sha256 text) RETURNS void`
  - `red_evaluate_identity_control_run(p_control_run_id uuid) RETURNS text` ∈ `not_ready|passed|failed`
  - `private.control_run_status(p_control_run_id uuid) RETURNS TABLE(status text, reason text)` og `private.append_control_event(uuid,text,text)` — bruges af Task 8's maskin-RPC til genvalidering.
  - Stikprøvekontekst i `red_afgoer_source_persona` og `red_afgoer_relation_interpretation`: nøglerne `control_run_id`, `display_position` (spec §7.1).
- **Planlægnings-ruling (stikprøvestørrelse):** pr. stratum tages `ceil(k·n_s/N)` med `k=min(N,max(10,ceil(0,1·N)))`; summen er ≥ k og højst k+(antal strata−1). Det holder »mindst én pr. ikke-tomt stratum« uden en restfordeling, som ville kræve et ekstra tie-break. Koster: op til ét ekstra kort pr. stratum.

- [ ] **Step 1: Skriv den fejlende test**

`tests/sql/test-identity-control-run.sql`:
```sql
-- Trin 5b, Task 6: kontrolkørslen — serverens udvalg, forsegling, status og stikprøveregler.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

-- Én kilde med tre ægtefælle-personas, hver med én familie og én egnet rang-1-kandidat.
CREATE FUNCTION pg_temp.f5b_control_world(p_source bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; p jsonb; c jsonb; v_sp uuid; v_ids uuid[]:='{}'; v_in jsonb; v_run uuid; v_cands jsonb:='[]'; i int;
BEGIN
  s:=pg_temp.f5b_source(p_source);
  FOR i IN 1..3 LOOP
    INSERT INTO person(id,levende,privat,status) VALUES (p_source*10-i*2,false,false,'5b'),(p_source*10-i*2-1,false,false,'5b');
    p:=pg_temp.f5b_post(p_source,s,'C-'||i,'Hoved '||i||'. g. m. Mage '||i||'.',ARRAY['Hoved '||i||'.','g. m. Mage '||i||'.'],
       p_source*10-i*2,p_actor);
    c:=pg_temp.f5b_claim(p_source,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Mage '||i||'.');
    v_sp:=pg_temp.f5b_spouse(p_source,s,p,c,(p->'clauses'->>1)::uuid,'Mage '||i,1);
    PERFORM pg_temp.f5b_family(p_source*10-i*2,p_source*10-i*2-1,1);
    v_ids:=v_ids||v_sp;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(p_source,'{"mode":"undecided"}');
  FOR i IN 1..3 LOOP
    v_cands:=v_cands||jsonb_build_array(
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-i*2-1,'rank',1,'score',0.95,'tier','auto',
        'basis',jsonb_build_object('signals','["name","family_partner"]'::jsonb,'corroboration_eligible',true)),
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-i*2,'rank',2,'score',0.4,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb),
      -- rang 3 og 4 (andre posters personer): mappingen må kun rumme rang 1-3
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-((i%3)+1)*2,'rank',3,'score',0.3,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb),
      jsonb_build_object('source_persona_id',v_ids[i],'candidate_person_id',p_source*10-((i%3)+1)*2-1,'rank',4,'score',0.2,'tier','none',
        'basis','{"signals":["name"],"corroboration_eligible":false}'::jsonb));
  END LOOP;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',p_source,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),v_cands);
  RESET ROLE;
  RETURN jsonb_build_object('run',v_run,'personas',to_jsonb(v_ids),'src',s);
END $$;

-- Afgør én stikprøvesag som på arket (visningsplads → serveren opløser).
CREATE FUNCTION pg_temp.f5b_decide_sample(p_ctl uuid,p_persona uuid,p_pos text,p_sheet text,p_rows text) RETURNS integer LANGUAGE sql AS $$
  SELECT red_afgoer_source_persona(p_persona,0,'same',NULL,'stikprøve',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',p_sheet,'rows_sha256',p_rows,'line',1,'control_run_id',p_ctl,'display_position',p_pos::int));
$$;

DO $identity_control_run$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b601';
  w jsonb; v_ctl uuid; v_smp jsonb; v_sheet text:=repeat('a',64); v_rows text:=repeat('b',64); v_pos text; v_st text; v_i int;
  v_persona uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5601,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  IF jsonb_array_length(v_smp->'samples')<>3 OR v_smp->'samples'->0->'mapping' IS NULL OR v_smp->'samples'->0 ? 'expected' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: stikprøve %',jsonb_array_length(v_smp->'samples');
  END IF;
  IF red_evaluate_identity_control_run(v_ctl)<>'not_ready' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: før forsegling'; END IF;
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  BEGIN
    PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: dobbelt forsegling';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_RUN_STATE_INVALID%' THEN RAISE; END IF;
  END;
  v_persona:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  -- klientleveret candidate_id og webkø-basis afvises for en stikprøvesag
  BEGIN
    PERFORM red_afgoer_source_persona(v_persona,0,'same',-56011,'web','{}'::jsonb);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: web på stikprøve';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  -- de tre stikprøvesager afgøres som kandidat 1 via visningsplads
  FOR v_i IN 0..2 LOOP
    SELECT key INTO v_pos FROM jsonb_each_text(v_smp->'samples'->v_i->'mapping') m
     WHERE m.value=(SELECT c.id::text FROM private.source_persona_identity_candidate c
                     WHERE c.run_id=(w->>'run')::uuid AND c.rank=1
                       AND c.source_persona_id=(v_smp->'samples'->v_i->>'source_persona_id')::uuid);
    PERFORM pg_temp.f5b_decide_sample(v_ctl,(v_smp->'samples'->v_i->>'source_persona_id')::uuid,v_pos,v_sheet,v_rows);
    IF v_i<2 AND red_evaluate_identity_control_run(v_ctl)<>'not_ready' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: not_ready'; END IF;
  END LOOP;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: passed'; END IF;
  -- seneste status er autoritativ: en senere om-afgørelse af en stikprøvesag gør kørslen failed
  PERFORM red_afgoer_source_persona(v_persona,1,'unresolved',NULL,'fortrudt','{}'::jsonb);
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: stale efter passed'; END IF;
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: failed genopstod'; END IF;
  RESET ROLE;
  IF (SELECT array_agg(status ORDER BY seq) FROM private.identity_control_event WHERE control_run_id=v_ctl)<>ARRAY['sealed','passed','failed'] THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: events';
  END IF;
  RAISE NOTICE 'OK: udvalg, forsegling, visningsplads, not_ready → passed → failed, ingen genopstandelse';
END $identity_control_run$;

DO $identity_control_deviation$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b602';
  w jsonb; v_ctl uuid; v_smp jsonb; v_sheet text:=repeat('c',64); v_rows text:=repeat('d',64); v_p uuid; v_person bigint; v_in jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5602,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  PERFORM red_seal_identity_control_run(v_ctl,v_sheet,v_rows);
  -- Review Focus 4: P <id> med rang-1-personens id tæller som afvigelse
  v_p:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  SELECT candidate_person_id INTO v_person FROM private.source_persona_identity_candidate
   WHERE run_id=(w->>'run')::uuid AND source_persona_id=v_p AND rank=1;
  BEGIN
    PERFORM red_afgoer_source_persona(v_p,0,'same',v_person,'P-token',jsonb_build_object('basis','human_sheet',
      'sheet_sha256',v_sheet,'rows_sha256',v_rows,'line',1,'control_run_id',v_ctl,'display_position',1));
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: P med visningsplads godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID%' THEN RAISE; END IF;
  END;
  PERFORM red_afgoer_source_persona(v_p,0,'same',v_person,'P-token',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',v_sheet,'rows_sha256',v_rows,'line',1,'control_run_id',v_ctl));
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: P-token bestod'; END IF;
  RESET ROLE;
  -- Codex plan-r1 fund 5: kun pladserne 1-3, selv med fire kandidater
  IF EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_object_keys(s.mapping) k
              WHERE s.control_run_id=v_ctl AND s.sample_kind='identity' AND k NOT IN ('1','2','3'))
     OR NOT EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_object_keys(s.mapping) k
              WHERE s.control_run_id=v_ctl AND s.sample_kind='identity' AND k='3') THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: mapping uden for 1-3';
  END IF;
  RAISE NOTICE 'OK: P <id> på en stikprøvesag er en afvigelse; mappingen rummer kun pladserne 1-3';
END $identity_control_deviation$;

DO $identity_control_stale_run$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b603';
  w jsonb; v_ctl uuid; v_in jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5603,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  PERFORM red_seal_identity_control_run(v_ctl,repeat('e',64),repeat('f',64));
  -- Review Focus 5: ny kandidatkørsel efter forsegling
  v_in:=red_identity_candidate_input(-5603,'{"mode":"undecided"}');
  PERFORM red_record_identity_candidates(jsonb_build_object('source_id',-5603,'generator_version','t2','config','{"v":2}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),'[]'::jsonb);
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: forældet kørsel'; END IF;
  RESET ROLE;
  IF (SELECT reason FROM private.identity_control_event WHERE control_run_id=v_ctl ORDER BY seq DESC LIMIT 1)<>'kandidatkoersel_foraeldet' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: grund';
  END IF;
  RAISE NOTICE 'OK: ny kandidatkørsel gør kontrolkørslen failed';
END $identity_control_stale_run$;

-- Codex plan-r1 fund 2: en stikprøvesag kan ikke afgøres, før kørslen er forseglet.
DO $identity_control_unsealed$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b605';
  w jsonb; v_ctl uuid; v_smp jsonb; v_p uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5605,v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  v_smp:=red_identity_control_sample(v_ctl);
  v_p:=(v_smp->'samples'->0->>'source_persona_id')::uuid;
  BEGIN
    PERFORM red_afgoer_source_persona(v_p,0,'unresolved',NULL,'web før forsegling','{}'::jsonb);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: afgjort før forsegling';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_SAMPLE_NOT_SEALED%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: stikprøvesag låst før forsegling';
END $identity_control_unsealed$;

-- Codex plan-r1 fund 1: inputdrift før registrering afvises; ændret input efter forsegling → failed.
DO $identity_control_input_drift$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b604';
  w jsonb; v_ctl uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  w:=pg_temp.f5b_control_world(-5604,v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-56049,false,false,'5b drift');   -- ny person efter kørslen
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_register_identity_control_run((w->>'run')::uuid);
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: inputdrift godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_INPUT_DRIFT%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  DELETE FROM person WHERE id=-56049;
  SET LOCAL ROLE authenticated;
  v_ctl:=red_register_identity_control_run((w->>'run')::uuid);
  PERFORM red_seal_identity_control_run(v_ctl,repeat('1',64),repeat('2',64));
  RESET ROLE;
  INSERT INTO person(id,levende,privat,status) VALUES (-56049,false,false,'5b drift');
  SET LOCAL ROLE authenticated;
  IF red_evaluate_identity_control_run(v_ctl)<>'failed' THEN RAISE EXCEPTION 'CONTROL_TEST_FAILED: ændret input bestod'; END IF;
  RESET ROLE;
  IF (SELECT reason FROM private.identity_control_event WHERE control_run_id=v_ctl ORDER BY seq DESC LIMIT 1)<>'kandidatinput_aendret' THEN
    RAISE EXCEPTION 'CONTROL_TEST_FAILED: grund';
  END IF;
  RAISE NOTICE 'OK: inputdrift før registrering afvist; ændret input efter forsegling gør kørslen failed';
END $identity_control_input_drift$;
ROLLBACK;
```

- [ ] **Step 2: Kør og se den fejle**

Run: `fresh ci5b_t6 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t6 -f tests/sql/test-identity-control-run.sql`
Expected: FAIL — `function red_register_identity_control_run(uuid) does not exist`.

- [ ] **Step 3: Tabeller (schema.sql + 5b-sektionen med `IF NOT EXISTS`)**

```sql
CREATE TABLE private.identity_control_run (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id                   bigint NOT NULL REFERENCES public.source(id),
  candidate_run_id            uuid NOT NULL REFERENCES private.source_persona_identity_candidate_run(id),
  identity_population_sha256  text NOT NULL CHECK (identity_population_sha256 ~ '^[0-9a-f]{64}$'),
  relation_population_sha256  text NOT NULL CHECK (relation_population_sha256 ~ '^[0-9a-f]{64}$'),
  -- Kandidatinputtet (list-mode over alle egnede rang-1-personas) ved registreringen; stabilt under
  -- arkets afgørelser, men ændres af nye/ændrede personer, familier, samme_som og persona-data.
  input_list_sha256           text NOT NULL CHECK (input_list_sha256 ~ '^[0-9a-f]{64}$'),
  created_by                  uuid NOT NULL,
  created_at                  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.identity_control_sample (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  control_run_id         uuid NOT NULL REFERENCES private.identity_control_run(id),
  sample_kind            text NOT NULL CHECK (sample_kind IN ('identity','relation')),
  stratum                text NOT NULL CHECK (stratum IN ('single_family','multi_family','relation')),
  source_persona_id      uuid REFERENCES private.source_persona(id),
  interpretation_key     uuid,
  interpretation_version integer,
  identity_version       integer CHECK (identity_version>=0),   -- identitetens version ved udtrækningen
  mapping                jsonb NOT NULL CHECK (jsonb_typeof(mapping)='object' AND mapping<>'{}'::jsonb),
  expected               text NOT NULL,
  CONSTRAINT identity_control_sample_kind_check CHECK (
    (sample_kind='identity' AND source_persona_id IS NOT NULL AND identity_version IS NOT NULL
       AND interpretation_key IS NULL AND interpretation_version IS NULL)
    OR (sample_kind='relation' AND source_persona_id IS NULL AND identity_version IS NULL
       AND interpretation_key IS NOT NULL AND interpretation_version IS NOT NULL)),
  UNIQUE (control_run_id,source_persona_id),
  UNIQUE (control_run_id,interpretation_key)
);
CREATE TABLE private.identity_control_event (
  control_run_id uuid NOT NULL REFERENCES private.identity_control_run(id),
  seq            integer NOT NULL CHECK (seq>=1),
  status         text NOT NULL CHECK (status IN ('sealed','passed','failed')),
  sheet_sha256   text CHECK (sheet_sha256 IS NULL OR sheet_sha256 ~ '^[0-9a-f]{64}$'),
  rows_sha256    text CHECK (rows_sha256 IS NULL OR rows_sha256 ~ '^[0-9a-f]{64}$'),
  reason         text,
  created_by     uuid NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (control_run_id,seq),
  CONSTRAINT identity_control_event_seal_check CHECK (status<>'sealed' OR (sheet_sha256 IS NOT NULL AND rows_sha256 IS NOT NULL))
);
DO $identity_control_tables$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['identity_control_run','identity_control_sample','identity_control_event'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON private.%I','trg_'||v_table||'_append_only',v_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation()',
                   'trg_'||v_table||'_append_only',v_table);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON private.%I','trg_'||v_table||'_no_truncate',v_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation()',
                   'trg_'||v_table||'_no_truncate',v_table);
    EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',v_table);
  END LOOP;
END $identity_control_tables$;
```
Tilføj de tre tabeller til `db-rls.sql`'s master-array og en `db-verify.sql`-blok `$identity_control_verify$` (eksistens, RLS, ingen SELECT for `anon`/`authenticated`) efter samme mønster som Task 1.

- [ ] **Step 4: Status, events og de fire RPC'er (schema.sql + 5b-sektionen)**

```sql
CREATE OR REPLACE FUNCTION private.append_control_event(p_control_run_id uuid,p_status text,p_reason text,
  p_sheet text DEFAULT NULL,p_rows text DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  INSERT INTO private.identity_control_event(control_run_id,seq,status,sheet_sha256,rows_sha256,reason,created_by)
  SELECT p_control_run_id,coalesce(max(seq),0)+1,p_status,p_sheet,p_rows,p_reason,auth.uid()
    FROM private.identity_control_event WHERE control_run_id=p_control_run_id;
$$;
REVOKE ALL ON FUNCTION private.append_control_event(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;

-- Spec §7.2. Beregner status; skriver intet. Seneste failed er terminal.
-- Kandidatinputtets hash over alle personas med egnet rang-1-kandidat i kørslen (uanset afgørelse).
-- 'list'-mode filtrerer ikke på afgørelser, så arkets afgørelser ændrer den ikke; nye eller ændrede
-- personer, fakta, familier, samme_som og persona-fortolkninger gør (Codex plan-r1 fund 1).
CREATE OR REPLACE FUNCTION private.control_input_list_sha256(p_candidate_run_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_source bigint; v_ids jsonb;
BEGIN
  SELECT source_id INTO v_source FROM private.source_persona_identity_candidate_run WHERE id=p_candidate_run_id;
  SELECT coalesce(jsonb_agg(x.pid ORDER BY x.pid COLLATE "C"),'[]'::jsonb) INTO v_ids
    FROM (SELECT DISTINCT c.source_persona_id::text AS pid FROM private.source_persona_identity_candidate c
           WHERE c.run_id=p_candidate_run_id AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean IS TRUE) x;
  IF v_ids='[]'::jsonb THEN RETURN private.reimport_canonical_json_sha256('[]'::jsonb); END IF;
  RETURN private.reimport_canonical_json_sha256(
    private.identity_candidate_input(v_source,jsonb_build_object('mode','list','persona_ids',v_ids)));
END $$;
REVOKE ALL ON FUNCTION private.control_input_list_sha256(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.control_run_status(p_control_run_id uuid)
RETURNS TABLE(status text,reason text) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE r private.identity_control_run%ROWTYPE; v_last private.identity_control_event%ROWTYPE;
  v_seal private.identity_control_event%ROWTYPE; smp private.identity_control_sample%ROWTYPE;
  v_id private.source_persona_identity%ROWTYPE; v_ic private.interpretation%ROWTYPE; v_cur uuid; v_wait boolean:=false;
  v_ev jsonb; v_at timestamptz;
BEGIN
  SELECT * INTO r FROM private.identity_control_run WHERE id=p_control_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_UNKNOWN'; END IF;
  SELECT * INTO v_last FROM private.identity_control_event e WHERE e.control_run_id=r.id ORDER BY e.seq DESC LIMIT 1;
  IF v_last.status='failed' THEN RETURN QUERY SELECT 'failed'::text,v_last.reason; RETURN; END IF;
  SELECT * INTO v_seal FROM private.identity_control_event e WHERE e.control_run_id=r.id AND e.status='sealed';
  IF NOT FOUND THEN RETURN QUERY SELECT 'not_ready'::text,'ikke_forseglet'::text; RETURN; END IF;
  SELECT cr.id INTO v_cur FROM private.source_persona_identity_candidate_run cr
   WHERE cr.source_id=r.source_id ORDER BY cr.run_seq DESC LIMIT 1;
  IF v_cur IS DISTINCT FROM r.candidate_run_id THEN RETURN QUERY SELECT 'failed'::text,'kandidatkoersel_foraeldet'::text; RETURN; END IF;
  IF private.control_input_list_sha256(r.candidate_run_id) IS DISTINCT FROM r.input_list_sha256 THEN
    RETURN QUERY SELECT 'failed'::text,'kandidatinput_aendret'::text; RETURN;
  END IF;
  FOR smp IN SELECT * FROM private.identity_control_sample s WHERE s.control_run_id=r.id ORDER BY s.id LOOP
    IF smp.sample_kind='identity' THEN
      SELECT * INTO v_id FROM private.source_persona_identity i WHERE i.source_persona_id=smp.source_persona_id;
      IF coalesce(v_id.version,0)=smp.identity_version AND (v_id.source_persona_id IS NULL OR v_id.decision_status='proposed') THEN
        v_wait:=true; CONTINUE;
      END IF;
      v_ev:=v_id.evidence; v_at:=v_id.decided_at;
      -- Afgørelsen skal være netop den samplede version + 1 (ingen »vask« via en mellemliggende afgørelse).
      IF v_id.decision_status<>'accepted' OR v_id.version<>smp.identity_version+1
         OR v_ev->>'candidate_id' IS DISTINCT FROM smp.expected THEN
        RETURN QUERY SELECT 'failed'::text,'afvigelse'::text; RETURN;
      END IF;
    ELSE
      SELECT * INTO v_ic FROM private.interpretation_current ic WHERE ic.interpretation_key=smp.interpretation_key;
      IF v_ic.status='proposed' AND v_ic.version=smp.interpretation_version THEN v_wait:=true; CONTINUE; END IF;
      v_ev:=v_ic.decision_evidence; v_at:=v_ic.decided_at;
      IF v_ic.status<>'accepted' OR v_ic.version<>smp.interpretation_version+1 OR v_ev->>'family_id' IS DISTINCT FROM smp.expected THEN
        RETURN QUERY SELECT 'failed'::text,'afvigelse'::text; RETURN;
      END IF;
    END IF;
    IF v_ev->>'basis' IS DISTINCT FROM 'human_sheet' OR v_ev->>'sheet_sha256' IS DISTINCT FROM v_seal.sheet_sha256
       OR v_ev->>'rows_sha256' IS DISTINCT FROM v_seal.rows_sha256 OR v_ev->>'control_run_id' IS DISTINCT FROM r.id::text
       OR v_at<=v_seal.created_at OR smp.mapping->>(v_ev->>'display_position') IS DISTINCT FROM smp.expected THEN
      RETURN QUERY SELECT 'failed'::text,'afvigelse'::text; RETURN;
    END IF;
  END LOOP;
  IF v_wait THEN RETURN QUERY SELECT 'not_ready'::text,'uafgjort'::text; RETURN; END IF;
  RETURN QUERY SELECT 'passed'::text,'ok'::text;
END $$;
REVOKE ALL ON FUNCTION private.control_run_status(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION red_register_identity_control_run(p_candidate_run_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_source bigint; v_cur uuid; v_id uuid:=gen_random_uuid(); v_ipop text; v_rpop text; v_run private.source_persona_identity_candidate_run%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  SELECT source_id INTO v_source FROM private.source_persona_identity_candidate_run WHERE id=p_candidate_run_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_INVALID'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  SELECT id INTO v_cur FROM private.source_persona_identity_candidate_run WHERE source_id=v_source ORDER BY run_seq DESC LIMIT 1;
  IF v_cur IS DISTINCT FROM p_candidate_run_id THEN RAISE EXCEPTION 'IDENTITY_CANDIDATE_RUN_STALE'; END IF;
  -- Kørslens input skal være uændret ved registreringen (samme kontrol som red_record_identity_candidates):
  -- ellers bygger stikprøven på kandidater, der ikke længere svarer til basen. Registrér straks efter kørslen.
  SELECT * INTO v_run FROM private.source_persona_identity_candidate_run WHERE id=p_candidate_run_id;
  IF private.reimport_canonical_json_sha256(private.identity_candidate_input(v_source,v_run.input_spec))<>v_run.input_sha256 THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_INPUT_DRIFT';
  END IF;

  -- DROP før CTAS: et andet kald i samme transaktion må ikke ramme 'already exists' — og
  -- IF NOT EXISTS ville lydløst genbruge første kalds population.
  DROP TABLE IF EXISTS pg_temp.ctl_ipop, pg_temp.ctl_rpop;
  CREATE TEMP TABLE pg_temp.ctl_ipop ON COMMIT DROP AS
    SELECT c.source_persona_id AS pid, c.id AS cand_id, coalesce(i.version,0) AS ver,
           CASE WHEN jsonb_array_length(private.persona_family_context(c.source_persona_id)->'families')=1
                THEN 'single_family' ELSE 'multi_family' END AS stratum,
           encode(extensions.digest(convert_to(p_candidate_run_id::text||':'||c.source_persona_id::text,'UTF8'),'sha256'),'hex') AS h
      FROM private.source_persona_identity_candidate c
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=c.source_persona_id
     WHERE c.run_id=p_candidate_run_id AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean IS TRUE
       AND (i.source_persona_id IS NULL OR i.decision_status='proposed');
  CREATE TEMP TABLE pg_temp.ctl_rpop ON COMMIT DROP AS
    SELECT ic.interpretation_key AS k, ic.version AS v, min(sc.family_id) AS fam,
           encode(extensions.digest(convert_to(p_candidate_run_id::text||':'||ic.interpretation_key::text,'UTF8'),'sha256'),'hex') AS h
      FROM private.interpretation_current ic
      CROSS JOIN LATERAL private.relation_structural_candidates(ic.interpretation_key) sc
     WHERE ic.source_id=v_source AND ic.predicate IN ('relation.child','relation.parent') AND ic.status='proposed'
     GROUP BY ic.interpretation_key,ic.version HAVING count(*)=1;
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(pid::text ORDER BY pid::text COLLATE "C"),'[]'::jsonb)) INTO v_ipop FROM pg_temp.ctl_ipop;
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(k::text ORDER BY k::text COLLATE "C"),'[]'::jsonb)) INTO v_rpop FROM pg_temp.ctl_rpop;
  INSERT INTO private.identity_control_run(id,source_id,candidate_run_id,identity_population_sha256,relation_population_sha256,
    input_list_sha256,created_by)
    VALUES (v_id,v_source,p_candidate_run_id,v_ipop,v_rpop,private.control_input_list_sha256(p_candidate_run_id),auth.uid());

  -- Identitetsstikprøve: ceil(k·n_s/N) pr. stratum (planlægnings-ruling), blandet mapping pr. sag.
  -- Mappingen rummer kun rang 1–3 (spec §7.1: visningsplads 1–3), uanset generatorens --top-k.
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,source_persona_id,identity_version,mapping,expected)
  SELECT v_id,'identity',x.stratum,x.pid,x.ver,
         (SELECT jsonb_object_agg(m.pos::text,m.cid::text) FROM (
            SELECT c2.id AS cid,row_number() OVER (ORDER BY encode(extensions.digest(convert_to(v_id::text||':'||c2.id::text,'UTF8'),'sha256'),'hex')) AS pos
              FROM private.source_persona_identity_candidate c2
             WHERE c2.run_id=p_candidate_run_id AND c2.source_persona_id=x.pid AND c2.rank<=3) m),
         x.cand_id::text
    FROM (SELECT p.*,row_number() OVER (PARTITION BY p.stratum ORDER BY p.h) AS rn,
                 count(*) OVER (PARTITION BY p.stratum) AS ns,count(*) OVER () AS n
            FROM pg_temp.ctl_ipop p) x
   WHERE x.rn<=ceil(least(x.n,greatest(10,ceil(0.1*x.n)))::numeric*x.ns/x.n);
  -- Relationsstikprøve: ét stratum; én kandidat-familie → plads 1.
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,interpretation_key,interpretation_version,mapping,expected)
  SELECT v_id,'relation','relation',x.k,x.v,jsonb_build_object('1',x.fam::text),x.fam::text
    FROM (SELECT p.*,row_number() OVER (ORDER BY p.h) AS rn,count(*) OVER () AS n FROM pg_temp.ctl_rpop p) x
   WHERE x.rn<=least(x.n,greatest(10,ceil(0.1*x.n)));
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_identity_control_sample(p_control_run_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  -- 'expected' udleveres aldrig: arket skal være blindt (spec §7.3).
  RETURN (SELECT jsonb_build_object('control_run_id',r.id,'candidate_run_id',r.candidate_run_id,
      'samples',coalesce((SELECT jsonb_agg(jsonb_build_object('sample_id',s.id,'sample_kind',s.sample_kind,'stratum',s.stratum,
          'source_persona_id',s.source_persona_id,'interpretation_key',s.interpretation_key,
          'interpretation_version',s.interpretation_version,'identity_version',s.identity_version,'mapping',s.mapping) ORDER BY s.id)
        FROM private.identity_control_sample s WHERE s.control_run_id=r.id),'[]'::jsonb))
    FROM private.identity_control_run r WHERE r.id=p_control_run_id);
END $$;

CREATE OR REPLACE FUNCTION red_seal_identity_control_run(p_control_run_id uuid,p_sheet_sha256 text,p_rows_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF coalesce(p_sheet_sha256,'') !~ '^[0-9a-f]{64}$' OR coalesce(p_rows_sha256,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_INVALID';
  END IF;
  PERFORM 1 FROM private.identity_control_run WHERE id=p_control_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_UNKNOWN'; END IF;
  IF EXISTS (SELECT 1 FROM private.identity_control_event WHERE control_run_id=p_control_run_id) THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_STATE_INVALID: allerede forseglet';
  END IF;
  PERFORM private.append_control_event(p_control_run_id,'sealed',NULL,p_sheet_sha256,p_rows_sha256);
END $$;

CREATE OR REPLACE FUNCTION red_evaluate_identity_control_run(p_control_run_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_source bigint; v_status text; v_reason text; v_last text;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  SELECT source_id INTO v_source FROM private.identity_control_run WHERE id=p_control_run_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_UNKNOWN'; END IF;
  -- Eksklusiv kildelås: ingen menneskelig afgørelse (delt lås) kan interleave (spec §7.2).
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  PERFORM 1 FROM private.identity_control_run WHERE id=p_control_run_id FOR UPDATE;
  SELECT s.status,s.reason INTO v_status,v_reason FROM private.control_run_status(p_control_run_id) s;
  SELECT e.status INTO v_last FROM private.identity_control_event e WHERE e.control_run_id=p_control_run_id ORDER BY e.seq DESC LIMIT 1;
  IF v_status IN ('passed','failed') AND v_last IS DISTINCT FROM v_status THEN
    PERFORM private.append_control_event(p_control_run_id,v_status,v_reason);
  END IF;
  RETURN v_status;
END $$;

REVOKE ALL ON FUNCTION red_register_identity_control_run(uuid),red_identity_control_sample(uuid),
  red_seal_identity_control_run(uuid,text,text),red_evaluate_identity_control_run(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_register_identity_control_run(uuid),red_identity_control_sample(uuid),
  red_seal_identity_control_run(uuid,text,text),red_evaluate_identity_control_run(uuid) TO authenticated;
```
Tilføj de fire `red_*`-signaturer i `v_authenticated`, `$public_red_acl_verify$` og `db-rls.sql`'s allow-liste.

- [ ] **Step 5: Stikprøveregler i `red_afgoer_source_persona` (erstat funktionen på dens plads i schema.sql og 5a-sektionen)**

```sql
CREATE OR REPLACE FUNCTION red_afgoer_source_persona(
  p_source_persona_id uuid, p_expected_version integer, p_action text,
  p_canonical_person_id bigint, p_note text, p_context jsonb DEFAULT '{}'::jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_status text; v_basis text; v_evidence jsonb; v_cand record; v_source bigint; v_current_run uuid;
  v_ctx jsonb:=coalesce(p_context,'{}'::jsonb); v_person bigint:=p_canonical_person_id;
  v_smp private.identity_control_sample%ROWTYPE; v_seal private.identity_control_event%ROWTYPE; v_pos text;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v_basis:=coalesce(v_ctx->>'basis','web_detail');
  IF jsonb_typeof(v_ctx)<>'object'
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_ctx) k
                 WHERE k NOT IN ('basis','candidate_id','run_id','sheet_sha256','rows_sha256','line','control_run_id','display_position'))
     OR (v_ctx ? 'candidate_id') <> (v_ctx ? 'run_id')
     OR p_action NOT IN ('same','different','unresolved','new_person_needed')
     OR nullif(btrim(p_note),'') IS NULL
     OR (p_action<>'same' AND p_canonical_person_id IS NOT NULL)
     OR v_basis NOT IN ('web_detail','human_sheet')
     OR (v_basis='human_sheet' AND (coalesce(v_ctx->>'sheet_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'rows_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'line','') !~ '^[1-9][0-9]*$')) THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID';
  END IF;
  SELECT source_id INTO v_source FROM private.source_persona WHERE id=p_source_persona_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED'; END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention WHERE persona_id=p_source_persona_id) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED';
  END IF;
  v_status:=CASE p_action WHEN 'same' THEN 'accepted' WHEN 'different' THEN 'rejected' ELSE 'unresolved' END;
  v_evidence:=jsonb_build_object('note',btrim(p_note),'action',p_action,'basis',v_basis);
  IF p_action='new_person_needed' THEN v_evidence:=v_evidence||'{"reason":"new_person_needed"}'; END IF;

  -- Trin 5b (spec §7.1): en stikprøvesag i en registreret, endnu ikke forseglet kørsel (hvis kandidatkørsel
  -- stadig er den gældende) kan slet ikke afgøres — ellers kunne den afgøres uden om arket og »vaskes« bagefter.
  IF EXISTS (SELECT 1 FROM private.identity_control_sample s JOIN private.identity_control_run r ON r.id=s.control_run_id
              WHERE s.source_persona_id=p_source_persona_id
                AND NOT EXISTS (SELECT 1 FROM private.identity_control_event e WHERE e.control_run_id=r.id)
                AND r.candidate_run_id=(SELECT cr.id FROM private.source_persona_identity_candidate_run cr
                                         WHERE cr.source_id=r.source_id ORDER BY cr.run_seq DESC LIMIT 1)) THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_NOT_SEALED';
  END IF;
  -- En sag i en forseglet, aktiv kontrolkørsel afgøres kun fra arket.
  SELECT s.* INTO v_smp FROM private.identity_control_sample s
   WHERE s.source_persona_id=p_source_persona_id
     AND (SELECT e.status FROM private.identity_control_event e WHERE e.control_run_id=s.control_run_id ORDER BY e.seq DESC LIMIT 1)='sealed';
  IF FOUND THEN
    SELECT * INTO v_seal FROM private.identity_control_event WHERE control_run_id=v_smp.control_run_id AND status='sealed';
    IF v_basis<>'human_sheet' OR v_ctx->>'control_run_id' IS DISTINCT FROM v_smp.control_run_id::text
       OR v_ctx ? 'candidate_id' OR v_ctx->>'sheet_sha256' IS DISTINCT FROM v_seal.sheet_sha256
       OR v_ctx->>'rows_sha256' IS DISTINCT FROM v_seal.rows_sha256
       OR p_expected_version IS DISTINCT FROM v_smp.identity_version
       OR (p_action='same' AND p_canonical_person_id IS NULL) <> (v_ctx ? 'display_position') THEN
      RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID';
    END IF;
    v_evidence:=v_evidence||jsonb_build_object('control_run_id',v_smp.control_run_id);
    IF v_ctx ? 'display_position' THEN
      v_pos:=v_ctx->>'display_position';
      IF v_pos !~ '^[1-3]$' OR NOT v_smp.mapping ? v_pos THEN RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID'; END IF;
      SELECT c.id,c.run_id,c.rank,c.candidate_person_id INTO v_cand
        FROM private.source_persona_identity_candidate c WHERE c.id=(v_smp.mapping->>v_pos)::uuid;
      v_person:=v_cand.candidate_person_id;
      v_evidence:=v_evidence||jsonb_build_object('candidate_id',v_cand.id,'run_id',v_cand.run_id,
        'candidate_rank',v_cand.rank,'display_position',v_pos::int);
    END IF;
  ELSIF v_ctx ? 'control_run_id' OR v_ctx ? 'display_position' THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID';
  ELSIF v_ctx ? 'candidate_id' THEN
    SELECT c.id,c.run_id,c.rank,c.source_persona_id,c.candidate_person_id INTO v_cand
      FROM private.source_persona_identity_candidate c WHERE c.id=(v_ctx->>'candidate_id')::uuid;
    IF NOT FOUND OR v_cand.run_id<>(v_ctx->>'run_id')::uuid OR v_cand.source_persona_id<>p_source_persona_id
       OR p_action<>'same' OR v_cand.candidate_person_id<>p_canonical_person_id THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_CANDIDATE_MISMATCH';
    END IF;
    SELECT r.id INTO v_current_run FROM private.source_persona_identity_candidate_run r
     WHERE r.source_id=v_source ORDER BY r.run_seq DESC LIMIT 1;
    IF v_current_run IS DISTINCT FROM v_cand.run_id THEN RAISE EXCEPTION 'EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE'; END IF;
    v_evidence:=v_evidence||jsonb_build_object('candidate_id',v_cand.id,'run_id',v_cand.run_id,'candidate_rank',v_cand.rank);
  END IF;
  IF p_action='same' AND v_person IS NULL THEN RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID'; END IF;
  IF v_basis='human_sheet' THEN
    v_evidence:=v_evidence||jsonb_build_object('sheet_sha256',v_ctx->>'sheet_sha256',
      'rows_sha256',v_ctx->>'rows_sha256','line',(v_ctx->>'line')::int);
  END IF;
  RETURN private.decide_source_persona_identity(p_source_persona_id,v_person,p_expected_version,v_status,v_evidence,'human');
END $$;
```

- [ ] **Step 6: Stikprøveregler i `red_afgoer_relation_interpretation` (erstat Task 5's version)**

I Task 5's funktion: tilføj `'control_run_id','display_position'` til de tilladte kontekstnøgler; ret `(p_action='same' AND p_family_id IS NULL)` til at gælde **kun** uden for en stikprøve; og indsæt efter `v_role:=…`:
```sql
  -- Som i red_afgoer_source_persona: en stikprøvesag i en registreret, uforseglet kørsel er låst.
  IF EXISTS (SELECT 1 FROM private.identity_control_sample s JOIN private.identity_control_run r ON r.id=s.control_run_id
              WHERE s.interpretation_key=p_interpretation_key
                AND NOT EXISTS (SELECT 1 FROM private.identity_control_event e WHERE e.control_run_id=r.id)
                AND r.candidate_run_id=(SELECT cr.id FROM private.source_persona_identity_candidate_run cr
                                         WHERE cr.source_id=r.source_id ORDER BY cr.run_seq DESC LIMIT 1)) THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_NOT_SEALED';
  END IF;
  SELECT s.* INTO v_smp FROM private.identity_control_sample s
   WHERE s.interpretation_key=p_interpretation_key
     AND (SELECT e.status FROM private.identity_control_event e WHERE e.control_run_id=s.control_run_id ORDER BY e.seq DESC LIMIT 1)='sealed';
  IF FOUND THEN
    SELECT * INTO v_seal FROM private.identity_control_event WHERE control_run_id=v_smp.control_run_id AND status='sealed';
    IF v_basis<>'human_sheet' OR v_ctx->>'control_run_id' IS DISTINCT FROM v_smp.control_run_id::text
       OR v_ctx->>'sheet_sha256' IS DISTINCT FROM v_seal.sheet_sha256 OR v_ctx->>'rows_sha256' IS DISTINCT FROM v_seal.rows_sha256
       OR p_family_id IS NOT NULL OR (p_action='same') <> (v_ctx ? 'display_position')
       OR p_expected_version IS DISTINCT FROM v_smp.interpretation_version
       OR (v_ctx ? 'display_position' AND (v_ctx->>'display_position' !~ '^[1-3]$'
                                            OR NOT v_smp.mapping ? (v_ctx->>'display_position'))) THEN
      RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID';
    END IF;
    v_family:=CASE WHEN p_action='same' THEN (v_smp.mapping->>(v_ctx->>'display_position'))::bigint END;
    v_evidence:=v_evidence||jsonb_build_object('control_run_id',v_smp.control_run_id)
      ||CASE WHEN v_ctx ? 'display_position' THEN jsonb_build_object('display_position',(v_ctx->>'display_position')::int) ELSE '{}'::jsonb END;
  ELSIF v_ctx ? 'control_run_id' OR v_ctx ? 'display_position' THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_CONTEXT_INVALID';
  ELSE
    v_family:=p_family_id;
    IF (p_action='same' AND v_family IS NULL) THEN RAISE EXCEPTION 'RELATION_DECISION_INVALID'; END IF;
  END IF;
```
med de nye variable `v_smp private.identity_control_sample%ROWTYPE; v_seal private.identity_control_event%ROWTYPE; v_family bigint;`, og brug `v_family` i stedet for `p_family_id` resten af funktionen. Den oprindelige første validering beholder `(p_action<>'same' AND p_family_id IS NOT NULL)`, men **ikke** `(p_action='same' AND p_family_id IS NULL)`.

- [ ] **Step 7: Kør Task 6's, 5a's og Task 5's tests**

Run: `fresh ci5b_t6b && for t in test-identity-control-run test-identity-decision test-identity-detail test-relation-decision; do psql -X -v ON_ERROR_STOP=1 -d ci5b_t6b -f tests/sql/$t.sql || break; done`
Expected: Task 6's seks `OK`-noticer; 5a's afgørelses- og detaljetests og Task 5's test uændret grønne.

- [ ] **Step 8: CI og commit**

CI: fresh-trinnet efter `test-relation-decision.sql`: `psql -v ON_ERROR_STOP=1 -f tests/sql/test-identity-control-run.sql`.
```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-identity-control-run.sql .github/workflows/ci.yml
git commit -m "feat(151): kontrolkørsel med serverens blinde stikprøve, forsegling og status

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 7: Kontrolarket — blinde stikprøvelinjer, uoverensstemmelser og relationslinjer

**Files:**
- Create: `.claude/skills/daa-extract/scripts/identity_control_rows.sql`, `.claude/skills/daa-extract/scripts/identity_control_sheet.py`, `.claude/skills/daa-extract/scripts/test_identity_control_sheet.py`
- Modify: `.github/workflows/ci.yml` (job `python`)

**Interfaces:**
- Consumes: `red_identity_control_sample`, `red_seal_identity_control_run`, `red_evaluate_identity_control_run`, stikprøvekonteksten i begge afgørelses-RPC'er (Task 6); `decision_sheet_core.verify_bound/sql_literal/require_hex64/SheetError` (5a).
- Produces: rækkefil (JSON, 0600) `{control_run_id, candidate_run_id, items:[…]}` med item-typerne nedenfor; arket; SQL der i **én** transaktion forsegler kørslen, afgør linjerne og evaluerer (spec §7.1's tre skridt: registrér → generér → forsegl).
- **Arkdeling (spec §7.3, errata §22):** `split_rows(rows, max_lines=80)` deler i ark. **Hele stikprøven står i ark 1**, som alene forsegler og evaluerer; ark 2.. bærer kun ikke-stikprøvelinjer (uoverensstemmelser og ikke-udtrukne relationslinjer), forsegler intet og anvendes efter ark 1. Serveren binder kun stikprøvesager til forseglingens arkhash (Task 6), så én forsegling er tilstrækkelig. En stikprøve over grænsen afvises (`SHEET_SAMPLE_TOO_LARGE`) — så hæves grænsen med en ledgeret ruling; stikprøven deles aldrig.
- **Planlægnings-ruling (kandidatvisning):** personer har kun faktatypen `titel` (målt: 806 titelfakta, ingen `embede`). Visningen viser titler; embeder er i praksis indeholdt i dem. Koster: intet ekstra felt at vise, hvis embeder senere får egen faktatype.

Item-typer i rækkefilen:
- `{"kind":"identity","sample":true, "source_persona_id","version","record_key","principal_record_key","marriage_ordinal","name","display":[{"position","candidate_id","person_id","person_name","born","died","titles":[…],"own_post_key"}]}` — ingen score/tier/signaler/familiemarkør.
- `{"kind":"identity","sample":false, …, "reason","run_id","candidates":[{"rank","candidate_id","person_id","person_name","born","died","titles","own_post_key","score","tier","signals","family_id","ordinal"}]}`
- `{"kind":"relation","sample":bool, "interpretation_key","version","record_key","predicate","raw_note":"<postnøgle-kontekst>","families":[{"position","family_id","counterpart_name","counterpart_post_key"}]}`

- [ ] **Step 1: Skriv de fejlende tests**

`.claude/skills/daa-extract/scripts/test_identity_control_sheet.py`:
```python
import hashlib
import json
import sys
from pathlib import Path

import pytest

import identity_control_sheet as ics
from decision_sheet_core import SheetError

CTL = "c" * 8 + "-0000-4000-8000-" + "0" * 12
P1, P2 = "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"
K1 = "33333333-3333-4333-8333-333333333333"
C1, C2 = "44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555"
RUN = "66666666-6666-4666-8666-666666666666"


def rows():
    return {"control_run_id": CTL, "candidate_run_id": RUN, "items": [
        {"kind": "identity", "sample": True, "source_persona_id": P1, "version": 0, "record_key": "I-1",
         "principal_record_key": "I-1", "marriage_ordinal": 1, "name": "Mage Et",
         "display": [{"position": 1, "candidate_id": C2, "person_id": 9, "person_name": "Anden", "born": None, "died": None,
                      "titles": [], "own_post_key": None},
                     {"position": 2, "candidate_id": C1, "person_id": 7, "person_name": "Mage Et", "born": "1801", "died": None,
                      "titles": ["kammerherre"], "own_post_key": None}]},
        {"kind": "identity", "sample": False, "source_persona_id": P2, "version": 0, "record_key": "I-2",
         "principal_record_key": "I-2", "marriage_ordinal": 2, "name": "Mage To", "reason": "count_mismatch", "run_id": RUN,
         "candidates": [{"rank": 1, "candidate_id": C1, "person_id": 7, "person_name": "Mage To", "born": None, "died": None,
                         "titles": [], "own_post_key": None, "score": 0.9, "tier": "review", "signals": ["name", "family_partner"],
                         "family_id": 30, "ordinal": 2}]},
        {"kind": "relation", "sample": True, "interpretation_key": K1, "version": 1, "record_key": "I-3",
         "predicate": "relation.child", "families": [{"position": 1, "family_id": 40, "counterpart_name": "Barn", "counterpart_post_key": "I-9"}]},
    ]}


def ark(tokens):
    text = ics.render_sheet(rows())
    for tok in tokens:
        text = text.replace(" : _", f" : {tok}", 1)
    return text


def sql_for(tokens):
    r = rows()
    text = ark(tokens)
    return ics.decision_sql(ics.parse_sheet(text), r, sheet_sha256="a" * 64, rows_sha256="b" * 64)


def test_stikproeve_er_blind_og_i_serverens_orden():
    text = ics.render_sheet(rows())
    blok = text.split("D " + P1)[0].split("# POST I-1")[1]
    assert "score" not in blok and "auto" not in blok and "familie" not in blok
    assert blok.index("1: Anden") < blok.index("2: Mage Et")


def test_uoverensstemmelse_viser_grund_og_signaler():
    text = ics.render_sheet(rows())
    assert "grund: count_mismatch" in text and "score 0.9" in text and "familie 30 nr 2" in text


def test_sql_forsegler_foerst_og_evaluerer_sidst():
    sql = sql_for(["2", "1", "1"])
    lines = [l for l in sql.splitlines() if "red_" in l]
    assert "red_seal_identity_control_run" in lines[0]
    assert "red_evaluate_identity_control_run" in lines[-1]


def test_stikproeve_same_sender_null_og_visningsplads():
    sql = sql_for(["2", "1", "1"])
    s1 = next(l for l in sql.splitlines() if P1 in l)
    assert "'same', NULL" in s1 and '"display_position": 2' in s1 and f'"control_run_id": "{CTL}"' in s1
    assert "candidate_id" not in s1


def test_p_paa_stikproeve_har_ingen_visningsplads():
    sql = sql_for(["P 7", "1", "1"])
    s1 = next(l for l in sql.splitlines() if P1 in l)
    assert "'same', 7" in s1 and "display_position" not in s1 and f'"control_run_id": "{CTL}"' in s1


def test_uoverensstemmelse_bruger_kandidat_id_uden_kontrol():
    sql = sql_for(["2", "1", "1"])
    s2 = next(l for l in sql.splitlines() if P2 in l)
    assert C1 in s2 and RUN in s2 and "control_run_id" not in s2


def test_relationslinje_sample():
    sql = sql_for(["2", "1", "1"])
    r = next(l for l in sql.splitlines() if K1 in l)
    assert "red_afgoer_relation_interpretation" in r and "'same', NULL" in r and '"display_position": 1' in r


def test_relationslinje_afviser_x():
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        ics.parse_sheet(ark(["2", "1", "X"]))


def test_cli_laeser_arket_én_gang(tmp_path, monkeypatch):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows()), encoding="utf-8")
    af = tmp_path / "ark.txt"; godkendt = ark(["2", "1", "1"]); af.write_text(godkendt, encoding="utf-8")
    sha = hashlib.sha256(af.read_bytes()).hexdigest()
    ægte = Path.read_bytes
    læst = {"n": 0}

    def bytes_(self):
        if self == af:
            læst["n"] += 1
            if læst["n"] > 1:
                return ark(["1", "1", "U"]).encode("utf-8")
        return ægte(self)

    monkeypatch.setattr(Path, "read_bytes", bytes_)
    monkeypatch.setattr(sys, "argv", ["x", "sql", "--sheet", str(af), "--approved-sha256", sha, "--rows", str(rf),
                                      "--expect-rows-sha256", hashlib.sha256(rf.read_bytes()).hexdigest(),
                                      "--out", str(tmp_path / "d.sql")])
    assert ics.main() == 0 and læst["n"] == 1
    assert '"display_position": 2' in (tmp_path / "d.sql").read_text(encoding="utf-8")


def many(n_sample, n_rest):
    base = rows()
    s, d = base["items"][0], base["items"][1]
    items = [{**s, "source_persona_id": f"{i:08x}-1111-4111-8111-111111111111", "record_key": f"S-{i:03d}"}
             for i in range(n_sample)]
    items += [{**d, "source_persona_id": f"{i:08x}-2222-4222-8222-222222222222", "record_key": f"A-{i:03d}"}
              for i in range(n_rest)]
    return {**base, "items": items}


def test_hele_stikproeven_i_ark_1_og_kun_ark_1_forsegler():
    parts = ics.split_rows(many(12, 100))
    assert [p["part"] for p in parts] == [1, 2] and [p["seal"] for p in parts] == [True, False]
    assert sum(it["sample"] for it in parts[0]["items"]) == 12 and len(parts[0]["items"]) == 80
    assert not any(it["sample"] for it in parts[1]["items"]) and len(parts[1]["items"]) == 32


def test_overloebsark_forsegler_og_evaluerer_ikke():
    part = ics.split_rows(many(12, 100))[1]
    text = ics.render_sheet(part).replace(" : _", " : U")
    sql = ics.decision_sql(ics.parse_sheet(text), part, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert "# Ark 2 af 2" in text
    assert "red_seal_identity_control_run" not in sql and "red_evaluate_identity_control_run" not in sql


def test_stikproeve_over_graensen_afvises():
    with pytest.raises(SheetError, match="SHEET_SAMPLE_TOO_LARGE"):
        ics.split_rows(many(81, 0))


def test_overloebsark_med_stikproeve_afvises():
    part = dict(ics.split_rows(many(12, 100))[1])
    part["items"] = part["items"] + many(1, 0)["items"]
    with pytest.raises(SheetError, match="SHEET_PART_INVALID"):
        ics.decision_sql([], part, sheet_sha256="a" * 64, rows_sha256="b" * 64)
```

- [ ] **Step 2: Kør og se dem fejle**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_identity_control_sheet.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'identity_control_sheet'`.

- [ ] **Step 3: Implementér arket**

`.claude/skills/daa-extract/scripts/identity_control_sheet.py`:
```python
#!/usr/bin/env python3
"""Kontrolark (trin 5b): blind stikprøve + uoverensstemmelser + relationslinjer i ét hash-bundet ark.

SQL'en forsegler kontrolkørslen med arkets og rækkefilens hash, afgør hver linje og evaluerer —
alt i én transaktion (spec §7.1). Stikprøvelinjer sendes som visningsplads; serveren opløser målet."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
D_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|P [1-9][0-9]*|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
R_RE = re.compile(rf"^R (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|U)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^[DR] {UUID} [0-9]+ : ")


@dataclass(frozen=True)
class Line:
    kind: str          # 'D' eller 'R'
    item_id: str
    version: int
    tok: str
    note: str
    line: int


def _key(it: dict) -> tuple:
    return (it["record_key"], it["kind"], it.get("source_persona_id") or it.get("interpretation_key"))


def ordered(rows: dict) -> list[dict]:
    return sorted(rows["items"], key=_key)


MAX_LINES = 80


def split_rows(rows: dict, max_lines: int = MAX_LINES) -> list[dict]:
    """Del rækkefilen i ark (spec §7.3, errata §22). Hele stikprøven står i ark 1 — det eneste ark,
    der forsegler og evaluerer; ark 2.. bærer kun ikke-stikprøvelinjer."""
    items = ordered(rows)
    samples = [it for it in items if it["sample"]]
    rest = [it for it in items if not it["sample"]]
    if len(samples) > max_lines:
        raise SheetError(f"SHEET_SAMPLE_TOO_LARGE stikproeve={len(samples)} max={max_lines}")
    plads = max_lines - len(samples)
    parts = [samples + rest[:plads]] + [rest[i:i + max_lines] for i in range(plads, len(rest), max_lines)]
    return [{**rows, "items": sorted(p, key=_key), "part": n, "parts": len(parts), "seal": n == 1}
            for n, p in enumerate(parts, 1)]


def _cand_blind(d: dict) -> str:
    t = f"  · {', '.join(d['titles'])}" if d["titles"] else ""
    post = f"  · egen post {d['own_post_key']}" if d["own_post_key"] else ""
    return f"#   {d['position']}: {d['person_name']}  {d['born'] or '?'}–{d['died'] or '?'}{t}{post}"


def _cand_full(c: dict) -> str:
    t = f"  · {', '.join(c['titles'])}" if c["titles"] else ""
    fam = f"  familie {c['family_id']} nr {c['ordinal']}" if c.get("family_id") is not None else ""
    return (f"#   {c['rank']}: person {c['person_id']}  {c['person_name']}  {c['born'] or '?'}–{c['died'] or '?'}{t}"
            f"  score {c['score']}  {c['tier']}  [{', '.join(c['signals'])}]{fam}")


def render_sheet(rows: dict) -> str:
    out = ["# KONTROLARK (trin 5b) — ægtefæller og børn/forældre",
           "# D-linjer: 1/2/3 = samme som kandidat nr., 'P <id>' = anden person, X = ikke i basen,",
           "#           N = ny person nødvendig, U = uafklaret. R-linjer: 1/2/3 = familie nr., U = uafklaret.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    if rows.get("parts", 1) > 1:   # et enkelt ark renderes uændret
        out.insert(1, f"# Ark {rows['part']} af {rows['parts']} — " + (
            "hele stikprøven; forsegler kontrolkørslen" if rows["seal"] else "kun uoverensstemmelser; anvendes efter ark 1"))
    for it in ordered(rows):
        if it["kind"] == "identity":
            out.append(f"# POST {it['record_key']} · ægtefælle nr. {it['marriage_ordinal']}: {it['name'] or '(intet navn)'}")
            if it["sample"]:
                out += [_cand_blind(d) for d in sorted(it["display"], key=lambda d: d["position"])]
            else:
                out.append(f"#   grund: {it['reason']}")
                out += [_cand_full(c) for c in it["candidates"]] or ["#   ingen kandidat"]
            out.append(f"D {it['source_persona_id']} {it['version']} : _")
        else:
            out.append(f"# POST {it['record_key']} · {it['predicate']}")
            out += [f"#   {f['position']}: familie med {f['counterpart_name']} (post {f['counterpart_post_key']})"
                    for f in it["families"]] or ["#   ingen familie"]
            out.append(f"R {it['interpretation_key']} {it['version']} : _")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    res, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not (line.startswith("D ") or line.startswith("R ")):
            if line.lstrip().startswith(("D ", "R ")):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")
            continue
        m = (D_RE if line.startswith("D ") else R_RE).match(line)
        if not m:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}" if LOOSE_RE.match(line) else f"SHEET_LINE_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        if m["tok"] == "_":
            undecided.append(n); continue
        res.append(Line(line[0], m["id"], int(m["ver"]), m["tok"], (m["note"] or "").strip(), n))
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return res


def check_render(text: str, rows: dict) -> None:
    forventet, faktisk = render_sheet(rows).splitlines(), text.splitlines()
    if len(faktisk) != len(forventet):
        raise SheetError(f"SHEET_RENDER_MISMATCH lines={len(faktisk)} forventet={len(forventet)}")
    for n, (f, a) in enumerate(zip(forventet, faktisk), 1):
        if f.startswith(("D ", "R ")):
            if not a.startswith(f[:f.rindex(" : ") + 3]):
                raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")
        elif a != f:
            raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")


def check_identity(lines: list[Line], rows: dict) -> None:
    forventet = [((it.get("source_persona_id") or it["interpretation_key"]), it["version"]) for it in ordered(rows)]
    if [(l.item_id, l.version) for l in lines] != forventet:
        raise SheetError("SHEET_IDENTITY_MISMATCH")


def _call(fn: str, args: str, ctx: dict) -> str:
    return (f"INSERT INTO decided SELECT {fn}({args}, "
            f"{sql_literal(json.dumps(ctx, ensure_ascii=False, sort_keys=True))}::jsonb);")


def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    ctl = rows["control_run_id"]
    seal = rows.get("seal", True)
    if not seal and any(it["sample"] for it in rows["items"]):
        raise SheetError("SHEET_PART_INVALID stikprøvelinje uden for ark 1")
    by_id = {(it.get("source_persona_id") or it["interpretation_key"]): it for it in rows["items"]}
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    if seal:
        out.append(f"SELECT red_seal_identity_control_run('{ctl}'::uuid, '{sheet_sha256}', '{rows_sha256}');")
    for l in lines:
        it = by_id[l.item_id]
        base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line}
        note = sql_literal(f"ark {sheet_sha256[:12]} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        if it["sample"]:
            base["control_run_id"] = ctl
        if l.kind == "D":
            pid = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok in "123" and it["sample"]:
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', NULL, {note}", {**base, "display_position": int(l.tok)}))
            elif l.tok in "123":
                c = next((c for c in it["candidates"] if c["rank"] == int(l.tok)), None)
                if c is None:
                    raise SheetError(f"SHEET_CANDIDATE_MISSING line={l.line}")
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', {int(c['person_id'])}, {note}",
                                 {**base, "candidate_id": c["candidate_id"], "run_id": it["run_id"]}))
            elif l.tok.startswith("P "):
                out.append(_call("red_afgoer_source_persona", f"{pid}, 'same', {int(l.tok[2:])}, {note}", base))
            else:
                act = {"X": "different", "N": "new_person_needed", "U": "unresolved"}[l.tok]
                out.append(_call("red_afgoer_source_persona", f"{pid}, '{act}', NULL, {note}", base))
        else:
            key = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok == "U":
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'unresolved', NULL, {note}", base))
            elif it["sample"]:
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'same', NULL, {note}",
                                 {**base, "display_position": int(l.tok)}))
            else:
                f = next((f for f in it["families"] if f["position"] == int(l.tok)), None)
                if f is None:
                    raise SheetError(f"SHEET_CANDIDATE_MISSING line={l.line}")
                out.append(_call("red_afgoer_relation_interpretation", f"{key}, 'same', {int(f['family_id'])}, {note}", base))
    out.append(f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {len(lines)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    if seal:
        out.append(f"SELECT red_evaluate_identity_control_run('{ctl}'::uuid) AS kontrolstatus;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("--rows", required=True); r.add_argument("--out", required=True)
    s = sub.add_parser("sql")
    for a in ("--sheet", "--approved-sha256", "--rows", "--expect-rows-sha256", "--out"):
        s.add_argument(a, required=True)
    s.add_argument("--part", type=int, default=1)
    args = ap.parse_args()
    rows_bytes = Path(args.rows).read_bytes()
    alle = json.loads(rows_bytes.decode("utf-8"))
    if args.cmd == "render":
        try:
            parts = split_rows(alle)
        except SheetError as exc:
            print(str(exc)); return 1
        out = Path(args.out)
        for part in parts:
            f = out if part["part"] == 1 else out.with_name(f"{out.stem}-{part['part']}{out.suffix}")
            f.write_text(render_sheet(part), encoding="utf-8"); f.chmod(0o600)
        n_s = sum(1 for it in alle["items"] if it["sample"])
        print(f"ARK_OK ark={len(parts)} linjer={len(alle['items'])} stikproeve={n_s} uoverensstemmelser={len(alle['items']) - n_s}")
        print(f"  rows_sha256 {hashlib.sha256(rows_bytes).hexdigest()}")
        return 0
    sheet_bytes = Path(args.sheet).read_bytes()          # læses præcis én gang
    try:
        parts = split_rows(alle)
        if not 1 <= args.part <= len(parts):
            raise SheetError(f"SHEET_PART_INVALID part={args.part} af {len(parts)}")
        rows = parts[args.part - 1]
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        tekst = sheet_bytes.decode("utf-8")
        check_render(tekst, rows)
        lines = parse_sheet(tekst)
        check_identity(lines, rows)
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc)); return 1
    out = Path(args.out); out.write_text(sql, encoding="utf-8"); out.chmod(0o600)
    print(f"SQL_OK linjer={len(lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Kør og se dem bestå**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_identity_control_sheet.py test_identity_decision_sheet.py -q`
Expected: alle grønne (5a's ark uændret).

- [ ] **Step 5: Rækkefilens SQL**

`.claude/skills/daa-extract/scripts/identity_control_rows.sql` (ejer, læse-kun; variabler `actor`, `control_run_id`; output med navne → 0600):
```sql
-- Trin 5b: rækkefil til kontrolarket. Indeholder navne → 0600 under ~/.private/5b/.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_identity_control_sample(:'control_run_id'::uuid) AS smp \gset
RESET ROLE;
WITH ctl AS (SELECT * FROM private.identity_control_run WHERE id=:'control_run_id'::uuid),
smp AS (SELECT * FROM jsonb_to_recordset((:'smp'::jsonb)->'samples')
          AS x(sample_id uuid,sample_kind text,stratum text,source_persona_id uuid,interpretation_key uuid,
               interpretation_version int,identity_version int,mapping jsonb)),
person_view AS (
  SELECT p.id,p.visning_navn,p.visning_foedt,p.visning_doed,
    coalesce((SELECT jsonb_agg(DISTINCT a.vaerdi_tekst) FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
               JOIN assertion a ON a.id=k.valgt_assertion_id WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='titel'),'[]'::jsonb) AS titles,
    (SELECT sr.record_key FROM private.source_persona_identity i
       JOIN private.source_persona_mention spm ON spm.persona_id=i.source_persona_id AND spm.mention_role='primary'
       JOIN private.source_mention sm ON sm.id=spm.mention_id
       JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
       JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
       JOIN private.source_record sr ON sr.id=ac.source_record_id
      WHERE i.canonical_person_id=p.id AND i.decision_status='accepted' ORDER BY sr.record_key LIMIT 1) AS own_post_key
    FROM person p),
spouse AS (
  SELECT sp.id AS pid,coalesce(i.version,0) AS version,pc.interpretation_key,pc.marriage_ordinal,
         (SELECT sm.verbatim_text FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
           WHERE spm.persona_id=sp.id AND spm.mention_role='spouse') AS name,
         (SELECT sr.record_key FROM private.interpretation_current ic
            JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
            JOIN private.source_observation o ON o.id=io.observation_id
            JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
            JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE ic.interpretation_key=pc.interpretation_key) AS record_key
    FROM private.interpretation_party_current pc
    JOIN private.source_persona sp ON sp.id=pc.source_persona_id
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
   WHERE pc.party_role='spouse' AND sp.source_id=(SELECT source_id FROM ctl)
     AND (i.source_persona_id IS NULL OR i.decision_status='proposed')),
id_items AS (
  SELECT s.*,
    (SELECT x.mapping FROM smp x WHERE x.source_persona_id=s.pid) AS mapping,
    (SELECT x.identity_version FROM smp x WHERE x.source_persona_id=s.pid) AS sample_version,
    (SELECT c.basis FROM private.source_persona_identity_candidate c WHERE c.run_id=(SELECT candidate_run_id FROM ctl)
      AND c.source_persona_id=s.pid AND c.rank=1) AS top_basis
    FROM spouse s),
rel AS (
  SELECT ic.interpretation_key,ic.version,ic.predicate,
         (SELECT x.mapping FROM smp x WHERE x.interpretation_key=ic.interpretation_key) AS mapping,
         (SELECT sr.record_key FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
            JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
            JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE io.interpretation_id=ic.id AND io.ordinal=1) AS record_key
    FROM private.interpretation_current ic
   WHERE ic.source_id=(SELECT source_id FROM ctl) AND ic.predicate IN ('relation.child','relation.parent') AND ic.status='proposed'
     AND EXISTS (SELECT 1 FROM private.interpretation_party_current pc WHERE pc.interpretation_key=ic.interpretation_key AND pc.party_role='principal'))
SELECT jsonb_build_object('control_run_id',(SELECT id FROM ctl),'candidate_run_id',(SELECT candidate_run_id FROM ctl),'items',
  coalesce((SELECT jsonb_agg(item) FROM (
    -- identitet: stikprøve (blind) og uoverensstemmelser (ikke-egnede); egnede uden for stikprøven er maskinens
    SELECT CASE WHEN it.mapping IS NOT NULL THEN jsonb_build_object('kind','identity','sample',true,'source_persona_id',it.pid,
             'version',it.sample_version,'record_key',it.record_key,'principal_record_key',it.record_key,'marriage_ordinal',it.marriage_ordinal,
             'name',it.name,'display',(SELECT jsonb_agg(jsonb_build_object('position',m.key::int,'candidate_id',c.id,'person_id',pv.id,
                'person_name',pv.visning_navn,'born',pv.visning_foedt,'died',pv.visning_doed,'titles',pv.titles,'own_post_key',pv.own_post_key)
                ORDER BY m.key::int) FROM jsonb_each_text(it.mapping) m
                JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid JOIN person_view pv ON pv.id=c.candidate_person_id))
           ELSE jsonb_build_object('kind','identity','sample',false,'source_persona_id',it.pid,'version',it.version,
             'record_key',it.record_key,'principal_record_key',it.record_key,'marriage_ordinal',it.marriage_ordinal,'name',it.name,
             'reason',coalesce(it.top_basis->>'eligibility_reason','ingen_kandidat'),'run_id',(SELECT candidate_run_id FROM ctl),
             'candidates',coalesce((SELECT jsonb_agg(jsonb_build_object('rank',c.rank,'candidate_id',c.id,'person_id',pv.id,
                'person_name',pv.visning_navn,'born',pv.visning_foedt,'died',pv.visning_doed,'titles',pv.titles,'own_post_key',pv.own_post_key,
                'score',c.score,'tier',c.tier,'signals',c.basis->'signals',
                'family_id',(SELECT fm.family_id FROM family_member fm JOIN family_member fp ON fp.family_id=fm.family_id
                              AND fp.person_id=(private.persona_family_context(it.pid)->>'principal_person_id')::bigint
                              WHERE fm.person_id=c.candidate_person_id AND fm.rolle='partner' LIMIT 1),
                'ordinal',(SELECT fp.ordinal FROM family_member fm JOIN family_member fp ON fp.family_id=fm.family_id
                              AND fp.person_id=(private.persona_family_context(it.pid)->>'principal_person_id')::bigint
                              WHERE fm.person_id=c.candidate_person_id AND fm.rolle='partner' LIMIT 1)) ORDER BY c.rank)
                FROM private.source_persona_identity_candidate c JOIN person_view pv ON pv.id=c.candidate_person_id
                WHERE c.run_id=(SELECT candidate_run_id FROM ctl) AND c.source_persona_id=it.pid),'[]'::jsonb)) END AS item
      FROM id_items it
     WHERE it.mapping IS NOT NULL OR coalesce((it.top_basis->>'corroboration_eligible')::boolean,false) IS FALSE
    UNION ALL
    -- relation: stikprøve (serverens mapping) og uoverensstemmelser (≠ 1 kandidat)
    SELECT jsonb_build_object('kind','relation','sample',r.mapping IS NOT NULL,'interpretation_key',r.interpretation_key,
             'version',r.version,'record_key',r.record_key,'predicate',r.predicate,
             'families',coalesce((SELECT jsonb_agg(jsonb_build_object('position',q.pos,'family_id',q.family_id,
                 'counterpart_name',pv.visning_navn,'counterpart_post_key',pv.own_post_key) ORDER BY q.pos)
               FROM (SELECT sc.*,row_number() OVER (ORDER BY sc.family_id,sc.counterpart_person_id) AS pos
                       FROM private.relation_structural_candidates(r.interpretation_key) sc) q
               JOIN person_view pv ON pv.id=q.counterpart_person_id WHERE q.pos<=3),'[]'::jsonb))
      FROM rel r
     WHERE r.mapping IS NOT NULL
        OR (SELECT count(*) FROM private.relation_structural_candidates(r.interpretation_key))<>1
  ) items),'[]'::jsonb));
COMMIT;
```

- [ ] **Step 6: CI og commit**

`.github/workflows/ci.yml`, job `python`: tilføj `test_identity_control_sheet.py`.
```bash
git add .claude/skills/daa-extract/scripts/identity_control_sheet.py .claude/skills/daa-extract/scripts/test_identity_control_sheet.py \
  .claude/skills/daa-extract/scripts/identity_control_rows.sql .github/workflows/ci.yml
git commit -m "feat(151): kontrolark med blinde stikprøvelinjer, uoverensstemmelser og relationslinjer

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 8: Kerne-oprindelsen `family_corroboration` og `red_corroborate_family_identities`

**Files:**
- Create: `tests/sql/test-family-corroboration.sql`
- Modify: `tests/sql/fixtures/relation-5b.sql` (writer-verden), `schema.sql` + 5a-sektionen (kernen erstattes på sin plads) + 5b-sektionen (ny check-funktion og RPC), `.claude/skills/daa-extract/scripts/test_identity_guard_static.py`, `db-migrations.sql` `v_authenticated`, `db-verify.sql`, `db-rls.sql`, `.github/workflows/ci.yml` (job `writer-1939-v50-db`)

**Interfaces:**
- Consumes: `relation_persona`-events (Task 2), `persona_family_context` og `family_context_sha256` (Task 4), `lock_family_rows` (Task 5), `control_run_status`/`append_control_event` (Task 6).
- Produces:
  - Kernen `private.decide_source_persona_identity(…, p_origin)` accepterer `family_corroboration`; **alle** oprindelser låser nu gammelt og nyt mål (og for `family_corroboration` også hovedpersonen) via `lock_family_rows` før skrivning.
  - `private.check_family_corroboration(p_persona uuid, p_person bigint, p_expected integer, p_status text, p_evidence jsonb) RETURNS void` — spec §6.2 (a)-(d); kaldes kun af kernen efter låsene.
  - `red_corroborate_family_identities(p_control_run_id uuid, p_expect_set_sha256 text) RETURNS integer` (antal accepterede; 0 når kørslen er/blev `failed`).
  - Fejlkoder `FAMILY_CORROBORATION_{PROVENANCE_INVALID,PRINCIPAL_NOT_ACCEPTED,COUNT_MISMATCH,ORDINAL_NULL,FAMILY_INVALID,TARGET_INVALID,KONFIDENS,DOUBLE_TARGET,CANDIDATE_INVALID,CONTROL_NOT_PASSED}`, `IDENTITY_CONTROL_NOT_PASSED`, `IDENTITY_CORROBORATION_SET_DRIFT`.

- [ ] **Step 1: Udvid fixtures med en writer-verden**

Tilføj til `tests/sql/fixtures/relation-5b.sql` (kræver contract v2; bruges i writer-jobbet):
```sql
-- Payload til relation_persona for en ægteskabspåstand, hvis klausul er præcis raw.
CREATE OR REPLACE FUNCTION pg_temp.f5b_payload(p jsonb,c jsonb,p_clause uuid,p_raw text,p_name text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_co private.source_observation%ROWTYPE; v_from int;
BEGIN
  SELECT * INTO v_co FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_co.verbatim_text,p_raw)-1;
  RETURN jsonb_build_object('birth_raw',NULL,'clause_observation_id',p_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256(v_co.parent_observation_id,1),'death_raw',NULL,
    'interpretation_key',c->>'key','interpretation_version',1,
    'marriage_ordinal',(SELECT o.marriage_ordinal FROM private.relation_marriage_ordinals(v_co.occurrence_id) o
                         WHERE o.interpretation_key=(c->>'key')::uuid),
    'name_from',v_from+strpos(p_raw,p_name)-1,'name_to',v_from+strpos(p_raw,p_name)-1+char_length(p_name),
    'post_offset',v_co.post_char_from+v_from,'predicate','relation.marriage','profile','relation-persona-2018-20-v1',
    'span_from',v_from,'span_to',v_from+char_length(p_raw));
END $$;

-- Skriver de givne payloads gennem den rigtige writer og finaliserer. Kaldes som ejer: autorisation
-- og begin som ejer (f5b_batch), apply og finalize som authenticated redaktion.
CREATE OR REPLACE FUNCTION pg_temp.f5b_write(p_source bigint,p_actor uuid,p_elements jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE prof jsonb; b jsonb; e record;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_elements);
  SET LOCAL ROLE authenticated;
  FOR e IN SELECT * FROM jsonb_each(p_elements) LOOP
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,e.key,e.value);
  END LOOP;
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  RESET ROLE;
END $$;
```

- [ ] **Step 2: Skriv den fejlende test**

`tests/sql/test-family-corroboration.sql`:
```sql
-- Trin 5b, Task 8: family_corroboration — kernens egne efterprøvelser og bekræftelses-RPC'en.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $family_corroboration$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b801';
  s jsonb; p jsonb; c jsonb; c2 jsonb; v_el jsonb:='{}'; i int; v_in jsonb; v_run uuid; v_cands jsonb:='[]'; v_ctl uuid;
  v_smp jsonb; v_pos text; v_set text; v_n int; v_sp uuid; v_fam bigint; v_defect jsonb:='{}'; v_name text; v_err text;
  v_cand uuid; v_ev jsonb; v_good uuid[]:='{}';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-5801);
  -- 11 gode poster: én ægteskabspåstand, én familie (ordinal 1) med præcis én partner.
  FOR i IN 1..11 LOOP
    INSERT INTO person(id,levende,privat,status) VALUES (-58000-i*2,false,false,'5b'),(-58000-i*2-1,false,false,'5b');
    v_name:='Mage '||i;
    p:=pg_temp.f5b_post(-5801,s,'G-'||lpad(i::text,2,'0'),'Hoved '||i||'. g. m. '||v_name||'.',
       ARRAY['Hoved '||i||'.','g. m. '||v_name||'.'],-58000-i*2,v_actor);
    c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. '||v_name||'.');
    PERFORM pg_temp.f5b_family(-58000-i*2,-58000-i*2-1,1);
    v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),
      pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. '||v_name||'.',v_name));
  END LOOP;
  -- Defekter (Review Focus 1-3 + struktur): hver sin post.
  INSERT INTO person(id,levende,privat,status) VALUES
    (-58101,false,false,'5b'),(-58102,false,false,'5b'),   -- D1 hovedperson skifter identitet
    (-58111,false,false,'5b'),(-58112,false,false,'5b'),   -- D2 count_mismatch m. parkeret påstand
    (-58121,false,false,'5b'),(-58122,false,false,'5b'),   -- D3 to ægteskaber, samme partner
    (-58131,false,false,'5b'),(-58132,false,false,'5b'),   -- D4 omstridt
    (-58141,false,false,'5b'),(-58142,false,false,'5b'),(-58143,false,false,'5b'), -- D5 NULL-ordinal, to familier
    (-58151,false,false,'5b'),(-58152,false,false,'5b');   -- D6 familiekontekst ændret efter kørslen
  p:=pg_temp.f5b_post(-5801,s,'D-1','Hoved D1. g. m. Dea.',ARRAY['Hoved D1.','g. m. Dea.'],-58101,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Dea.');
  PERFORM pg_temp.f5b_family(-58101,-58102,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Dea.','Dea'));
  v_defect:=v_defect||jsonb_build_object('D1',jsonb_build_object('claim',c->>'key','post',p,'partner',-58102));
  p:=pg_temp.f5b_post(-5801,s,'D-2','Hoved D2. g. m. Deb. Gift igen m. ??',ARRAY['Hoved D2.','g. m. Deb.','Gift igen m. ??'],-58111,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Deb.');
  PERFORM pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift igen m. ??');   -- parkeres (intet navn)
  PERFORM pg_temp.f5b_family(-58111,-58112,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Deb.','Deb'));
  v_defect:=v_defect||jsonb_build_object('D2',jsonb_build_object('claim',c->>'key','partner',-58112));
  p:=pg_temp.f5b_post(-5801,s,'D-3','Hoved D3. g. 1° m. Dec. g. 2° m. Dec.',ARRAY['Hoved D3.','g. 1° m. Dec.','g. 2° m. Dec.'],-58121,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. 1° m. Dec.');
  c2:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. 2° m. Dec.');
  PERFORM pg_temp.f5b_family(-58121,-58122,1); PERFORM pg_temp.f5b_family(-58121,-58122,2);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. 1° m. Dec.','Dec'),
                                 'relation-persona:'||(c2->>'key'),pg_temp.f5b_payload(p,c2,(p->'clauses'->>2)::uuid,'g. 2° m. Dec.','Dec'));
  v_defect:=v_defect||jsonb_build_object('D3a',jsonb_build_object('claim',c->>'key','partner',-58122),
                                         'D3b',jsonb_build_object('claim',c2->>'key','partner',-58122));
  p:=pg_temp.f5b_post(-5801,s,'D-4','Hoved D4. g. m. Ded.',ARRAY['Hoved D4.','g. m. Ded.'],-58131,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Ded.');
  v_fam:=pg_temp.f5b_family(-58131,-58132,1); UPDATE family_member SET konfidens='omstridt' WHERE family_id=v_fam AND person_id=-58132;
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Ded.','Ded'));
  v_defect:=v_defect||jsonb_build_object('D4',jsonb_build_object('claim',c->>'key','partner',-58132));
  p:=pg_temp.f5b_post(-5801,s,'D-5','Hoved D5. g. m. Dee. g. m. Def.',ARRAY['Hoved D5.','g. m. Dee.','g. m. Def.'],-58141,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Dee.');
  PERFORM pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>2)::uuid,'g. m. Def.');
  PERFORM pg_temp.f5b_family(-58141,-58142,NULL); PERFORM pg_temp.f5b_family(-58141,-58143,2);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Dee.','Dee'));
  v_defect:=v_defect||jsonb_build_object('D5',jsonb_build_object('claim',c->>'key','partner',-58142));
  p:=pg_temp.f5b_post(-5801,s,'D-6','Hoved D6. g. m. Deg.',ARRAY['Hoved D6.','g. m. Deg.'],-58151,v_actor);
  c:=pg_temp.f5b_claim(-5801,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Deg.');
  v_fam:=pg_temp.f5b_family(-58151,-58152,1);
  v_el:=v_el||jsonb_build_object('relation-persona:'||(c->>'key'),pg_temp.f5b_payload(p,c,(p->'clauses'->>1)::uuid,'g. m. Deg.','Deg'));
  v_defect:=v_defect||jsonb_build_object('D6',jsonb_build_object('claim',c->>'key','partner',-58152,'family',v_fam));

  PERFORM pg_temp.f5b_write(-5801,v_actor,v_el);

  -- Kandidatkørsel: de 11 gode er egnede; defekterne markeres ikke-egnede (uden for populationen)
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5801,'{"mode":"undecided"}');
  RESET ROLE;
  SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',pc.source_persona_id,'candidate_person_id',
           (SELECT o.person_id FROM family_member o JOIN family_member me ON me.family_id=o.family_id AND me.rolle='partner'
              AND me.person_id=(private.persona_family_context(pc.source_persona_id)->>'principal_person_id')::bigint
             WHERE o.rolle='partner' AND o.person_id<>me.person_id ORDER BY o.family_id LIMIT 1),
           'rank',1,'score',0.95,'tier','auto',
           'basis',jsonb_build_object('signals','["name","family_partner"]'::jsonb,
             'corroboration_eligible',(SELECT sr.record_key LIKE 'G-%' FROM private.interpretation_observation io
               JOIN private.interpretation_current ic ON ic.id=io.interpretation_id JOIN private.source_observation o ON o.id=io.observation_id
               JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
               JOIN private.source_record sr ON sr.id=ac.source_record_id WHERE ic.interpretation_key=pc.interpretation_key LIMIT 1)))),'[]')
    INTO v_cands FROM private.interpretation_party_current pc JOIN private.source_persona sp ON sp.id=pc.source_persona_id
   WHERE pc.party_role='spouse' AND sp.source_id=-5801;
  SET LOCAL ROLE authenticated;
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5801,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),v_cands);
  v_ctl:=red_register_identity_control_run(v_run);
  -- ikke bestået endnu → RPC'en afviser (not_ready) uden at skrive
  BEGIN
    PERFORM red_corroborate_family_identities(v_ctl,repeat('0',64));
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: not_ready godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CONTROL_NOT_PASSED%' THEN RAISE; END IF;
  END;
  v_smp:=red_identity_control_sample(v_ctl);
  IF jsonb_array_length(v_smp->'samples')<>10 THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: stikprøve %',jsonb_array_length(v_smp->'samples'); END IF;
  PERFORM red_seal_identity_control_run(v_ctl,repeat('a',64),repeat('b',64));
  FOR i IN 0..9 LOOP
    SELECT key INTO v_pos FROM jsonb_each_text(v_smp->'samples'->i->'mapping') m
     WHERE m.value=(SELECT c3.id::text FROM private.source_persona_identity_candidate c3 WHERE c3.run_id=v_run AND c3.rank=1
                      AND c3.source_persona_id=(v_smp->'samples'->i->>'source_persona_id')::uuid);
    PERFORM red_afgoer_source_persona((v_smp->'samples'->i->>'source_persona_id')::uuid,0,'same',NULL,'stikprøve',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',i+1,
        'control_run_id',v_ctl,'display_position',v_pos::int));
  END LOOP;
  IF red_evaluate_identity_control_run(v_ctl)<>'passed' THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: ikke bestået'; END IF;

  -- mængde-drift afvises uden skrivning
  BEGIN
    PERFORM red_corroborate_family_identities(v_ctl,repeat('0',64));
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: drift godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'IDENTITY_CORROBORATION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  SELECT private.reimport_canonical_json_sha256(jsonb_agg(c3.source_persona_id::text ORDER BY c3.source_persona_id::text COLLATE "C"))
    INTO v_set FROM private.source_persona_identity_candidate c3
    LEFT JOIN private.source_persona_identity i3 ON i3.source_persona_id=c3.source_persona_id
   WHERE c3.run_id=v_run AND c3.rank=1 AND (c3.basis->>'corroboration_eligible')::boolean
     AND i3.source_persona_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM private.identity_control_sample x WHERE x.control_run_id=v_ctl AND x.source_persona_id=c3.source_persona_id);
  SET LOCAL ROLE authenticated;
  v_n:=red_corroborate_family_identities(v_ctl,v_set);
  IF v_n<>1 THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % accepteret',v_n; END IF;
  RESET ROLE;

  -- Defekterne: kernen kaldes direkte (ejer, med redaktør-aktør), hver skal afvises med sin kode.
  UPDATE private.source_persona_identity SET decision_status='unresolved',canonical_person_id=NULL
   WHERE source_persona_id=((v_defect->'D1'->'post')->>'principal')::uuid;   -- ejer-mutation: simulerer ny afgørelse
  UPDATE family_member SET konfidens='sikker' WHERE family_id=(v_defect->'D6'->>'family')::bigint AND person_id=-58152;
  -- D3a afgøres menneskeligt først, så D3b rammer dobbelt mål
  SELECT pc.source_persona_id INTO v_sp FROM private.interpretation_party_current pc
   WHERE pc.interpretation_key=(v_defect->'D3a'->>'claim')::uuid AND pc.party_role='spouse';
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(v_sp,0,'same',-58122,'menneske','{}'::jsonb);
  RESET ROLE;
  FOR v_name,v_err IN SELECT * FROM (VALUES ('D1','FAMILY_CORROBORATION_PRINCIPAL_NOT_ACCEPTED'),('D2','FAMILY_CORROBORATION_COUNT_MISMATCH'),
      ('D3b','FAMILY_CORROBORATION_DOUBLE_TARGET'),('D4','FAMILY_CORROBORATION_KONFIDENS'),('D5','FAMILY_CORROBORATION_ORDINAL_NULL'),
      ('D6','FAMILY_CORROBORATION_CANDIDATE_INVALID')) t LOOP
    SELECT pc.source_persona_id INTO v_sp FROM private.interpretation_party_current pc
     WHERE pc.interpretation_key=(v_defect->v_name->>'claim')::uuid AND pc.party_role='spouse';
    SELECT id INTO v_cand FROM private.source_persona_identity_candidate WHERE run_id=v_run AND source_persona_id=v_sp AND rank=1;
    v_ev:=jsonb_build_object('basis','family_corroboration','method','family-corroboration-v1','run_id',v_run,'candidate_id',v_cand,
      'family_id',0,'ordinal',1,'control_run_id',v_ctl,'family_context_sha256',repeat('0',64));
    BEGIN
      PERFORM private.decide_source_persona_identity(v_sp,(v_defect->v_name->>'partner')::bigint,0,'accepted',v_ev,'family_corroboration');
      RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % godtaget',v_name;
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE v_err||'%' THEN RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: % gav %',v_name,SQLERRM; END IF;
    END;
  END LOOP;
  -- direkte kald fra klientrolle er umuligt
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM private.decide_source_persona_identity(v_sp,-58152,0,'accepted',v_ev,'family_corroboration');
    RAISE EXCEPTION 'CORROBORATION_TEST_FAILED: kernen kaldbar';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: not_ready, drift, ét maskinelt accept, seks defekter afvist med egen kode, kernen privat';
END $family_corroboration$;
ROLLBACK;
```
(D1's ejer-`UPDATE` på `source_persona_identity` er en testgenvej: tabellens state-række er ikke append-only, kun event-tabellen er; testen simulerer en senere menneskelig afgørelse uden at skabe en ny event.)

- [ ] **Step 3: Kør og se den fejle**

Run: `fresh_v2 ci5b_t8 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t8 -f tests/sql/test-family-corroboration.sql`
Expected: FAIL — `function red_corroborate_family_identities(uuid, text) does not exist`.

- [ ] **Step 4: Kernens efterprøvning (schema.sql + 5b-sektionen)**

```sql
CREATE OR REPLACE FUNCTION private.spouse_principal_person(p_persona uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  SELECT i.canonical_person_id FROM private.interpretation_party_current sp
    JOIN private.interpretation_party_current pr ON pr.interpretation_key=sp.interpretation_key AND pr.party_role='principal'
    JOIN private.source_persona_identity i ON i.source_persona_id=pr.source_persona_id AND i.decision_status='accepted'
   WHERE sp.source_persona_id=p_persona AND sp.party_role='spouse';
$$;
REVOKE ALL ON FUNCTION private.spouse_principal_person(uuid) FROM PUBLIC,anon,authenticated;

-- Spec §6.2 (a)-(d). Kaldes KUN af kernen, efter at kernen har låst persona, identitet,
-- personer, familier og medlemmer. Intet tages fra kalderens evidens uden genberegning.
CREATE OR REPLACE FUNCTION private.check_family_corroboration(p_persona uuid,p_person bigint,p_expected integer,
  p_status text,p_evidence jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_party private.interpretation_party%ROWTYPE; v_pparty private.interpretation_party%ROWTYPE;
  v_ic private.interpretation%ROWTYPE; v_ev private.reimport_event%ROWTYPE; v_occ uuid; v_principal uuid; v_n integer;
  v_pid bigint; v_fams integer; v_claims integer; v_fam bigint; v_partners bigint[]; v_cand private.source_persona_identity_candidate%ROWTYPE;
  v_cur uuid; v_source bigint;
BEGIN
  IF p_status<>'accepted' OR p_expected<>0 OR p_evidence->>'basis' IS DISTINCT FROM 'family_corroboration'
     OR p_evidence->>'method' IS DISTINCT FROM 'family-corroboration-v1' THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_BASIS_REQUIRED';
  END IF;
  -- (a) proveniens
  SELECT * INTO v_party FROM private.interpretation_party_current WHERE source_persona_id=p_persona AND party_role='spouse';
  IF NOT FOUND OR v_party.origin<>'relation_persona' THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_PROVENANCE_INVALID'; END IF;
  SELECT * INTO v_ic FROM private.interpretation_current WHERE interpretation_key=v_party.interpretation_key;
  IF v_ic.predicate<>'relation.marriage' OR v_ic.status NOT IN ('proposed','accepted') THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_PROVENANCE_INVALID';
  END IF;
  SELECT e.* INTO v_ev FROM private.reimport_event e JOIN private.reimport_batch b ON b.id=e.batch_id
   WHERE e.batch_id=v_party.origin_ref AND e.operation='relation_persona' AND b.status IN ('finalized','activated')
     AND e.payload->>'interpretation_key'=v_party.interpretation_key::text;
  SELECT * INTO v_pparty FROM private.interpretation_party_current WHERE interpretation_key=v_party.interpretation_key AND party_role='principal';
  IF v_ev.id IS NULL
     OR v_ev.payload->'result_receipt'->>'spouse_source_persona_id' IS DISTINCT FROM p_persona::text
     OR v_ev.payload->'result_receipt'->>'principal_source_persona_id' IS DISTINCT FROM v_pparty.source_persona_id::text
     OR (v_ev.payload->>'marriage_ordinal')::integer IS DISTINCT FROM v_party.marriage_ordinal
     OR (v_ev.payload->>'post_offset')::integer IS DISTINCT FROM v_party.post_offset THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_PROVENANCE_INVALID';
  END IF;
  SELECT o.occurrence_id INTO v_occ FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
   WHERE io.interpretation_id=v_ic.id AND io.evidence_role='supporting' AND io.ordinal=1;
  SELECT count(*),min(spm.persona_id::text)::uuid INTO v_n,v_principal
    FROM private.source_observation h JOIN private.source_mention sm ON sm.observation_id=h.id
    JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
   WHERE h.occurrence_id=v_occ AND h.parent_observation_id IS NULL;
  IF v_n<>1 OR v_principal IS DISTINCT FROM v_pparty.source_persona_id THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_PROVENANCE_INVALID'; END IF;
  SELECT canonical_person_id INTO v_pid FROM private.source_persona_identity WHERE source_persona_id=v_principal AND decision_status='accepted';
  IF v_pid IS NULL THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_PRINCIPAL_NOT_ACCEPTED'; END IF;
  -- (b) struktur, talt af kernen
  SELECT count(*) INTO v_claims FROM private.relation_marriage_ordinals(v_occ);
  SELECT count(DISTINCT family_id) INTO v_fams FROM public.family_member WHERE person_id=v_pid AND rolle='partner';
  IF v_claims<>v_fams THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_COUNT_MISMATCH'; END IF;
  IF v_fams>1 AND EXISTS (SELECT 1 FROM public.family_member WHERE person_id=v_pid AND rolle='partner' AND ordinal IS NULL) THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_ORDINAL_NULL';
  END IF;
  IF (SELECT count(*) FROM public.family_member WHERE person_id=v_pid AND rolle='partner'
       AND (v_fams=1 OR ordinal=v_party.marriage_ordinal))<>1 THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_FAMILY_INVALID';
  END IF;
  SELECT family_id INTO v_fam FROM public.family_member WHERE person_id=v_pid AND rolle='partner'
     AND (v_fams=1 OR ordinal=v_party.marriage_ordinal);
  SELECT array_agg(person_id ORDER BY person_id) INTO v_partners FROM public.family_member
   WHERE family_id=v_fam AND rolle='partner' AND person_id<>v_pid;
  IF v_partners IS DISTINCT FROM ARRAY[p_person] THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_TARGET_INVALID'; END IF;
  IF EXISTS (SELECT 1 FROM public.family_member WHERE family_id=v_fam AND rolle='partner' AND konfidens IN ('omstridt','formodet')) THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_KONFIDENS';
  END IF;
  IF EXISTS (SELECT 1 FROM private.interpretation_party_current pc2
               JOIN private.source_persona_identity i2 ON i2.source_persona_id=pc2.source_persona_id AND i2.decision_status='accepted'
               JOIN private.interpretation_current ic2 ON ic2.interpretation_key=pc2.interpretation_key
               JOIN private.interpretation_observation io2 ON io2.interpretation_id=ic2.id AND io2.ordinal=1
               JOIN private.source_observation o2 ON o2.id=io2.observation_id
              WHERE pc2.party_role='spouse' AND pc2.source_persona_id<>p_persona AND i2.canonical_person_id=p_person
                AND o2.occurrence_id=v_occ) THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_DOUBLE_TARGET';
  END IF;
  -- (c) kandidat i den gældende kørsel + uændret familiekontekst
  SELECT source_id INTO v_source FROM private.source_persona WHERE id=p_persona;
  SELECT r.id INTO v_cur FROM private.source_persona_identity_candidate_run r WHERE r.source_id=v_source ORDER BY r.run_seq DESC LIMIT 1;
  SELECT * INTO v_cand FROM private.source_persona_identity_candidate WHERE id=(p_evidence->>'candidate_id')::uuid;
  IF v_cand.id IS NULL OR v_cand.source_persona_id<>p_persona OR v_cand.rank<>1 OR v_cand.run_id IS DISTINCT FROM v_cur
     OR v_cand.candidate_person_id<>p_person OR p_evidence->>'run_id' IS DISTINCT FROM v_cur::text
     OR v_cand.family_context_sha256 IS DISTINCT FROM
        private.reimport_canonical_json_sha256(private.persona_family_context(p_persona))
     OR (p_evidence->>'family_id')::bigint IS DISTINCT FROM v_fam THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_CANDIDATE_INVALID';
  END IF;
  -- (d) autorisation: bestået kontrolkørsel for netop denne kandidatkørsel; stikprøvesager er menneskets
  IF NOT EXISTS (SELECT 1 FROM private.identity_control_run r WHERE r.id=(p_evidence->>'control_run_id')::uuid AND r.candidate_run_id=v_cur)
     OR (SELECT e.status FROM private.identity_control_event e WHERE e.control_run_id=(p_evidence->>'control_run_id')::uuid
          ORDER BY e.seq DESC LIMIT 1) IS DISTINCT FROM 'passed'
     OR EXISTS (SELECT 1 FROM private.identity_control_sample x WHERE x.control_run_id=(p_evidence->>'control_run_id')::uuid
                 AND x.source_persona_id=p_persona) THEN
    RAISE EXCEPTION 'FAMILY_CORROBORATION_CONTROL_NOT_PASSED';
  END IF;
END $$;
REVOKE ALL ON FUNCTION private.check_family_corroboration(uuid,bigint,integer,text,jsonb) FROM PUBLIC,anon,authenticated;
```
Bemærk: D6-defekten (`konfidens` sat til `sikker` efter kørslen) består (b) men ændrer konteksthashen og rammer derfor (c) — det er netop testens pointe. D2's parkerede påstand tæller med i `relation_marriage_ordinals` (Review Focus 2).

- [ ] **Step 5: Kernen (erstat på sin plads i schema.sql 8171 og 5a-sektionen)**

I `private.decide_source_persona_identity`:
1. Efter versionskontrollen (`IF v_current_version<>p_expected_version THEN … END IF;`) og før `-- Trin 5a-guard`:
```sql
  -- Trin 5b (spec §6.2): lås gammelt og nyt mål — og ved family_corroboration også hovedpersonen —
  -- i den totale orden (person → familie → medlemmer) før nogen efterprøvning eller skrivning.
  PERFORM private.lock_family_rows(ARRAY(SELECT DISTINCT x FROM unnest(ARRAY[
      (SELECT canonical_person_id FROM private.source_persona_identity WHERE source_persona_id=p_source_persona_id),
      p_canonical_person_id,
      CASE WHEN p_origin='family_corroboration' THEN private.spouse_principal_person(p_source_persona_id) END]) x
    WHERE x IS NOT NULL ORDER BY 1));
```
2. Ny gren før `ELSE RAISE EXCEPTION 'EVIDENCE_IDENTITY_ORIGIN_INVALID'`:
```sql
  ELSIF p_origin='family_corroboration' THEN
    PERFORM private.check_family_corroboration(p_source_persona_id,p_canonical_person_id,p_expected_version,
                                                p_decision_status,p_evidence);
```

- [ ] **Step 6: Bekræftelses-RPC'en (schema.sql + 5b-sektionen)**

```sql
CREATE OR REPLACE FUNCTION red_corroborate_family_identities(p_control_run_id uuid,p_expect_set_sha256 text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_source bigint; v_run uuid; v_status text; v_reason text; v_last text; v_set text; r record; v_n integer:=0;
  v_ctx jsonb; v_fam bigint; v_ord integer;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  SELECT source_id,candidate_run_id INTO v_source,v_run FROM private.identity_control_run WHERE id=p_control_run_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'IDENTITY_CONTROL_RUN_UNKNOWN'; END IF;
  -- Eksklusiv kildelås (spec §6.3): ingen menneskelig afgørelse kan interleave med genvalideringen.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  PERFORM 1 FROM private.identity_control_run WHERE id=p_control_run_id FOR UPDATE;
  PERFORM 1 FROM private.source_persona_identity i JOIN private.identity_control_sample s ON s.source_persona_id=i.source_persona_id
   WHERE s.control_run_id=p_control_run_id ORDER BY i.source_persona_id FOR UPDATE OF i;
  SELECT s.status,s.reason INTO v_status,v_reason FROM private.control_run_status(p_control_run_id) s;
  IF v_status='not_ready' THEN RAISE EXCEPTION 'IDENTITY_CONTROL_NOT_PASSED: %',v_reason; END IF;
  SELECT e.status INTO v_last FROM private.identity_control_event e WHERE e.control_run_id=p_control_run_id ORDER BY e.seq DESC LIMIT 1;
  IF v_status='failed' THEN
    IF v_last IS DISTINCT FROM 'failed' THEN PERFORM private.append_control_event(p_control_run_id,'failed',v_reason); END IF;
    RETURN 0;
  END IF;
  -- Kernens (d) læser den seneste EVENT; en beregnet passed uden event skrives her.
  IF v_last IS DISTINCT FROM 'passed' THEN PERFORM private.append_control_event(p_control_run_id,'passed','ok'); END IF;
  DROP TABLE IF EXISTS pg_temp.corr_set;   -- se ctl_ipop: genkald i samme transaktion
  CREATE TEMP TABLE pg_temp.corr_set ON COMMIT DROP AS
    SELECT c.source_persona_id AS pid,c.id AS cid,c.candidate_person_id AS person
      FROM private.source_persona_identity_candidate c
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=c.source_persona_id
     WHERE c.run_id=v_run AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean IS TRUE
       AND (i.source_persona_id IS NULL OR i.decision_status='proposed')
       AND NOT EXISTS (SELECT 1 FROM private.identity_control_sample x WHERE x.control_run_id=p_control_run_id AND x.source_persona_id=c.source_persona_id);
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(pid::text ORDER BY pid::text COLLATE "C"),'[]'::jsonb))
    INTO v_set FROM pg_temp.corr_set;
  IF v_set IS DISTINCT FROM p_expect_set_sha256 THEN RAISE EXCEPTION 'IDENTITY_CORROBORATION_SET_DRIFT'; END IF;
  FOR r IN SELECT * FROM pg_temp.corr_set ORDER BY pid LOOP
    v_ctx:=private.persona_family_context(r.pid);
    SELECT (f->>'family_id')::bigint,(f->>'ordinal')::integer INTO v_fam,v_ord
      FROM jsonb_array_elements(v_ctx->'families') f
     WHERE jsonb_array_length(v_ctx->'families')=1 OR (f->>'ordinal')::integer=(v_ctx->>'marriage_ordinal')::integer
     LIMIT 1;
    PERFORM private.decide_source_persona_identity(r.pid,r.person,0,'accepted',
      jsonb_build_object('basis','family_corroboration','method','family-corroboration-v1','run_id',v_run,'candidate_id',r.cid,
        'family_id',v_fam,'ordinal',v_ord,'control_run_id',p_control_run_id,
        'family_context_sha256',private.reimport_canonical_json_sha256(v_ctx)),
      'family_corroboration');
    v_n:=v_n+1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION red_corroborate_family_identities(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_corroborate_family_identities(uuid,text) TO authenticated;
```
Tilføj signaturen i `v_authenticated`, `$public_red_acl_verify$` og `db-rls.sql`'s allow-liste.

- [ ] **Step 7: Den statiske kalder-allowlist**

`.claude/skills/daa-extract/scripts/test_identity_guard_static.py`: tilføj `"family_corroboration"` til `OPRINDELSER` og i `ALLOWLIST`:
```python
    ("schema.sql", "red_corroborate_family_identities", "family_corroboration"): 1,
    ("db-migrations.sql", "red_corroborate_family_identities", "family_corroboration"): 1,
```
Kommentaren over `ALLOWLIST` udvides med `# 5b 2026-10-06: family_corroboration (decisions 2026-10-06).`

- [ ] **Step 8: Kør testene og se dem bestå**

Run:
```bash
fresh_v2 ci5b_t8b && for t in test-family-corroboration test-identity-control-run test-identity-decision test-relation-decision; do
  psql -X -v ON_ERROR_STOP=1 -d ci5b_t8b -f tests/sql/$t.sql || break; done
cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_identity_guard_static.py -q
```
Expected: `OK: not_ready, drift, ét maskinelt accept, seks defekter afvist med egen kode, kernen privat`; de øvrige grønne; den statiske test grøn.

- [ ] **Step 9: CI og commit**

CI, job `writer-1939-v50-db`, efter »Relationspersona-writer SQL (5b)«:
```yaml
      - name: Family corroboration SQL (5b)
        env: {PGPASSWORD: postgres}
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-family-corroboration.sql
```
```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/fixtures/relation-5b.sql tests/sql/test-family-corroboration.sql \
  .claude/skills/daa-extract/scripts/test_identity_guard_static.py .github/workflows/ci.yml
git commit -m "feat(151): kerne-oprindelsen family_corroboration og bekræftelses-RPC med genvalidering

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 9: Webkøen — rollefilter, familiekontekst og kandidatvisning

**Files:**
- Modify: `schema.sql` 8290-8386 + 5a-sektionen i `db-migrations.sql` (`red_source_persona_queue` erstattes på sin plads med ny signatur; `red_source_persona_detail` udvides), `db-migrations.sql` `v_authenticated`, `db-verify.sql` ACL-listen, `db-rls.sql` allow-listen, `tests/sql/test-identity-detail.sql`, `web/src/data/sourcePersona.ts`, `web/src/data/__tests__/sourcePersona.test.ts`, `web/src/components/KildepersonaKo.tsx`, `web/src/components/__tests__/KildepersonaKo.test.tsx`

**Interfaces:**
- Consumes: `persona_family_context` (Task 4).
- Produces: `red_source_persona_queue(p_status text, p_source_id bigint, p_cursor uuid, p_page_size integer, p_mention_role text DEFAULT NULL)` med ny returkolonne `mention_role text`; detaljens kandidater får `titles`, `own_post_key`, `family_id`, `ordinal`; detaljen får `family_context` (`principal_record_key`, `marriage_ordinal`) for ægtefæller. Web: `fetchSourcePersonaQueue(status, sourceId, cursor, mentionRole?)`, `SourcePersonaCandidate.titles/ownPostKey/familyId/ordinal`, `SourcePersonaDetail.familyContext`.

- [ ] **Step 1: Skriv de fejlende tests**

`tests/sql/test-identity-detail.sql` — tilføj en blok:
```sql
\ir fixtures/relation-5b.sql
DO $identity_detail_5b$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b901'; s jsonb; p jsonb; c jsonb; v_sp uuid; v_in jsonb; v_run uuid; d jsonb; q record;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES (-5901,false,false,'5b','Hoved'),(-5902,false,false,'5b','Mage');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-5902,'person',-5902,'titel');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES (-5902,'fact',-5902,'kammerherre');
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id) VALUES ('fact',-5902,-5902);
  s:=pg_temp.f5b_source(-5901);
  p:=pg_temp.f5b_post(-5901,s,'IX-1','Hoved. g. m. Mage.',ARRAY['Hoved.','g. m. Mage.'],-5901,v_actor);
  c:=pg_temp.f5b_claim(-5901,s,'relation.marriage',(p->'clauses'->>1)::uuid,'g. m. Mage.');
  v_sp:=pg_temp.f5b_spouse(-5901,s,p,c,(p->'clauses'->>1)::uuid,'Mage',1);
  PERFORM pg_temp.f5b_family(-5901,-5902,1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_identity_candidate_input(-5901,'{"mode":"undecided"}');
  v_run:=red_record_identity_candidates(jsonb_build_object('source_id',-5901,'generator_version','t','config','{}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    jsonb_build_array(jsonb_build_object('source_persona_id',v_sp,'candidate_person_id',-5902,'rank',1,'score',0.9,'tier','review',
      'basis','{"signals":["name","family_partner"]}'::jsonb)));
  d:=red_source_persona_detail(v_sp);
  SELECT * INTO q FROM red_source_persona_queue(NULL,-5901,NULL,50,'spouse');
  RESET ROLE;
  IF d->'family_context'->>'principal_record_key'<>'IX-1' OR (d->'family_context'->>'marriage_ordinal')::int<>1
     OR d->'candidates'->0->'titles'<>'["kammerherre"]'::jsonb OR (d->'candidates'->0->>'family_id') IS NULL
     OR q.mention_role<>'spouse' OR q.source_persona_id<>v_sp THEN
    RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: 5b-felter %',d->'family_context';
  END IF;
  RAISE NOTICE 'OK: rollefilter, familiekontekst og kandidaternes titler/familie';
END $identity_detail_5b$;
```
(placeres før filens afsluttende `ROLLBACK`, hvis filen kører i én transaktion; ellers omsluttet af `BEGIN; … ROLLBACK;`.)

`web/src/data/__tests__/sourcePersona.test.ts` — tilføj:
```ts
it('mapper 5b-felterne: rollefilter, titler, familie og familiekontekst', async () => {
  rpc.mockResolvedValueOnce({ data: [], error: null });
  await fetchSourcePersonaQueue('proposed', 7, null, 'spouse');
  expect(rpc).toHaveBeenLastCalledWith('red_source_persona_queue',
    { p_status: 'proposed', p_source_id: 7, p_cursor: null, p_page_size: 50, p_mention_role: 'spouse' });
  rpc.mockResolvedValueOnce({ data: { persona: { source_persona_id: 's', source_id: 7, persona_key: 'k', decision_status: 'proposed', version: 0 },
    mentions: [], placements: [], interpretations: [], collisions: [],
    family_context: { principal_record_key: 'IX-1', marriage_ordinal: 2 },
    candidates: [{ candidate_id: 'c', run_id: 'r', rank: 1, score: 0.9, tier: 'review', person_id: 5, person_name: 'Mage',
                   born: null, died: null, basis: { signals: ['name'] }, titles: ['kammerherre'], own_post_key: 'II-4', family_id: 30, ordinal: 2 }] },
    error: null });
  const d = await fetchSourcePersonaDetail('s');
  expect(d.familyContext).toEqual({ principalRecordKey: 'IX-1', marriageOrdinal: 2 });
  expect(d.candidates[0]).toMatchObject({ titles: ['kammerherre'], ownPostKey: 'II-4', familyId: 30, ordinal: 2 });
});
```
(`rpc` er filens eksisterende mock af `supabase.rpc`.)

`web/src/components/__tests__/KildepersonaKo.test.tsx` — tilføj:
```tsx
it('viser rollefilter og kandidatens titler, egen post og familie', async () => {
  mocks.queue.mockResolvedValue([{ ...row(1), mentionRole: 'spouse' }]);
  mocks.history.mockResolvedValue([]);
  mocks.detail.mockResolvedValue({ persona: { ...row(1), mentionRole: 'spouse' }, mentions: [], placements: [], interpretations: [], collisions: [],
    familyContext: { principalRecordKey: 'IX-1', marriageOrdinal: 2 },
    candidates: [{ candidateId: 'c', runId: 'r', rank: 1, score: 0.9, tier: 'review', personId: 5, personName: 'Mage', born: null, died: null,
                   signals: ['name'], titles: ['kammerherre'], ownPostKey: 'II-4', familyId: 30, ordinal: 2 }] });
  render(<KildepersonaKo role="redaktion" />);
  fireEvent.change(await screen.findByLabelText('Rolle'), { target: { value: 'spouse' } });
  await waitFor(() => expect(mocks.queue).toHaveBeenLastCalledWith('proposed', null, null, 'spouse'));
  fireEvent.click(await screen.findByText(/persona-1/));
  expect(await screen.findByText(/ægtefælle nr\. 2 i IX-1/)).toBeTruthy();
  expect(await screen.findByText(/kammerherre · egen post II-4 · familie 30 nr\. 2/)).toBeTruthy();
});
```
(Brug filens eksisterende `row()`-hjælper og samme klik-mønster som de øvrige tests for at åbne en detalje.)

- [ ] **Step 2: Kør og se dem fejle**

Run:
```bash
fresh ci5b_t9 && psql -X -v ON_ERROR_STOP=1 -d ci5b_t9 -f tests/sql/test-identity-detail.sql
cd web && env -u NODE_OPTIONS VITE_SUPABASE_URL=http://x VITE_SUPABASE_ANON_KEY=x npx vitest run src/data/__tests__/sourcePersona.test.ts src/components/__tests__/KildepersonaKo.test.tsx
```
Expected: SQL FAIL (`function red_source_persona_queue(…, unknown) does not exist` eller manglende felter); vitest FAIL på de nye tests.

- [ ] **Step 3: SQL — kø og detalje**

1. Køen erstattes på sin plads (schema.sql 8290 og db-migrations ~7208) — signaturen ændres, så migrationen dropper den gamle først:
```sql
DROP FUNCTION IF EXISTS red_source_persona_queue(text,bigint,uuid,integer);
CREATE OR REPLACE FUNCTION red_source_persona_queue(
  p_status text DEFAULT NULL, p_source_id bigint DEFAULT NULL,
  p_cursor uuid DEFAULT NULL, p_page_size integer DEFAULT 50, p_mention_role text DEFAULT NULL
) RETURNS TABLE(
  source_persona_id uuid, source_id bigint, persona_key text,
  decision_status text, version integer, canonical_person_id bigint, mention_count bigint,
  best_tier text, reason text, mention_role text
)
```
Kroppen er 5a's uændret, med to tilføjelser: kolonnen
`(SELECT spm.mention_role FROM private.source_persona_mention spm WHERE spm.persona_id=persona.id ORDER BY spm.ordinal LIMIT 1)`
sidst i SELECT-listen, og i WHERE: `AND (p_mention_role IS NULL OR EXISTS (SELECT 1 FROM private.source_persona_mention spm WHERE spm.persona_id=persona.id AND spm.mention_role=p_mention_role))`. Validering øverst: `IF p_mention_role IS NOT NULL AND p_mention_role NOT IN ('primary','spouse') THEN RAISE EXCEPTION 'EVIDENCE_IDENTITY_STATUS_INVALID'; END IF;`. REVOKE/GRANT og ACL-listerne (`v_authenticated`, `$public_red_acl_verify$`, `db-rls.sql`) ændres fra `red_source_persona_queue(text,bigint,uuid,integer)` til `red_source_persona_queue(text,bigint,uuid,integer,text)`.
2. Detaljen: i `'candidates'`-aggregatet tilføjes
```sql
        'titles',coalesce((SELECT jsonb_agg(DISTINCT a.vaerdi_tekst) FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
                            JOIN assertion a ON a.id=k.valgt_assertion_id WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='titel'),'[]'::jsonb),
        'own_post_key',(SELECT sr.record_key FROM private.source_persona_identity i2
            JOIN private.source_persona_mention spm ON spm.persona_id=i2.source_persona_id AND spm.mention_role='primary'
            JOIN private.source_mention sm ON sm.id=spm.mention_id
            JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
            JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
            JOIN private.source_record sr ON sr.id=ac.source_record_id
           WHERE i2.canonical_person_id=p.id AND i2.decision_status='accepted' ORDER BY sr.record_key LIMIT 1),
        'family_id',(SELECT (f->>'family_id')::bigint FROM jsonb_array_elements(private.persona_family_context(persona.id)->'families') f
                      WHERE f->'partners' @> to_jsonb(p.id) LIMIT 1),
        'ordinal',(SELECT (f->>'ordinal')::int FROM jsonb_array_elements(private.persona_family_context(persona.id)->'families') f
                      WHERE f->'partners' @> to_jsonb(p.id) LIMIT 1)
```
og på top-niveau:
```sql
    'family_context',(SELECT jsonb_build_object('principal_record_key',
        (SELECT sr.record_key FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
           JOIN private.source_observation o ON o.id=sm.observation_id
           JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
           JOIN private.source_record sr ON sr.id=ac.source_record_id
          WHERE spm.persona_id=persona.id AND spm.mention_role='spouse' LIMIT 1),
        'marriage_ordinal',(fc->>'marriage_ordinal')::int)
      FROM private.persona_family_context(persona.id) fc WHERE fc IS NOT NULL),
```

- [ ] **Step 4: Web — datalag og komponent**

`web/src/data/sourcePersona.ts`:
```ts
export type SourcePersonaCandidate = {
  candidateId: string; runId: string; rank: number; score: number; tier: string;
  personId: number; personName: string; born: string | null; died: string | null; signals: string[];
  titles: string[]; ownPostKey: string | null; familyId: number | null; ordinal: number | null;
};
// SourcePersonaQueueRow får: mentionRole: string | null;
// SourcePersonaDetail får: familyContext: { principalRecordKey: string; marriageOrdinal: number } | null;
export async function fetchSourcePersonaQueue(status: string | null = null, sourceId: number | null = null,
  cursor: string | null = null, mentionRole: string | null = null): Promise<SourcePersonaQueueRow[]> {
  const { data, error } = await supabase.rpc('red_source_persona_queue', {
    p_status: status, p_source_id: sourceId, p_cursor: cursor, p_page_size: 50, p_mention_role: mentionRole,
  });
  // … uændret mapping + mentionRole: row.mention_role == null ? null : String(row.mention_role)
}
```
I detaljens kandidat-mapping tilføjes `titles: Array.isArray(v.titles) ? (v.titles as unknown[]).map(String) : []`, `ownPostKey: v.own_post_key == null ? null : String(v.own_post_key)`, `familyId: v.family_id == null ? null : Number(v.family_id)`, `ordinal: v.ordinal == null ? null : Number(v.ordinal)`; og `familyContext: raw.family_context ? { principalRecordKey: String(fc.principal_record_key), marriageOrdinal: Number(fc.marriage_ordinal) } : null`.

`web/src/components/KildepersonaKo.tsx`:
- ny state `const [mentionRole, setMentionRole] = useState('');` ved siden af `status`; `load` kalder `fetchSourcePersonaQueue(status, sourceId, cursor, mentionRole || null)`; `mentionRole` med i `useEffect`-afhængighederne;
- ved siden af status-select:
```tsx
      <label>Rolle <select value={mentionRole} onChange={(e) => setMentionRole(e.target.value)}>
        <option value="">alle</option><option value="primary">hovedperson</option><option value="spouse">ægtefælle</option>
      </select></label>
```
- over »Kildegrundlag«: `{detail.familyContext && <div>ægtefælle nr. {detail.familyContext.marriageOrdinal} i {detail.familyContext.principalRecordKey}</div>}`
- i kandidatlinjen efter signalerne:
```tsx
              {(c.titles.length || c.ownPostKey || c.familyId != null) && <div style={{ fontSize: 12 }}>
                {[c.titles.join(', ') || null, c.ownPostKey ? `egen post ${c.ownPostKey}` : null,
                  c.familyId != null ? `familie ${c.familyId} nr. ${c.ordinal ?? '?'}` : null].filter(Boolean).join(' · ')}
              </div>}
```

- [ ] **Step 5: Kør og se dem bestå**

Run: samme som Step 2, plus `cd web && env -u NODE_OPTIONS VITE_SUPABASE_URL=http://x VITE_SUPABASE_ANON_KEY=x npm run test && npm run build`
Expected: SQL `OK: rollefilter, familiekontekst og kandidaternes titler/familie`; alle web-tests grønne (5a's tests uændret — de nye felter er valgfrie i fixtures, fordi mappingen giver `[]`/`null`), build rc 0.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-identity-detail.sql web/src
git commit -m "feat(151): webkø med rollefilter, familiekontekst og kandidaternes titler/familie

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```

---

### Task 10: Del 1's færdigbevis i restoren (spec §10 punkt 1-4 og 7)

**Files:** ingen kode. Tal i ledgeren; rapporten skrives i del 2 (`relationspersonas-5b-bevis.md`) og får del 1's tal derfra.

**Interfaces:** alt fra Task 1-9. Navne og arket ligger kun i `~/.private/5b/` (0700/0600).

- [ ] **Step 1: Arbejdsbase**

Run:
```bash
TS=$(date +%Y%m%d%H%M%S); createdb -T daa2018f_20261001133125 daa5b_bevis_$TS
for f in db-migrations.sql db-rls.sql; do psql -X -q -v ON_ERROR_STOP=1 -d daa5b_bevis_$TS -f $f >/dev/null || break; done
psql -X -q -v ON_ERROR_STOP=1 -d daa5b_bevis_$TS -f tests/sql/run-db-verify-disposable.sql >/dev/null && echo VERIFY_OK
```
Expected: `VERIFY_OK` (5a's cutover-blok og 5b's sektion løfter et prod-ækvivalent katalog). Skriv basenavnet i ledgeren.

- [ ] **Step 2: Udtræk og writer (punkt 1)**

Kør Task 3 Step 6's input + udtræk mod arbejdsbasen, derefter:
```bash
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -v source_id=1 -v manifest_file=$HOME/.private/5b/relation-manifest.json \
  -f .claude/skills/daa-extract/scripts/relation_persona_apply.sql | grep -v -- "$A"
```
Expected: `skrevet = N` (= udtrækkets `elementer`), `counts` med `relation_personas = N`, `relation_results` med `derived_counts`; manifest_sha256. Ingen navne i output. Ledger: tallene.

- [ ] **Step 3: Kandidater og kalibrering (punkt 2)**

```bash
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -v source_id=1 -v mode=undecided -v personas= \
  -f packages/identity-candidates/sql/export-input.sql > ~/.private/5b/cand-input.json
for m in 0.85 0.9 0.95; do env -u NODE_OPTIONS npm run cli -w @daa/identity-candidates -- generate --input ~/.private/5b/cand-input.json \
  --source-id 1 --family-name-min $m --out ~/.private/5b/cand-$m.json | grep CANDIDATES_OK; done
```
Expected: tre linjer `CANDIDATES_OK personas=… egnede=…`. Vælg `familyNameMin` ud fra antal egnede og ledger en `Ruling:` med tallene (forsigtig: vælg den højeste værdi, hvor uoverensstemmelserne ikke overstiger cirka 80 linjer i alt med stikprøven). Skriv den valgte kørsel:
```bash
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -v cand_file=$HOME/.private/5b/cand-<valgt>.json \
  -f packages/identity-candidates/sql/write-candidates.sql | grep -v -- "$A" | tail -1
```
Expected: kørslens uuid (sidste linje; aktøren filtreret fra — memory `set-config-ekko-aktoer`).

- [ ] **Step 3b: Spec §6.5 — er 1939-årstal nødvendige? (kun tal)**

```bash
psql -X -At -d daa5b_bevis_$TS <<'SQL'
WITH r AS (SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=1 ORDER BY run_seq DESC LIMIT 1)
SELECT count(*) FILTER (WHERE NOT coalesce((c.basis->>'family_partner')::boolean,false)) AS globale_kandidater,
       count(*) FILTER (WHERE NOT coalesce((c.basis->>'family_partner')::boolean,false)
         AND EXISTS (SELECT 1 FROM person_external_id x WHERE x.person_id=c.candidate_person_id AND x.source_id=3)
         AND NOT EXISTS (SELECT 1 FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
                          JOIN assertion a ON a.id=k.valgt_assertion_id
                         WHERE f.subjekt_type='person' AND f.subjekt_id=c.candidate_person_id AND f.faktatype IN ('fødsel','død')
                           AND a.date_min IS NOT NULL)) AS globale_1939_uden_dato
  FROM private.source_persona_identity_candidate c, r WHERE c.run_id=r.id AND c.rank<=3;
SQL
```
Expected: to tal. Er `globale_1939_uden_dato` > 10 % af `globale_kandidater`, registreres 1939-årstallene som en del 2-opgave (ledger `Ruling:`); ellers åbent punkt til trin 6 (spec §6.5, §14.1).

- [ ] **Step 4: Kontrolkørsel og ark (punkt 3)**

```bash
psql -X -At -q -d daa5b_bevis_$TS -c "BEGIN; SELECT set_config('request.jwt.claim.sub','$A',true) IS NOT NULL \g /dev/null
SET LOCAL ROLE authenticated; SELECT 'ctl='||red_register_identity_control_run('<run>'::uuid); COMMIT;" | grep '^ctl='
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -v control_run_id=<ctl> -f .claude/skills/daa-extract/scripts/identity_control_rows.sql > ~/.private/5b/kontrol-rows.json
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py render --rows ~/.private/5b/kontrol-rows.json --out ~/.private/5b/KONTROL.txt
```
Registreringen skal ske, mens basen er uændret siden kandidatkørslen (ellers `IDENTITY_CONTROL_INPUT_DRIFT` → ny kandidatkørsel), og intet må ændre personer, familier eller `samme_som` i basen, før bekræftelsen er kørt (ellers `failed`/`kandidatinput_aendret`).
Expected: `ARK_OK ark=… linjer=… stikproeve=… uoverensstemmelser=…` og `rows_sha256 …`. Ved `ark=1` findes kun `~/.private/5b/KONTROL.txt`; ved flere ark også `KONTROL-2.txt` … (spec §7.3, errata §22): **ark 1 rummer hele stikprøven** og forsegler; ark 2.. rummer kun uoverensstemmelser. Projektejeren udfylder arkene og giver én hash pr. ark (`! shasum -a 256 ~/.private/5b/KONTROL*.txt`). **Stop her og vent på hasherne.** `SHEET_SAMPLE_TOO_LARGE` betyder, at stikprøven alene er over 80 linjer: stop og spørg projektejeren, om grænsen må hæves (ledger `Ruling:`) — stikprøven deles aldrig.

- [ ] **Step 5: Negativtests før den rigtige kørsel (punkt 3-4)**

I en **kopi** af arbejdsbasen (`createdb -T daa5b_bevis_$TS daa5b_neg_$TS`):
1. `red_corroborate_family_identities` før forsegling → `IDENTITY_CONTROL_NOT_PASSED`.
2. Arkets SQL med én stikprøvelinje ændret til `U` (ny hash via en kopi af arket) → `kontrolstatus = failed`, og bekræftelsen bagefter returnerer 0.
3. Bekræftelse med forkert mængde-hash → `IDENTITY_CORROBORATION_SET_DRIFT`, 0 nye hændelser (`select count(*) from private.source_persona_identity_event` før/efter).
Kopien slettes ikke på eget initiativ: mål dens størrelse, omdøb den til karantæne (`ALTER DATABASE daa5b_neg_$TS RENAME TO slet_<MMDD>__daa5b_neg_$TS`), og sletning sker kun efter projektejerens ja på målingen. Ledger: de tre udfald og karantænenavnet.

- [ ] **Step 6: Den rigtige kørsel**

Ark 1 først (forsegler, afgør stikprøven og evaluerer):
```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py sql --part 1 --sheet ~/.private/5b/KONTROL.txt --approved-sha256 <hash-1> \
  --rows ~/.private/5b/kontrol-rows.json --expect-rows-sha256 <rows_sha256> --out ~/.private/5b/kontrol-1.sql
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -f ~/.private/5b/kontrol-1.sql | grep -v -- "$A"
```
Derefter hvert overløbsark `n` = 2.. (ingen forsegling, ingen evaluering):
```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py sql --part <n> --sheet ~/.private/5b/KONTROL-<n>.txt --approved-sha256 <hash-n> \
  --rows ~/.private/5b/kontrol-rows.json --expect-rows-sha256 <rows_sha256> --out ~/.private/5b/kontrol-<n>.sql
psql -X -At -q -d daa5b_bevis_$TS -v actor="$A" -f ~/.private/5b/kontrol-<n>.sql | grep -v -- "$A"
```
Expected: ark 1 giver `kontrolstatus = passed` (eller `failed` — så stoppes her, og afvigelserne gennemgås med projektejeren; spec §7.2); hvert overløbsark slutter med `COMMIT` uden fejl. Først når **alle** ark er anvendt: beregn mængde-hashen som i Task 8's test og kør `red_corroborate_family_identities(<ctl>, '<hash>')`. Ledger: antal stikprøve, antal uoverensstemmelser afgjort pr. udfald, antal maskinelt accepteret.

- [ ] **Step 7: Webspor-paritet (punkt 7)**

Som 5a §8.2: én uoverensstemmelses-persona afgøres via psql med webkøens payload (`basis: web_detail`, `candidate_id`, `run_id`) som fastlåst i `sourcePersona.test.ts`; sammenlign evidensnøglerne med en arklinjes. Ledger: nøglesæt (kun nøgler).

- [ ] **Step 8: Ledger-afslutning**

`Task 10: complete (del 1-bevis: base daa5b_bevis_<ts>, N personas, P parkeret, E egnede, S stikprøve, U uoverensstemmelser, M maskinelt, status passed)`. Arbejdsbasen **bevares** til del 2. Ingen commit.

---

## Anden læser

Efter Task 10: Codex (`gpt-5.6-sol`) læser hele grenens diff mod `main` (kode-runde) med fokus på spec §6.2 (a)-(d), låseordenen, kontrolkørslens blindhed og writer-kontrakten; fund rettes efter executing-plans' regler.

## Selvreview-checkliste (udført ved planlægningen)

- **Spec-dækning (del 1):** §5.1 → Task 3; §5.2/§5.2.1 (`relation_persona`) → Task 2; §5.3 → Task 1; §6.1 → Task 4; §6.2 → Task 5 (låse) + Task 8; §6.3 → Task 8; §6.4 → Task 7 + 9; §6.5 → Task 10 Step 3 (måles); §7.1-7.3 → Task 6 + 7; §7.4 → Task 9 + 10; §8.2-8.3 (menneskelig vej for børn/forældre) → Task 5; §10 punkt 1-4, 7 → Task 10. **Del 2:** §8.1 strukturel binding, §8.2 maskinel relationsafgørelse + `relation_disposition`, §8.4 `relation_person_create` + `family.id`, §10 punkt 5, 6, 8 og rapporten.
- **Typer/navne på tværs:** `relation_marriage_ordinals` (Task 2) bruges af Task 4 og 8; `lock_family_rows` (Task 5) af Task 8; `control_run_status`/`append_control_event` (Task 6) af Task 8; `f5b_*`-fixtures defineres i Task 1, 2, 4 og 8 og bruges kun efter definitionen.
- **Review Focus:** 1 → Task 8 D1; 2 → Task 8 D2; 3 → Task 8 D3b; 4 → Task 6 `identity_control_deviation`; 5 → Task 6 `identity_control_stale_run`.
