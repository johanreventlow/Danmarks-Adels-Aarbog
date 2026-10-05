# Trin 5a — én identitetsvej: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Maskinen foreslår identitetskandidater for source personas, og redaktøren afgør dem i et hash-bundet token-ark eller i webkøen gennem én og samme RPC, så hver afgørelse står i databasen med aktør, grundlag og om forslaget blev fulgt — og batch-vejen til `accepted` for eksisterende personer er lukket, bortset fra 149b's faste 1:1-kobling via `person_external_id`, som kernen selv efterprøver.

**Architecture:** To nye append-only tabeller i `private` gemmer kandidatkørsler og kandidater. En Node-CLI (`@daa/identity-candidates`) genbruger `@daa/core`'s matcher som ren funktion: psql eksporterer JSON, CLI'en rangerer pr. persona, psql skriver resultatet gennem en ny writer-RPC. Generatorens input bygges og genberegnes på serveren. `red_afgoer_source_persona` får en kontekstparameter (basis, kandidat + kørsel, arkhashes) og udgangen `new_person_needed` og er den eneste klientindgang; identitetskernen bliver privat (`private.decide_source_persona_identity(…, p_origin)`, ingen grants) med en strukturel oprindelse pr. kalder (`human`, `person_create` med oprettelseskvittering, `legacy_match` for 149b's faste 1:1-kobling, `reversal`); batch-match ud fra lighed er lukket. Alle berørte definitioner erstattes på deres eksisterende plads i `db-migrations.sql`, og en cutover-blok øverst lukker klientvejen til den gamle kerne, før resten af filen kører. Token-arket og webkøen kalder samme RPC.

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql, psql; TypeScript + vitest + tsx (Node 22); Python 3.11 + pytest; React + vitest (web).

**Spec:** `docs/superpowers/specs/2026-09-24-trin5a-identitetsvej-design.md` (branch `docs/151-identitetsvej`).

**Genbekræftet 2026-10-05** mod `main` 984070e (19 commits efter planens grundlag 77a0c22: 4.5, kontrolmodel, omsegmentering, udvalgsbygger, prod-overførsel). De berørte funktioner er byte-identiske, kalderne er de samme, og linjenumrene er opdateret; øvrige rettelser står som »Genbekræftet 2026-10-05«-noter øverst i Task 4, 5, 6, 7 og 9. Codex-genreview samme dag: runde 1 NO-GO (9 fund) og runde 2 NO-GO (fund 5 ufuldstændig + 3 nye) og runde 3 NO-GO (opgraderingsblokken ikke fail-closed) er rettet direkte i kodestykkerne og efterprøvet (årstalsregressionen fejler uden rettelsen; opgraderings- og R-blokken i Task 3 Step 10 grøn mod `main` og stopper ved fejl).

## Global Constraints

- Implementering kræver, at projektejeren har aktiveret trin 5 i `docs/decisions.md` (Task 0 tjekker det).
- 4.5 (og kontrolmodellen) er merget til `main`; Task 7 refaktorerer `interpretation_decision_sheet.py`, som de har udvidet.
- `schema.sql` er source of truth; hver funktion står ordret i både `schema.sql` og `db-migrations.sql`. `db-migrations.sql` er idempotent (køres to gange i CI).
- En eksisterende definition, der indgår i identitetsguarden (kernen, wrapperen, `person_create`-, legacy- og reversal-writerne), **erstattes på sin plads** i `db-migrations.sql` — den får aldrig en rettet kopi længere nede, fordi filen ikke kører i én transaktion (spec §4.2; håndhævet af `test_identity_guard_static.py`).
- Nye `private`-tabeller: RLS slået til, `REVOKE ALL … FROM PUBLIC,anon,authenticated`, append-only-trigger `private.reject_evidence_mutation()`, og navnet i `db-rls.sql`'s master-array.
- Nye/ændrede `red_*`-signaturer skal stå i `db-rls.sql`'s allow-list (ellers `RLS_REDACTION_RPC_ALLOW_LIST_SIGNATURE_MISSING`), og `REVOKE ALL … FROM PUBLIC,anon,authenticated` + `GRANT EXECUTE … TO authenticated`.
- Rollegate i alle nye RPC'er: `auth.uid() IS NOT NULL AND public.current_rolle()='redaktion'`, ellers `EVIDENCE_ROLE_FORBIDDEN`.
- Ingen modelkald. Scripts printer kun tal, id'er og hashes — aldrig navne eller kildetekst. Filer med navne/kildetekst (rækkefil, ark, eksport-JSON) skrives 0600 under `~/.private/5a/`, aldrig i repoet, og læses aldrig af agenten.
- Prod røres ikke i denne plan. Alle kørsler sker i lokale baser.
- Testsprog og fejlkoder følger repoet: SQL-tests `RAISE EXCEPTION '<KODE>: …'`, succes `RAISE NOTICE 'OK: …'`; db-verify `'FEJL: …'`.
- Atomiske commits, Conventional Commits på dansk, ingen Claude-attribution; afslut beskeden med den udførende sessions egen `Claude-Session:`-linje. Push/PR kun efter udtrykkeligt ja; PR altid draft.
- Kør pytest med `env -u NODE_OPTIONS /usr/bin/python3 -m pytest` (NODE_OPTIONS peger på en død fil lokalt).

**Frisk testbase (bruges af flere tasks)** — kopiér som den står:

```bash
FRESH=daa5a_$(date +%Y%m%d%H%M%S); createdb "$FRESH"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f "$f" >> /tmp/claude-501/fresh-$FRESH.log 2>&1 || { echo "FEJL i $f"; break; }
done; echo "base=$FRESH"; tail -3 /tmp/claude-501/fresh-$FRESH.log
```

Frisk-baser noteres i ledgeren og ryddes i Task 9's oprydningsgate (måling først, sletning kun med ja).

## Review Focus

1. **Samme person er bedste kandidat for to personas** (fx samme mand nævnt i to poster) — begge skal have ham som kandidat 1; rangeringen må ikke være injektiv. Test: Task 5 `rank.test.ts` »ikke-injektiv«.
2. **Generatoren køres igen mellem eksport og afgørelse** — et kandidat-token skal pege på det, redaktøren så; RPC'en afviser en forældet kørsel atomisk under kildelåsen. Test: Task 3 `test-identity-decision.sql` (`EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE` + låsetesten), i CI.
3. **Persona uden navn / uden kandidater** — står i arket med »ingen kandidat«; token `1` er ugyldigt, `X`/`N`/`U`/`P` er gyldige. Test: Task 7 `test_kandidat_token_uden_kandidat_stopper`.
4. **Guarden må ikke vælte oprettelse, 149b og fortrydelse** — `red_apply_reimport_person_create` (nu via kvittering), 149b's migration (`legacy_match`) og reversal-writerne skal stadig virke. Test: Task 3 kører uændret grønt `test-reimport-legacy-migration.sql` (149b), `test-reimport-name-completion.sql` og `test-1939-v50-production-writer.sql` (positive kald af oprettelse og fortrydelse) samt 1939-writerens rollback/apply/reversal-integration (`tests/integration/test-1939-v50-production-writer.R`); `test-reimport-writer.sql` dækker kun afvisninger. Plus egne guard-cases pr. oprindelse.
5. **Kollision** — kandidatpersonen er allerede accepteret for en anden persona i samme kilde; skal vises, ikke blokere. Test: Task 4 `collisions` i detalje-RPC'en og Task 8 komponent-test.

---

## File Structure

| Fil | Ansvar |
| --- | --- |
| `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | Tabeller, RPC'er, guard, RLS, asserts |
| `tests/sql/test-identity-candidates.sql` (ny) | Tabeller + writer-RPC |
| `tests/sql/test-identity-decision.sql` (ny) | `red_afgoer_source_persona` v2, guard pr. oprindelse, kvittering, funktionsflade, kildelås |
| `tests/sql/test-identity-cutover.sql` (ny) | Cutover-blokken lukker klientvejen i et prod-lignende katalog |
| `.claude/skills/daa-extract/scripts/test_identity_guard_static.py` (ny) | Ingen uguardet definition/grant nogetsteds i schema/migrationer |
| `tests/sql/test-identity-detail.sql` (ny) | Detalje- og kø-RPC |
| `packages/identity-candidates/` (ny workspace) | Frames, rangering, kalibrering, CLI; `sql/` med eksport-/skrive-scripts |
| `.claude/skills/daa-extract/scripts/decision_sheet_core.py` (ny) | Fælles hash-/orden-/SQL-hjælpere for token-ark |
| `.claude/skills/daa-extract/scripts/identity_decision_sheet.py` (ny) + test | Identitetsarket |
| `.claude/skills/daa-extract/scripts/interpretation_decision_sheet.py` | Bruger kernen (adfærd uændret) |
| `web/src/data/sourcePersona.ts`, `web/src/components/KildepersonaKo.tsx` + tests | Webkøen |
| `.github/workflows/ci.yml` | Nye tests i node-, python- og frisk-schema-trinnene |
| `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md` (ny), `status.md`, `docs/changelog.md` | Bevis og status |

---

### Task 0: Forudsætninger og baseline

**Files:** ingen.

- [ ] **Step 1: Aktivering og 4.5.**

```bash
grep -n -i 'trin 5' docs/decisions.md | head
git fetch origin && git log --oneline origin/main | grep -c 'interpretation_decision_sheet\|4.5' ; git show origin/main:.claude/skills/daa-extract/scripts/interpretation_decision_sheet.py > /dev/null && echo "4.5 i main"
```

Expected: en `BESLUTTET`-post, der aktiverer trin 5, og `4.5 i main`. Mangler en af dem: **STOP** — spørg projektejeren.

- [ ] **Step 2: Branch.** `git switch -c feat/151-identitetsvej docs/151-identitetsvej` (lokal gren, rebaset på `main` 2026-10-05; spec og plan med). Er `main` gået videre: `git rebase origin/main` først.
- [ ] **Step 3: Baseline.** Kør »Frisk testbase«, derefter:

```bash
for t in test-evidence-promotion test-reimport-writer test-reimport-legacy-migration test-interpretation-promotion-targets test-interpretation-control-classification test-transfer-fingerprint-digests test-transfer-baseline; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/$t.sql > /tmp/claude-501/base-$t.log 2>&1; echo "$t rc=$?"; done
psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/run-db-verify-disposable.sql > /tmp/claude-501/base-verify.log 2>&1; echo "verify rc=$?"
npm ci > /tmp/claude-501/npmci.log 2>&1; npm run test -w @daa/core > /tmp/claude-501/core.log 2>&1; echo "core rc=$?"
```

Expected: alle `rc=0`. Noter resultatet i ledgeren; et rødt baseline-trin er et fund før arbejdet, ikke efter.

---

### Task 1: Kandidattabellerne

**Files:**
- Modify: `schema.sql` (indsæt efter `private.source_persona_identity_event`-tabellen, der slutter ved `schema.sql:1479`)
- Modify: `db-migrations.sql` (ny sektion sidst i filen)
- Modify: `db-rls.sql:17-32` (master-arrayet)
- Modify: `db-verify.sql` (ny blok efter `$promotion_rule_verify$`)
- Create: `tests/sql/test-identity-candidates.sql`
- Modify: `.github/workflows/ci.yml` (frisk-schema-trinnet efter `test-interpretation-predicate.sql`, ca. linje 202)

**Interfaces:**
- Produces: `private.source_persona_identity_candidate_run(id uuid, run_seq bigint, source_id bigint, generator_version text, config jsonb, config_sha256 text, input_spec jsonb, input_sha256 text, candidates_sha256 text, persona_count int, candidate_count int, created_by uuid, created_by_name text, created_at timestamptz)` med `UNIQUE(source_id,input_sha256,config_sha256)`; **gældende kørsel** pr. kilde = højeste `run_seq`; `private.source_persona_identity_candidate(id uuid, run_id uuid, source_persona_id uuid, candidate_person_id bigint, rank int, score numeric, tier text, basis jsonb)`.

- [ ] **Step 1: Skriv den fejlende SQL-test** `tests/sql/test-identity-candidates.sql`:

```sql
-- Trin 5a, Task 1-2: kandidatlaget. Kør efter bootstrap, schema.sql, db-rls.sql og
-- migrationerne på en frisk base. Hver blok ruller sin fixture tilbage selv.

DO $identity_candidate_tables$
DECLARE v_table text; v_role text; v_state text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['source_persona_identity_candidate_run','source_persona_identity_candidate'] LOOP
    IF to_regclass(format('private.%I',v_table)) IS NULL THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: private.% mangler',v_table;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=format('private.%I',v_table)::regclass) THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: RLS er slået fra på %',v_table;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      v_state:=NULL;
      BEGIN
        EXECUTE format('SET LOCAL ROLE %I',v_role);
        EXECUTE format('SELECT 1 FROM private.%I LIMIT 1',v_table);
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
      END;
      EXECUTE 'SET LOCAL ROLE NONE';
      IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % kunne læse % (%)',v_role,v_table,v_state;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'OK: kandidattabellerne findes, har RLS og ingen API-adgang';
END $identity_candidate_tables$;

DO $identity_candidate_constraints$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a01';
  v_run uuid := '22000000-0000-0000-0000-000000005a01';
  v_persona uuid := '88000000-0000-0000-0000-000000005a01';
  v_cand_run uuid;
  v_state text;
BEGIN
  BEGIN
    INSERT INTO person(id,levende,privat,status) VALUES (-987655001,false,false,'5a fixture'),(-987655002,false,false,'5a fixture');
    INSERT INTO source(id,titel,import_key) VALUES (-987655001,'5a kandidat','verify:5a:cand');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655001,'5a-run','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_persona,-987655001,'5a-persona',v_run);
    INSERT INTO private.source_persona_identity_candidate_run(
      source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name
    ) VALUES (-987655001,'test','{}',repeat('a',64),'{"mode":"undecided"}',repeat('b',64),repeat('c',64),1,1,v_actor,'test') RETURNING id INTO v_cand_run;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_cand_run,v_persona,-987655001,1,0.91,'auto','{"signals":["name"]}');
    -- rang 0, score over 1, ukendt tier og tom basis skal alle afvises
    FOREACH v_state IN ARRAY ARRAY['rank','score','tier','basis'] LOOP
      BEGIN
        INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
          VALUES (v_cand_run,v_persona,-987655002,
                  CASE WHEN v_state='rank' THEN 0 ELSE 2 END,
                  CASE WHEN v_state='score' THEN 1.5 ELSE 0.5 END,
                  CASE WHEN v_state='tier' THEN 'x' ELSE 'none' END,
                  CASE WHEN v_state='basis' THEN '{}'::jsonb ELSE '{"signals":[]}'::jsonb END);
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % blev accepteret',v_state;
      EXCEPTION WHEN check_violation THEN NULL;
      END;
    END LOOP;
    -- append-only: UPDATE, DELETE og TRUNCATE afvises af triggeren (ikke af en FK eller rettighed)
    FOREACH v_state IN ARRAY ARRAY['update','delete','truncate','truncate_run'] LOOP
      BEGIN
        IF v_state='update' THEN UPDATE private.source_persona_identity_candidate SET score=0.1 WHERE run_id=v_cand_run;
        ELSIF v_state='delete' THEN DELETE FROM private.source_persona_identity_candidate WHERE run_id=v_cand_run;
        ELSIF v_state='truncate' THEN TRUNCATE private.source_persona_identity_candidate;
        ELSE TRUNCATE private.source_persona_identity_candidate_run CASCADE;
        END IF;
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % lykkedes',v_state;
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'EVIDENCE_APPEND_ONLY:%' THEN RAISE; END IF;
      END;
    END LOOP;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_CONSTRAINTS';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_CANDIDATE_CONSTRAINTS' THEN
      RAISE NOTICE 'OK: kandidatrækkernes constraints og append-only holder';
    ELSE RAISE; END IF;
  END;
END $identity_candidate_constraints$;
```

- [ ] **Step 2: Kør den** (Frisk testbase først): `psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/test-identity-candidates.sql`
Expected: FAIL `IDENTITY_CANDIDATE_TEST_FAILED: private.source_persona_identity_candidate_run mangler`.

- [ ] **Step 3: Tabellerne i `schema.sql`** (efter linje 1475):

```sql
-- Trin 5a: maskinens identitetskandidater. Forslag og afgørelse holdes adskilt:
-- source_persona_identity forbliver uden mål for 'proposed'; kandidaterne bor her.
CREATE TABLE private.source_persona_identity_candidate_run (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Gældende kørsel = højeste run_seq pr. kilde (tidsstempler kan være ens).
  run_seq            bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  source_id          bigint NOT NULL REFERENCES public.source(id),
  generator_version  text NOT NULL CHECK (btrim(generator_version)<>''),
  config             jsonb NOT NULL CHECK (jsonb_typeof(config)='object'),
  config_sha256      text NOT NULL CHECK (config_sha256 ~ '^[0-9a-f]{64}$'),
  input_spec         jsonb NOT NULL CHECK (jsonb_typeof(input_spec)='object'),
  input_sha256       text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
  candidates_sha256  text NOT NULL CHECK (candidates_sha256 ~ '^[0-9a-f]{64}$'),
  persona_count      integer NOT NULL CHECK (persona_count>=0),
  candidate_count    integer NOT NULL CHECK (candidate_count>=0),
  created_by         uuid NOT NULL,
  created_by_name    text NOT NULL CHECK (btrim(created_by_name)<>''),
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (source_id,input_sha256,config_sha256)
);

CREATE TABLE private.source_persona_identity_candidate (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               uuid NOT NULL REFERENCES private.source_persona_identity_candidate_run(id),
  source_persona_id    uuid NOT NULL REFERENCES private.source_persona(id),
  candidate_person_id  bigint NOT NULL REFERENCES public.person(id),
  rank                 integer NOT NULL CHECK (rank>=1),
  score                numeric NOT NULL CHECK (score>=0 AND score<=1),
  tier                 text NOT NULL CHECK (tier IN ('auto','review','none')),
  basis                jsonb NOT NULL CHECK (jsonb_typeof(basis)='object' AND basis<>'{}'::jsonb),
  UNIQUE (run_id,source_persona_id,candidate_person_id),
  UNIQUE (run_id,source_persona_id,rank)
);
CREATE INDEX source_persona_identity_candidate_persona_idx
  ON private.source_persona_identity_candidate(source_persona_id,run_id);
```

Tilføj denne blok lige efter tabellerne (den eksisterende løkke ved `schema.sql:1032` ligger før tabellerne og kan ikke genbruges); den giver samme to triggere som løkken — rækketrigger og `TRUNCATE`-statementtrigger:

```sql
DO $$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['source_persona_identity_candidate_run','source_persona_identity_candidate'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON private.%I','trg_'||v_table||'_append_only',v_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation()','trg_'||v_table||'_append_only',v_table);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON private.%I','trg_'||v_table||'_append_only_truncate',v_table);
    EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation()','trg_'||v_table||'_append_only_truncate',v_table);
    EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',v_table);
  END LOOP;
END $$;
```

- [ ] **Step 4: Samme i `db-migrations.sql`** — ny sektion sidst i filen med overskriften `-- Trin 5a (#151): identitetskandidater`. Brug de to `CREATE TABLE`-blokke fra Step 3 med `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, og DO-blokken fra Step 3 ordret.

- [ ] **Step 5: `db-rls.sql:17-32`** — tilføj `'source_persona_identity_candidate_run','source_persona_identity_candidate',` i master-arrayet lige efter `'source_persona_identity','source_persona_identity_event',`.

- [ ] **Step 6: `db-verify.sql`** — ny blok efter `$promotion_rule_verify$`:

```sql
DO $identity_candidate_verify$
DECLARE v_required text[] := ARRAY['source_persona_identity_candidate_run','source_persona_identity_candidate'];
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(v_required) t WHERE to_regclass(format('private.%I',t)) IS NULL) THEN
    RAISE EXCEPTION 'FEJL: #151 kandidatlaget mangler';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname=ANY(v_required)
       AND (NOT c.relrowsecurity
         OR has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('authenticated',c.oid,'SELECT')
         OR has_table_privilege('anon',c.oid,'INSERT') OR has_table_privilege('authenticated',c.oid,'INSERT'))
  ) THEN
    RAISE EXCEPTION 'FEJL: #151 kandidatlaget har API-rettigheder eller mangler RLS';
  END IF;
  RAISE NOTICE 'OK: #151 kandidatlaget findes med RLS og uden API-rettigheder';
END $identity_candidate_verify$;
```

- [ ] **Step 7: Kør igen** — ny Frisk testbase, derefter testen og db-verify:

```bash
psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/test-identity-candidates.sql 2>&1 | grep -E 'OK:|FAILED|ERROR'
psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/run-db-verify-disposable.sql > /tmp/claude-501/v1.log 2>&1; echo "verify rc=$?"; grep -c 'OK: #151' /tmp/claude-501/v1.log
```

Expected: to `OK:`-linjer, `verify rc=0`, `1`.

- [ ] **Step 8: CI** — i `.github/workflows/ci.yml`, trinnet »Evidens-hardening på frisk schema-sti«, tilføj efter `psql -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-predicate.sql`:

```yaml
          psql -v ON_ERROR_STOP=1 -f tests/sql/test-identity-candidates.sql
```

- [ ] **Step 9: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-identity-candidates.sql .github/workflows/ci.yml
git commit -m "feat(151): kandidattabeller for identitetsforslag med RLS og append-only"
```

---

### Task 2: Serverbygget input og writer-RPC for kandidatkørsler

**Files:**
- Modify: `schema.sql` (efter `red_afgoer_source_persona`, før den fælles REVOKE/GRANT ved `schema.sql:8303`), `db-migrations.sql` (5a-sektionen — nye objekter; intet eksisterende omdefineres her), `db-rls.sql:672-748` (allow-list)
- Modify: `tests/sql/test-identity-candidates.sql`

**Interfaces:**
- Consumes: tabellerne fra Task 1; `public.red_match_personer()` (rollegatet, returnerer `jsonb` med arrays `persons`, `facts`, `concs`, `assertions`, `extIds`).
- Produces: `private.identity_candidate_input(p_source_id bigint, p_input_spec jsonb) RETURNS jsonb` = `{personas: PersonaExportRow[], persons: MatchPayload}`, deterministisk (hvert array sorteret efter elementets tekst `COLLATE "C"`). `p_input_spec` er præcis `{"mode":"undecided"}` eller `{"mode":"list","persona_ids":[uuid,…]}` (ikke-tom, unik); ellers `IDENTITY_CANDIDATE_INPUT_SPEC_INVALID`.
- Produces: `red_identity_candidate_input(p_source_id bigint, p_input_spec jsonb) RETURNS jsonb` = `{input_spec, input_sha256, input}`; rollegate; `input_sha256 = private.reimport_canonical_json_sha256(input)`.
- Produces: `red_record_identity_candidates(p_run jsonb, p_candidates jsonb) RETURNS uuid`. `p_run` = præcis `{source_id:int, generator_version:text, input_spec:object, input_sha256:hex64, config:object}`. `p_candidates` = array af `{source_persona_id:uuid, candidate_person_id:int, rank:int, score:number, tier:'auto'|'review'|'none', basis:object}`. Writeren tager `pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||source_id,0))` (eksklusiv), genberegner inputtet og kræver `input_sha256` lig (`IDENTITY_CANDIDATE_INPUT_DRIFT`), udleder `persona_count` af inputtet, kræver hver kandidats persona og person i inputtet, beregner `config_sha256` og `candidates_sha256` selv. Idempotent via `INSERT … ON CONFLICT (source_id,input_sha256,config_sha256) DO NOTHING` + sammenligning af `candidates_sha256` (andre kandidater ⇒ `IDENTITY_CANDIDATE_RUN_CONFLICT`). Fejlkoder i øvrigt: `EVIDENCE_ROLE_FORBIDDEN`, `IDENTITY_CANDIDATE_RUN_INVALID`, `IDENTITY_CANDIDATE_PERSONA_NOT_IN_INPUT`, `IDENTITY_CANDIDATE_PERSON_NOT_IN_INPUT`, `IDENTITY_CANDIDATE_RANK_GAP`.

- [ ] **Step 1: Tilføj de fejlende tests** sidst i `tests/sql/test-identity-candidates.sql`. Første linje i filen (over alle blokke) bliver `CREATE EXTENSION IF NOT EXISTS dblink;` — låsetesten må ikke springes over, hvis dblink mangler.

```sql
DO $identity_candidate_writer$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a02';
  v_run uuid := '22000000-0000-0000-0000-000000005a02';
  v_p1 uuid := '88000000-0000-0000-0000-000000005a21';
  v_p2 uuid := '88000000-0000-0000-0000-000000005a22';
  v_other uuid := '88000000-0000-0000-0000-000000005a23';
  v_spec jsonb := '{"mode":"undecided"}';
  v_in jsonb; v_meta jsonb; v_cands jsonb; v_id uuid; v_id2 uuid; v_err text; v_state text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-writer@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a writer','5a-writer@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655021,false,false,'5a'),(-987655022,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655021,'5a A','verify:5a:a'),(-987655022,'5a B','verify:5a:b');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655021,'5a-run-w','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_p1,-987655021,'5a-p1',v_run),(v_p2,-987655021,'5a-p2',v_run),(v_other,-987655022,'5a-other',v_run);

    -- uden redaktionsrolle
    BEGIN PERFORM red_identity_candidate_input(-987655021,v_spec);
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: input uden rolle lykkedes';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_ROLE_FORBIDDEN' THEN RAISE; END IF; END;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    v_in := red_identity_candidate_input(-987655021,v_spec);
    IF v_in->'input' IS NULL OR jsonb_array_length(v_in->'input'->'personas')<>2
       OR v_in->>'input_sha256' !~ '^[0-9a-f]{64}$'
       OR v_in->>'input_sha256'<>(red_identity_candidate_input(-987655021,v_spec)->>'input_sha256') THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: input er ikke deterministisk eller forkert afgrænset (%)',v_in->'input'->'personas';
    END IF;
    v_meta := jsonb_build_object('source_id',-987655021,'generator_version','test-1','input_spec',v_spec,
                                 'input_sha256',v_in->>'input_sha256','config',jsonb_build_object('topK',3));
    -- samme person er kandidat 1 for begge personas: ikke-injektivt er tilladt; p2 får kun én kandidat
    v_cands := jsonb_build_array(
      jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655021,'rank',1,'score',0.93,'tier','auto','basis',jsonb_build_object('signals',jsonb_build_array('name','birth'))),
      jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655022,'rank',2,'score',0.71,'tier','review','basis',jsonb_build_object('signals',jsonb_build_array('name'))),
      jsonb_build_object('source_persona_id',v_p2,'candidate_person_id',-987655021,'rank',1,'score',0.8,'tier','review','basis',jsonb_build_object('signals',jsonb_build_array('name'))));
    v_id := red_record_identity_candidates(v_meta,v_cands);
    v_id2 := red_record_identity_candidates(v_meta,v_cands);
    IF v_id IS DISTINCT FROM v_id2 THEN RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: ikke idempotent'; END IF;

    FOR v_err IN SELECT unnest(ARRAY['conflict','foreign','person','gap','keys','count','hash','spec']) LOOP
      BEGIN
        IF v_err='conflict' THEN
          PERFORM red_record_identity_candidates(v_meta, v_cands - 2);
        ELSIF v_err='foreign' THEN   -- persona fra en anden kilde er ikke i inputtet
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":4}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_other,'candidate_person_id',-987655021,'rank',1,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='person' THEN    -- person, der ikke findes i inputtets personmængde
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":5}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-1,'rank',1,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='gap' THEN
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":6}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655021,'rank',2,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='keys' THEN
          PERFORM red_record_identity_candidates(v_meta || '{"extra":1}', v_cands);
        ELSIF v_err='count' THEN     -- klienten må ikke selv angive antal
          PERFORM red_record_identity_candidates(v_meta || '{"persona_count":99}', v_cands);
        ELSIF v_err='hash' THEN      -- falsk input-hash
          PERFORM red_record_identity_candidates(v_meta || jsonb_build_object('input_sha256',repeat('e',64)), v_cands);
        ELSE
          PERFORM red_record_identity_candidates(v_meta || '{"input_spec":{"mode":"alle"}}', v_cands);
        END IF;
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % blev accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        -- præcis den forventede kode pr. tilfælde, så et tilfælde ikke kan bestå på en andens fejl
        IF SQLERRM IS DISTINCT FROM (CASE v_err
             WHEN 'conflict' THEN 'IDENTITY_CANDIDATE_RUN_CONFLICT' WHEN 'foreign' THEN 'IDENTITY_CANDIDATE_PERSONA_NOT_IN_INPUT'
             WHEN 'person' THEN 'IDENTITY_CANDIDATE_PERSON_NOT_IN_INPUT' WHEN 'gap' THEN 'IDENTITY_CANDIDATE_RANK_GAP'
             WHEN 'keys' THEN 'IDENTITY_CANDIDATE_RUN_INVALID' WHEN 'count' THEN 'IDENTITY_CANDIDATE_RUN_INVALID'
             WHEN 'hash' THEN 'IDENTITY_CANDIDATE_INPUT_DRIFT' ELSE 'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID' END) THEN RAISE; END IF;
      END;
    END LOOP;
    RESET ROLE;

    -- ændret DB-input efter eksport: en ny persona i kilden ⇒ drift
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES ('88000000-0000-0000-0000-000000005a24',-987655021,'5a-p4',v_run);
    SET LOCAL ROLE authenticated;
    BEGIN PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":7}}', v_cands);
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: forældet input accepteret';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'IDENTITY_CANDIDATE_INPUT_DRIFT' THEN RAISE; END IF; END;
    RESET ROLE;

    IF (SELECT persona_count FROM private.source_persona_identity_candidate_run WHERE id=v_id)<>2
       OR (SELECT candidate_count FROM private.source_persona_identity_candidate_run WHERE id=v_id)<>3
       OR (SELECT count(*) FROM private.source_persona_identity_candidate WHERE run_id=v_id)<>3
       OR (SELECT config_sha256 FROM private.source_persona_identity_candidate_run WHERE id=v_id)
          <>private.reimport_canonical_json_sha256('{"topK":3}'::jsonb) THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: serverens antal eller hashes er forkerte';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_WRITER';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_CANDIDATE_WRITER' THEN
      RAISE NOTICE 'OK: kandidat-writeren genberegner input, udleder antal, er idempotent og ikke-injektiv, og afviser konflikt, fremmed persona/person, ranghul, ukendte nøgler, falsk hash og drift';
    ELSE RAISE; END IF;
  END;
END $identity_candidate_writer$;

-- Writeren tager kildelåsen: holder en anden forbindelse den, venter writeren (her: timeout 55P03).
DO $identity_candidate_lock$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a09';
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_state text;
BEGIN
  PERFORM dblink_connect('cand_lock',v_conn);
  PERFORM dblink_exec('cand_lock','BEGIN');
  PERFORM dblink_exec('cand_lock','SELECT pg_advisory_xact_lock(hashtextextended(''daa-identity-candidates:-987655021'',0))');
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-lock@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a lock','5a-lock@test.invalid');
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_record_identity_candidates(
        '{"source_id":-987655021,"generator_version":"t","input_spec":{"mode":"undecided"},"input_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","config":{}}','[]');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_LOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_5A_CANDIDATE_LOCK' THEN
      PERFORM dblink_exec('cand_lock','ROLLBACK'); PERFORM dblink_disconnect('cand_lock'); RAISE;
    END IF;
  END;
  PERFORM dblink_exec('cand_lock','ROLLBACK'); PERFORM dblink_disconnect('cand_lock');
  IF v_state IS DISTINCT FROM '55P03' THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: writeren ventede ikke på kildelåsen (%)',v_state;
  END IF;
  RAISE NOTICE 'OK: kandidat-writeren tager kildelåsen';
END $identity_candidate_lock$;
```

To samtidige, identiske writer-kald fra hver sin forbindelse skal give samme kørsel og én run-række (Codex runde 2). Fixturen skal være committet for at være synlig for begge forbindelser; oprydningen følger `db-verify.sql:3100-3130` (`session_replication_role=replica` for append-only-rækkerne):

```sql
DO $identity_candidate_concurrent$
DECLARE
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_fix text := $fix$
    INSERT INTO auth.users(id,email) VALUES ('11000000-0000-0000-0000-000000005a07','5a-conc@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES ('11000000-0000-0000-0000-000000005a07','redaktion','5a conc','5a-conc@test.invalid');
    INSERT INTO source(id,titel,import_key) VALUES (-987655071,'5a C','verify:5a:c');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES ('22000000-0000-0000-0000-000000005a07',-987655071,'5a-run-c','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES ('88000000-0000-0000-0000-000000005a71',-987655071,'5a-c1','22000000-0000-0000-0000-000000005a07');
  $fix$;
  v_cleanup text := $cl$
    SET session_replication_role=replica;
    DELETE FROM private.source_persona_identity_candidate c USING private.source_persona_identity_candidate_run r
     WHERE c.run_id=r.id AND r.source_id=-987655071;
    DELETE FROM private.source_persona_identity_candidate_run WHERE source_id=-987655071;
    DELETE FROM private.source_persona WHERE source_id=-987655071;
    DELETE FROM private.extraction_run WHERE id='22000000-0000-0000-0000-000000005a07';
    DELETE FROM source WHERE id=-987655071;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000005a07';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000005a07';
    SET session_replication_role=origin;
  $cl$;
  v_role text := $r$SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000005a07',false); SET ROLE authenticated;$r$;
  v_hash text; v_call text; v_a text; v_b text; v_runs int;
BEGIN
  PERFORM dblink_connect('cc_setup',v_conn);
  PERFORM dblink_exec('cc_setup',v_cleanup);
  PERFORM dblink_exec('cc_setup',v_fix);
  BEGIN
    PERFORM dblink_connect('cc_a',v_conn); PERFORM dblink_connect('cc_b',v_conn);
    PERFORM dblink_exec('cc_a',v_role); PERFORM dblink_exec('cc_b',v_role);
    SELECT h INTO v_hash FROM dblink('cc_a',$q$SELECT red_identity_candidate_input(-987655071,'{"mode":"undecided"}')->>'input_sha256'$q$) AS t(h text);
    v_call := format($q$SELECT red_record_identity_candidates(jsonb_build_object('source_id',-987655071,'generator_version','t',
      'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',%L,'config','{"topK":3}'::jsonb),'[]'::jsonb)::text$q$,v_hash);
    PERFORM dblink_exec('cc_a','BEGIN'); PERFORM dblink_exec('cc_b','BEGIN');
    PERFORM dblink_send_query('cc_a',v_call);
    PERFORM dblink_send_query('cc_b',v_call);            -- venter på A's kildelås
    SELECT r INTO v_a FROM dblink_get_result('cc_a') AS t(r text); PERFORM * FROM dblink_get_result('cc_a') AS t(r text);
    PERFORM dblink_exec('cc_a','COMMIT');
    SELECT r INTO v_b FROM dblink_get_result('cc_b') AS t(r text); PERFORM * FROM dblink_get_result('cc_b') AS t(r text);
    PERFORM dblink_exec('cc_b','COMMIT');
    SELECT count(*) INTO v_runs FROM private.source_persona_identity_candidate_run WHERE source_id=-987655071;
    IF v_a IS NULL OR v_a IS DISTINCT FROM v_b OR v_runs<>1 THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: samtidige kald gav % og % (% kørsler)',v_a,v_b,v_runs;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    BEGIN PERFORM dblink_disconnect('cc_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('cc_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM dblink_exec('cc_setup',v_cleanup); PERFORM dblink_disconnect('cc_setup');
    RAISE;
  END;
  PERFORM dblink_disconnect('cc_a'); PERFORM dblink_disconnect('cc_b');
  PERFORM dblink_exec('cc_setup',v_cleanup); PERFORM dblink_disconnect('cc_setup');
  RAISE NOTICE 'OK: samtidige identiske writer-kald giver samme kørsel og én run-række';
END $identity_candidate_concurrent$;
```

- [ ] **Step 2: Kør** (Frisk testbase). Expected: FAIL `function red_identity_candidate_input(integer, jsonb) does not exist`.

- [ ] **Step 3: Implementér** (ordret i `schema.sql` og `db-migrations.sql`). Persona-delen bygger generatorens persona-rækker (`PersonaExportRow`, Task 5) på serveren, så writeren kan genberegne dem:

```sql
CREATE OR REPLACE FUNCTION private.identity_candidate_input(p_source_id bigint,p_input_spec jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_mode text; v_ids uuid[]; v_personas jsonb; v_match jsonb; v_persons jsonb;
BEGIN
  v_mode:=p_input_spec->>'mode';
  IF jsonb_typeof(p_input_spec)<>'object' OR v_mode NOT IN ('undecided','list')
     OR (v_mode='undecided' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_input_spec) k)<>ARRAY['mode'])
     OR (v_mode='list' AND ((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_input_spec) k)<>ARRAY['mode','persona_ids']
                            OR jsonb_typeof(p_input_spec->'persona_ids')<>'array'
                            OR jsonb_array_length(p_input_spec->'persona_ids')=0)) THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID';
  END IF;
  IF v_mode='list' THEN
    SELECT array_agg(DISTINCT e::uuid) INTO v_ids FROM jsonb_array_elements_text(p_input_spec->'persona_ids') e;
    IF cardinality(v_ids)<>jsonb_array_length(p_input_spec->'persona_ids') THEN RAISE EXCEPTION 'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID'; END IF;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.source_persona_id COLLATE "C"),'[]'::jsonb) INTO v_personas FROM (
    SELECT p.id::text AS source_persona_id,
           coalesce(nm.v, men.v) AS name,
           CASE WHEN nm.v IS NOT NULL THEN nm.origin WHEN men.v IS NOT NULL THEN 'mention' END AS name_origin,
           b.v AS birth_raw, b.origin AS birth_origin, d.v AS death_raw, d.origin AS death_origin
      FROM private.source_persona p
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=p.id
      LEFT JOIN LATERAL (SELECT ic.value #>> '{}' v, ic.status||'_interpretation' origin FROM private.interpretation_current ic
                          WHERE ic.source_persona_id=p.id AND ic.predicate='person.name' AND ic.status IN ('accepted','proposed')
                          ORDER BY (ic.status='accepted') DESC, ic.confidence DESC NULLS LAST, ic.id LIMIT 1) nm ON true
      LEFT JOIN LATERAL (SELECT sm.verbatim_text v FROM private.source_persona_mention spm
                          JOIN private.source_mention sm ON sm.id=spm.mention_id
                          WHERE spm.persona_id=p.id AND sm.mention_kind='person' ORDER BY spm.ordinal LIMIT 1) men ON true
      LEFT JOIN LATERAL (SELECT ic.value #>> '{}' v, ic.status||'_interpretation' origin FROM private.interpretation_current ic
                          WHERE ic.source_persona_id=p.id AND ic.predicate='person.birth' AND ic.status IN ('accepted','proposed')
                          ORDER BY (ic.status='accepted') DESC, ic.confidence DESC NULLS LAST, ic.id LIMIT 1) b ON true
      LEFT JOIN LATERAL (SELECT ic.value #>> '{}' v, ic.status||'_interpretation' origin FROM private.interpretation_current ic
                          WHERE ic.source_persona_id=p.id AND ic.predicate='person.death' AND ic.status IN ('accepted','proposed')
                          ORDER BY (ic.status='accepted') DESC, ic.confidence DESC NULLS LAST, ic.id LIMIT 1) d ON true
     WHERE p.source_id=p_source_id
       AND ((v_mode='undecided' AND (i.source_persona_id IS NULL OR i.decision_status='proposed'))
         OR (v_mode='list' AND p.id=ANY(v_ids)))
  ) x;
  IF v_mode='list' AND jsonb_array_length(v_personas)<>cardinality(v_ids) THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID';   -- id uden for kilden eller ukendt
  END IF;
  v_match:=public.red_match_personer();
  -- Sortér hvert array efter elementets tekst: red_match_personer lover ingen orden.
  SELECT coalesce(jsonb_object_agg(k.key,(SELECT coalesce(jsonb_agg(e ORDER BY e::text COLLATE "C"),'[]'::jsonb)
                                           FROM jsonb_array_elements(k.value) e)),'{}'::jsonb)
    INTO v_persons FROM jsonb_each(v_match) k WHERE jsonb_typeof(k.value)='array';
  RETURN jsonb_build_object('personas',v_personas,'persons',v_persons);
END $$;
REVOKE ALL ON FUNCTION private.identity_candidate_input(bigint,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION red_identity_candidate_input(p_source_id bigint,p_input_spec jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_input jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v_input:=private.identity_candidate_input(p_source_id,p_input_spec);
  RETURN jsonb_build_object('input_spec',p_input_spec,'input_sha256',private.reimport_canonical_json_sha256(v_input),'input',v_input);
END $$;
REVOKE ALL ON FUNCTION red_identity_candidate_input(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_identity_candidate_input(bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION red_record_identity_candidates(p_run jsonb,p_candidates jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_actor_name text; v_source bigint; v_input jsonb; v_cand_hash text; v_config_hash text;
  v_run uuid; v_existing text;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF jsonb_typeof(p_run)<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_run) k)
        <> ARRAY['config','generator_version','input_sha256','input_spec','source_id']
     OR coalesce(p_run->>'input_sha256','') !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(p_run->>'generator_version'),'') IS NULL
     OR jsonb_typeof(p_run->'config')<>'object' OR jsonb_typeof(p_run->'source_id')<>'number'
     OR jsonb_typeof(p_candidates)<>'array' THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_RUN_INVALID';
  END IF;
  v_source:=(p_run->>'source_id')::bigint;
  -- Eksklusiv kildelås: afgørelses-RPC'en tager den delt (Task 3), så en ny kørsel
  -- ikke kan indsættes mellem en afgørelses aktualitetskontrol og dens commit.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  v_input:=private.identity_candidate_input(v_source,p_run->'input_spec');
  IF private.reimport_canonical_json_sha256(v_input)<>p_run->>'input_sha256' THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_INPUT_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_candidates) c
              WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_input->'personas') pe
                                 WHERE pe->>'source_persona_id'=c->>'source_persona_id')) THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_PERSONA_NOT_IN_INPUT';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_candidates) c
              WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_input->'persons'->'persons') pp
                                 WHERE (pp->>'id')=(c->>'candidate_person_id'))) THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_PERSON_NOT_IN_INPUT';
  END IF;
  -- Rangerne pr. persona skal være 1..n uden huller.
  IF EXISTS (SELECT 1 FROM (
      SELECT c->>'source_persona_id' pid, count(*) n, max((c->>'rank')::int) mx, min((c->>'rank')::int) mn
        FROM jsonb_array_elements(p_candidates) c GROUP BY 1) g
     WHERE g.mn<>1 OR g.mx<>g.n) THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_RANK_GAP';
  END IF;
  v_cand_hash:=private.reimport_canonical_json_sha256(p_candidates);
  v_config_hash:=private.reimport_canonical_json_sha256(p_run->'config');
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;

  INSERT INTO private.source_persona_identity_candidate_run(
    source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,
    persona_count,candidate_count,created_by,created_by_name
  ) VALUES (
    v_source,p_run->>'generator_version',p_run->'config',v_config_hash,p_run->'input_spec',p_run->>'input_sha256',v_cand_hash,
    jsonb_array_length(v_input->'personas'),jsonb_array_length(p_candidates),v_actor,v_actor_name
  ) ON CONFLICT (source_id,input_sha256,config_sha256) DO NOTHING
  RETURNING id INTO v_run;
  IF v_run IS NULL THEN
    SELECT id,candidates_sha256 INTO v_run,v_existing FROM private.source_persona_identity_candidate_run
     WHERE source_id=v_source AND input_sha256=p_run->>'input_sha256' AND config_sha256=v_config_hash;
    IF v_existing<>v_cand_hash THEN RAISE EXCEPTION 'IDENTITY_CANDIDATE_RUN_CONFLICT'; END IF;
    RETURN v_run;
  END IF;
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
  SELECT v_run,(c->>'source_persona_id')::uuid,(c->>'candidate_person_id')::bigint,(c->>'rank')::int,
         (c->>'score')::numeric,c->>'tier',c->'basis'
    FROM jsonb_array_elements(p_candidates) c;
  RETURN v_run;
END $$;
REVOKE ALL ON FUNCTION red_record_identity_candidates(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_record_identity_candidates(jsonb,jsonb) TO authenticated;
```

Fejler den gyldige kørsel på `IDENTITY_CANDIDATE_PERSON_NOT_IN_INPUT`, filtrerer `red_match_personer()` fixturens personer fra: læs dens `WHERE` og tilpas fixturens personrækker (ikke writeren), og notér det som ruling.

Før Step 5: kontrollér, at nøglen for person-id i `red_match_personer()`'s `persons`-array hedder `id` (`grep -n "'persons'" schema.sql` omkring `schema.sql:7974`). Hedder den noget andet, ret `pp->>'id'` og notér det som ruling.

- [ ] **Step 4: Allow-list** — `db-rls.sql`, arrayet der starter linje 673: tilføj alfabetisk `'public.red_identity_candidate_input(bigint,jsonb)',` og `'public.red_record_identity_candidates(jsonb,jsonb)',`.

- [ ] **Step 5: Kør igen** (ny Frisk testbase): testfilen + db-verify.
Expected: fem `OK:`-linjer fra testfilen (tabeller, constraints, writer, lås, samtidighed); `verify rc=0`.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql tests/sql/test-identity-candidates.sql
git commit -m "feat(151): serverbygget kandidat-input og writer-RPC — genberegnet hash, kildelås, idempotent"
```

---

### Task 3: Afgørelsens udgange og den strukturelle guard

Spec §4.2 (revideret) og §14–15. Kernen bliver privat med en eksplicit oprindelse; den offentlige kerne forsvinder; alle definitioner erstattes **på deres eksisterende plads**, og en **cutover-blok øverst** i `db-migrations.sql` lukker klientvejen til den allerede installerede gamle kerne og femarguments-wrapper, før resten af filen kører (Codex runde 1 og 2, BLOCKER 2). `person_create` bindes til en oprettelseskvittering, og 149b kører videre som `legacy_match` med kernens egen 1:1-kontrol (projektejerens valg 2026-09-24).

**Kaldere (målt 2026-09-24 — genmål med `grep -n "red_decide_source_persona_identity" schema.sql db-migrations.sql` før Step 3; et afvigende sæt er STOP):**

| Fil:linje (funktion) | Art | Ny oprindelse |
| --- | --- | --- |
| `schema.sql:8103` / `db-migrations.sql:6472` (kernen selv) | — | bliver `private.decide_source_persona_identity(…, p_origin)` |
| `schema.sql:8296` / `db-migrations.sql:7187` (`red_afgoer_source_persona`) | menneske | `'human'` |
| `schema.sql:3146` / `db-migrations.sql:11811`, `:12012` (`red_apply_reimport_person_create`, alle versioner) | opretter selv personen | `'person_create'` |
| `db-migrations.sql:7660` (`red_apply_1939_v50_person_create`) | opretter selv personen | `'person_create'` |
| `schema.sql:3256` / `db-migrations.sql:16834` (`private.migrate_legacy_narrative_record`, 149b) | fast 1:1-kobling via `person_external_id` | `'legacy_match'` |
| `schema.sql:4292` / `db-migrations.sql:12338` (`red_reverse_reimport`) | fortrydelse | `'reversal'` |
| `db-migrations.sql:7667` (`red_reverse_1939_v50_reimport`) | fortrydelse | `'reversal'` |
| `db-migrations.sql:8066`, `:8246` (senere versioner af `red_reverse_1939_v50_reimport`) | fortrydelse (`superseded` + `reversed_batch_id`) | `'reversal'` |
| `schema.sql:8305`, `:8312`; `db-migrations.sql:6531`, `:6535`, `:18272`; `db-rls.sql:677`; `db-verify.sql:2951`, `:3749`, `:3759` | grants/regprocedure-lister/asserts | fjernes eller skiftes til den private signatur (Step 6) |
| `db-verify.sql` 7 direkte + 4 dblink-kald, `tests/sql/test-evidence-promotion.sql:298` | testfixtures (superbruger) | `private.…(…, 'human')` med `basis: web_detail` (Step 7) |

**Files:**
- Modify: `schema.sql` og `db-migrations.sql` på linjerne i tabellen (erstatning på stedet); `db-migrations.sql`'s 5a-sektion får **ingen** omdefinition af eksisterende objekter
- Modify: `db-rls.sql:17-32` (master-array: `person_create_receipt`), `:674`, `:677`; `db-verify.sql` (Step 6–7); `tests/sql/test-evidence-promotion.sql:298`
- Create: `tests/sql/test-identity-decision.sql`, `tests/sql/test-identity-cutover.sql`, `.claude/skills/daa-extract/scripts/test_identity_guard_static.py`
- Modify: `.github/workflows/ci.yml` (frisk-schema-trinnet og pytest-listen)

**Interfaces:**
- Consumes: kandidattabellerne (Task 1), kildelåsens nøgle `hashtextextended('daa-identity-candidates:'||source_id,0)` (Task 2).
- Produces: `private.decide_source_persona_identity(p_source_persona_id uuid, p_canonical_person_id bigint, p_expected_version integer, p_decision_status text, p_evidence jsonb, p_origin text) RETURNS integer` — ingen grants. `p_origin` ∈ `human` (kræver `basis` ∈ `web_detail|human_sheet`), `person_create` (kræver `accepted`, forventet version 0, `batch_id`, ingen `basis`, **og en oprettelseskvittering for netop personen i denne toptransaktion**, som forbruges), `legacy_match` (kræver `accepted`, forventet version 0, `authority='person_external_id'`, ingen `basis`, og at `person_external_id` er 1:1 mellem postnøglen og personen i personaens kilde), `reversal` (kræver `superseded`, `reversed_batch_id`, ingen `basis`); andet ⇒ `EVIDENCE_IDENTITY_ORIGIN_INVALID`; brud på kravene ⇒ `EVIDENCE_IDENTITY_BASIS_REQUIRED`; manglende kvittering ⇒ `EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING`.
- Produces: `private.person_create_receipt(person_id bigint PRIMARY KEY, xact_id xid8)` og `private.insert_person_with_receipt(p_staged boolean, p_visning_navn text) RETURNS bigint` (indsætter personen og kvitteringen med `pg_current_xact_id()` — toptransaktionens 64-bit id, ens i subtransaktioner); begge uden grants.
- Produces: `red_afgoer_source_persona(p_source_persona_id uuid, p_expected_version integer, p_action text, p_canonical_person_id bigint, p_note text, p_context jsonb DEFAULT '{}') RETURNS integer`. `p_action` ∈ `same|different|unresolved|new_person_needed`. `p_context` har kun nøglerne `basis` (`web_detail` default | `human_sheet`), `candidate_id` + `run_id` (altid sammen), og ved `human_sheet` `sheet_sha256`, `rows_sha256` (hex64) og `line` (>0). Tager den delte kildelås. Evidens: `{note, action, basis, [reason:'new_person_needed'], [candidate_id, run_id, candidate_rank], [sheet_sha256, rows_sha256, line]}`. Fejlkoder: `EVIDENCE_IDENTITY_DECISION_INVALID`, `EVIDENCE_IDENTITY_CANDIDATE_MISMATCH`, `EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE`.
- Den offentlige `red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)` og femarguments-`red_afgoer_source_persona(uuid,integer,text,bigint,text)` findes ikke efter migrationen.

- [ ] **Step 1: Skriv den statiske test** `.claude/skills/daa-extract/scripts/test_identity_guard_static.py` — den håndhæver, at ingen uguardet definition eller grant står **nogetsteds** i filerne (ikke kun i sluttilstanden):

```python
"""Trin 5a (#151): identitetskernen er privat, og hver kalder har en lovlig, allowlistet oprindelse.

Statisk, fordi db-migrations.sql ikke kører i én transaktion: en uguardet definition eller grant
nogetsteds i filen ville være aktiv under deployet, selv om sluttilstanden er rigtig. Mellemtilstanden
før de omskrevne linjer dækkes af cutover-blokken øverst (testet i test-identity-cutover.sql).
"""
from __future__ import annotations  # /usr/bin/python3 lokalt er 3.9; CI kører 3.11

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[4]
KERNE = "private.decide_source_persona_identity("
OPRINDELSER = ("human", "person_create", "legacy_match", "reversal")
CUTOVER = re.compile(r"-- BEGIN 5a-cutover.*?-- END 5a-cutover", re.S)
# Eksakt allowlist (fil, omsluttende funktion, oprindelse) -> antal kald. Målt 2026-09-24.
# En ny kalder kræver en ændring her OG en beslutning (spec §4.2) — aldrig bare en ny linje.
ALLOWLIST = {
    ("schema.sql", "red_afgoer_source_persona", "human"): 1,
    ("schema.sql", "red_apply_reimport_person_create", "person_create"): 1,
    ("schema.sql", "migrate_legacy_narrative_record", "legacy_match"): 1,
    ("schema.sql", "red_reverse_reimport", "reversal"): 1,
    ("db-migrations.sql", "red_afgoer_source_persona", "human"): 1,
    ("db-migrations.sql", "red_apply_1939_v50_person_create", "person_create"): 1,
    ("db-migrations.sql", "red_apply_reimport_person_create", "person_create"): 2,
    ("db-migrations.sql", "migrate_legacy_narrative_record", "legacy_match"): 1,
    ("db-migrations.sql", "red_reverse_1939_v50_reimport", "reversal"): 3,
    ("db-migrations.sql", "red_reverse_reimport", "reversal"): 1,
}


def _uden_kommentarer(s: str) -> str:
    return re.sub(r"--[^\n]*", "", s)


def _tekst(navn: str) -> str:
    return _uden_kommentarer((ROOT / navn).read_text(encoding="utf-8"))


def _uden_cutover(raa: str) -> str:
    """Skær cutover-blokken ud af RÅTEKSTEN og strip derefter kommentarer. Rækkefølgen er bærende:
    blokkens markører er selv kommentarer og forsvinder, hvis der strippes først (Codex 2026-10-05)."""
    return _uden_kommentarer(CUTOVER.sub("", raa))


def offentlig_kerne_uden_for_cutover(raa: str) -> list[str]:
    s = _uden_cutover(raa)
    fund = []
    for m in re.finditer(r"red_decide_source_persona_identity\(", s):
        linje = s[s.rfind("\n", 0, m.start()) + 1:s.find("\n", m.start())]
        if "DROP FUNCTION IF EXISTS public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)" not in linje:
            fund.append(linje.strip()[:120])
    return fund


def femarguments_wrapper_uden_for_cutover(raa: str) -> bool:
    s = _uden_cutover(raa).replace("DROP FUNCTION IF EXISTS red_afgoer_source_persona(uuid,integer,text,bigint,text)", "")
    return ("red_afgoer_source_persona(uuid,integer,text,bigint,text)" in s
            or bool(re.search(r"FUNCTION\s+(public\.)?red_afgoer_source_persona\(\s*p_source_persona_id uuid,\s*"
                              r"p_expected_version integer,\s*p_action text,\s*p_canonical_person_id bigint,\s*p_note text\s*\)", s)))


def kernekald(s: str) -> list[tuple[str | None, str | None, str, int]]:
    """(omsluttende funktion, oprindelse, kaldtekst, position) for hvert kald af kernen."""
    ud = []
    for m in re.finditer(re.escape(KERNE), s):
        if re.search(r"FUNCTION\s+$", s[max(0, m.start() - 30):m.start()]) or s[m.end():m.end() + 5] == "uuid,":
            continue   # definitionen selv og REVOKE-signaturer
        i, dybde = m.end(), 1
        while dybde:
            dybde += {"(": 1, ")": -1}.get(s[i], 0)
            i += 1
        kald = s[m.start():i]
        o = re.search(r"'([a-z_]+)'\s*\)$", kald)
        fn = None
        for f in re.finditer(r"FUNCTION\s+([a-z_.]+)\(", s[:m.start()]):
            fn = f
        ud.append((fn.group(1).split(".")[-1] if fn else None, o.group(1) if o else None, kald, m.start()))
    return ud


def optael(s: str, fil: str) -> dict:
    t: dict = {}
    for fn, o, kald, _ in kernekald(s):
        assert o in OPRINDELSER, f"{fil}: kald uden lovlig oprindelse i {fn}: {kald[-80:]}"
        t[(fil, fn, o)] = t.get((fil, fn, o), 0) + 1
    return t


def test_checkeren_fanger_fejl():
    ok = "CREATE FUNCTION public.red_afgoer_source_persona(x int) AS $$ BEGIN PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','human'); END $$;"
    assert optael(ok, "f") == {("f", "red_afgoer_source_persona", "human"): 1}
    for daarlig in ["CREATE FUNCTION f() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}'); $$;",
                    "CREATE FUNCTION f() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','batch'); $$;"]:
        with pytest.raises(AssertionError):
            optael(daarlig, "f")
    ukendt = "CREATE FUNCTION public.ny_writer() AS $$ PERFORM private.decide_source_persona_identity(a,b,0,'x','{}','human'); $$;"
    assert ("f", "ny_writer", "human") in optael(ukendt, "f")   # fanges af allowlist-sammenligningen


def test_kaldere_er_praecis_allowlisten():
    faktisk = {**optael(_tekst("schema.sql"), "schema.sql"), **optael(_tekst("db-migrations.sql"), "db-migrations.sql")}
    assert faktisk == ALLOWLIST


def test_ingen_offentlig_kerne_uden_for_cutover_og_drop():
    for navn in ("schema.sql", "db-migrations.sql"):
        assert offentlig_kerne_uden_for_cutover((ROOT / navn).read_text(encoding="utf-8")) == [], navn


def test_femarguments_wrapper_findes_kun_i_cutover_og_drop():
    for navn in ("schema.sql", "db-migrations.sql"):
        assert not femarguments_wrapper_uden_for_cutover((ROOT / navn).read_text(encoding="utf-8")), navn


# Den planlagte blok (Step 8) ordret: vagten skal ignorere den, men kun inden for markørerne.
CUTOVER_FIXTURE = r"""-- BEGIN 5a-cutover (#151): lukker klientvejen til den gamle identitetskerne og femarguments-
DO $cutover_5a$
BEGIN
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
  IF to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
END $cutover_5a$;
-- END 5a-cutover
"""


def test_cutover_blokken_ignoreres_kun_inden_for_markoererne():
    assert offentlig_kerne_uden_for_cutover(CUTOVER_FIXTURE) == []
    assert not femarguments_wrapper_uden_for_cutover(CUTOVER_FIXTURE)
    uden_markoerer = CUTOVER_FIXTURE.replace("-- BEGIN 5a-cutover", "-- BEGIN x").replace("-- END 5a-cutover", "-- END x")
    assert offentlig_kerne_uden_for_cutover(uden_markoerer)
    assert femarguments_wrapper_uden_for_cutover(uden_markoerer)
    # Regressionsvagt: strip-først-rækkefølgen ville aldrig skære blokken ud.
    assert "red_decide_source_persona_identity(" in CUTOVER.sub("", _uden_kommentarer(CUTOVER_FIXTURE))


def test_kernen_grantes_aldrig():
    for navn in ("schema.sql", "db-migrations.sql"):
        for g in re.findall(r"GRANT[^;]*;", _tekst(navn), re.S):
            assert "decide_source_persona_identity" not in g and "insert_person_with_receipt" not in g, f"{navn}: {g[:120]}"


def test_person_create_kaldere_opretter_via_kvittering():
    for navn in ("schema.sql", "db-migrations.sql"):
        s = _tekst(navn)
        for fn, o, _, pos in kernekald(s):
            if o != "person_create":
                continue
            start = max(m.start() for m in re.finditer(r"FUNCTION\s+[a-z_.]+\(", s[:pos]))
            krop = s[start:pos]
            assert "insert_person_with_receipt(" in krop and "INSERT INTO public.person(" not in krop, f"{navn}: {fn}"


def test_cutover_staar_foer_foerste_saetning():
    raa = (ROOT / "db-migrations.sql").read_text(encoding="utf-8")
    blok = CUTOVER.search(raa)
    assert blok, "cutover-blokken mangler"
    foerste = re.search(r"^(CREATE|ALTER|DROP|GRANT|REVOKE|INSERT|UPDATE|DELETE|DO|COMMENT)\b", raa, re.M)
    assert foerste and foerste.start() > blok.start(), "en sætning står før cutover-blokken"
    for sig in ("public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)",
                "public.red_afgoer_source_persona(uuid,integer,text,bigint,text)"):
        assert f"REVOKE ALL ON FUNCTION {sig} FROM PUBLIC,anon,authenticated,service_role" in blok.group(0), sig
```

Kør: `cd .claude/skills/daa-extract/scripts && env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_identity_guard_static.py -q`. Expected: `3 passed, 5 failed` — `test_checkeren_fanger_fejl`, `test_cutover_blokken_ignoreres_kun_inden_for_markoererne` og `test_person_create_kaldere_opretter_via_kvittering` (tom, før der findes `person_create`-kald) består; de øvrige fejler (kernen er offentlig, ingen cutover). Efterprøvet mod `main` 2026-10-05.

- [ ] **Step 2: Skriv den fejlende SQL-test** `tests/sql/test-identity-decision.sql`:

```sql
-- Trin 5a, Task 3: afgørelsens udgange, kandidatbinding, aktualitet, kildelås og den strukturelle guard.
CREATE EXTENSION IF NOT EXISTS dblink;

DO $identity_surface$
BEGIN
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: den offentlige kerne findes stadig';
  END IF;
  IF to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: femarguments-wrapperen findes stadig';
  END IF;
  IF has_function_privilege('authenticated','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE')
     OR has_function_privilege('anon','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kernen kan kaldes af en klientrolle';
  END IF;
  IF NOT has_function_privilege('authenticated','public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: wrapperen kan ikke kaldes af authenticated';
  END IF;
  RAISE NOTICE 'OK: funktionsfladen — privat kerne, kun seksarguments-wrapperen for klienter';
END $identity_surface$;

DO $identity_decision$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a03';
  v_run uuid := '22000000-0000-0000-0000-000000005a03';
  v_rend uuid := '33000000-0000-0000-0000-000000005a03';
  v_occ uuid := '55000000-0000-0000-0000-000000005a03';
  v_obs uuid := '66000000-0000-0000-0000-000000005a03';
  v_ps uuid[] := ARRAY['88000000-0000-0000-0000-000000005a31','88000000-0000-0000-0000-000000005a32',
                       '88000000-0000-0000-0000-000000005a33','88000000-0000-0000-0000-000000005a34',
                       '88000000-0000-0000-0000-000000005a35','88000000-0000-0000-0000-000000005a36',
                       '88000000-0000-0000-0000-000000005a37']::uuid[];
  v_old_run uuid; v_new_run uuid; v_cand uuid; v_cand5 uuid; v_ev jsonb; v_i int; v_new bigint; v_state text; v_err text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-decide@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a decide','5a-decide@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655031,false,false,'5a'),(-987655032,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655031,'5a D','verify:5a:d');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655031,'5a-run-d','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES (v_rend,-987655031,'5a-rend','text_layer',repeat('8',64),'{}');
    INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'5a-occ',1,1,0,9,'Anna Test','phys-5a','struct-5a',v_run);
    INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES (v_obs,v_occ,'name_clause',1,1,0,9,'Anna Test','clear','verify',v_run);
    FOR v_i IN 1..7 LOOP
      INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_ps[v_i],-987655031,'5a-d'||v_i,v_run);
      INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
        VALUES (('70000000-0000-0000-0000-000000005a3'||v_i)::uuid,v_obs,'person',0,9,'Anna Test',v_run);
      INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
        VALUES (v_ps[v_i],('70000000-0000-0000-0000-000000005a3'||v_i)::uuid,'principal',1);
    END LOOP;
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
      input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655031,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('b',64),repeat('c',64),6,2,v_actor,'t')
      RETURNING id INTO v_old_run;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old_run,v_ps[1],-987655031,1,0.92,'auto','{"signals":["name"]}') RETURNING id INTO v_cand;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old_run,v_ps[5],-987655032,1,0.7,'review','{"signals":["name"]}') RETURNING id INTO v_cand5;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    -- 1 same med fulgt kandidat fra gældende kørsel (web)
    PERFORM red_afgoer_source_persona(v_ps[1],0,'same',-987655031,'kandidat fulgt',
      jsonb_build_object('candidate_id',v_cand,'run_id',v_old_run));
    -- 2 different, 3 unresolved, 4 new_person_needed (ark)
    PERFORM red_afgoer_source_persona(v_ps[2],0,'different',NULL,'ikke ham','{}');
    PERFORM red_afgoer_source_persona(v_ps[3],0,'unresolved',NULL,'uklart','{}');
    PERFORM red_afgoer_source_persona(v_ps[4],0,'new_person_needed',NULL,'findes ikke',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('e',64),'rows_sha256',repeat('f',64),'line',7));
    -- ugyldige kontekster og kandidater
    FOR v_err IN SELECT unnest(ARRAY['uden_run','fremmed','ark_uden_hash','ukendt_noegle','klient_kerne']) LOOP
      v_state:=NULL;
      BEGIN
        IF v_err='uden_run' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655032,'x',jsonb_build_object('candidate_id',v_cand5));
        ELSIF v_err='fremmed' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655031,'x',jsonb_build_object('candidate_id',v_cand,'run_id',v_old_run));
        ELSIF v_err='ark_uden_hash' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'different',NULL,'x','{"basis":"human_sheet"}');
        ELSIF v_err='ukendt_noegle' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'different',NULL,'x','{"batch_id":"00000000-0000-0000-0000-000000000001"}');
        ELSE
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"basis":"web_detail"}','human');
        END IF;
        RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: % blev accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
        IF (v_err='klient_kerne' AND v_state<>'42501')
           OR (v_err<>'klient_kerne' AND SQLERRM IS DISTINCT FROM (CASE v_err
                 WHEN 'fremmed' THEN 'EVIDENCE_IDENTITY_CANDIDATE_MISMATCH' ELSE 'EVIDENCE_IDENTITY_DECISION_INVALID' END)) THEN
          RAISE;
        END IF;
      END;
    END LOOP;
    RESET ROLE;

    -- en nyere kørsel gør v_cand5's kørsel forældet: afgørelsen skal afvises
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
      input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655031,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('d',64),repeat('c',64),6,0,v_actor,'t')
      RETURNING id INTO v_new_run;
    SET LOCAL ROLE authenticated;
    BEGIN
      PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655032,'forældet',jsonb_build_object('candidate_id',v_cand5,'run_id',v_old_run));
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: forældet kørsel accepteret';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE' THEN RAISE; END IF; END;
    RESET ROLE;

    -- kernen direkte (superbruger = serverfunktionernes rettighed): hver oprindelse og dens krav
    -- fast 1:1-kobling til person -987655032 for postnøglen 5a-R1 i kilden (til legacy_match)
    INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES (-987655032,-987655031,'5a-R1');
    FOR v_err IN SELECT unnest(ARRAY['human_fri','create_status','create_basis','create_uden_kvittering',
                                     'legacy_forkert_person','legacy_uden_autoritet','reversal_uden','ukendt']) LOOP
      BEGIN
        IF v_err='human_fri' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"basis":"fri tekst"}','human');
        ELSIF v_err='create_status' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],NULL,0,'rejected','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
        ELSIF v_err='create_basis' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001","basis":"web_detail"}','person_create');
        ELSIF v_err='create_uden_kvittering' THEN   -- eksisterende person, ingen kvittering
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
        ELSIF v_err='legacy_forkert_person' THEN     -- evidensen peger på en anden person end koblingen
          PERFORM private.decide_source_persona_identity(v_ps[6],-987655031,0,'accepted',
            '{"authority":"person_external_id","person_external_id":{"person_id":-987655031,"source_id":-987655031,"record_key":"5a-R1"}}','legacy_match');
        ELSIF v_err='legacy_uden_autoritet' THEN
          PERFORM private.decide_source_persona_identity(v_ps[6],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','legacy_match');
        ELSIF v_err='reversal_uden' THEN
          PERFORM private.decide_source_persona_identity(v_ps[1],NULL,1,'superseded','{"note":"x"}','reversal');
        ELSE
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','batch');
        END IF;
        RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kerne-% accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM IS DISTINCT FROM (CASE v_err WHEN 'ukendt' THEN 'EVIDENCE_IDENTITY_ORIGIN_INVALID'
             WHEN 'create_uden_kvittering' THEN 'EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING'
             ELSE 'EVIDENCE_IDENTITY_BASIS_REQUIRED' END) THEN RAISE; END IF;
      END;
    END LOOP;
    -- oprettelse med kvittering (også inde i en subtransaktion) tillades; kvitteringen forbruges
    BEGIN
      v_new := private.insert_person_with_receipt(true,'5a oprettet nu');
      PERFORM private.decide_source_persona_identity(v_ps[5],v_new,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
    EXCEPTION WHEN OTHERS THEN RAISE;   -- EXCEPTION-klausulen gør blokken til en subtransaktion
    END;
    BEGIN PERFORM private.decide_source_persona_identity(v_ps[7],v_new,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kvittering genbrugt';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING' THEN RAISE; END IF; END;
    PERFORM private.decide_source_persona_identity(v_ps[5],NULL,1,'superseded','{"reversed_batch_id":"00000000-0000-0000-0000-000000000001"}','reversal');
    -- 149b's faste 1:1-kobling tillades som legacy_match
    PERFORM private.decide_source_persona_identity(v_ps[6],-987655032,0,'accepted',
      '{"authority":"person_external_id","person_external_id":{"person_id":-987655032,"source_id":-987655031,"record_key":"5a-R1"}}','legacy_match');

    SELECT evidence INTO v_ev FROM private.source_persona_identity WHERE source_persona_id=v_ps[1];
    IF v_ev->>'basis'<>'web_detail' OR v_ev->>'candidate_id'<>v_cand::text OR v_ev->>'run_id'<>v_old_run::text
       OR (v_ev->>'candidate_rank')::int<>1 THEN
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kandidatspor mangler i evidensen (%)',v_ev;
    END IF;
    SELECT evidence INTO v_ev FROM private.source_persona_identity WHERE source_persona_id=v_ps[4];
    IF v_ev->>'reason'<>'new_person_needed' OR v_ev->>'basis'<>'human_sheet' OR (v_ev->>'line')::int<>7
       OR (SELECT decision_status FROM private.source_persona_identity WHERE source_persona_id=v_ps[4])<>'unresolved' THEN
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: new_person_needed forkert skrevet (%)',v_ev;
    END IF;
    RAISE EXCEPTION 'ROLLBACK_5A_DECISION';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_DECISION' THEN
      RAISE NOTICE 'OK: fire udgange, kandidatspor, aktualitet, arkbasis og guard pr. oprindelse (kvittering, 1:1-kobling); kernen utilgængelig for klienter';
    ELSE RAISE; END IF;
  END;
END $identity_decision$;

-- Afgørelsen tager den delte kildelås: holder en anden forbindelse den eksklusivt, venter afgørelsen.
DO $identity_decision_lock$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a08';
  v_run uuid := '22000000-0000-0000-0000-000000005a08';
  v_persona uuid := '88000000-0000-0000-0000-000000005a81';
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_state text;
BEGIN
  PERFORM dblink_connect('decide_lock',v_conn);
  PERFORM dblink_exec('decide_lock','BEGIN');
  PERFORM dblink_exec('decide_lock','SELECT pg_advisory_xact_lock(hashtextextended(''daa-identity-candidates:-987655081'',0))');
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-dlock@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a dlock','5a-dlock@test.invalid');
    INSERT INTO source(id,titel,import_key) VALUES (-987655081,'5a L','verify:5a:l');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655081,'5a-run-l','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_persona,-987655081,'5a-l1',v_run);
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_afgoer_source_persona(v_persona,0,'different',NULL,'lås','{}');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_DECISION_LOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_5A_DECISION_LOCK' THEN
      PERFORM dblink_exec('decide_lock','ROLLBACK'); PERFORM dblink_disconnect('decide_lock'); RAISE;
    END IF;
  END;
  PERFORM dblink_exec('decide_lock','ROLLBACK'); PERFORM dblink_disconnect('decide_lock');
  IF v_state IS DISTINCT FROM '55P03' THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: afgørelsen ventede ikke på kildelåsen (%)',v_state;
  END IF;
  RAISE NOTICE 'OK: afgørelsen tager kildelåsen';
END $identity_decision_lock$;
```

Låsetesten kræver, at wrapperen tager låsen **før** persona-/mention-kontrollen (personaen her har ingen mention); rækkefølgen i Step 5 er derfor: rollegate → kontekstform → find kilde → lås → resten.

- [ ] **Step 3: Kør begge tests** (Frisk testbase): SQL-testen og den statiske. Expected: SQL FAIL `IDENTITY_DECISION_TEST_FAILED: den offentlige kerne findes stadig`; pytest FAIL som i Step 1.

- [ ] **Step 4: Kernen — erstat på stedet.** I `schema.sql:8103` og `db-migrations.sql:6472`: omdøb `red_decide_source_persona_identity(` til `private.decide_source_persona_identity(`, tilføj parameteren `p_origin text` sidst, og indsæt guarden **efter** versionskontrollen (`IF v_current_version<>p_expected_version THEN … END IF;`) og **før** `v_new_version:=v_current_version+1;`, så eksisterende fejlkoder (rolle, version, mention, konflikt) kommer først:

```sql
  -- Trin 5a-guard (#151): oprindelsen er strukturel. Kernen har ingen grants; kun
  -- serverfunktioner kalder den, og hver oprindelse har sine egne krav.
  IF p_origin='human' THEN
    IF coalesce(p_evidence->>'basis','') NOT IN ('web_detail','human_sheet') THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_BASIS_REQUIRED';
    END IF;
  ELSIF p_origin='person_create' THEN
    IF p_decision_status<>'accepted' OR p_expected_version<>0 OR NOT (p_evidence ? 'batch_id') OR p_evidence ? 'basis' THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_BASIS_REQUIRED';
    END IF;
    -- Kvitteringen beviser, at personen er oprettet af insert_person_with_receipt i DENNE
    -- toptransaktion (xid8: epoke-sikker og ens i subtransaktioner); den forbruges én gang.
    DELETE FROM private.person_create_receipt WHERE person_id=p_canonical_person_id AND xact_id=pg_current_xact_id();
    IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING'; END IF;
  ELSIF p_origin='legacy_match' THEN
    -- 149b: den faste 1:1-kobling via person_external_id, efterprøvet her — ikke kun i writeren.
    IF p_decision_status<>'accepted' OR p_expected_version<>0 OR p_evidence ? 'basis'
       OR p_evidence->>'authority' IS DISTINCT FROM 'person_external_id'
       OR (p_evidence->'person_external_id'->>'person_id')::bigint IS DISTINCT FROM p_canonical_person_id
       OR (p_evidence->'person_external_id'->>'source_id')::bigint IS DISTINCT FROM
          (SELECT sp.source_id FROM private.source_persona sp WHERE sp.id=p_source_persona_id)
       OR (SELECT count(*) FROM public.person_external_id x
            WHERE x.source_id=(p_evidence->'person_external_id'->>'source_id')::bigint
              AND x.record_key=p_evidence->'person_external_id'->>'record_key')<>1
       OR NOT EXISTS (SELECT 1 FROM public.person_external_id x
            WHERE x.source_id=(p_evidence->'person_external_id'->>'source_id')::bigint
              AND x.record_key=p_evidence->'person_external_id'->>'record_key' AND x.person_id=p_canonical_person_id)
       OR (SELECT count(*) FROM public.person_external_id x
            WHERE x.source_id=(p_evidence->'person_external_id'->>'source_id')::bigint AND x.person_id=p_canonical_person_id)<>1 THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_BASIS_REQUIRED';
    END IF;
  ELSIF p_origin='reversal' THEN
    IF p_decision_status<>'superseded' OR NOT (p_evidence ? 'reversed_batch_id') OR p_evidence ? 'basis' THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_BASIS_REQUIRED';
    END IF;
  ELSE
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_ORIGIN_INVALID';
  END IF;
```

I `db-migrations.sql` står umiddelbart **før** den omdøbte `CREATE OR REPLACE FUNCTION private.decide_source_persona_identity(`:

```sql
DROP FUNCTION IF EXISTS public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb);
```

og kernens grant-linjer (`db-migrations.sql:6531-6536`) erstattes af:

```sql
REVOKE ALL ON FUNCTION private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
```

Gør det samme i `schema.sql:8303-8316`: kernen ud af `GRANT`-listen, den private signatur ind i `REVOKE`-listen, og den offentlige fjernes fra regprocedure-listen (`schema.sql:8312`, `db-migrations.sql:18272`).

Kvitteringen — i `schema.sql` lige før kernen og i `db-migrations.sql`'s 5a-sektion (ny; et `person_create`-kald, der når kernen, før sektionen er kørt, fejler lukket på den manglende tabel):

```sql
-- Trin 5a (#151): oprettelseskvittering. Kun insert_person_with_receipt udsteder den, og
-- kernen forbruger den; et person_create-match til en eksisterende person har ingen kvittering.
CREATE TABLE IF NOT EXISTS private.person_create_receipt (
  person_id bigint PRIMARY KEY REFERENCES public.person(id) ON DELETE CASCADE,
  xact_id   xid8 NOT NULL
);
ALTER TABLE private.person_create_receipt ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.person_create_receipt FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.insert_person_with_receipt(p_staged boolean,p_visning_navn text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.person(staged,visning_navn) VALUES(p_staged,p_visning_navn) RETURNING id INTO v_id;
  INSERT INTO private.person_create_receipt(person_id,xact_id) VALUES(v_id,pg_current_xact_id());
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION private.insert_person_with_receipt(boolean,text) FROM PUBLIC,anon,authenticated,service_role;
```

Tilføj `'person_create_receipt'` i `db-rls.sql`'s master-array.

- [ ] **Step 5: Wrapperen — erstat på stedet.** Erstat definitionen i `schema.sql:8276-8299`; i `db-migrations.sql:7180-7191` erstattes den gamle femarguments-definition og dens grants af `DROP FUNCTION IF EXISTS red_afgoer_source_persona(uuid,integer,text,bigint,text);` efterfulgt af samme tekst:

```sql
CREATE OR REPLACE FUNCTION red_afgoer_source_persona(
  p_source_persona_id uuid, p_expected_version integer, p_action text,
  p_canonical_person_id bigint, p_note text, p_context jsonb DEFAULT '{}'::jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_status text; v_basis text; v_evidence jsonb; v_cand record; v_source bigint; v_current_run uuid;
  v_ctx jsonb:=coalesce(p_context,'{}'::jsonb);
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v_basis:=coalesce(v_ctx->>'basis','web_detail');
  IF jsonb_typeof(v_ctx)<>'object'
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_ctx) k
                 WHERE k NOT IN ('basis','candidate_id','run_id','sheet_sha256','rows_sha256','line'))
     OR (v_ctx ? 'candidate_id') <> (v_ctx ? 'run_id')
     OR p_action NOT IN ('same','different','unresolved','new_person_needed')
     OR nullif(btrim(p_note),'') IS NULL
     OR (p_action='same' AND p_canonical_person_id IS NULL)
     OR (p_action<>'same' AND p_canonical_person_id IS NOT NULL)
     OR v_basis NOT IN ('web_detail','human_sheet')
     OR (v_basis='human_sheet' AND (coalesce(v_ctx->>'sheet_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'rows_sha256','') !~ '^[0-9a-f]{64}$'
                                   OR coalesce(v_ctx->>'line','') !~ '^[1-9][0-9]*$')) THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_DECISION_INVALID';
  END IF;
  SELECT source_id INTO v_source FROM private.source_persona WHERE id=p_source_persona_id;
  IF v_source IS NULL THEN RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED'; END IF;
  -- Delt kildelås: kandidatwriteren tager den eksklusivt (Task 2), så en ny kørsel ikke
  -- kan indsættes mellem aktualitetskontrollen nedenfor og denne transaktions commit.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_source::text,0));
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_mention WHERE persona_id=p_source_persona_id) THEN
    RAISE EXCEPTION 'EVIDENCE_PERSONA_BASIS_REQUIRED';
  END IF;
  v_status:=CASE p_action WHEN 'same' THEN 'accepted' WHEN 'different' THEN 'rejected' ELSE 'unresolved' END;
  v_evidence:=jsonb_build_object('note',btrim(p_note),'action',p_action,'basis',v_basis);
  IF p_action='new_person_needed' THEN v_evidence:=v_evidence||'{"reason":"new_person_needed"}'; END IF;
  IF v_ctx ? 'candidate_id' THEN
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
  IF v_basis='human_sheet' THEN
    v_evidence:=v_evidence||jsonb_build_object('sheet_sha256',v_ctx->>'sheet_sha256',
      'rows_sha256',v_ctx->>'rows_sha256','line',(v_ctx->>'line')::int);
  END IF;
  RETURN private.decide_source_persona_identity(p_source_persona_id,p_canonical_person_id,p_expected_version,v_status,v_evidence,'human');
END $$;
REVOKE ALL ON FUNCTION red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb) TO authenticated;
```

- [ ] **Step 6: Writere, lister og asserts — erstat på stedet.**
  1. Hvert kald i tabellens `person_create`-, `legacy_match`- og `reversal`-rækker: `public.red_decide_source_persona_identity(` → `private.decide_source_persona_identity(`, og tilføj `,'person_create'`, `,'legacy_match'` hhv. `,'reversal'` som sidste argument (kun argumentlisten ændres).
  2. I hver `person_create`-writer (tabellens tre funktioner, alle versioner): erstat `INSERT INTO public.person(staged,visning_navn) VALUES(<a>,<b>) RETURNING id INTO <v>;` med `<v>:=private.insert_person_with_receipt(<a>,<b>);` — samme argumenter, samme variabel. Findes en anden `INSERT INTO public.person`-form i en af dem: STOP (kvitteringsfunktionen dækker kun `staged,visning_navn`).
  3. `db-rls.sql:677`: fjern kernen fra allow-listen; `db-rls.sql:674`: wrapper-signaturen → `(uuid,integer,text,bigint,text,jsonb)`.
  4. `db-verify.sql:2951`, `:3749`, `:3759` og `schema.sql:8308`, `:8315`: den offentlige kerne → kontrol af, at den **ikke** findes (`to_regprocedure(...) IS NOT NULL ⇒ FEJL`), og at `authenticated`/`anon` ikke har `EXECUTE` på `private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)`; femarguments-wrapper-signaturer → seksarguments.
  Tjek: `grep -rn "red_decide_source_persona_identity\|red_afgoer_source_persona(uuid,integer,text,bigint,text)" schema.sql db-migrations.sql db-rls.sql db-verify.sql` → kun `DROP FUNCTION IF EXISTS`-linjerne og db-verify's »findes ikke«-kontroller.

- [ ] **Step 7: Fixtures (superbruger).** De 7 direkte kald i `db-verify.sql` og det ene i `tests/sql/test-evidence-promotion.sql:298` omskrives mekanisk:

```bash
python3 - <<'EOF'
import re, pathlib
pat = re.compile(r"red_decide_source_persona_identity\(\s*([^;]*?)'\{\"basis\":\"([^\"]*)\"\}'\s*\)", re.S)
for p, forventet in [("db-verify.sql", 7), ("tests/sql/test-evidence-promotion.sql", 1)]:
    s = pathlib.Path(p).read_text(encoding="utf-8")
    s, n = pat.subn(lambda m: "private.decide_source_persona_identity(" + m.group(1)
                    + "'{\"basis\":\"web_detail\",\"note\":\"" + m.group(2) + "\"}','human')", s)
    assert n == forventet, (p, n)
    pathlib.Path(p).write_text(s, encoding="utf-8"); print(p, "omskrevet", n)
EOF
```

De 4 dblink-strenge i `db-verify.sql` (`:5194`, `:5260`, `:5455`, `:5465`) omskrives i hånden på samme måde — i den fordoblede citering: `red_decide_source_persona_identity(` → `private.decide_source_persona_identity(`, `''{"basis":"X"}''` → `''{"basis":"web_detail","note":"X"}'',''human''`. dblink-forbindelserne kører som superbruger (`v_conn` uden rolleskift), så den private kerne er tilgængelig. Tjek: `grep -c "private.decide_source_persona_identity(" db-verify.sql` = 11 kald + de signaturer, Step 6 tilføjede.

- [ ] **Step 8: Cutover øverst i `db-migrations.sql`.** Erstatning på stedet lukker ikke tidsrummet, før kørslen når de omskrevne linjer: i prod findes den gamle offentlige kerne og femarguments-wrapper med grants, indtil da (Codex runde 2). Indsæt som **første sætning** i filen (efter eventuelle indledende kommentarer og `\set`-linjer):

```sql
-- BEGIN 5a-cutover (#151): lukker klientvejen til den gamle identitetskerne og femarguments-
-- wrapperen, FØR resten af filen kører (filen er ikke én transaktion). Webkøens afgørelser fejler
-- lukket fra her, til den nye wrapper er oprettet længere nede; serverwritere påvirkes ikke.
DO $cutover_5a$
BEGIN
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
  IF to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
  END IF;
END $cutover_5a$;
-- END 5a-cutover
```

Deployet af 5a's DDL sker desuden under skrivepause for redaktionens identitetsafgørelser (webkøen), som det operationelle lag.

Test mellemtilstanden fra et prod-lignende katalog: `tests/sql/test-identity-cutover.sql` (køres med `-v cutover=<fil>`, hvor filen er blokken udtrukket af `db-migrations.sql`):

```sql
-- Trin 5a: cutover-blokken lukker klientvejen i et katalog, hvor den GAMLE kerne og wrapper findes med grants.
\set ON_ERROR_STOP on
BEGIN;
DROP FUNCTION IF EXISTS public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb);
CREATE FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) RETURNS integer LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) RETURNS integer LANGUAGE sql AS 'SELECT 1';
GRANT EXECUTE ON FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) TO anon,authenticated,service_role;
\i :cutover
DO $cutover_assert$
DECLARE v_role text; v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)',
                               'public.red_afgoer_source_persona(uuid,integer,text,bigint,text)'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_sig,'EXECUTE') THEN
        RAISE EXCEPTION 'IDENTITY_CUTOVER_TEST_FAILED: % kan stadig kalde %',v_role,v_sig;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'OK: cutover-blokken lukker klientvejen i et prod-lignende katalog';
END $cutover_assert$;
ROLLBACK;
```

Kør (ny Frisk testbase): `sed -n '/^-- BEGIN 5a-cutover/,/^-- END 5a-cutover/p' db-migrations.sql > /tmp/claude-501/cutover-5a.sql && psql -X -q -d "$FRESH" -v cutover=/tmp/claude-501/cutover-5a.sql -f tests/sql/test-identity-cutover.sql 2>&1 | grep -E 'OK:|FAILED|ERROR'`. Expected: `OK: cutover-blokken lukker klientvejen …`.

- [ ] **Step 9: CI** — frisk-schema-trinnet: `psql -v ON_ERROR_STOP=1 -f tests/sql/test-identity-decision.sql` efter Task 1's linje, derefter `sed -n '/^-- BEGIN 5a-cutover/,/^-- END 5a-cutover/p' db-migrations.sql > /tmp/cutover-5a.sql && psql -v ON_ERROR_STOP=1 -v cutover=/tmp/cutover-5a.sql -f tests/sql/test-identity-cutover.sql`; pytest-listen: `.claude/skills/daa-extract/scripts/test_identity_guard_static.py`.

- [ ] **Step 10: Kør alt** (ny Frisk testbase):

```bash
for t in test-identity-candidates test-identity-decision test-evidence-promotion test-reimport-writer test-reimport-legacy-migration; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/$t.sql > /tmp/claude-501/t3-$t.log 2>&1; echo "$t rc=$?"; done
psql -X -q -v ON_ERROR_STOP=1 -d "$FRESH" -f tests/sql/run-db-verify-disposable.sql > /tmp/claude-501/t3-verify.log 2>&1; echo "verify rc=$?"
(cd .claude/skills/daa-extract/scripts && env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_identity_guard_static.py -q) | tail -2
```

Kør derefter writer-beviserne på en opgraderet base i samme rækkefølge som CI's job (`ci.yml:319-330`) — den beviser samtidig opgraderingsstien fra et gammelt skema gennem cutover-blokken — og 1939-writerens R-integration på en base bygget som CI's `writer_1939` (`ci.yml:272-287`). Blokken er fail-closed (zsh-subshell med `set -euo pipefail`): manglende commit (CI's kontrol, `ci.yml:294`), fejl i `createdb`, opgradering, en test eller bootstrap stopper med `STOP: …` og rc 1, før næste trin; R kører med `R_ENVIRON_USER=/dev/null` efter en probe, der beviser at R ser den lokale engangsbase (`~/.Renviron` overskriver ellers shell-env). Efterprøvet mod `main` 2026-10-05: grøn vej `T3_UPGRADE_OK`; ugyldigt commit og manglende testfil stopper med rc 1.

```zsh
( set -euo pipefail
  fejl() { print -u2 "STOP: $1"; exit 1; }
  git cat-file -e '2d6aabf^{commit}' || fejl "2d6aabf mangler — git fetch origin"
  LE=daa5a_legacy_$(date +%Y%m%d%H%M%S); createdb "$LE" || fejl "createdb $LE"
  { psql -X -q -v ON_ERROR_STOP=1 -d "$LE" -f tests/sql/evidence-promotion-bootstrap.sql &&
    git show 2d6aabf:schema.sql | psql -X -q -v ON_ERROR_STOP=1 -d "$LE" &&
    psql -X -q -v ON_ERROR_STOP=1 -d "$LE" -f tests/sql/reimport-writer-legacy-empty-fixture.sql &&
    psql -X -q -v ON_ERROR_STOP=1 -d "$LE" -f db-migrations.sql && psql -X -q -v ON_ERROR_STOP=1 -d "$LE" -f db-rls.sql; } \
    > /tmp/claude-501/t3-$LE-setup.log 2>&1 || fejl "opgradering af $LE (se t3-$LE-setup.log)"
  # Samme rækkefølge som CI (ci.yml:319-330): db-rls.sql genanvendes efter test-reimport-writer.
  for f in tests/sql/test-reimport-writer.sql db-rls.sql tests/sql/test-reimport-name-completion.sql tests/sql/test-1939-v50-production-writer.sql \
           tests/sql/test-1939-v50-name-completion.sql tests/sql/run-db-verify-disposable.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$LE" -f "$f" > /tmp/claude-501/t3-$LE-${f:t:r}.log 2>&1 || fejl "$f på $LE"
    print "${f:t:r} ok"; done
  # 1939-writerens R-integration på en base bygget som CI's writer_1939 (ci.yml:272-287).
  W39=daa5a_w1939_$(date +%Y%m%d%H%M%S); createdb "$W39" || fejl "createdb $W39"
  for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql tests/sql/test-1939-v50-production-writer.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$W39" -f "$f" >> /tmp/claude-501/t3-$W39.log 2>&1 || fejl "$f på $W39"; done
  # R læser ~/.Renviron og overskriver shell-env: slå den fra, og bevis hvilken base R ser, før integrationen skriver.
  export R_ENVIRON_USER=/dev/null PGDATABASE="$W39" PGHOST=localhost PGPORT=5432 PGUSER="$(whoami)" PGPASSWORD=
  SER=$(Rscript -e 'cat(Sys.getenv("PGHOST"), Sys.getenv("PGDATABASE"))')
  [[ "$SER" == "localhost $W39" ]] || fejl "R ser '$SER', ikke localhost $W39"
  Rscript tests/integration/test-1939-v50-production-writer.R > /tmp/claude-501/t3-$W39-r.log 2>&1 || fejl "R-integration (se t3-$W39-r.log)"
  print "T3_UPGRADE_OK baser: $LE $W39" )
```

Expected: alle `rc=0`, pytest `8 passed`, og opgraderingsblokken slutter med `T3_UPGRADE_OK` (ingen `STOP:`). `test-reimport-name-completion.sql` kalder den generiske oprettelse (nu med kvittering) og fortrydelse positivt, `test-1939-v50-production-writer.sql` beviser positiv 1939-oprettelse, og R-integrationen beviser 1939's rollback/apply/reversal, og `test-reimport-legacy-migration.sql` — **uændret** — beviser, at 149b's migration og dens fortrydelse per element virker som `legacy_match` (Review Focus 4). `test-reimport-writer.sql` beviser kun, at afvisningerne er uændrede. Fejler en test på `EVIDENCE_IDENTITY_BASIS_REQUIRED` eller `EVIDENCE_IDENTITY_ORIGIN_INVALID`: **STOP** — en kalder mangler i tabellen; afgør med projektejeren, ikke med en ny oprindelse.

- [ ] **Step 11: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-identity-decision.sql tests/sql/test-identity-cutover.sql \
        tests/sql/test-evidence-promotion.sql .claude/skills/daa-extract/scripts/test_identity_guard_static.py .github/workflows/ci.yml
git commit -m "feat(151): privat identitetskerne med strukturel oprindelse, oprettelseskvittering, cutover og kandidataktualitet under kildelås"
```

---

### Task 4: Detalje- og kø-RPC

> **Genbekræftet 2026-10-05:** detalje og kø omdefineres i 5a-sektionen sidst i `db-migrations.sql` (ikke på stedet, `db-migrations.sql:7156-7191`). Det er tilladt: de indgår ikke i identitetsguarden, og en mellemtilstand med den gamle version under deploy er harmløs — samme praksis som omsegmenteringens »denne sidste version vinder« (`db-migrations.sql:19144`). Global Constraint om erstatning på stedet gælder kun guardens funktioner.

**Files:**
- Modify: `schema.sql:8183-8211` (kø), `schema.sql:8213-8256` (detalje); `db-migrations.sql` 5a-sektionen
- Create: `tests/sql/test-identity-detail.sql`; Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: kandidattabellerne, evidensformatet fra Task 3.
- Produces: `red_source_persona_detail(uuid)` returnerer også `candidates` (array af `{candidate_id, run_id, rank, score, tier, basis, person_id, person_name, born, died}` fra kildens **gældende** kørsel (højeste `run_seq`), sorteret efter rank) og `collisions` (array af `{person_id, persona_key}`: andre personas i samme kilde, der er `accepted` til en af kandidatpersonerne **i samme gældende kørsel**). `red_source_persona_queue(text,bigint,uuid,integer)` (uændret signatur) returnerer to nye kolonner `best_tier text` og `reason text`; `p_status='new_person_needed'` filtrerer på `unresolved` med `evidence->>'reason'='new_person_needed'`.

- [ ] **Step 1: Fejlende test** `tests/sql/test-identity-detail.sql`:

```sql
-- Trin 5a, Task 4: kandidater, kollisioner og kø-filter.
DO $identity_detail$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a04';
  v_run uuid := '22000000-0000-0000-0000-000000005a04';
  v_obs uuid := '66000000-0000-0000-0000-000000005a04';
  v_p1 uuid := '88000000-0000-0000-0000-000000005a41';
  v_p2 uuid := '88000000-0000-0000-0000-000000005a42';
  v_old uuid; v_new uuid; v_detail jsonb; v_n int; v_tier text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-detail@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a detail','5a-detail@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655041,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655041,'5a E','verify:5a:e');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655041,'5a-run-e','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES ('33000000-0000-0000-0000-000000005a04',-987655041,'5a-rend-e','text_layer',repeat('8',64),'{}');
    INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES ('55000000-0000-0000-0000-000000005a04','33000000-0000-0000-0000-000000005a04','5a-occ-e',1,1,0,9,'Anna Test','p5ae','s5ae',v_run);
    INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES (v_obs,'55000000-0000-0000-0000-000000005a04','name_clause',1,1,0,9,'Anna Test','clear','verify',v_run);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_p1,-987655041,'5a-e1',v_run),(v_p2,-987655041,'5a-e2',v_run);
    INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES ('70000000-0000-0000-0000-000000005a41',v_obs,'person',0,9,'Anna Test',v_run),
             ('70000000-0000-0000-0000-000000005a42',v_obs,'person',0,9,'Anna Test',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_p1,'70000000-0000-0000-0000-000000005a41','principal',1),(v_p2,'70000000-0000-0000-0000-000000005a42','principal',1);
    -- to kørsler: den gamle skal ignoreres
    -- tredje persona, accepteret til en person, der KUN er kandidat i den gamle kørsel
    INSERT INTO person(id,levende,privat,status) VALUES (-987655042,false,false,'5a');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES ('88000000-0000-0000-0000-000000005a43',-987655041,'5a-e3',v_run);
    INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES ('70000000-0000-0000-0000-000000005a43',v_obs,'person',0,9,'Anna Test',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES ('88000000-0000-0000-0000-000000005a43','70000000-0000-0000-0000-000000005a43','principal',1);
    -- to kørsler (gældende = højeste run_seq = den sidst indsatte): den gamle skal ignoreres
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655041,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('1',64),repeat('c',64),1,2,v_actor,'t') RETURNING id INTO v_old;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old,v_p1,-987655041,1,0.5,'none','{"signals":["name"]}'),(v_old,v_p1,-987655042,2,0.4,'none','{"signals":["name"]}');
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655041,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('2',64),repeat('c',64),1,1,v_actor,'t') RETURNING id INTO v_new;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_new,v_p1,-987655041,1,0.95,'auto','{"signals":["name","birth"]}');

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    -- persona 2 er allerede accepteret til kandidatpersonen → kollision for persona 1
    PERFORM red_afgoer_source_persona(v_p2,0,'same',-987655041,'samme','{}');
    PERFORM red_afgoer_source_persona('88000000-0000-0000-0000-000000005a43',0,'same',-987655042,'gammel kandidat','{}');
    v_detail := red_source_persona_detail(v_p1);
    IF jsonb_typeof(v_detail->'candidates') IS DISTINCT FROM 'array' OR jsonb_typeof(v_detail->'collisions') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: candidates/collisions mangler (%)',v_detail;
    END IF;
    IF jsonb_array_length(v_detail->'candidates') IS DISTINCT FROM 1 OR (v_detail->'candidates'->0->>'run_id')<>v_new::text
       OR (v_detail->'candidates'->0->>'tier')<>'auto' OR NOT (v_detail->'candidates'->0 ? 'person_name')
       OR (v_detail->'candidates'->0->>'person_id')::bigint<>-987655041 THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: kandidater fra forkert kørsel (%)',v_detail->'candidates';
    END IF;
    -- kun kollisionen fra den gældende kørsel (5a-e2); 5a-e3's person er kun kandidat i den gamle
    IF jsonb_array_length(v_detail->'collisions') IS DISTINCT FROM 1 OR (v_detail->'collisions'->0->>'persona_key')<>'5a-e2' THEN
      RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: forkerte kollisioner (%)',v_detail->'collisions';
    END IF;
    SELECT best_tier INTO v_tier FROM red_source_persona_queue('proposed',-987655041,NULL,50) WHERE source_persona_id=v_p1;
    IF v_tier IS DISTINCT FROM 'auto' THEN RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: best_tier %',v_tier; END IF;
    PERFORM red_afgoer_source_persona(v_p1,0,'new_person_needed',NULL,'ny','{}');
    SELECT count(*) INTO v_n FROM red_source_persona_queue('new_person_needed',-987655041,NULL,50);
    IF v_n<>1 THEN RAISE EXCEPTION 'IDENTITY_DETAIL_TEST_FAILED: new_person_needed-filter gav %',v_n; END IF;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_DETAIL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_DETAIL' THEN RAISE NOTICE 'OK: detalje viser seneste kørsels kandidater og kollisioner; kø har best_tier og ny-person-filter';
    ELSE RAISE; END IF;
  END;
END $identity_detail$;
```

- [ ] **Step 2: Kør** (Frisk testbase). Expected: FAIL `IDENTITY_DETAIL_TEST_FAILED: candidates/collisions mangler`.

- [ ] **Step 3: Detalje-RPC** — i `red_source_persona_detail` (begge filer; i migrations som `CREATE OR REPLACE` af hele funktionen), tilføj to nøgler i `jsonb_build_object(...)` efter `'interpretations', …`:

```sql
    'candidates',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'candidate_id',c.id,'run_id',c.run_id,'rank',c.rank,'score',c.score,'tier',c.tier,'basis',c.basis,
        'person_id',p.id,'person_name',p.visning_navn,'born',p.visning_foedt,'died',p.visning_doed) ORDER BY c.rank)
      FROM private.source_persona_identity_candidate c
      JOIN public.person p ON p.id=c.candidate_person_id
      WHERE c.source_persona_id=persona.id
        AND c.run_id=(SELECT r.id FROM private.source_persona_identity_candidate_run r
                       WHERE r.source_id=persona.source_id ORDER BY r.run_seq DESC LIMIT 1)),'[]'::jsonb),
    -- Synlig, ikke blokerende: målarkitekturen kræver, at kollisioner vises.
    'collisions',coalesce((SELECT jsonb_agg(DISTINCT jsonb_build_object('person_id',other.canonical_person_id,'persona_key',op.persona_key))
      FROM private.source_persona_identity other
      JOIN private.source_persona op ON op.id=other.source_persona_id
      WHERE other.decision_status='accepted' AND op.source_id=persona.source_id AND op.id<>persona.id
        AND other.canonical_person_id IN (SELECT c.candidate_person_id FROM private.source_persona_identity_candidate c
                                           WHERE c.source_persona_id=persona.id
                                             AND c.run_id=(SELECT r.id FROM private.source_persona_identity_candidate_run r
                                                            WHERE r.source_id=persona.source_id ORDER BY r.run_seq DESC LIMIT 1))),'[]'::jsonb)
```

- [ ] **Step 4: Kø-RPC** — erstat i `schema.sql:8183-8211`; i migrations: `DROP FUNCTION IF EXISTS red_source_persona_queue(text,bigint,uuid,integer);` og derefter:

```sql
CREATE OR REPLACE FUNCTION red_source_persona_queue(
  p_status text DEFAULT NULL, p_source_id bigint DEFAULT NULL,
  p_cursor uuid DEFAULT NULL, p_page_size integer DEFAULT 50
) RETURNS TABLE(
  source_persona_id uuid, source_id bigint, persona_key text,
  decision_status text, version integer, canonical_person_id bigint, mention_count bigint,
  best_tier text, reason text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('proposed','accepted','rejected','unresolved','superseded','new_person_needed') THEN
    RAISE EXCEPTION 'EVIDENCE_IDENTITY_STATUS_INVALID';
  END IF;
  RETURN QUERY
  SELECT persona.id,persona.source_id,persona.persona_key,
         coalesce(identity_state.decision_status,'proposed'),coalesce(identity_state.version,0),
         identity_state.canonical_person_id,
         (SELECT count(*) FROM private.source_persona_mention pm WHERE pm.persona_id=persona.id),
         (SELECT c.tier FROM private.source_persona_identity_candidate c
           WHERE c.source_persona_id=persona.id AND c.rank=1
             AND c.run_id=(SELECT r.id FROM private.source_persona_identity_candidate_run r
                            WHERE r.source_id=persona.source_id ORDER BY r.run_seq DESC LIMIT 1)),
         identity_state.evidence->>'reason'
    FROM private.source_persona persona
    LEFT JOIN private.source_persona_identity identity_state ON identity_state.source_persona_id=persona.id
   WHERE (p_source_id IS NULL OR persona.source_id=p_source_id)
     AND (p_cursor IS NULL OR persona.id>p_cursor)
     AND (p_status IS NULL
          OR (p_status='new_person_needed' AND identity_state.decision_status='unresolved'
              AND identity_state.evidence->>'reason'='new_person_needed')
          OR (p_status<>'new_person_needed' AND coalesce(identity_state.decision_status,'proposed')=p_status))
   ORDER BY persona.id
   LIMIT greatest(1,least(coalesce(p_page_size,50),100));
END $$;
REVOKE ALL ON FUNCTION red_source_persona_queue(text,bigint,uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_source_persona_queue(text,bigint,uuid,integer) TO authenticated;
```

- [ ] **Step 5: CI** — tilføj `psql -v ON_ERROR_STOP=1 -f tests/sql/test-identity-detail.sql` efter Task 3's linje.

- [ ] **Step 6: Kør** (ny Frisk testbase): de tre 5a-testfiler + db-verify. Expected: alle `OK:`, `verify rc=0`.

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql tests/sql/test-identity-detail.sql .github/workflows/ci.yml
git commit -m "feat(151): persona-detalje med kandidater og kollisioner; kø med tier og ny-person-filter"
```

---

### Task 5: Generatoren (`@daa/identity-candidates`)

> **Genbekræftet 2026-10-05 (rettet efter Codex):** `tsx` findes ikke i `package-lock.json`; `npm install` i Step 1 henter den over nettet. Gennemse lockfilens diff (`git diff --stat package-lock.json`): kun nye indgange for `tsx` og dens afhængigheder plus `packages/identity-candidates`, ingen opgradering af eksisterende pakker. `@types/node` arves fra roden (26.1.1). SQL-scripts kører med `ON_ERROR_STOP` og pipelines med `set -o pipefail` (rettet i kodestykkerne nedenfor). Køn bruges ikke i 5a (spec §5).

**Files:**
- Create: `packages/identity-candidates/package.json`, `tsconfig.json`, `src/frames.ts`, `src/rank.ts`, `src/cli.ts`, `src/__tests__/frames.test.ts`, `src/__tests__/rank.test.ts`
- Create: `packages/identity-candidates/sql/export-input.sql`, `sql/write-candidates.sql`
- Modify: `package-lock.json` (via `npm install`), `.github/workflows/ci.yml` (node-jobbet)

**Interfaces:**
- Consumes: `buildScored`, `scorePair`, `scorePairEvidens`, `buildMatchFrame`, `buildMatchPersoner`, `defaultCfg`, typer `MatchFrame`, `MatchCfg`, `ScoredPair` fra `@daa/core`; `red_identity_candidate_input` og writer-RPC'en fra Task 2 (serveren beregner alle hashes — CLI'en hasher intet).
- Produces: `personaFrames(rows: PersonaExportRow[]): { frames: MatchFrame[]; origins: Map<string, PersonaOrigin> }`; `udenAarstal(frames: MatchFrame[]): string[]` (id'er uden parsebart år; CLI'ens `stats.uden_aar`); `personFrames(payload: MatchPayload): MatchFrame[]`; `rankCandidates(personas: MatchFrame[], persons: MatchFrame[], opts: RankOptions): Candidate[]` hvor `Candidate = { source_persona_id: string; candidate_person_id: number; rank: number; score: number; tier: 'auto'|'review'|'none'; basis: { signals: string[]; name_origin: string; birth_origin: string | null; death_origin: string | null } }`; CLI `npx tsx packages/identity-candidates/src/cli.ts generate --input F --source-id N --out F [--top-k 3] [--evidens-normaliseret]`, hvor `F` er output af `export-input.sql` (`{input_spec, input_sha256, input: {personas, persons}}`), og som skriver `{ run: {source_id, generator_version, input_spec, input_sha256, config}, candidates: [...], stats: {personas, uden_navn} }` — `run` har præcis Task 2's nøgler; `stats` sendes ikke til writeren.

`PersonaExportRow` (fra `input.personas`, bygget af `private.identity_candidate_input`): `{ source_persona_id: string; name: string | null; name_origin: 'accepted_interpretation'|'proposed_interpretation'|'mention'|null; birth_raw: string | null; birth_origin: string | null; death_raw: string | null; death_origin: string | null }`. `MatchPayload` = `input.persons` (arrays fra `red_match_personer()`, sorteret af serveren): `{ persons, facts, concs, assertions, extIds }`.

- [ ] **Step 1: Workspace-filer.** `packages/identity-candidates/package.json`:

```json
{
  "name": "@daa/identity-candidates",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": { "test": "vitest run", "typecheck": "tsc --noEmit", "cli": "tsx src/cli.ts" },
  "dependencies": { "@daa/core": "*" },
  "devDependencies": { "vitest": "^3.0.0", "typescript": "^5.5.3", "tsx": "^4.19.0" }
}
```

`packages/identity-candidates/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "ESNext", "lib": ["ES2022"], "moduleResolution": "bundler",
    "strict": true, "noEmit": true, "isolatedModules": true, "skipLibCheck": true, "types": ["node"]
  },
  "include": ["src"]
}
```

Kør `npm install > /tmp/claude-501/npmi.log 2>&1; echo rc=$?` fra roden. Expected: `rc=0`, `package-lock.json` ændret.

- [ ] **Step 2: Fejlende tests.** `src/__tests__/rank.test.ts`:

```ts
import { describe, expect, test } from 'vitest';
import type { MatchFrame } from '@daa/core';
import { rankCandidates } from '../rank';

const f = (id: string | number, nameKey: string, birth: number | null = null, sex: MatchFrame['sex'] = 'ukendt',
           death: number | null = null): MatchFrame => ({
  id, nameKey, birthMin: birth, birthMax: birth, deathMin: death, deathMax: death, sex,
});
const origins = new Map([['p1', { name: 'accepted_interpretation', birth: 'accepted_interpretation', death: null }],
                         ['p2', { name: 'accepted_interpretation', birth: null, death: null }]]);

describe('rankCandidates', () => {
  test('ikke-injektiv: samme person er kandidat 1 for to personas', () => {
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848), f('p2', 'ludvig reventlow', 1848)],
      [f(7, 'ludvig reventlow', 1848), f(8, 'ludvig reventlau', 1790)], { topK: 3, origins });
    const tops = out.filter((c) => c.rank === 1);
    expect(tops.map((c) => [c.source_persona_id, c.candidate_person_id])).toEqual([['p1', 7], ['p2', 7]]);
  });

  test('rang 1..n pr. persona og højst topK', () => {
    const persons = [1, 2, 3, 4].map((i) => f(i, `anna reventlow${'x'.repeat(i - 1)}`));
    const out = rankCandidates([f('p1', 'anna reventlow')], persons, { topK: 3, origins });
    expect(out.map((c) => c.rank)).toEqual([1, 2, 3]);
    expect(out[0].candidate_person_id).toBe(1);
  });

  test('persona uden navn får ingen kandidater', () => {
    expect(rankCandidates([f('p1', '')], [f(1, 'anna')], { topK: 3, origins })).toEqual([]);
  });

  test('tier: auto kræver cutoff, margin og rang 1 — aldrig automatisk accept', () => {
    // Personaens køn er ukendt i 5a (spec §5): auto kræver navn + fødsels- + dødsår (0,6+0,2+0,1).
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(9, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 3, origins });
    // to identiske kandidater: margin 0 → ingen auto
    expect(out.every((c) => c.tier !== 'auto')).toBe(true);
    const alene = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 3, origins });
    expect(alene[0].tier).toBe('auto');
  });

  test('topK=1 skjuler ikke tvetydighed: margin beregnes før afskæring', () => {
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(9, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 1, origins });
    expect(out).toHaveLength(1);
    expect(out[0].tier).not.toBe('auto');
  });

  test('basis bærer signaler og oprindelse, deterministisk', () => {
    const a = rankCandidates([f('p1', 'ludvig reventlow', 1848)], [f(7, 'ludvig reventlow', 1848)], { topK: 3, origins });
    const b = rankCandidates([f('p1', 'ludvig reventlow', 1848)], [f(7, 'ludvig reventlow', 1848)], { topK: 3, origins });
    expect(a).toEqual(b);
    expect(a[0].basis).toEqual({ signals: ['name', 'birth'], name_origin: 'accepted_interpretation', birth_origin: 'accepted_interpretation', death_origin: null });
  });
});
```

`src/__tests__/frames.test.ts`:

```ts
import { describe, expect, test } from 'vitest';
import { personaFrames, udenAarstal } from '../frames';

describe('personaFrames', () => {
  test('navn og år fra eksporten; manglende navn giver tom nøgle', () => {
    const { frames, origins } = personaFrames([
      { source_persona_id: 'p1', name: 'Ludvig Reventlow', name_origin: 'accepted_interpretation',
        birth_raw: '12.3.1848', birth_origin: 'proposed_interpretation', death_raw: null, death_origin: null },
      { source_persona_id: 'p2', name: null, name_origin: null, birth_raw: null, birth_origin: null, death_raw: null, death_origin: null },
    ]);
    expect(frames[0]).toMatchObject({ id: 'p1', birthMin: 1848, birthMax: 1848, sex: 'ukendt' });
    expect(frames[0].nameKey.length).toBeGreaterThan(0);
    expect(frames[1].nameKey).toBe('');
    expect(origins.get('p1')).toEqual({ name: 'accepted_interpretation', birth: 'proposed_interpretation', death: null });
  });

  test('uden årstal afgøres af de parsede år, ikke af råfeltets tilstedeværelse', () => {
    const { frames } = personaFrames([
      { source_persona_id: 'p1', name: 'A', name_origin: 'mention', birth_raw: 'uden tal', birth_origin: 'mention', death_raw: null, death_origin: null },
      { source_persona_id: 'p2', name: 'B', name_origin: 'mention', birth_raw: null, birth_origin: null, death_raw: 'd. 1900', death_origin: 'mention' },
      { source_persona_id: 'p3', name: 'C', name_origin: 'mention', birth_raw: null, birth_origin: null, death_raw: null, death_origin: null },
    ]);
    expect(udenAarstal(frames)).toEqual(['p1', 'p3']);
  });
});
```

- [ ] **Step 3: Kør** `npm run test -w @daa/identity-candidates > /tmp/claude-501/ic.log 2>&1; tail -5 /tmp/claude-501/ic.log`
Expected: FAIL — `Failed to resolve import "../rank"`.

- [ ] **Step 4: Implementér.** `src/frames.ts`:

```ts
import { buildMatchFrame, buildMatchPersoner, parseYear, type MatchFrame } from '@daa/core';
import type { MatchAssertRow, MatchConcRow, MatchExtIdRow, MatchFactRow, MatchPersonRow } from '@daa/core';

export type PersonaExportRow = {
  source_persona_id: string; name: string | null; name_origin: string | null;
  birth_raw: string | null; birth_origin: string | null; death_raw: string | null; death_origin: string | null;
};
export type PersonaOrigin = { name: string | null; birth: string | null; death: string | null };
export type MatchPayload = {
  persons: MatchPersonRow[]; facts: MatchFactRow[]; concs: MatchConcRow[];
  assertions: MatchAssertRow[]; extIds: MatchExtIdRow[];
};

// Personaen har intet køn i kilden på dette led; ukendt tæller ikke imod.
export function personaFrames(rows: PersonaExportRow[]): { frames: MatchFrame[]; origins: Map<string, PersonaOrigin> } {
  const origins = new Map<string, PersonaOrigin>();
  const frames = rows.map((r) => {
    origins.set(r.source_persona_id, { name: r.name_origin, birth: r.birth_origin, death: r.death_origin });
    const y = (s: string | null) => (s == null ? null : String(parseYear(s) ?? ''));
    return buildMatchFrame({
      id: r.source_persona_id, navn: r.name ?? '', koen: null,
      foedsel: r.birth_raw ? { date_min: y(r.birth_raw), date_max: y(r.birth_raw) } : null,
      doed: r.death_raw ? { date_min: y(r.death_raw), date_max: y(r.death_raw) } : null,
    });
  });
  return { frames, origins };
}

export function personFrames(payload: MatchPayload): MatchFrame[] {
  return buildMatchPersoner(payload.persons, payload.facts, payload.concs, payload.assertions, payload.extIds)
    .map((p) => buildMatchFrame({ id: Number(p.id), navn: p.navn, koen: p.koen, foedsel: p.foedsel, doed: p.doed }));
}

// Personas uden parsebart fødsels- eller dødsår (spec §8.1): afgøres af de byggede frames,
// ikke af råfelterne — en ikke-tom date_raw uden 3-4-cifret tal giver intet år for matcheren.
export function udenAarstal(frames: MatchFrame[]): string[] {
  return frames.filter((f) => f.birthMin == null && f.birthMax == null && f.deathMin == null && f.deathMax == null)
    .map((f) => String(f.id));
}
```

`src/rank.ts`:

```ts
import { buildScored, defaultCfg, scorePair, scorePairEvidens, type MatchCfg, type MatchFrame, type ScoredPair } from '@daa/core';
import type { PersonaOrigin } from './frames';

export type Tier = 'auto' | 'review' | 'none';
export type Candidate = {
  source_persona_id: string; candidate_person_id: number; rank: number; score: number; tier: Tier;
  basis: { signals: string[]; name_origin: string; birth_origin: string | null; death_origin: string | null };
};
export type RankOptions = { topK: number; origins: Map<string, PersonaOrigin>; evidensNormaliseret?: boolean };

export function rankConfig(opts: Pick<RankOptions, 'evidensNormaliseret'>): MatchCfg {
  // topK i buildScored sættes højt, så VI vælger top-K efter endelig score pr. persona.
  // Ingen forudvalg i buildScored (det sorterer efter standardscore og ville skæve den normaliserede rangering).
  return { ...defaultCfg(), topK: Number.MAX_SAFE_INTEGER, evidensNormaliseret: Boolean(opts.evidensNormaliseret) };
}

const round4 = (x: number) => Math.round(x * 10000) / 10000;

// Pr. persona, IKKE injektiv: flere personas kan være samme person (spec §5).
export function rankCandidates(personas: MatchFrame[], persons: MatchFrame[], opts: RankOptions): Candidate[] {
  const cfg = rankConfig(opts);
  const score = (p: ScoredPair) => (cfg.evidensNormaliseret ? scorePairEvidens(p, cfg)
    : scorePair(p.nameSim, p.birthOverlap, p.deathOverlap, p.sexEq, cfg));
  const byPersona = new Map<string, Array<ScoredPair & { s: number }>>();
  for (const p of buildScored(personas, persons, cfg)) {
    const arr = byPersona.get(String(p.aId)) ?? [];
    arr.push({ ...p, s: score(p) });
    byPersona.set(String(p.aId), arr);
  }
  const out: Candidate[] = [];
  for (const persona of personas) {
    const pid = String(persona.id);
    const sorted = (byPersona.get(pid) ?? []).sort((a, b) => b.s - a.s || Number(a.bId) - Number(b.bId));
    // Margin fra hele listen FØR afskæring: ellers giver --top-k 1 altid margin ∞ (Codex 2026-10-05).
    const margin = sorted.length < 2 ? Infinity : sorted[0].s - sorted[1].s;
    const list = sorted.slice(0, opts.topK);
    const origin = opts.origins.get(pid) ?? { name: null, birth: null, death: null };
    list.forEach((p, i) => {
      const kunNavn = !p.birthKendt && !p.deathKendt;
      const tier: Tier = i === 0 && !kunNavn && p.s >= cfg.autoCutoff && margin >= cfg.ambiguityMargin ? 'auto'
        : p.s >= cfg.reviewCutoff ? 'review' : 'none';
      const signals = ['name', ...(p.birthOverlap ? ['birth'] : []), ...(p.deathOverlap ? ['death'] : []), ...(p.sexEq ? ['sex'] : [])];
      out.push({
        source_persona_id: pid, candidate_person_id: Number(p.bId), rank: i + 1, score: round4(Math.min(1, Math.max(0, p.s))), tier,
        basis: { signals, name_origin: origin.name ?? 'unknown', birth_origin: origin.birth, death_origin: origin.death },
      });
    });
  }
  return out;
}
```

`src/cli.ts`:

```ts
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { personaFrames, personFrames, udenAarstal, type MatchPayload, type PersonaExportRow } from './frames';
import { rankCandidates, rankConfig } from './rank';

const GENERATOR_VERSION = 'identity-candidates-1.0';

function arg(name: string, required = true): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  const v = i >= 0 ? process.argv[i + 1] : undefined;
  if (required && !v) { console.error(`mangler --${name}`); process.exit(2); }
  return v;
}

const cmd = process.argv[2];
if (cmd !== 'generate' && cmd !== 'calibrate') { console.error('brug: cli.ts generate|calibrate …'); process.exit(2); }

if (cmd === 'generate') {
  // export-input.sql: serverens input og dens hash; CLI'en hasher intet selv.
  const exp = JSON.parse(readFileSync(arg('input')!, 'utf8')) as {
    input_spec: unknown; input_sha256: string; input: { personas: PersonaExportRow[]; persons: MatchPayload };
  };
  const personaRows = exp.input.personas;
  const payload = exp.input.persons;
  const sourceId = Number(arg('source-id'));
  const topK = Number(arg('top-k', false) ?? 3);
  if (!Number.isInteger(topK) || topK < 1) { console.error('--top-k skal være et positivt heltal'); process.exit(2); }
  const evidensNormaliseret = process.argv.includes('--evidens-normaliseret');
  const { frames, origins } = personaFrames(personaRows);
  const persons = personFrames(payload);
  const candidates = rankCandidates(frames, persons, { topK, origins, evidensNormaliseret });
  const run = {
    source_id: sourceId, generator_version: GENERATOR_VERSION, input_spec: exp.input_spec,
    input_sha256: exp.input_sha256, config: { ...rankConfig({ evidensNormaliseret }), topK },
  };
  const uden = frames.filter((f) => !f.nameKey).length;
  const out = arg('out')!;
  // Personas uden parsebart fødsels- og dødsår (kun id'er) — kalibreringen rapporterer dem for sig (spec §8.1).
  const udenAar = udenAarstal(frames);
  writeFileSync(out, JSON.stringify({ run, candidates, stats: { personas: frames.length, uden_navn: uden, uden_aar: udenAar } }), 'utf8');
  chmodSync(out, 0o600);
  const tiers = candidates.filter((c) => c.rank === 1).reduce<Record<string, number>>((m, c) => ({ ...m, [c.tier]: (m[c.tier] ?? 0) + 1 }), {});
  console.log(`CANDIDATES_OK personas=${frames.length} uden_navn=${uden} kandidater=${candidates.length} rang1_tier=${JSON.stringify(tiers)}`);
}
```

(`calibrate` implementeres i Task 6; indtil da afviser CLI'en den ikke, men gør intet.)

- [ ] **Step 5: Kør** testene og typecheck:

```bash
npm run test -w @daa/identity-candidates > /tmp/claude-501/ic.log 2>&1; tail -4 /tmp/claude-501/ic.log
npm run typecheck -w @daa/identity-candidates > /tmp/claude-501/ict.log 2>&1; echo "tsc rc=$?"
```

Expected: alle tests PASS (8: rank 6, frames 2), `tsc rc=0`.

- [ ] **Step 6: SQL-scripts.** `packages/identity-candidates/sql/export-input.sql` (læse-kun; `:actor` = redaktionsprofil, `:source_id`, `:mode` = `undecided` eller `list`, `:personas` = kommasepareret uuid-liste ved `list`):

```sql
-- Trin 5a: generatorens input, bygget og hashet af serveren. Output indeholder navne:
-- skriv til en 0600-fil under ~/.private/5a/, læs den aldrig i en agent.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SET LOCAL ROLE authenticated;
SELECT red_identity_candidate_input(:source_id,
  CASE WHEN :'mode'='undecided' THEN '{"mode":"undecided"}'::jsonb
       ELSE jsonb_build_object('mode','list','persona_ids',
              (SELECT jsonb_agg(x ORDER BY x) FROM unnest(string_to_array(:'personas',',')) x)) END);
COMMIT;
```

`sql/write-candidates.sql` (`:actor`, `:cand_file` = sti til generatorens output):

```sql
\set ON_ERROR_STOP on
\set content `cat :cand_file`
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SET LOCAL ROLE authenticated;
SELECT red_record_identity_candidates((:'content'::jsonb)->'run', (:'content'::jsonb)->'candidates') AS run_id;
COMMIT;
```

- [ ] **Step 7: Ende-til-ende på en frisk base** med syntetisk data (ingen PII): Frisk testbase → indsæt fixturen fra Task 4 Step 1 **uden** rollback: fixturen er en DO-blok, hvis INSERTs bruger plpgsql-variabler, så kopiér hele blokken inkl. `DECLARE` til `/tmp/claude-501/5a-fixture.sql`, slet alt fra `PERFORM set_config(...)` til blokkens slutning (også den indre `BEGIN … EXCEPTION`-ramme), afslut med `END $$;` og kør den. Derefter:

```bash
set -o pipefail
A=11000000-0000-0000-0000-000000005a04; mkdir -p ~/.private/5a && chmod 700 ~/.private/5a
psql -X -q -At -d "$FRESH" -v actor=$A -v source_id=-987655041 -v mode=undecided -v personas= -f packages/identity-candidates/sql/export-input.sql | grep '^{' > ~/.private/5a/t-input.json
npm run cli -w @daa/identity-candidates -- generate --input ~/.private/5a/t-input.json --source-id -987655041 --out ~/.private/5a/t-cand.json
psql -X -At -d "$FRESH" -v actor=$A -v cand_file=$HOME/.private/5a/t-cand.json -f packages/identity-candidates/sql/write-candidates.sql
```

Expected: `CANDIDATES_OK personas=3 …` (Task 4-fixturens tre personas; `kandidater=0` er forventet, fordi fixturens personer hverken har navn eller fakta) og en `run_id`-uuid. En anden kørsel af `write-candidates.sql` giver samme uuid (idempotens). Indsæt derefter en ny persona i kilden og kør `write-candidates.sql` igen med den gamle fil: Expected `IDENTITY_CANDIDATE_INPUT_DRIFT`.

- [ ] **Step 8: CI** — i node-jobbet efter `feed · typecheck`:

```yaml
      - name: identity-candidates · vitest
        if: ${{ !cancelled() && steps.install.outcome == 'success' }}
        run: npm run test -w @daa/identity-candidates
      - name: identity-candidates · typecheck
        if: ${{ !cancelled() && steps.install.outcome == 'success' }}
        run: npm run typecheck -w @daa/identity-candidates
```

- [ ] **Step 9: Commit**

```bash
git add packages/identity-candidates package-lock.json .github/workflows/ci.yml
git commit -m "feat(151): kandidatgenerator som workspace — pr.-persona-rangering oven på @daa/core"
```

---

### Task 6: Kalibrering

> **Genbekræftet 2026-10-05:** `sql/export-truth.sql` starter med `\set ON_ERROR_STOP on`. Navnekilden (`person.name`) har kendte titelfejl (decisions 2026-10-03; 138 navne-assertions med titelord) — det trækker navnelighed ned og skal nævnes i Task 9's rapport som kendt forstyrrelse.

**Files:**
- Create: `packages/identity-candidates/src/calibrate.ts`, `src/__tests__/calibrate.test.ts`, `sql/export-truth.sql`
- Modify: `packages/identity-candidates/src/cli.ts`

**Interfaces:**
- Consumes: `Candidate` (Task 5).
- Produces: `calibrate(candidates: Candidate[], truth: Array<{ source_persona_id: string; canonical_person_id: number }>, personaCount: number, udenNavn: number, udenAar?: ReadonlySet<string>): Calibration` hvor `Tal = { med_facit: number; uden_kandidat: number; top1: number; top3: number; tier: Record<'auto'|'review'|'none', { n: number; rigtige: number }> }` og `Calibration = Tal & { personas: number; uden_navn: number; uden_aarstal: Tal }` (`uden_aarstal` = samme tal for personas uden fødsels- og dødsår, spec §8.1). CLI `calibrate --candidates F --truth F` (antal personas, uden navn og `uden_aar` læses af generatorens `stats`).

- [ ] **Step 1: Fejlende test** `src/__tests__/calibrate.test.ts`:

```ts
import { describe, expect, test } from 'vitest';
import { calibrate } from '../calibrate';
import type { Candidate } from '../rank';

const c = (p: string, person: number, rank: number, tier: Candidate['tier']): Candidate => ({
  source_persona_id: p, candidate_person_id: person, rank, score: 0.8, tier,
  basis: { signals: ['name'], name_origin: 'accepted_interpretation', birth_origin: null, death_origin: null },
});

describe('calibrate', () => {
  test('top-1, top-3, uden kandidat og præcision pr. tier', () => {
    const cands = [c('a', 1, 1, 'auto'), c('b', 9, 1, 'review'), c('b', 2, 2, 'review'), c('c', 9, 1, 'none')];
    const truth = [{ source_persona_id: 'a', canonical_person_id: 1 }, { source_persona_id: 'b', canonical_person_id: 2 },
                   { source_persona_id: 'c', canonical_person_id: 3 }, { source_persona_id: 'd', canonical_person_id: 4 }];
    const nul = { auto: { n: 0, rigtige: 0 }, review: { n: 0, rigtige: 0 }, none: { n: 0, rigtige: 0 } };
    expect(calibrate(cands, truth, 4, 1)).toEqual({
      personas: 4, med_facit: 4, uden_navn: 1, uden_kandidat: 1, top1: 1, top3: 2,
      tier: { auto: { n: 1, rigtige: 1 }, review: { n: 1, rigtige: 0 }, none: { n: 1, rigtige: 0 } },
      uden_aarstal: { med_facit: 0, uden_kandidat: 0, top1: 0, top3: 0, tier: nul },
    });
  });

  test('samme tal særskilt for personas uden årstal', () => {
    const cands = [c('a', 1, 1, 'auto'), c('b', 9, 1, 'review'), c('b', 2, 2, 'review')];
    const truth = [{ source_persona_id: 'a', canonical_person_id: 1 }, { source_persona_id: 'b', canonical_person_id: 2 },
                   { source_persona_id: 'd', canonical_person_id: 4 }];
    expect(calibrate(cands, truth, 3, 0, new Set(['b', 'd'])).uden_aarstal).toEqual({
      med_facit: 2, uden_kandidat: 1, top1: 0, top3: 1,
      tier: { auto: { n: 0, rigtige: 0 }, review: { n: 1, rigtige: 0 }, none: { n: 0, rigtige: 0 } },
    });
  });
});
```

- [ ] **Step 2: Kør** — Expected: FAIL `Failed to resolve import "../calibrate"`.

- [ ] **Step 3: Implementér** `src/calibrate.ts`:

```ts
import type { Candidate, Tier } from './rank';

export type Tal = {
  med_facit: number; uden_kandidat: number; top1: number; top3: number;
  tier: Record<Tier, { n: number; rigtige: number }>;
};
export type Calibration = Tal & { personas: number; uden_navn: number; uden_aarstal: Tal };

type Facit = Array<{ source_persona_id: string; canonical_person_id: number }>;

// Kun tal: ingen navne forlader funktionen.
export function calibrate(
  candidates: Candidate[], truth: Facit, personaCount: number, udenNavn: number,
  udenAar: ReadonlySet<string> = new Set(),
): Calibration {
  const byPersona = new Map<string, Candidate[]>();
  for (const k of candidates) byPersona.set(k.source_persona_id, [...(byPersona.get(k.source_persona_id) ?? []), k]);
  return { personas: personaCount, uden_navn: udenNavn, ...tal(byPersona, truth),
           uden_aarstal: tal(byPersona, truth.filter((t) => udenAar.has(t.source_persona_id))) };
}

function tal(byPersona: Map<string, Candidate[]>, truth: Facit): Tal {
  const out: Tal = { med_facit: truth.length, uden_kandidat: 0, top1: 0, top3: 0,
    tier: { auto: { n: 0, rigtige: 0 }, review: { n: 0, rigtige: 0 }, none: { n: 0, rigtige: 0 } } };
  for (const t of truth) {
    const list = (byPersona.get(t.source_persona_id) ?? []).sort((a, b) => a.rank - b.rank);
    if (!list.length) { out.uden_kandidat++; continue; }
    const hit = (k: Candidate) => k.candidate_person_id === t.canonical_person_id;
    if (hit(list[0])) out.top1++;
    if (list.slice(0, 3).some(hit)) out.top3++;
    out.tier[list[0].tier].n++;
    if (hit(list[0])) out.tier[list[0].tier].rigtige++;
  }
  return out;
}
```

Tilføj i `src/cli.ts` importen `import { calibrate } from './calibrate';` øverst og efter `generate`-blokken:

```ts
if (cmd === 'calibrate') {
  const data = JSON.parse(readFileSync(arg('candidates')!, 'utf8'));
  const truth = JSON.parse(readFileSync(arg('truth')!, 'utf8'));
  console.log('CALIBRATION ' + JSON.stringify(calibrate(data.candidates, truth, data.stats.personas, data.stats.uden_navn,
    new Set<string>(data.stats.uden_aar ?? []))));
}
```

`sql/export-truth.sql` (læse-kun, kun id'er):

```sql
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',i.source_persona_id::text,'canonical_person_id',i.canonical_person_id)
       ORDER BY i.source_persona_id),'[]'::jsonb)
  FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
 WHERE p.source_id=:source_id AND i.decision_status='accepted';
```

- [ ] **Step 4: Kør** test + typecheck. Expected: PASS, `tsc rc=0`.

- [ ] **Step 5: Commit**

```bash
git add packages/identity-candidates
git commit -m "feat(151): kalibrering af kandidater mod kendte identiteter — kun tal"
```

---

### Task 7: Identitetsarket og den fælles arkkerne

> **Genbekræftet 2026-10-05:** kontrolmodellen har udvidet 4.5-arket: `decision_sql` har parameteren `method` og tjekker `SHEET_METHODS` (`interpretation_decision_sheet.py:126-133`) før hash-løkken, og `main` har `--method`. Step 8 erstatter hash-løkken **efter** method-tjekket, så `SHEET_METHOD_INVALID` stadig kommer først, og `--method` videregives uændret. `control_model.py`, `decision_sheet_html.py` og deres tests importerer `SheetError`, `check_identity`, `parse_sheet` og `sheet_order` fra `interpretation_decision_sheet` — navnene skal fortsat kunne importeres derfra (re-eksport via importen fra kernen). Step 8's testkommando udvides med `test_control_model.py test_evidence_runner.py`.

**Files:**
- Create: `.claude/skills/daa-extract/scripts/decision_sheet_core.py`, `identity_decision_sheet.py`, `test_identity_decision_sheet.py`, `identity_sheet_rows.sql`
- Modify: `.claude/skills/daa-extract/scripts/interpretation_decision_sheet.py` (importerer kernen), `.github/workflows/ci.yml` (python-trinnets pytest-liste)

**Interfaces:**
- Consumes: kø-/kandidatdata (Task 1-4); `red_afgoer_source_persona(…, p_context jsonb)` (Task 3).
- Produces (kernen): `SheetError`; `sql_literal(s: str) -> str`; `require_hex64(*hashes: str) -> None` (kaster `SHEET_HASH_REQUIRED`); `verify_bound(rows_bytes: bytes, expect_rows_sha256: str, sheet_bytes: bytes, approved_sha256: str) -> tuple[str, str]` (kaster `ROWS_HASH_MISMATCH` / `SHEET_HASH_MISMATCH`, returnerer `(rows_sha, sheet_sha)`).
- Produces (arket): `sheet_order(rows) -> list[dict]`; `render_sheet(rows) -> str`; `check_render(text, rows) -> None` (kaster `SHEET_RENDER_MISMATCH`: arket skal være præcis `render_sheet(rows)`, kun token og note på `D`-linjerne må afvige); `parse_sheet(text) -> list[IdDecision]` med `IdDecision(persona_id: str, version: int, action: str, person_id: int | None, candidate_rank: int | None, note: str, line: int)`; `check_identity(decisions, rows) -> None`; `decision_sql(decisions, rows, *, sheet_sha256, rows_sha256) -> str`. CLI: `render --rows --out` og `sql --sheet --approved-sha256 --rows --expect-rows-sha256 --out`.

Rækkefilens form (én række pr. persona, fra `identity_sheet_rows.sql`): `{source_persona_id, version, source_id, persona_key, record_key, mention_role, name, name_origin, interpretations: [{predicate, status, value_text}], run_id, candidates: [{candidate_id, rank, person_id, person_name, born, died, score, tier, signals}]}`.

- [ ] **Step 1: Fejlende tests** `test_identity_decision_sheet.py`:

```python
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest
from identity_decision_sheet import (IdDecision, SheetError, check_identity, check_render, decision_sql,
                                     parse_sheet, render_sheet, sheet_order)

P1 = "11111111-1111-4111-8111-111111111111"
P2 = "22222222-2222-4222-8222-222222222222"
C1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
RUN = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
H = "ab" * 32
SCRIPT = str(Path(__file__).resolve().parent / "identity_decision_sheet.py")


def row(pid, cands=True, tier="auto", score=0.93):
    return {"source_persona_id": pid, "version": 0, "source_id": 1, "persona_key": "k", "record_key": "I-1",
            "mention_role": "principal", "name": "Anna Test", "name_origin": "accepted_interpretation",
            "interpretations": [{"predicate": "person.birth", "status": "proposed", "value_text": "1801"}],
            "run_id": RUN if cands else None,
            "candidates": [{"candidate_id": C1, "rank": 1, "person_id": 42, "person_name": "Anna Kanon",
                            "born": "1801", "died": "1860", "score": score, "tier": tier,
                            "signals": ["name", "birth"]}] if cands else []}


def test_render_sorterer_sikreste_først_og_forudfylder_intet():
    ark = render_sheet([row(P2, tier="review", score=0.75), row(P1)])
    assert ark.index(P1) < ark.index(P2)
    assert f"D {P1} 0 : _" in ark and f"D {P2} 0 : _" in ark
    assert "1: person 42" in ark


def test_render_viser_ingen_kandidat():
    assert "ingen kandidat" in render_sheet([row(P1, cands=False)])


def test_parse_alle_tokens():
    ark = (f"D {P1} 0 : 1 # fulgt\nD {P2} 3 : P 4711\n"
           f"D 33333333-3333-4333-8333-333333333333 0 : X\n"
           f"D 44444444-4444-4444-8444-444444444444 0 : N # findes ikke\n"
           f"D 55555555-5555-4555-8555-555555555555 1 : U\n")
    d = parse_sheet(ark)
    assert d[0] == IdDecision(P1, 0, "same", None, 1, "fulgt", 1)
    assert d[1] == IdDecision(P2, 3, "same", 4711, None, "", 2)
    assert [x.action for x in d[2:]] == ["different", "new_person_needed", "unresolved"]


def test_uafgjort_og_ukendt_token_stopper():
    with pytest.raises(SheetError, match="SHEET_UNDECIDED lines=1"):
        parse_sheet(f"D {P1} 0 : _\n")
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        parse_sheet(f"D {P1} 0 : A\n")


def test_ombyttet_og_slettet_linje_fanges():
    rows = [row(P1), row(P2, tier="review", score=0.75)]
    with pytest.raises(SheetError, match="SHEET_ORDER_MISMATCH"):
        check_identity(parse_sheet(f"D {P2} 0 : X\nD {P1} 0 : X\n"), rows)
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        check_identity(parse_sheet(f"D {P1} 0 : X\n"), rows)


def test_kandidat_token_uden_kandidat_stopper():
    rows = [row(P1, cands=False)]
    with pytest.raises(SheetError, match="SHEET_CANDIDATE_MISSING line=1"):
        decision_sql(parse_sheet(f"D {P1} 0 : 1\n"), rows, sheet_sha256=H, rows_sha256=H)


def test_sql_binder_kandidat_ark_og_kørsel():
    rows = [row(P1)]
    sql = decision_sql(parse_sheet(f"D {P1} 0 : 1 # o'hara\n"), rows, sheet_sha256=H, rows_sha256=H)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;")
    # aktualiteten afgøres atomisk af RPC'en (Task 3); arket sender kørslen med kandidaten
    assert '"run_id": "' + RUN + '"' in sql and "SHEET_CANDIDATE_RUN_STALE" not in sql
    assert f"red_afgoer_source_persona('{P1}'::uuid, 0, 'same', 42," in sql
    assert '"candidate_id": "' + C1 + '"' in sql and '"basis": "human_sheet"' in sql
    assert "o''hara" in sql and "DECISION_COUNT_MISMATCH" in sql and sql.rstrip().endswith("COMMIT;")


def _ark(rows, tok="1"):
    return render_sheet(rows).replace(" : _", f" : {tok}")


def test_rettet_kandidatlinje_stopper():
    rows = [row(P1)]
    with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH line="):
        check_render(_ark(rows).replace("1: person 42", "1: person 99"), rows)
    for gammel, ny in [("Anna Kanon", "Anna Anden"), ("score 0.93", "score 0.99"), ("  auto  ", "  review  ")]:
        with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH"):
            check_render(_ark(rows).replace(gammel, ny), rows)
    with pytest.raises(SheetError, match="SHEET_RENDER_MISMATCH"):   # slettet/flyttet kommentarlinje
        check_render("".join(l for l in _ark(rows).splitlines(keepends=True) if "1: person" not in l), rows)
    check_render(_ark(rows).replace(" : 1", " : 1 # note"), rows)   # token og note må ændres


def test_cli_rettet_kandidatlinje_stopper(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)]).replace("person 42", "person 99"))
    assert p.returncode == 1 and "SHEET_RENDER_MISMATCH" in p.stdout and not out.exists()


def _cli(tmp_path, ark, godkend=None, rows=None):
    rf = tmp_path / "rows.json"; rf.write_text(json.dumps(rows or [row(P1)]), encoding="utf-8")
    af = tmp_path / "ark.txt"; af.write_text(godkend or ark, encoding="utf-8")
    sha = hashlib.sha256(af.read_bytes()).hexdigest(); af.write_text(ark, encoding="utf-8")
    p = subprocess.run([sys.executable, SCRIPT, "sql", "--sheet", str(af), "--approved-sha256", sha,
                        "--rows", str(rf), "--expect-rows-sha256", hashlib.sha256(rf.read_bytes()).hexdigest(),
                        "--out", str(tmp_path / "d.sql")], capture_output=True, text=True)
    return p, tmp_path / "d.sql"


def test_cli_ændret_ark_stopper(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)], "X"), godkend=_ark([row(P1)], "1"))
    assert p.returncode == 1 and "SHEET_HASH_MISMATCH" in p.stdout and not out.exists()


def test_cli_komplet_ark(tmp_path):
    p, out = _cli(tmp_path, _ark([row(P1)]))
    assert p.returncode == 0 and "SQL_OK afgørelser=1" in p.stdout and out.exists()
```

- [ ] **Step 2: Kør** `cd .claude/skills/daa-extract/scripts && env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_identity_decision_sheet.py -q` — Expected: FAIL `ModuleNotFoundError: No module named 'identity_decision_sheet'`.

- [ ] **Step 3: Kernen** `decision_sheet_core.py`:

```python
"""Fælles kerne for token-ark (4.5-fortolkninger, 5a-identitet): hash-binding og SQL-citering.

Arkene rummer kildetekst; kernen ser kun bytes, hashes og id'er."""
from __future__ import annotations

import hashlib
import re


class SheetError(RuntimeError):
    pass


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def require_hex64(*hashes: str) -> None:
    for h in hashes:
        if not re.fullmatch(r"[0-9a-f]{64}", h or ""):
            raise SheetError("SHEET_HASH_REQUIRED")


def verify_bound(rows_bytes: bytes, expect_rows_sha256: str,
                 sheet_bytes: bytes, approved_sha256: str) -> tuple[str, str]:
    rows_sha = hashlib.sha256(rows_bytes).hexdigest()
    if rows_sha != expect_rows_sha256:
        raise SheetError("ROWS_HASH_MISMATCH — rækkefilen er ikke den, arket blev bygget af.")
    sheet_sha = hashlib.sha256(sheet_bytes).hexdigest()
    if sheet_sha != approved_sha256:
        raise SheetError("SHEET_HASH_MISMATCH — arket er ikke det, der blev godkendt.")
    return rows_sha, sheet_sha
```

- [ ] **Step 4: Arket** `identity_decision_sheet.py`:

```python
#!/usr/bin/env python3
"""Identitetsark (trin 5a): token-fil → red_afgoer_source_persona med basis human_sheet.

Rækkefilen (0600, uden for repoet) binder personas, versioner og kandidatkørslen. Et
kandidat-token (1/2/3) betyder altid den kandidat, redaktøren så: SQL'en stopper, hvis
kørslen ikke længere er den seneste for kilden."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
LINE_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|P [1-9][0-9]*|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^D {UUID} [0-9]+ : ")
TIER_ORDER = {"auto": 0, "review": 1, "none": 2}


@dataclass(frozen=True)
class IdDecision:
    persona_id: str
    version: int
    action: str
    person_id: int | None
    candidate_rank: int | None
    note: str
    line: int


def _best(r: dict) -> tuple:
    c = r["candidates"][0] if r["candidates"] else None
    return (TIER_ORDER[c["tier"]] if c else 3, -(c["score"] if c else 0), r["source_persona_id"])


def sheet_order(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=_best)


def render_sheet(rows: list[dict]) -> str:
    out = ["# IDENTITETSAFGØRELSER (trin 5a)",
           "# Efter kolonet: 1/2/3 = samme som kandidat nr., 'P <id>' = samme som anden person,",
           "# X = en anden person (ikke i basen), N = ny person nødvendig, U = uafklaret.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    for r in sheet_order(rows):
        out.append(f"# POST {r['record_key']} · persona: {r['name'] or '(intet navn)'} · nævnt som: {r['mention_role']}")
        fort = " · ".join(f"{i['predicate']} {i['value_text']} ({i['status']})" for i in r["interpretations"])
        out.append(f"#   fortolkninger: {fort or 'ingen'}")
        if not r["candidates"]:
            out.append("#   ingen kandidat")
        for c in r["candidates"]:
            out.append(f"#   {c['rank']}: person {c['person_id']}  {c['person_name']}  {c['born'] or '?'}–{c['died'] or '?'}"
                       f"  score {c['score']}  {c['tier']}  [{', '.join(c['signals'])}]")
        out.append("#   ingen anbefaling udfyldt — vælg selv")
        out.append(f"D {r['source_persona_id']} {r['version']} : _")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[IdDecision]:
    decisions, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.startswith("D "):
            if line.lstrip().startswith("D "):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")
            continue
        m = LINE_RE.match(line)
        if not m:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}" if LOOSE_RE.match(line) else f"SHEET_LINE_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        tok, note = m["tok"], (m["note"] or "").strip()
        if tok == "_":
            undecided.append(n)
            continue
        if tok in "123":
            d = IdDecision(m["id"], int(m["ver"]), "same", None, int(tok), note, n)
        elif tok.startswith("P "):
            d = IdDecision(m["id"], int(m["ver"]), "same", int(tok[2:]), None, note, n)
        else:
            d = IdDecision(m["id"], int(m["ver"]), {"X": "different", "N": "new_person_needed", "U": "unresolved"}[tok],
                           None, None, note, n)
        decisions.append(d)
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return decisions


def check_identity(decisions: list[IdDecision], rows: list[dict]) -> None:
    forventet = {(r["source_persona_id"], r["version"]) for r in rows}
    faktisk = {(d.persona_id, d.version) for d in decisions}
    if faktisk != forventet:
        raise SheetError(f"SHEET_IDENTITY_MISMATCH mangler={len(forventet - faktisk)} ekstra={len(faktisk - forventet)}")
    for d, r in zip(decisions, sheet_order(rows)):
        if (d.persona_id, d.version) != (r["source_persona_id"], r["version"]):
            raise SheetError(f"SHEET_ORDER_MISMATCH line={d.line}")


def check_render(text: str, rows: list[dict]) -> None:
    """Arket skal være præcis det, render_sheet byggede af rækkefilen — kun token og note på D-linjerne
    må være ændret. Ellers kan en rettet kandidatlinje vise én person, mens tokenet binder en anden."""
    forventet, faktisk = render_sheet(rows).splitlines(), text.splitlines()
    if len(faktisk) != len(forventet):
        raise SheetError(f"SHEET_RENDER_MISMATCH lines={len(faktisk)} forventet={len(forventet)}")
    for n, (f, a) in enumerate(zip(forventet, faktisk), 1):
        if f.startswith("D "):
            if not a.startswith(f[:f.rindex(" : ") + 3]):
                raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")
        elif a != f:
            raise SheetError(f"SHEET_RENDER_MISMATCH line={n}")


def decision_sql(decisions: list[IdDecision], rows: list[dict], *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    by_id = {r["source_persona_id"]: r for r in rows}
    # Kandidatens kørsel sendes med; RPC'en afviser en forældet kørsel under kildelåsen (Task 3).
    out = ["\\set ON_ERROR_STOP on", "BEGIN;"]
    out += ["SET LOCAL ROLE authenticated;", "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
            "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    for d in decisions:
        r = by_id[d.persona_id]
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": d.line}
        person = d.person_id
        if d.candidate_rank is not None:
            cand = next((c for c in r["candidates"] if c["rank"] == d.candidate_rank), None)
            if cand is None:
                raise SheetError(f"SHEET_CANDIDATE_MISSING line={d.line}")
            person, ctx["candidate_id"], ctx["run_id"] = cand["person_id"], cand["candidate_id"], r["run_id"]
        note = f"ark {sheet_sha256[:12]} linje {d.line}" + (f" — {d.note}" if d.note else "")
        person_sql = str(int(person)) if person is not None else "NULL"
        out.append(f"INSERT INTO decided SELECT red_afgoer_source_persona('{d.persona_id}'::uuid, {d.version}, "
                   f"'{d.action}', {person_sql}, {sql_literal(note)}, "
                   f"{sql_literal(json.dumps(ctx, ensure_ascii=False, sort_keys=True))}::jsonb);")
    out.append("DO $$ BEGIN IF (SELECT count(*) FROM decided) <> "
               f"{len(decisions)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("--rows", required=True); r.add_argument("--out", required=True)
    s = sub.add_parser("sql")
    for a in ("--sheet", "--approved-sha256", "--rows", "--expect-rows-sha256", "--out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    rows_bytes = Path(args.rows).read_bytes()
    rows = json.loads(rows_bytes.decode("utf-8"))
    if args.cmd == "render":
        out = Path(args.out); out.write_text(render_sheet(rows), encoding="utf-8"); out.chmod(0o600)
        print(f"ARK_OK linjer={len(rows)} uden_kandidat={sum(1 for x in rows if not x['candidates'])}")
        print(f"  rows_sha256 {hashlib.sha256(rows_bytes).hexdigest()}")
        return 0
    try:
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256,
                                           Path(args.sheet).read_bytes(), args.approved_sha256)
        check_render(Path(args.sheet).read_text(encoding="utf-8"), rows)
        decisions = parse_sheet(Path(args.sheet).read_text(encoding="utf-8"))
        check_identity(decisions, rows)
        sql = decision_sql(decisions, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc))
        return 1
    out = Path(args.out); out.write_text(sql, encoding="utf-8"); out.chmod(0o600)
    tal = {a: sum(1 for d in decisions if d.action == a) for a in ("same", "different", "new_person_needed", "unresolved")}
    print(f"SQL_OK afgørelser={len(decisions)} {tal}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Kør** testfilen — Expected: 11 passed.

- [ ] **Step 6: Ingen springede tests.** Aktualiteten testes i SQL (Task 3, i CI), ikke med en betinget pytest. Kør `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_identity_decision_sheet.py -q -rs`. Expected: 11 passed, 0 skipped.

- [ ] **Step 7: Rækkefil-eksport** `identity_sheet_rows.sql` (læse-kun; `:source_id`, `:mode` = `undecided`|`list`, `:personas`):

```sql
-- Trin 5a: rækkefil til identitetsarket. Indeholder navne → 0600 under ~/.private/5a/.
SET default_transaction_read_only=on;
WITH latest AS (
  SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=:source_id
   ORDER BY run_seq DESC LIMIT 1
), personas AS (
  SELECT p.id, p.source_id, p.persona_key, coalesce(i.version,0) AS version
    FROM private.source_persona p LEFT JOIN private.source_persona_identity i ON i.source_persona_id=p.id
   WHERE p.source_id=:source_id
     AND ((:'mode'='undecided' AND (i.source_persona_id IS NULL OR i.decision_status='proposed'))
       OR (:'mode'='list' AND p.id = ANY(string_to_array(:'personas',',')::uuid[])))
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
  'source_persona_id',pe.id::text,'version',pe.version,'source_id',pe.source_id,'persona_key',pe.persona_key,
  'record_key',(SELECT sr.record_key FROM private.source_persona_mention spm
                  JOIN private.source_mention sm ON sm.id=spm.mention_id
                  JOIN private.source_observation so ON so.id=sm.observation_id
                  JOIN private.source_record_anchor_current ac ON ac.occurrence_id=so.occurrence_id AND ac.decision_status='accepted'
                  JOIN private.source_record sr ON sr.id=ac.source_record_id
                 WHERE spm.persona_id=pe.id ORDER BY spm.ordinal LIMIT 1),
  'mention_role',(SELECT spm.mention_role FROM private.source_persona_mention spm WHERE spm.persona_id=pe.id ORDER BY spm.ordinal LIMIT 1),
  'name',(SELECT ic.value #>> '{}' FROM private.interpretation_current ic WHERE ic.source_persona_id=pe.id AND ic.predicate='person.name'
           AND ic.status IN ('accepted','proposed') ORDER BY (ic.status='accepted') DESC, ic.id LIMIT 1),
  'name_origin',NULL,
  'interpretations',coalesce((SELECT jsonb_agg(jsonb_build_object('predicate',ic.predicate,'status',ic.status,
       'value_text',CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END) ORDER BY ic.predicate,ic.id)
     FROM private.interpretation_current ic WHERE ic.source_persona_id=pe.id AND ic.status IN ('accepted','proposed')),'[]'::jsonb),
  'run_id',(SELECT id::text FROM latest),
  'candidates',coalesce((SELECT jsonb_agg(jsonb_build_object('candidate_id',c.id::text,'rank',c.rank,'person_id',c.candidate_person_id,
       'person_name',p.visning_navn,'born',p.visning_foedt,'died',p.visning_doed,'score',c.score,'tier',c.tier,
       'signals',c.basis->'signals') ORDER BY c.rank)
     FROM private.source_persona_identity_candidate c JOIN public.person p ON p.id=c.candidate_person_id
     WHERE c.source_persona_id=pe.id AND c.run_id=(SELECT id FROM latest)),'[]'::jsonb)
) ORDER BY pe.id),'[]'::jsonb) FROM personas pe;
```

- [ ] **Step 8: Refaktorér 4.5-arket til kernen** (adfærd uændret). I `interpretation_decision_sheet.py`: fjern den lokale `class SheetError` og `def _lit`, og tilføj under importerne:

```python
from decision_sheet_core import SheetError, require_hex64, sql_literal as _lit, verify_bound
```

Erstat i `decision_sql` løkken `for h in (sheet_sha256, rows_sha256): …` med `require_hex64(sheet_sha256, rows_sha256)`. Erstat i `main` de to hash-tjek (`if rows_sha != args.expect_rows_sha256: …` og `if faktisk != args.approved_sha256: …`) med:

```python
    try:
        rows_sha, faktisk = verify_bound(rows_bytes, args.expect_rows_sha256,
                                         Path(args.sheet).read_bytes(), args.approved_sha256)
    except SheetError as exc:
        print(str(exc))
        return 1
    data = Path(args.sheet).read_bytes()
```

4.5-arket har fået underkommandoen `html` (commit 769e82c på `feat/147-4-5-pilot`, `decision_sheet_html.py`); den skal virke uændret efter refaktoreringen. Kør: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_interpretation_decision_sheet.py test_decision_sheet_html.py test_control_model.py test_evidence_runner.py test_identity_decision_sheet.py -q`. Expected: alle eksisterende tests uændret grønne + 11 nye; `SHEET_METHOD_INVALID` kommer stadig før hashfejl.

- [ ] **Step 9: CI** — tilføj `.claude/skills/daa-extract/scripts/test_identity_decision_sheet.py` i pytest-listen i trinnet `evidence builders/runner/comparators · pytest`.

- [ ] **Step 10: Commit**

```bash
git add .claude/skills/daa-extract/scripts/decision_sheet_core.py .claude/skills/daa-extract/scripts/identity_decision_sheet.py \
        .claude/skills/daa-extract/scripts/test_identity_decision_sheet.py .claude/skills/daa-extract/scripts/identity_sheet_rows.sql \
        .claude/skills/daa-extract/scripts/interpretation_decision_sheet.py .github/workflows/ci.yml
git commit -m "feat(151): identitetsark med kandidat-tokens og fælles arkkerne"
```

---

### Task 8: Webkøen

**Files:**
- Modify: `web/src/data/sourcePersona.ts`, `web/src/components/KildepersonaKo.tsx`
- Modify: `web/src/data/__tests__/sourcePersona.test.ts`, `web/src/components/__tests__/KildepersonaKo.test.tsx`

**Interfaces:**
- Consumes: `red_afgoer_source_persona(…, p_context)`, `red_source_persona_detail` (`candidates`, `collisions`), `red_source_persona_queue` (`best_tier`, `reason`), `red_source_persona_history`.
- Produces: `SourcePersonaAction = 'same' | 'different' | 'unresolved' | 'new_person_needed'`; `buildSourcePersonaDecisionCall(id, version, action, personId, note, candidate?: { candidateId: string; runId: string } | null)` → args inkl. `p_context: { basis: 'web_detail', candidate_id?, run_id? }` (kandidat og kørsel altid sammen); `decideSourcePersona(…, candidate?)`; `fetchSourcePersonaHistory(id): Promise<SourcePersonaHistoryRow[]>`; `SourcePersonaDetail.candidates: SourcePersonaCandidate[]`, `.collisions: Array<{ personId: number; personaKey: string }>`; kø-rækken får `bestTier: string | null`, `reason: string | null`.

- [ ] **Step 1: Fejlende datatest** — erstat `web/src/data/__tests__/sourcePersona.test.ts` med:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.hoisted(() => vi.fn());
vi.mock('../../supabase', () => ({ supabase: { rpc } }));

import { buildSourcePersonaDecisionCall, fetchSourcePersonaDetail, fetchSourcePersonaHistory, fetchSourcePersonaQueue } from '../sourcePersona';

const ID = '00000000-0000-0000-0000-000000000001';

describe('mapping fra RPC (snake_case → camelCase)', () => {
  beforeEach(() => rpc.mockReset());

  it('kø: best_tier og reason, null når de mangler', async () => {
    const base = { source_persona_id: ID, source_id: 1, persona_key: 'k', decision_status: 'unresolved', version: 2, canonical_person_id: null, mention_count: 1 };
    rpc.mockResolvedValue({ data: [{ ...base, best_tier: 'review', reason: 'new_person_needed' }, base], error: null });
    const rows = await fetchSourcePersonaQueue('new_person_needed');
    expect(rows.map((r) => [r.bestTier, r.reason])).toEqual([['review', 'new_person_needed'], [null, null]]);
  });

  it('detalje: kandidater og kollisioner', async () => {
    rpc.mockResolvedValue({ data: {
      persona: { source_persona_id: ID, source_id: 1, persona_key: 'k', decision_status: 'proposed', version: 0, canonical_person_id: null },
      mentions: [], placements: [], interpretations: [],
      candidates: [{ candidate_id: 'c1', run_id: 'r1', rank: 1, score: 0.93, tier: 'auto', person_id: 42, person_name: 'X', born: '1800', died: null, basis: { signals: ['name', 'birth'] } }],
      collisions: [{ person_id: 42, persona_key: 'persona-9' }],
    }, error: null });
    const d = await fetchSourcePersonaDetail(ID);
    expect(d.candidates).toEqual([{ candidateId: 'c1', runId: 'r1', rank: 1, score: 0.93, tier: 'auto', personId: 42, personName: 'X', born: '1800', died: null, signals: ['name', 'birth'] }]);
    expect(d.collisions).toEqual([{ personId: 42, personaKey: 'persona-9' }]);
  });

  it('historik: basis, kandidat fulgt og årsag fra evidensen', async () => {
    rpc.mockResolvedValue({ data: [
      { version: 3, decision_status: 'unresolved', canonical_person_id: null, evidence: { basis: 'human_sheet', reason: 'new_person_needed' }, decided_by_name: 'R', decided_at: '2026-10-05T00:00:00Z' },
      { version: 2, decision_status: 'accepted', canonical_person_id: 42, evidence: { basis: 'web_detail', candidate_id: 'c1' }, decided_by_name: null, decided_at: null },
    ], error: null });
    expect(await fetchSourcePersonaHistory(ID)).toEqual([
      { version: 3, decisionStatus: 'unresolved', canonicalPersonId: null, basis: 'human_sheet', candidateId: null, reason: 'new_person_needed', decidedByName: 'R', decidedAt: '2026-10-05T00:00:00Z' },
      { version: 2, decisionStatus: 'accepted', canonicalPersonId: 42, basis: 'web_detail', candidateId: 'c1', reason: null, decidedByName: null, decidedAt: null },
    ]);
  });
});

describe('buildSourcePersonaDecisionCall', () => {
  it('sender person, note og web-basis ved samme identitet', () => {
    expect(buildSourcePersonaDecisionCall(ID, 2, 'same', 42, 'samme ægtefælle og dato')).toEqual({
      fn: 'red_afgoer_source_persona', args: {
        p_source_persona_id: ID, p_expected_version: 2, p_action: 'same', p_canonical_person_id: 42,
        p_note: 'samme ægtefælle og dato', p_context: { basis: 'web_detail' },
      },
    });
  });

  it('binder den fulgte kandidat i konteksten', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'same', 42, 'kandidat', { candidateId: 'cand-1', runId: 'run-1' })?.args.p_context)
      .toEqual({ basis: 'web_detail', candidate_id: 'cand-1', run_id: 'run-1' });
  });

  it('ny person nødvendig sendes uden person', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'new_person_needed', null, 'findes ikke')?.args.p_action).toBe('new_person_needed');
  });

  it.each([
    ['same', null, 'basis'], ['different', 42, 'basis'], ['unresolved', 42, 'basis'], ['new_person_needed', 42, 'basis'],
    ['same', 42, '   '], ['same', 42, 'basis', -1],
  ] as const)('afviser fail-closed ugyldig afgørelse %s', (action, personId, note, version = 0) => {
    expect(buildSourcePersonaDecisionCall('persona', version, action, personId, note)).toBeNull();
  });

  it('kandidat uden samme-handling afvises', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'different', null, 'x', { candidateId: 'cand-1', runId: 'run-1' })).toBeNull();
  });
});
```

- [ ] **Step 2: Fejlende komponenttest** — tilføj i `KildepersonaKo.test.tsx` (mocken af `fetchRedaktionPersoner` hedder i testen `mocks.persons`; hedder den noget andet i den eksisterende fil, brug det navn og notér det): udvid `vi.mock('../../data/sourcePersona', …)` med `fetchSourcePersonaHistory: mocks.history` (tilføj `history: vi.fn()` i `mocks` og `mocks.history.mockResolvedValue([])` i `beforeEach`), sæt `detail` til også at have `candidates` og `collisions`:

```tsx
const detail = {
  persona: row(),
  mentions: [{ mentionKind: 'person_name', mentionRole: 'primary', verbatimText: 'Johan Example', observationKind: 'name_clause', pageFrom: 12, pageTo: 12, textVersions: [] }],
  placements: [], interpretations: [],
  candidates: [{ candidateId: 'cand-1', runId: 'run-1', rank: 1, score: 0.93, tier: 'auto', personId: 42, personName: 'Johan Canonical', born: '1800', died: '1860', signals: ['name', 'birth'] }],
  collisions: [{ personId: 42, personaKey: 'persona-9' }],
};
```

og tilføj tests (eksisterende tests forventer nu ét ekstra argument `null` for kandidat — opdater deres `toHaveBeenCalledWith(…, note)` til `toHaveBeenCalledWith(…, note, null)`):

```tsx
  it('følger en kandidat med ét klik og sender kandidat-id', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByRole('button', { name: 'Samme som kandidat 1' });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'navn og år' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme som kandidat 1' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 42, 'navn og år', { candidateId: 'cand-1', runId: 'run-1' }));
  });

  it('søger en person, der ikke er kandidat, og vælger den uden kandidatspor', async () => {
    mocks.persons.mockResolvedValue([
      { id: '42', navn: 'Johan Canonical', aar: '1800', born: 1800, levende: false, privat: false },
      { id: '77', navn: 'Anna Anden', aar: '1790', born: 1790, levende: false, privat: false },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    fireEvent.change(await screen.findByLabelText('Søg person'), { target: { value: 'anna' } });
    fireEvent.change(screen.getByLabelText('Kanonisk kandidat'), { target: { value: '77' } });
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'fundet ved søgning' } });
    fireEvent.click(screen.getByRole('button', { name: 'Samme person' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'same', 77, 'fundet ved søgning', null));
    // (Kræver RedPerson-felter ud over disse, så tilføj dem med neutrale værdier — typen står i web/src/data/redaktionRead.ts:15.)
  });

  it('viser kollision uden at blokere', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText(/allerede accepteret for persona-9/)).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Samme som kandidat 1' }) as HTMLButtonElement).disabled).toBe(false);
  });

  it('sender ny person nødvendig uden person', async () => {
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    await screen.findByText('Johan Example');
    fireEvent.change(screen.getByLabelText('Begrundelse'), { target: { value: 'ikke i basen' } });
    fireEvent.click(screen.getByRole('button', { name: 'Ny person nødvendig' }));
    await waitFor(() => expect(mocks.decide).toHaveBeenCalledWith(row().sourcePersonaId, 0, 'new_person_needed', null, 'ikke i basen', null));
  });

  it('viser historik med kandidat fulgt og ny person nødvendig', async () => {
    mocks.history.mockResolvedValue([
      { version: 2, decisionStatus: 'unresolved', canonicalPersonId: null, basis: 'human_sheet', candidateId: null, reason: 'new_person_needed', decidedByName: 'R', decidedAt: null },
      { version: 1, decisionStatus: 'accepted', canonicalPersonId: 42, basis: 'web_detail', candidateId: 'cand-1', reason: null, decidedByName: 'R', decidedAt: null },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Vis kildegrundlag' }));
    expect(await screen.findByText(/v1 · accepted · #42 · web_detail · kandidat fulgt/)).toBeTruthy();
    expect(screen.getByText(/v2 · unresolved · human_sheet · ny person nødvendig/)).toBeTruthy();
  });

  it('sorterer køen auto → review → none → ingen kandidat', async () => {
    mocks.queue.mockResolvedValue([
      { ...row(1), bestTier: null, reason: null }, { ...row(2), bestTier: 'none', reason: null },
      { ...row(3), bestTier: 'auto', reason: null }, { ...row(4), bestTier: 'review', reason: null },
    ]);
    render(<KildepersonaKo role="redaktion" />);
    await screen.findByText('persona-3');
    const tekst = document.body.textContent ?? '';
    const pos = ['persona-3', 'persona-4', 'persona-2', 'persona-1'].map((k) => tekst.indexOf(k));
    expect(pos.every((p) => p >= 0)).toBe(true);
    expect(pos).toEqual([...pos].sort((a, b) => a - b));
  });
```

- [ ] **Step 3: Kør** `npm run test -w daa-folgesvend-web -- sourcePersona KildepersonaKo > /tmp/claude-501/w.log 2>&1; tail -8 /tmp/claude-501/w.log` — Expected: FAIL (ukendt knap `Samme som kandidat 1`, manglende `p_context`).

- [ ] **Step 4: Datalaget** — i `web/src/data/sourcePersona.ts`:

```ts
export type SourcePersonaAction = 'same' | 'different' | 'unresolved' | 'new_person_needed';

export type SourcePersonaCandidate = {
  candidateId: string; runId: string; rank: number; score: number; tier: string;
  personId: number; personName: string; born: string | null; died: string | null; signals: string[];
};
export type SourcePersonaHistoryRow = {
  version: number; decisionStatus: string; canonicalPersonId: number | null;
  basis: string | null; candidateId: string | null; reason: string | null; decidedByName: string | null; decidedAt: string | null;
};
```

Udvid `SourcePersonaQueueRow` med `bestTier: string | null; reason: string | null;` (mappet fra `row.best_tier`/`row.reason`, `null` hvis fraværende), `SourcePersonaDetail` med `candidates: SourcePersonaCandidate[]; collisions: Array<{ personId: number; personaKey: string }>;`. Erstat `buildSourcePersonaDecisionCall` og `decideSourcePersona`:

```ts
export function buildSourcePersonaDecisionCall(
  sourcePersonaId: string, expectedVersion: number, action: SourcePersonaAction,
  canonicalPersonId: number | null, note: string, candidate: { candidateId: string; runId: string } | null = null,
) {
  if (!sourcePersonaId || !Number.isInteger(expectedVersion) || expectedVersion < 0 || !note.trim()) return null;
  if (action === 'same' && (canonicalPersonId == null || !Number.isSafeInteger(canonicalPersonId) || canonicalPersonId <= 0)) return null;
  if (action !== 'same' && (canonicalPersonId !== null || candidate !== null)) return null;
  return {
    fn: 'red_afgoer_source_persona' as const,
    args: {
      p_source_persona_id: sourcePersonaId, p_expected_version: expectedVersion, p_action: action,
      p_canonical_person_id: canonicalPersonId, p_note: note.trim(),
      p_context: candidate ? { basis: 'web_detail', candidate_id: candidate.candidateId, run_id: candidate.runId } : { basis: 'web_detail' },
    },
  };
}

export async function decideSourcePersona(
  sourcePersonaId: string, expectedVersion: number, action: SourcePersonaAction,
  canonicalPersonId: number | null, note: string, candidate: { candidateId: string; runId: string } | null = null,
): Promise<number> {
  const call = buildSourcePersonaDecisionCall(sourcePersonaId, expectedVersion, action, canonicalPersonId, note, candidate);
  if (!call) throw new Error('Ugyldig identitetsafgørelse.');
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  return Number(data);
}

export async function fetchSourcePersonaHistory(sourcePersonaId: string): Promise<SourcePersonaHistoryRow[]> {
  const { data, error } = await supabase.rpc('red_source_persona_history', { p_source_persona_id: sourcePersonaId });
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: Record<string, unknown>) => {
    const ev = (r.evidence ?? {}) as Record<string, unknown>;
    return {
      version: Number(r.version), decisionStatus: String(r.decision_status),
      canonicalPersonId: r.canonical_person_id == null ? null : Number(r.canonical_person_id),
      basis: ev.basis == null ? null : String(ev.basis), candidateId: ev.candidate_id == null ? null : String(ev.candidate_id),
      reason: ev.reason == null ? null : String(ev.reason),
      decidedByName: r.decided_by_name == null ? null : String(r.decided_by_name),
      decidedAt: r.decided_at == null ? null : String(r.decided_at),
    };
  });
}
```

I `fetchSourcePersonaDetail` tilføj efter `interpretations`:

```ts
      candidates: Array.isArray(raw.candidates) ? raw.candidates.map((c) => {
        const v = c as Record<string, unknown>;
        return { candidateId: String(v.candidate_id), runId: String(v.run_id), rank: Number(v.rank), score: Number(v.score),
          tier: String(v.tier), personId: Number(v.person_id), personName: String(v.person_name ?? ''),
          born: v.born == null ? null : String(v.born), died: v.died == null ? null : String(v.died),
          signals: Array.isArray((v.basis as Record<string, unknown> | undefined)?.signals) ? ((v.basis as Record<string, unknown>).signals as unknown[]).map(String) : [] };
      }) : [],
      collisions: Array.isArray(raw.collisions) ? raw.collisions.map((c) => {
        const v = c as Record<string, unknown>;
        return { personId: Number(v.person_id), personaKey: String(v.persona_key) };
      }) : [],
```

- [ ] **Step 5: Komponenten** — i `KildepersonaKo.tsx`:
  1. Importér `fetchSourcePersonaHistory` og typen `SourcePersonaHistoryRow`; ny state `const [history, setHistory] = useState<SourcePersonaHistoryRow[]>([]);`; hent den i `showEvidence` sammen med detaljen (`Promise.all([... , fetchSourcePersonaHistory(row.sourcePersonaId)])`).
  2. **Personsøgning (spec §7):** et filterfelt over den eksisterende personliste (`fetchRedaktionPersoner`, allerede hentet i `showEvidence`): ny state `personFilter`, et `<input aria-label="Søg person">` over select'en, og select'en viser kun `candidates.filter((p) => !personFilter.trim() || p.navn.toLowerCase().includes(personFilter.trim().toLowerCase()) || String(p.id) === personFilter.trim()).slice(0, 50)`.
  2b. `decide` får signaturen `(row, action, personId: number | null = null, candidate: { candidateId: string; runId: string } | null = null)`; target bliver `action === 'same' ? (personId ?? sourceIdFromInput(pickedPersonId)) : null`, og kaldet bliver `decideSourcePersona(row.sourcePersonaId, row.version, action, target, note, candidate)`. (Omdøb den eksisterende state `candidateId` til `pickedPersonId` for at undgå navnesammenfald; select'en ændrer den.)
  3. Status-select'en får valgmuligheden `new_person_needed`; rækkerne sorteres inden for siden: `const shown = [...rows].sort((a, b) => (TIER[a.bestTier ?? ''] ?? 3) - (TIER[b.bestTier ?? ''] ?? 3));` med `const TIER: Record<string, number> = { auto: 0, review: 1, none: 2 };`, og `rows.map` → `shown.map`; vis `· {row.bestTier ?? 'ingen kandidat'}` og `· ny person nødvendig` når `row.reason === 'new_person_needed'`.
  4. Ny knap i rækken efter »Uafklaret«: `<button disabled={busy === row.sourcePersonaId} onClick={() => void decide(row, 'new_person_needed')}>Ny person nødvendig</button>`.
  5. I `aside` før »Kanonisk kandidat«-select'en:

```tsx
        {detail.candidates.length ? <div style={{ marginTop: 12 }}>
          <strong>Maskinens kandidater</strong>
          {detail.candidates.map((c) => {
            const kollision = detail.collisions.find((k) => k.personId === c.personId);
            return <div key={c.candidateId} style={{ marginTop: 6, padding: 8, border: '1px solid #cabfa9', borderRadius: 6 }}>
              {c.rank}. {c.personName} · #{c.personId} · {c.born ?? '?'}–{c.died ?? '?'} · score {c.score} · {c.tier} · [{c.signals.join(', ')}]
              {kollision && <div role="note" style={{ color: '#8a5a00', fontSize: 12 }}>Obs: allerede accepteret for {kollision.personaKey}</div>}
              <div><button disabled={busy === detail.persona.sourcePersonaId}
                onClick={() => { const r = rows.find((x) => x.sourcePersonaId === detail.persona.sourcePersonaId); if (r) void decide(r, 'same', c.personId, { candidateId: c.candidateId, runId: c.runId }); }}>
                Samme som kandidat {c.rank}</button></div>
            </div>;
          })}
        </div> : <p style={{ fontSize: 12 }}>Ingen kandidater fra generatoren.</p>}
        {history.length > 0 && <div style={{ marginTop: 12, fontSize: 12 }}>
          <strong>Historik</strong>
          {history.map((h) => <div key={h.version}>v{h.version} · {h.decisionStatus}{h.canonicalPersonId ? ` · #${h.canonicalPersonId}` : ''} · {h.basis ?? 'migration'}{h.candidateId ? ' · kandidat fulgt' : ''}{h.reason === 'new_person_needed' ? ' · ny person nødvendig' : ''} · {h.decidedByName ?? ''}</div>)}
        </div>}
```

- [ ] **Step 6: Kør** web-testene og typecheck:

```bash
npm run test -w daa-folgesvend-web -- sourcePersona KildepersonaKo > /tmp/claude-501/w.log 2>&1; tail -6 /tmp/claude-501/w.log
npm run build -w daa-folgesvend-web > /tmp/claude-501/wb.log 2>&1; echo "build rc=$?"
```

Expected: alle PASS; `build rc=0`.

- [ ] **Step 7: Commit**

```bash
git add web/src/data/sourcePersona.ts web/src/components/KildepersonaKo.tsx web/src/data/__tests__/sourcePersona.test.ts web/src/components/__tests__/KildepersonaKo.test.tsx
git commit -m "feat(151): webkø med maskinens kandidater, kollisionsadvarsel, ny-person-knap og historik"
```

---

### Task 9: Færdigbevis i restoren, rapport og status

> **Genbekræftet 2026-10-05 — besluttet:** kalibreringen og genbekræftelsen kører i en kopi af den fulde 2018-20-kørsels base `daa2018f_20261001133125` (projektejerens valg; spec §8.1 og §16). Basen selv skrives aldrig i.

**Files:**
- Create: `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md`
- Modify: `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`

**Interfaces:**
- Consumes: alt ovenfor. Arbejdsbasen er en kopi af den fulde 2018-20-kørsels base `daa2018f_20261001133125` (den indeholder `person.name`-fortolkninger for alle 488 tilladte poster), aldrig basen selv og aldrig prod.

- [ ] **Step 1: Arbejdsbase.** `W5=daa5a_bevis_$(date +%Y%m%d%H%M%S); createdb -T daa2018f_20261001133125 "$W5"` (ingen må være forbundet til skabelonen), kør `db-migrations.sql` og `db-rls.sql` mod den (output til fil, `grep -c ERROR` = 0). Findes basen ikke: STOP — spørg projektejeren. Aktør: `A=$(psql -X -At -d "$W5" -c "SELECT id FROM profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1")`.

- [ ] **Step 2: Kalibrering (§8.1).** For kilde 1 (2018-20), `mode=list` med alle accepterede personas:

```bash
set -o pipefail
L=$(psql -X -At -d "$W5" -c "SELECT string_agg(i.source_persona_id::text,',') FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.source_id=1 AND i.decision_status='accepted'")
psql -X -q -At -d "$W5" -v actor=$A -v source_id=1 -v mode=list -v personas="$L" -f packages/identity-candidates/sql/export-input.sql | grep '^{' > ~/.private/5a/k-input.json
psql -X -q -At -d "$W5" -v source_id=1 -f packages/identity-candidates/sql/export-truth.sql > ~/.private/5a/k-truth.json
for mode in std norm; do
  X=$([ $mode = norm ] && echo --evidens-normaliseret)
  npm run cli -w @daa/identity-candidates -- generate --input ~/.private/5a/k-input.json --source-id 1 --out ~/.private/5a/k-cand-$mode.json $X > ~/.private/5a/k-gen-$mode.out 2>&1
  npm run cli -w @daa/identity-candidates -- calibrate --candidates ~/.private/5a/k-cand-$mode.json --truth ~/.private/5a/k-truth.json > ~/.private/5a/k-cal-$mode.out 2>&1
  grep -E '^CANDIDATES_OK|^CALIBRATION' ~/.private/5a/k-gen-$mode.out ~/.private/5a/k-cal-$mode.out
done
```

Outputtet er kun tal og må læses. Kalibreringen skriver intet i databasen. Notér begge konfigurationers tal; vælg konfiguration på tallene (top-1 og præcision for `auto`) og notér valget som ruling.

- [ ] **Step 3: Blind genbekræftelse (§8.2).** Reservér **først** én persona med kandidat til webspor-pariteten (den første `review`, ellers den første `auto`, ellers den første `none`), og vælg derefter op til 30 af de øvrige, stratificeret på rang-1-tier (`auto` op til 12, `review` op til 12, `none` op til 6; færre findes, tages alle):

```bash
node -e '
const d=require(process.env.HOME+"/.private/5a/k-cand-'"$VALGT"'.json");const by={auto:[],review:[],none:[]};
for(const c of d.candidates) if(c.rank===1) by[c.tier].push(c.source_persona_id);
for(const t of ["auto","review","none"]) by[t].sort();
const web=(by.review.shift()??by.auto.shift()??by.none.shift());
if(!web){console.error("INGEN_PERSONA_MED_KANDIDAT");process.exit(1);}
const pick=[...by.auto.slice(0,12),...by.review.slice(0,12),...by.none.slice(0,6)];
console.log(pick.join(","));console.error(web);' > ~/.private/5a/g-personas.txt 2> ~/.private/5a/g-web.txt
wc -c < ~/.private/5a/g-personas.txt
```

(`VALGT` = `std` eller `norm` fra Step 2; sæt `X=$([ "$VALGT" = norm ] && echo --evidens-normaliseret)`.) Skriv stikprøvens **og** webspor-personaens kandidater til basen i én kørsel (den bliver gældende kørsel), og byg rækkefilen og arket **kun** for stikprøven:

```bash
set -o pipefail
G=$(cat ~/.private/5a/g-personas.txt); WEB=$(cat ~/.private/5a/g-web.txt)
psql -X -q -At -d "$W5" -v actor=$A -v source_id=1 -v mode=list -v personas="$G,$WEB" -f packages/identity-candidates/sql/export-input.sql | grep '^{' > ~/.private/5a/g-input.json
npm run cli -w @daa/identity-candidates -- generate --input ~/.private/5a/g-input.json --source-id 1 --out ~/.private/5a/g-cand.json $X
psql -X -At -d "$W5" -v actor=$A -v cand_file=$HOME/.private/5a/g-cand.json -f packages/identity-candidates/sql/write-candidates.sql
psql -X -q -At -d "$W5" -v source_id=1 -v mode=list -v personas="$G" -f .claude/skills/daa-extract/scripts/identity_sheet_rows.sql > ~/.private/5a/g-rows.json
chmod 600 ~/.private/5a/*.json
python3 .claude/skills/daa-extract/scripts/identity_decision_sheet.py render --rows ~/.private/5a/g-rows.json --out ~/.private/5a/IDENTITET.txt
```

Arket viser **ikke** det gamle svar (rækkefilen indeholder kun kandidater). **STOP:** projektejeren udfylder `~/.private/5a/IDENTITET.txt` og giver `shasum -a 256 ~/.private/5a/IDENTITET.txt` i chatten.

Webkøen startes **ikke** mod arbejdsbasen (der findes ingen lokal Supabase-API; webben må aldrig pege på en ukendt base — spec §8.2). Webspor-pariteten: projektejeren afgør webspor-personaen ud fra kandidatlisten (tallet 1–3, eller `X`/`N`/`U`, sagt i chatten); agenten sender derefter præcis den payload, Task 8's vitest fastlåser (`p_context: {basis:'web_detail', candidate_id, run_id}`), via psql:

```bash
psql -X -At -d "$W5" -v actor=$A -v p="$WEB" -v rank=<tal> -f - > ~/.private/5a/web.out 2>&1 <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
CREATE TEMP TABLE k ON COMMIT DROP AS
  SELECT c.id, c.run_id, c.candidate_person_id, coalesce(i.version,0) AS v
    FROM private.source_persona_identity_candidate c
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=c.source_persona_id
   WHERE c.source_persona_id=:'p'::uuid AND c.rank=:rank
     AND c.run_id=(SELECT r.id FROM private.source_persona_identity_candidate_run r WHERE r.source_id=1 ORDER BY r.run_seq DESC LIMIT 1);
GRANT SELECT ON k TO authenticated;   -- temp-tabellen ejes af ejeren; uden grant kan authenticated ikke læse den
SET LOCAL ROLE authenticated;
SELECT red_afgoer_source_persona(:'p'::uuid, k.v, 'same', k.candidate_person_id, 'webspor-paritet',
       jsonb_build_object('basis','web_detail','candidate_id',k.id,'run_id',k.run_id)) FROM k;
COMMIT;
SQL
grep -c ERROR ~/.private/5a/web.out
```

(Ved `X`/`N`/`U` bruges handlingen `different`/`new_person_needed`/`unresolved`, person `NULL` og konteksten `{"basis":"web_detail"}`.) Expected: `0`.

- [ ] **Step 4: Oversæt og kør** (efter hash): `sql` med `--approved-sha256 <hash> --expect-rows-sha256 <render-output>`; negativtest først (kopiér SQL'en, ændr sidste linjes version med +1 og kør: skal fejle med `EVIDENCE_IDENTITY_VERSION_CONFLICT` og efterlade 0 nye hændelser — tæl `private.source_persona_identity_event` før og efter), derefter den rigtige med `psql -v actor=$A`. Sammenlign bagefter med det gamle svar — kun tal:

```sql
SELECT count(*) FILTER (WHERE e_new.decision_status='accepted' AND e_new.canonical_person_id=e_old.canonical_person_id) AS samme,
       count(*) FILTER (WHERE e_new.decision_status='accepted' AND e_new.canonical_person_id<>e_old.canonical_person_id) AS anden,
       count(*) FILTER (WHERE e_new.decision_status<>'accepted') AS ikke_accepteret,
       count(*) FILTER (WHERE e_new.evidence ? 'candidate_id') AS kandidat_fulgt
  FROM private.source_persona_identity_event e_new
  JOIN private.source_persona_identity_event e_old ON e_old.source_persona_id=e_new.source_persona_id AND e_old.version=e_new.version-1
 WHERE e_new.evidence->>'basis' IN ('human_sheet','web_detail') AND e_new.decided_at > now() - interval '1 day';
```

Sammenlign også de to spor (ark vs. web) felt for felt: samme nøgler i `evidence` bortset fra `basis`, `sheet_sha256`, `rows_sha256`, `line`.

- [ ] **Step 5: Rapport** `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md` — kun tal, id-fri: kalibreringstabellen for begge konfigurationer (personas, med navn, uden navn, uden kandidat, top-1, top-3, præcision pr. tier) — samlet og særskilt for personas uden årstal (`uden_aarstal`), det valgte og hvorfor, genbekræftelsens tal (samme/anden/ikke accepteret/kandidat fulgt), negativtestens udfald, spor-sammenligningen, arbejdsbasens navn og hashes (ark, rækkefil, kandidatkørsel). Skriv tydeligt, at kalibreringen omfatter alle accepterede personas fra den fulde 2018-20-kørsel (`mode=list`), med navn fra `person.name`-fortolkningen eller mention-fallback (`uden_navn` rapporteres særskilt), at navnene har kendte titelfejl (decisions 2026-10-03), og at den gentages i 5b.

- [ ] **Step 6: Status og changelog.** `status.md`, tabellen »Modenhed pr. værdikædeled«: `Source persona, identitetskandidater og webkø` → `integreret ende-til-ende` (restore; ikke prod), med henvisning til rapporten. Ny linje i `docs/changelog.md` for datoen.

- [ ] **Step 7: Commit**

```bash
git add docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md docs/evidensbaseret-genimport/status.md docs/changelog.md
git commit -m "docs(151): trin 5a — kalibrering, blind genbekræftelse og status"
```

- [ ] **Step 8: Oprydningsgate** (måling først, sletning kun med projektejerens ja): alle `daa5a_*`-baser, `~/.private/5a/*`. Vis for hver: størrelse, indhold (kun kategori), og om det findes andre steder.

---

## Anden læser

Leverancen rører DDL, RLS og en sikkerhedsguard ⇒ reviewbudget **2 + 2** (decisions 2026-09-23). Planen har brugt sine to runder (runde 1 NO-GO → revision; runde 2); koden får sine to før Task 9. Codex `gpt-5.6-sol` bedes i koderunden efterprøve:

1. Om nogen vej kan skrive et identitetsmatch til en **eksisterende** person uden oprindelsen `human` eller `legacy_match`'s 1:1-kobling (ny writer, dynamisk SQL, en kvittering udstedt for en eksisterende person).
2. Om `db-migrations.sql` på noget tidspunkt under en kørsel mod prod har en klientkaldbar gammel kerne eller femarguments-wrapper (cutover-blokken) eller en grant til den private kerne.
3. Om arket eller webkøen kan skrive en afgørelse, mennesket ikke har truffet (token → forkert kandidat, forældet kørsel, ombyttede linjer, delvis transaktion).
4. Om kandidatwriteren kan registrere en kørsel med falsk provenance (input, antal, persona-/personmængde).
5. Om nogen ny RPC eller tabel giver `anon`/`authenticated` adgang til private data ud over det tilsigtede.

Fund, hvis værste udfald er et falsk STOP, er højst MINOR.

## Selvreview-checkliste

- [ ] Skriver ingen task i prod?
- [ ] Står nye signaturer i `db-rls.sql`'s allow-list, og består `run-db-verify-disposable.sql`?
- [ ] Består `test-reimport-writer.sql` og `test-reimport-legacy-migration.sql` uændret efter guarden?
- [ ] Står nogen rettet definition som ny kopi længere nede i `db-migrations.sql` i stedet for på sin plads?
- [ ] Er rangeringen ikke-injektiv, og forudfylder arket intet?
- [ ] Står der navne eller kildetekst i repo, commits, logs eller chat?
- [ ] Er kalibreringens tyndhed skrevet lige så tydeligt som dens tal?
