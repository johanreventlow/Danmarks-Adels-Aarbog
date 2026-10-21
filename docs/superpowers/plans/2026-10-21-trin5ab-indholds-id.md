# Trin 5a + 5b — id'er af indholdet: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De 8 rækkearter i 5a/5b, der bærer menneskelige artefakter eller kontrolstikprøven, får id'er afledt af indholdet. Stikprøve og kortrækkefølge trækkes efter indhold, og arkværktøjerne bliver deterministiske på tværs af baser og platforme.

**Architecture:** En ny hjælper `private.content_uuid(kind, key)` bygger på den eksisterende `private.deterministic_uuid`. Seks serverfunktioner indsætter eksplicitte id'er fra hjælperen og fanger `unique_violation` som `DETERMINISTIC_ID_COLLISION`. Tre arkværktøjer og to rækkefiler rettes. En hovedtest kører samme kæde i to baser med forskellig collation, tidszone og tilfældig forhistorik og kræver byte-identiske artefakter.

**Tech Stack:** PostgreSQL 17 (plpgsql), psql-scripts, Python 3 (pytest), bash; CI i `.github/workflows/ci.yml`.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-indholds-id-design.md` (GODKENDT 2026-10-21). Overordnet: `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (draft-PR #250).

## Global Constraints

- Afledning: `private.deterministic_uuid(jsonb_build_object('kind',<art>,'key_version',1, <naturlig nøgle>)::text)` via `private.content_uuid`.
- Kollision: `DETERMINISTIC_ID_COLLISION: <art>`; samme indhold igen opfører sig som i dag.
- Stikprøve: `sha256('control-sample-v2:' ‖ input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key)`; visning: `sha256('control-display-v2:' ‖ input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key ‖ ':' ‖ candidate_person_id)`.
- Uændret: #153's writer- og batch-/autorisationstabeller, `red_decide_interpretation`, ekstraktionskørsler, bindinger, #244's rettelsestabel, alle offentlige signaturer, tabellernes kolonnestandarder.
- Hver tekst-`ORDER BY`/`DISTINCT` i en rækkefil, projektion eller hash: `COLLATE "C"`. Brud på lighed: `interpretation_key`, aldrig `interpretation.id`. Rækkefiler låser `TimeZone='UTC'` og `search_path`.
- Migration: én afsluttende blok i `db-migrations.sql` mellem `-- #244-blokken slutter her.` og `-- 5b-sektionen slutter her`, med funktionskroppe byte-identiske med `schema.sql`.
- Delte regler: aldrig navne eller kildetekst i chat; `env -u PGOPTIONS` (psql), `env -u NODE_OPTIONS` (pytest/npm); danske Conventional Commits med trailer `Claude-Session: https://claude.ai/code/session_011rKEYw62xDPse4zhLARtjo`; subagenter læser aldrig `~/.private`, `work*/` eller en database med persondata.

## Review Focus

1. **Collation i tekst, der ikke findes i testens data:** en titel, et postnavn eller en note med tegn, hvor `C`, `en_US` og ICU-`da` sorterer forskelligt (»aa«, »Æ«, store/små bogstaver). Det forventede er samme rækkefil i alle baser. Task 2's fixtur skal derfor indeholde netop sådanne strenge.
2. **CI's psql-klient er version 16 mod en server i version 17.** Hovedtesten må ikke bruge `pg_dump`. Den kopierer med `COPY` (Task 2).
3. **En kontrolkørsel efter en fejlet kontrol** (`p_cause` sat) på en ny kandidatkørsel skal give et nyt kontrol-id, og den gamle kørsel skal være uændret (Task 5).
4. **Et v1-rækkefil eller et v1-ark** givet til 2b-i-værktøjets CLI skal give `SHEET_CONTRACT_UNSUPPORTED`/`SHEET_LINE_INVALID`, ikke en Python-traceback (Task 6). (To samtidige writer-batches med samme persona-nøgle er dækket af `UNIQUE (source_id,persona_key)` og writerens `…_RELATION_PERSONA_EXISTS`; det kræver ingen ny test.)
5. **Et gammelt 2b-i-ark (v1, `O <interpretation_id> b/f`)** givet til det nye værktøj skal afvises med en tydelig fejl, ikke fejlfortolkes (Task 6).

---

### Task 1: Hjælperen `private.content_uuid`

**Files:**
- Modify: `schema.sql` (lige efter `COMMENT ON FUNCTION private.deterministic_uuid`)
- Create: `tests/sql/test-content-uuid.sql`
- Modify: `.github/workflows/ci.yml` (SQL-løkken i jobbet, der kører `test-marriage-ordinal-correction`, l. ~491)

**Interfaces:**
- Produces: `private.content_uuid(p_kind text, p_key jsonb) RETURNS uuid` (IMMUTABLE, STRICT; afviser `p_key` med nøglerne `kind`/`key_version` med `CONTENT_UUID_KEY_INVALID`).

- [ ] **Step 1: Skriv den fejlende test** `tests/sql/test-content-uuid.sql`:

```sql
\set ON_ERROR_STOP on
BEGIN;
DO $cu$
DECLARE a uuid; b uuid; v_err text;
BEGIN
  a:=private.content_uuid('source-persona',jsonb_build_object('source_id',1,'persona_key','K'));
  b:=private.content_uuid('source-persona',jsonb_build_object('persona_key','K','source_id',1));
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: nøgleorden'; END IF;
  IF a<>private.deterministic_uuid('{"kind": "source-persona", "source_id": 1, "key_version": 1, "persona_key": "K"}') THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: afledning'; END IF;
  IF a=private.content_uuid('source-mention',jsonb_build_object('source_id',1,'persona_key','K')) THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: art'; END IF;
  IF a=private.content_uuid('source-persona',jsonb_build_object('source_id',1,'persona_key','L')) THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: nøgle'; END IF;
  BEGIN PERFORM private.content_uuid('x',jsonb_build_object('kind','y')); RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: kind';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'CONTENT_UUID_KEY_INVALID%' THEN RAISE; END IF; END;
  IF has_function_privilege('anon','private.content_uuid(text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.content_uuid(text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CONTENT_UUID_TEST_FAILED: rettigheder'; END IF;
  RAISE NOTICE 'OK: content_uuid';
END $cu$;
ROLLBACK;
```

- [ ] **Step 2: Kør den.** Byg en engangsbase som CI's writer-job (bootstrap → `schema.sql` → `db-rls.sql`) og kør `env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d <db> -f tests/sql/test-content-uuid.sql`.
  Expected: FAIL, `function private.content_uuid(unknown, jsonb) does not exist`.

- [ ] **Step 3: Implementér** i `schema.sql`:

```sql
-- Trin 5a/5b (#151, indholds-id-spec §3): id af indhold. kind og key_version adskiller arter og nøgleversioner;
-- jsonb::text giver kanonisk nøgleorden.
CREATE OR REPLACE FUNCTION private.content_uuid(p_kind text,p_key jsonb)
RETURNS uuid LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
BEGIN
  IF btrim(p_kind)='' OR jsonb_typeof(p_key)<>'object' OR p_key ?| ARRAY['kind','key_version'] THEN
    RAISE EXCEPTION 'CONTENT_UUID_KEY_INVALID';
  END IF;
  RETURN private.deterministic_uuid((jsonb_build_object('kind',p_kind,'key_version',1)||p_key)::text);
END $$;
REVOKE ALL ON FUNCTION private.content_uuid(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
```

- [ ] **Step 4: Kør testen igen.** Expected: `NOTICE: OK: content_uuid`.
- [ ] **Step 5: Tilføj `test-content-uuid`** til SQL-løkken i `ci.yml` (samme `for t in …`-linje som `test-marriage-ordinal-correction`).
- [ ] **Step 6: Commit** `feat(151): content_uuid — id af indhold` (`schema.sql`, testen, `ci.yml`).

---

### Task 2: Hovedtesten »to baser giver det samme« (rød)

**Files:**
- Create: `tests/sql/fixtures/indholds-id-dump.sql` (prod-lignende data: det, der i virkeligheden ligger i D1)
- Create: `tests/sql/fixtures/indholds-id-chain.sql` (det, kæden selv skriver)
- Create: `tests/sql/indholds-id-export.sql` (læse-kun eksport af id'er og stikprøve)
- Create: `tests/sql/test-indholds-id-determinism.sh`

**Interfaces:**
- Consumes: fixturhjælperne i `tests/sql/fixtures/relation-5b.sql` (`f5b_actor`, `f5b_source`, `f5b_post`, `f5b_claim`, `f5b_family`, `f5b_life`, `f5b_payload`, `f5b_write`) og `relation-2a.sql` (`f2a_event_for_state`); `private.content_uuid` (Task 1, kun i eksporten).
- Produces: `bash tests/sql/test-indholds-id-determinism.sh <prefix> [<build>]` → `DETERMINISM_OK`, eller `DETERMINISM_DIFF: <artefakter>` med exit 1. `<build>` er `fresh` (standard) eller `upgrade:<commit>` (Task 7).

**Fixturkontrakt (spec §5.1):** dumpet køres kun i base A og kopieres med `COPY` til base B. Intet, kæden skriver, ligger i dumpet. Base B får derefter en tilfældig forhistorik i en anden kilde. Begge baser kører kæden.

**Basebygning** (begge tilstande). Writeren kræver narrativkontrakt 2 og writer-v2-bootstrappen, som CI's writer-job (`ci.yml:416-423`, `:496-500`):
- `fresh`: bootstrap → `schema.sql` → `db-rls.sql` → `tests/sql/1939-v50-writer-bootstrap.sql` → `BEGIN; tests/sql/reimport-writer-v2-bootstrap.sql; COMMIT` → `db-rls.sql`;
- `upgrade:<c>`: bootstrap → `<c>`'s `schema.sql`, `db-rls.sql`, `db-migrations.sql`, `db-rls.sql` → nuværende `db-migrations.sql`, `db-rls.sql`, `db-migrations.sql`, `db-rls.sql` → de tre writer-bootstrap-trin ovenfor.

- [ ] **Step 1: Skriv `tests/sql/fixtures/indholds-id-dump.sql`.** Filen er uden `BEGIN`/`COMMIT`; harnesset indlæser den efter `relation-5b.sql` og `relation-2a.sql` i én transaktion. Kilde `-25001`, aktør `11000000-0000-0000-0000-000000025001` (`f5b_actor`), personer `-25001..-25030`. Indhold:
  - **Post `'aa-1'`** (hovedperson -25001) med to ægteskabsklausuler »Gift 1° m. Bo Beta f. 1800.« og »Gift 2° m. Cia Ceta f. 1810.«. Familierne laves med `f5b_family(-25001,-25002,2)` og `f5b_family(-25001,-25003,1)`, så bogens 1° står mod familiens 2: det giver afvigelsen.
  - **Post `'Ab-2'`** (hovedperson -25004) med ét ægteskab »Gift m. Dy Delta f. 1805.«. Familie `f5b_family(-25004,-25005,1)`.
  - **Post `'Zz-3'`** (hovedperson -25006), barn i familien `f5b_family(-25004,-25005,1)` (`INSERT INTO family_member(family_id,person_id,rolle) VALUES (<fam>,-25006,'barn')`). Den har en **forslået `relation.parent`-påstand** (`f5b_claim(…,'relation.parent',<klausul>,'Søn af Ea Eta.')`) med en principal-part (`INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref) VALUES (<key>,'principal',1,<post 'Zz-3' principal>,0,'relation_persona',gen_random_uuid())`). Den afgøres **ikke**, så den bliver et forældrekort i kontrolkørslen (`relation_structural_candidates`, `schema.sql:15721-15745`). Bliver kortet ikke dannet, så justér fixturen efter funktionens krav (én familie, én modpart, der er hovedperson-persona i en anden post), ikke testen.
  - `f2a_event_for_state(<principal>)` for **hver** post med hovedperson. Uden det fejler den udskudte `identity_state_has_event` (`schema.sql:1894-1897`) ved `COMMIT`.
  - Ægteskabspåstande via `f5b_claim(…,'relation.marriage',<klausul>,<raw>)`.
  - **Kandidatpersoner** -25010..-25020 med leveår (`f5b_life`) og **collation-følsomme titler**. Hver får 3 `titel`-fakta med `vaerdi_tekst` blandt `'aaben'`, `'Zobel'`, `'Ærø'`, `'baron'`, `'Baron'` i blandet rækkefølge: `INSERT INTO fact(subjekt_type,subjekt_id,faktatype) … 'titel'` → `assertion(target_type,target_id,vaerdi_tekst)` → `conclusion(target_type,target_id,valgt_assertion_id,status) … 'afklaret'`.
- [ ] **Step 2: Skriv `tests/sql/fixtures/indholds-id-chain.sql`.** Den køres som ejer i harnessets transaktion og afslutter selv med `COMMIT;`.
  1. **Ægtefællepersonas gennem den rigtige writer:** `pg_temp.f5b_write(-25001,actor, jsonb_object_agg('relation-persona:'||key, pg_temp.f5b_payload(post, claim, klausul, raw, navn)))` for de tre ægteskabspåstande.
  2. **Kandidatkørsel 1** (`config {"k":1}`, `generator_version 'test'`) som `authenticated` med aktørens claim: `red_identity_candidate_input(-25001,'{"mode":"undecided"}')` → `red_record_identity_candidates`. Kandidaterne bygges i SQL fra `input->'personas'` og en fast `VALUES`-tabel (`persona_key` → `person_id`, rang, score, tier og `corroboration_eligible`):
     - **Bo Beta** (afvigelsens ægtefælle, post `aa-1`) og **Cia Ceta**: rang 1 med `corroboration_eligible:false`. De bliver dermed ikke trukket til stikprøven (`schema.sql:16144`), men står stadig på undtagelsesarket.
     - **Dy Delta**: rang 1 med `corroboration_eligible:true`, så stikprøven ikke er tom.
     - Hver persona får 2 kandidater (rang 1 og 2). Hovedpersonernes egne personas får ingen kandidater.
  3. **Kontrolkørsel:** `red_register_identity_control_run(<kørsel 1>)`.
  4. **Bo Beta afgøres `same`:** `red_afgoer_source_persona(<persona>,0,'same',<rang 1-person>,'test', ctx)` med `ctx = {"basis":"human_sheet","sheet_sha256":repeat('a',64),"rows_sha256":repeat('b',64),"line":1,"candidate_id":<rang 1-kandidat>,"run_id":<kørsel 1>}` mens kørsel 1 er den gældende.
  5. **Kandidatkørsel 2** med `config {"k":2}` og samme regel (spec §5.1: »kandidatkørsel 2«).
  6. **2a for kilden:** preview → `red_decide_relation_interpretations`, efter mønstret i `marriage-ordinal-244.sql`'s `f244_decide_and_bind`, uden binding. Bo Betas ægteskab får `ordinal_afvigelse`, fordi bogen siger 1° og familien 2.
  7. `COMMIT;`
- [ ] **Step 3: Skriv `tests/sql/indholds-id-export.sql`** (læse-kun, `-At`, én linje pr. række, sorteret med `COLLATE "C"`):

```sql
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SET TimeZone='UTC';
SELECT 'source-persona|'||persona_key||'|'||id FROM private.source_persona WHERE source_id=-25001 ORDER BY persona_key COLLATE "C";
SELECT 'source-mention|'||sp.persona_key||'|'||spm.mention_role||'|'||spm.ordinal||'|'||spm.mention_id
  FROM private.source_persona_mention spm JOIN private.source_persona sp ON sp.id=spm.persona_id
 WHERE sp.source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'identity-event|'||sp.persona_key||'|'||e.version||'|'||e.id FROM private.source_persona_identity_event e
  JOIN private.source_persona sp ON sp.id=e.source_persona_id WHERE sp.source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'candidate-run|'||input_sha256||'|'||config_sha256||'|'||id FROM private.source_persona_identity_candidate_run
 WHERE source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'candidate|'||sp.persona_key||'|'||c.candidate_person_id||'|'||c.rank||'|'||c.id
  FROM private.source_persona_identity_candidate c JOIN private.source_persona sp ON sp.id=c.source_persona_id
 WHERE sp.source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'control-run|'||r.candidate_run_id||'|'||r.id FROM private.identity_control_run r WHERE r.source_id=-25001;
SELECT 'sample|'||sp.persona_key||'|'||s.stratum||'|'||s.id||'|'||s.mapping::text||'|'||s.expected
  FROM private.identity_control_sample s JOIN private.source_persona sp ON sp.id=s.source_persona_id
  JOIN private.identity_control_run r ON r.id=s.control_run_id WHERE r.source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'parent-card|'||pc.interpretation_key||'|'||pc.id FROM private.identity_control_parent_card pc
  JOIN private.identity_control_run r ON r.id=pc.control_run_id WHERE r.source_id=-25001 ORDER BY 1 COLLATE "C";
SELECT 'antal|'||(SELECT count(*) FROM private.identity_control_parent_card)||'|'||
       (SELECT count(*) FROM private.identity_control_sample)||'|'||(SELECT count(*) FROM private.source_persona_identity_candidate_run WHERE source_id=-25001);
```

- [ ] **Step 4: Skriv `tests/sql/test-indholds-id-determinism.sh`:**

```bash
#!/usr/bin/env bash
# Indholds-id (#151, spec §5.1): samme kæde i to baser med forskellig collation, tidszone og tilfældig
# forhistorik skal give byte-identiske id'er, stikprøver, rækkefiler og ark-SQL. Ingen pg_dump (CI-klient 16).
set -euo pipefail
pre=${1:?prefix}; build=${2:-fresh}; A=${pre}_a; B=${pre}_b
S=.claude/skills/daa-extract/scripts; export PGCLIENTENCODING=UTF8
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/priv/A" "$tmp/priv/B" "$tmp/out/A" "$tmp/out/B"; chmod 700 "$tmp/priv" "$tmp/priv/A" "$tmp/priv/B"
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
qa() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" "${@:2}"; }
createdb -E UTF8 --template=template0 --locale=C "$A"
createdb -E UTF8 --template=template0 --locale-provider=icu --icu-locale=da --locale=C "$B"
q "$A" -c "ALTER DATABASE \"$A\" SET TimeZone='UTC'"; q "$B" -c "ALTER DATABASE \"$B\" SET TimeZone='Pacific/Chatham'"
writer_boot() {
  q "$1" -f tests/sql/1939-v50-writer-bootstrap.sql
  q "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
  q "$1" -f db-rls.sql
}
build_db() {
  local db=$1
  if [ "$build" = fresh ]; then
    for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$db" -f "$f"; done
  else
    local base=${build#upgrade:} t; t=$(mktemp -d)
    for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$t/$f"; done
    for f in tests/sql/evidence-promotion-bootstrap.sql "$t/schema.sql" "$t/db-rls.sql" "$t/db-migrations.sql" "$t/db-rls.sql" \
             db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$db" -f "$f"; done
    rm -rf "$t"
  fi
  writer_boot "$db"
}
build_db "$A"; build_db "$B"
# Dumpet: kun i A, i én transaktion med fixturhjælperne; kopieres tabel for tabel til B.
q "$A" -c 'BEGIN' -f tests/sql/fixtures/relation-5b.sql -f tests/sql/fixtures/relation-2a.sql \
       -f tests/sql/fixtures/indholds-id-dump.sql -c 'COMMIT'
tables=$(qa "$A" -c "SELECT format('%I.%I',n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind='r' AND n.nspname IN ('public','private','auth') ORDER BY 1")
q "$B" -c "SET session_replication_role=replica" -c "TRUNCATE $(echo $tables | tr ' ' ',') CASCADE"
for t in $tables; do
  env -u PGOPTIONS psql -X -q -d "$A" -c "\copy $t TO STDOUT" | \
    env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" -c "SET session_replication_role=replica" -c "\copy $t FROM pstdin"
done
qa "$A" -c "SELECT format('SELECT setval(%L,%s,%s);',format('%I.%I',schemaname,sequencename),coalesce(last_value,1),last_value IS NOT NULL)
  FROM pg_sequences WHERE schemaname IN ('public','private')" | env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$B" >/dev/null
# Tilfældig forhistorik kun i B: en anden kilde med en post (tilfældige id'er, fremskudte sekvenser).
q "$B" -c 'BEGIN' -f tests/sql/fixtures/relation-5b.sql -c "SELECT pg_temp.f5b_post(-25099,pg_temp.f5b_source(-25099),'x',
  'Anna Alfa.',ARRAY['Anna Alfa.'],NULL,'11000000-0000-0000-0000-000000025001')" -c 'COMMIT'
for side in A B; do
  db=$([ $side = A ] && echo "$A" || echo "$B"); d=$tmp/out/$side; P=$tmp/priv/$side
  q "$db" -c 'BEGIN' -f tests/sql/fixtures/relation-5b.sql -f tests/sql/fixtures/relation-2a.sql -f tests/sql/fixtures/indholds-id-chain.sql
  qa "$db" -f tests/sql/indholds-id-export.sql > "$d/ids.txt"
  ctl=$(qa "$db" -c "SELECT id FROM private.identity_control_run WHERE source_id=-25001")
  qa "$db" -v source_id=-25001 -v mode=undecided -v personas= -f $S/identity_sheet_rows.sql > "$P/identity-rows.json"
  qa "$db" -v control_run_id="$ctl" -f $S/identity_control_rows.sql > "$P/control-rows.json"
  qa "$db" -v source=-25001 -f $S/spouse_exception_rows.sql > "$P/spouse-rows.json"
  env -u NODE_OPTIONS python3 $S/spouse_exception_sheet.py render --rows "$P/spouse-rows.json" --out "$P/spouse-ark.txt" --private-root "$tmp/priv" >/dev/null
  sh=$(shasum -a 256 "$P/spouse-ark.txt" | cut -c1-64); rh=$(shasum -a 256 "$P/spouse-rows.json" | cut -c1-64)
  env -u NODE_OPTIONS python3 $S/spouse_exception_sheet.py sql --rows "$P/spouse-rows.json" --sheet "$P/spouse-ark.txt" \
    --approved-sha256 "$sh" --expect-rows-sha256 "$rh" --source -25001 --out "$P/spouse.sql" --private-root "$tmp/priv" >/dev/null
  cp "$P"/identity-rows.json "$P"/control-rows.json "$P"/spouse-rows.json "$P"/spouse-ark.txt "$P"/spouse.sql "$d/"
done
grep -q '^parent-card|' "$tmp/out/A/ids.txt" || { echo 'DETERMINISM_SETUP: intet forældrekort'; exit 2; }
[ "$(grep -c '^candidate-run|' "$tmp/out/A/ids.txt")" = 2 ] || { echo 'DETERMINISM_SETUP: ikke 2 kandidatkørsler'; exit 2; }
grep -q '^sample|' "$tmp/out/A/ids.txt" || { echo 'DETERMINISM_SETUP: tom stikprøve'; exit 2; }
diffs=$(cd "$tmp/out" && for f in $(ls A); do cmp -s "A/$f" "B/$f" || echo "$f"; done | tr '\n' ' ')
if [ -n "$diffs" ]; then
  echo "DETERMINISM_DIFF: $diffs"
  diff "$tmp/out/A/ids.txt" "$tmp/out/B/ids.txt" | grep '^[<>]' | cut -c3- | cut -d'|' -f1 | sort | uniq -c | sed 's/^/  /'
  dropdb "$A"; dropdb "$B"; exit 1
fi
dropdb "$A"; dropdb "$B"; echo DETERMINISM_OK
```

  `spouse_exception_rows.sql` bruger `:source` (`:8`). `identity_sheet_rows.sql` bruger `:source_id`, `:'mode'`, `:'personas'`. `identity_control_rows.sql` bruger `:'control_run_id'`. Exit 2 betyder en fejl i opsætningen, ikke en afvigelse.

- [ ] **Step 5: Kør den mod den nuværende kode.**
  Run: `bash tests/sql/test-indholds-id-determinism.sh t_det`
  Expected: exit 1 og `DETERMINISM_DIFF:` med mindst `ids.txt`, `identity-rows.json`, `control-rows.json`, `spouse-rows.json` og `spouse.sql`. Optællingen viser mindst `source-persona`, `source-mention`, `identity-event`, `candidate-run`, `candidate`, `control-run`, `sample` og `parent-card`.
  Exit 2 eller en SQL-fejl i opsætningen er en fejl i testen: ret fixturen, før du går videre.

- [ ] **Step 6: Commit** `test(151): hovedtest for id'er af indholdet (rød mod nuværende kode)` (fire filer). Testen kommer ikke i CI før Task 7.

---

### Task 3: Ægtefællepersona, omtale og identitetshændelse

**Files:**
- Modify: `schema.sql` — `private.write_relation_persona` (l. ~15187-15196), `private.decide_source_persona_identity` (l. ~8463-8469)
- Modify: `tests/sql/test-relation-persona-writer.sql`, `tests/sql/test-identity-decision.sql`

**Interfaces:**
- Consumes: `private.content_uuid` (Task 1).
- Produces: personas med `id = content_uuid('source-persona',{source_id,persona_key})`, omtaler med `content_uuid('source-mention',{persona_id,mention_role:'spouse',ordinal:1})` og hændelser med `content_uuid('identity-event',{source_persona_id,version})`.

- [ ] **Step 1: Skriv de fejlende tests.** Tilføj en blok `$det_persona$` i `test-relation-persona-writer.sql`, i sin egen `BEGIN … ROLLBACK` med samme fixturopsætning som filens eksisterende writer-blok:
  - Efter writeren: personaens `id = private.content_uuid('source-persona',jsonb_build_object('source_id',<src>,'persona_key',<nøgle>))`, og omtalens id er `content_uuid('source-mention',…)`.
  - Kollision: før writeren indsættes som ejer en persona med `id = content_uuid('source-persona',{src, nøglen})` og `persona_key='andet'`. Writeren skal så fejle med `DETERMINISTIC_ID_COLLISION: source-persona`.

  Tilføj i `test-identity-decision.sql` en blok, der efter en afgørelse kræver hændelses-id = `content_uuid('identity-event',jsonb_build_object('source_persona_id',<p>,'version',1))`.
- [ ] **Step 2: Kør begge.** Expected: FAIL på id-sammenligningen (tilfældige id'er).
- [ ] **Step 3: Implementér i `write_relation_persona`** og erstat de tre indsæt:

```sql
  IF v_marriage THEN
    v_key:=v_record_key||'#rel-marriage-'||(p_payload->>'post_offset')||'-'||(v_to-v_from);
    v_spouse:=private.content_uuid('source-persona',jsonb_build_object('source_id',v_batch.source_id,'persona_key',v_key));
    BEGIN
      INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_spouse,v_batch.source_id,v_key,v_run);
    EXCEPTION WHEN unique_violation THEN
      IF EXISTS (SELECT 1 FROM private.source_persona WHERE id=v_spouse
                  AND (source_id,persona_key) IS DISTINCT FROM (v_batch.source_id,v_key)) THEN
        RAISE EXCEPTION 'DETERMINISTIC_ID_COLLISION: source-persona';
      END IF;
      RAISE;
    END;
    v_mention:=private.content_uuid('source-mention',jsonb_build_object('persona_id',v_spouse,'mention_role','spouse','ordinal',1));
    INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES (v_mention,v_clause.id,'person',v_name_from,v_name_to,
              substr(v_clause.verbatim_text,v_name_from+1,v_name_to-v_name_from),v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_spouse,v_mention,'spouse',1);
```

  Tilføj `v_key text;` i DECLARE. Omtalens indsæt pakkes på samme måde: `unique_violation`, og id = `v_mention` med (`persona_id` fra `source_persona_mention`) ≠ `v_spouse` ⇒ `DETERMINISTIC_ID_COLLISION: source-mention`, ellers `RAISE`. Spec §3 kræver håndteringen ved hvert indsæt.

  **I `decide_source_persona_identity`:** tilføj `id` som første kolonne i `INSERT INTO private.source_persona_identity_event(…)` med værdien `private.content_uuid('identity-event',jsonb_build_object('source_persona_id',p_source_persona_id,'version',v_new_version))`. Personarækken er låst `FOR UPDATE` længere oppe, så indsættet er serialiseret pr. persona. Pak indsættet i `EXCEPTION WHEN unique_violation`: findes en hændelse med samme id og anden (`source_persona_id`, `version`), ⇒ `DETERMINISTIC_ID_COLLISION: identity-event`, ellers `RAISE`.
- [ ] **Step 4: Kør testene og hele 5b-SQL-sættet** (`test-relation-persona-writer`, `-v2`, `-v3`, `test-identity-decision`, `test-identity-cutover`, `test-relation-person-create`, `-v3`). Expected: alle OK.
- [ ] **Step 5: Commit** `feat(151): ægtefællepersona, omtale og identitetshændelse får id af indholdet`.

---

### Task 4: Kandidatkørsel og kandidater

**Files:**
- Modify: `schema.sql` — `red_record_identity_candidates` (l. ~8909-8925), `private.identity_candidate_input` (l. 8821, 8827, 8830)
- Modify: `tests/sql/test-identity-candidates.sql`

**Interfaces:**
- Produces: kørsels-id `content_uuid('identity-candidate-run',{source_id,input_sha256,config_sha256})`, kandidat-id `content_uuid('identity-candidate',{run_id,source_persona_id,candidate_person_id})`.

- [ ] **Step 1: Fejlende test** i `test-identity-candidates.sql`, ny blok med filens fixtur:
  - Kørsels-id og hver kandidats id er lig `content_uuid(...)` af deres nøgler.
  - Et gentaget kald med samme input og kandidater returnerer samme kørsel. Andre kandidater giver `IDENTITY_CANDIDATE_RUN_CONFLICT`.
  - Kollision: en kørsel indsat som ejer med det afledte id, men med en anden `config_sha256`, giver `DETERMINISTIC_ID_COLLISION: identity-candidate-run`.
- [ ] **Step 2: Kør.** Expected: FAIL på id-sammenligningen.
- [ ] **Step 3: Implementér.** Tilføj `v_new uuid;` i `red_record_identity_candidates`' DECLARE (`schema.sql:8862-8864`). Beregn
  `v_new:=private.content_uuid('identity-candidate-run',jsonb_build_object('source_id',v_source,'input_sha256',p_run->>'input_sha256','config_sha256',v_config_hash));`.
  Indsættet får `id` med `v_new`, og `ON CONFLICT (source_id,input_sha256,config_sha256) DO NOTHING` beholdes. Pak indsættet ind i `BEGIN … EXCEPTION WHEN unique_violation THEN` med samme kollisionstjek som Task 3: id = `v_new` og (`source_id`,`input_sha256`,`config_sha256`) afviger ⇒ `DETERMINISTIC_ID_COLLISION: identity-candidate-run`, ellers `RAISE`.
  Kandidatindsættet får `id` med
  `private.content_uuid('identity-candidate',jsonb_build_object('run_id',v_run,'source_persona_id',c->>'source_persona_id','candidate_person_id',(c->>'candidate_person_id')::bigint))`.
  Kandidatindsættet pakkes i `EXCEPTION WHEN unique_violation`: findes en kandidat, hvis id er en af de afledte, men hvis (`run_id`,`source_persona_id`,`candidate_person_id`) afviger,
  ```sql
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_candidates) c JOIN private.source_persona_identity_candidate x
               ON x.id=private.content_uuid('identity-candidate',jsonb_build_object('run_id',v_run,'source_persona_id',c->>'source_persona_id',
                                            'candidate_person_id',(c->>'candidate_person_id')::bigint))
              WHERE (x.run_id,x.source_persona_id,x.candidate_person_id)
                    IS DISTINCT FROM (v_run,(c->>'source_persona_id')::uuid,(c->>'candidate_person_id')::bigint)) THEN
    RAISE EXCEPTION 'DETERMINISTIC_ID_COLLISION: identity-candidate';
  END IF;
  RAISE;
  ```
  I `identity_candidate_input` ændres de tre `ORDER BY …, ic.id LIMIT 1` til `ORDER BY …, ic.interpretation_key LIMIT 1` (spec §4 pkt. 5).
- [ ] **Step 4: Kør** `test-identity-candidates`, `test-identity-decision`, `test-identity-control-run`, `test-identity-detail`. Expected: OK.
- [ ] **Step 5: Commit** `feat(151): kandidatkørsel og kandidater får id af indholdet`.

---

### Task 5: Kontrolkørsel, stikprøve og forældrekort; indholdsbaseret trækning

**Files:**
- Modify: `schema.sql` — `red_register_identity_control_run` (l. ~16099-16203)
- Modify: `tests/sql/test-identity-control-run.sql`
- Modify: `docs/superpowers/specs/<5b-spec med §23.3>` (erratum; find filen med `grep -l "23.3" docs/superpowers/specs/*5b*`), `docs/decisions.md`

**Interfaces:**
- Produces: kontrol-id `content_uuid('identity-control-run',{candidate_run_id})`, stikprøve-id `content_uuid('identity-control-sample',{control_run_id,source_persona_id})`, forældrekort-id `content_uuid('identity-control-parent-card',{control_run_id,interpretation_key})`; trækning og visning efter Global Constraints.

- [ ] **Step 1: Fejlende test** i `test-identity-control-run.sql`, ny blok:
  - De tre id-arter er lig `content_uuid(...)`.
  - Rækkefølgen af stikprøven inden for hvert stratum er lig rækkefølgen af `sha256('control-sample-v2:'||input_sha256||':'||config_sha256||':'||persona_key)`.
  - For hvert kort er `mapping`'s positioner lig rækkefølgen af `sha256('control-display-v2:'||…||persona_key||':'||candidate_person_id)`.
  - **Review Focus 3:** en ny kandidatkørsel (ændret config) efter en `failed`-kontrol med `p_cause` giver et andet kontrol-id, og den gamle kørsels rækker er uændrede.
- [ ] **Step 2: Kør.** Expected: FAIL.
- [ ] **Step 3: Implementér:**
  - `v_id` beregnes som `private.content_uuid('identity-control-run',jsonb_build_object('candidate_run_id',p_candidate_run_id))` i DECLARE (erstatter `gen_random_uuid()`). `v_run` hentes allerede før `DROP TABLE` (`schema.sql:16126` mod `:16133`); intet skal flyttes.
  - I `ctl_elig`: join `private.source_persona sp ON sp.id=c.source_persona_id`, tilføj kolonnen `sp.persona_key AS pkey`, og erstat `h` med
    `encode(extensions.digest(convert_to('control-sample-v2:'||v_run.input_sha256||':'||v_run.config_sha256||':'||sp.persona_key,'UTF8'),'sha256'),'hex') AS h`.
  - I `mapping`'s `row_number()`: join `private.source_persona_identity_candidate cc ON cc.id=d.cid`, og sorter efter
    `encode(extensions.digest(convert_to('control-display-v2:'||v_run.input_sha256||':'||v_run.config_sha256||':'||x.pkey||':'||cc.candidate_person_id::text,'UTF8'),'sha256'),'hex')`.
  - `ORDER BY p.h` (`schema.sql:16197`) og vinduets `ORDER BY` får `COLLATE "C"` (Global Constraints).
  - Indsættet i `identity_control_sample` får `id` med `private.content_uuid('identity-control-sample',jsonb_build_object('control_run_id',v_id,'source_persona_id',x.pid))`.
  - Indsættet i `identity_control_parent_card` får `id` med `private.content_uuid('identity-control-parent-card',jsonb_build_object('control_run_id',v_id,'interpretation_key',k))`.
  - Indsættene i `identity_control_run`, `identity_control_sample` og `identity_control_parent_card` pakkes hver i `EXCEPTION WHEN unique_violation` med kollisionstjek på deres naturlige nøgle (`candidate_run_id`; `control_run_id`+`source_persona_id`; `control_run_id`+`interpretation_key`) ⇒ `DETERMINISTIC_ID_COLLISION: <art>`, ellers `RAISE`. Den eksisterende idempotens over `candidate_run_id` er uændret.
- [ ] **Step 4: Kør** `test-identity-control-run`, `test-identity-candidates`, `test-identity-decision`, `test-spouse-exception-projection`. Expected: OK.
- [ ] **Step 5: Erratum.** I 5b-spec'ens §23.3 pkt. 4, under den gamle formel: »**Erratum 2026-10-21 (#151, indholds-id):** trækningen bruger nu `sha256('control-sample-v2:' ‖ input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key)` og visningen `…'control-display-v2:'… ‖ candidate_person_id`; garantierne er uændrede (indholds-id-spec §3).« I `docs/decisions.md`, under posten for 5b's kontrolkørsel: én linje med samme indhold.
- [ ] **Step 6: Commit** `feat(151): kontrolkørsel med id og trækning af indholdet; erratum til 5b §23.3`.

---

### Task 6: Arkværktøjer og rækkefiler

**Files:**
- Modify: `schema.sql` — `private.spouse_exception_projection` (l. ~16848-16871), `private.persona_family_context` (l. ~15372), `private.relation_persona_v3_input` (l. ~17318-17319)
- Modify: `.claude/skills/daa-extract/scripts/spouse_exception_sheet.py`, `identity_control_rows.sql`, `identity_sheet_rows.sql`, `relation_marriage_sheet_v3.py`
- Modify (tests): `test_spouse_exception_sheet.py`, `test_relation_marriage_sheet_v3.py`, `tests/sql/test-spouse-exception-projection.sql`, `tests/sql/test-spouse-exception-sheet.sh`, `tests/sql/test-relation-persona-v3.sql` (hvis den tjekker `decided_at`)

**Interfaces:**
- Produces: projektionskontrakten `spouse-exception-rows-v2`: `o_rows` = `{interpretation_key, interpretation_version, family_id, principal_person_id, spouse_person_id, book_ordinal, family_ordinal}`, sorteret på `interpretation_key COLLATE "C"`, uden `state_sha256`. Arklinjen bliver `O <interpretation_key> <version> <bog>/<fam> : <B|F>`.

- [ ] **Step 1: Fejlende pytest** i `test_spouse_exception_sheet.py`. Modulets fixturfunktion hedder `rows()`, og id-konstanten `I1` (l. 12-28). Opdatér `rows()` til v2: `contract 'spouse-exception-rows-v2'`, `o_rows` med `interpretation_key: K1` (ny konstant, en fast uuid) og `interpretation_version: 2`, uden `interpretation_id` og `state_sha256`. Omskriv hver eksisterende assertion på `O {I1} 2/1`, `2/?`, `?/1` og den parametriserede `"O {i} 2/1 : S"` (l. 34, 43, 66, 131-132, 143) til `O {K1} 2 …`. Tilføj:

```python
def test_o_line_keyed_on_interpretation_key_and_resolved_at_runtime():
    r = rows()
    text = render_sheet(r)
    assert f"O {K1} 2 2/1 : F" in text
    lines = parse_sheet(text)
    sql = sheet_sql(lines, r, sheet_sha256="a" * 64, rows_sha256="b" * 64, source_id=1)
    assert f"interpretation_key='{K1}'::uuid AND ic.version=2" in sql
    assert I1 not in sql   # intet tilfældigt afgørelsesversions-id i ark-SQL

def test_v1_rows_and_v1_o_line_rejected():
    r = rows(); r["contract"] = "spouse-exception-rows-v1"
    with pytest.raises(SheetError, match="SHEET_CONTRACT_UNSUPPORTED"):
        render_sheet(r)
    with pytest.raises(SheetError, match="SHEET_CONTRACT_UNSUPPORTED"):
        check_identity([], r)
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID"):
        parse_sheet(f"O {I1} 2/1 : F\n")
```

  Tilføj i `test_relation_marriage_sheet_v3.py` en test, der kræver, at et P-kort ikke indeholder et `YYYY-MM-DD`-mønster, når `previous` ikke har `decided_at`.
- [ ] **Step 2: Kør.** `env -u NODE_OPTIONS <venv>/bin/python -m pytest .claude/skills/daa-extract/scripts/test_spouse_exception_sheet.py .claude/skills/daa-extract/scripts/test_relation_marriage_sheet_v3.py -q`
  Expected: FAIL (de nye tests).
- [ ] **Step 3: Implementér værktøjerne:**
  - **`spouse_exception_sheet.py`:**
    - `O_RE = re.compile(rf"^O (?P<id>{UUID}) (?P<ver>[0-9]+) (?P<bog>[0-9]+|\?)/(?P<fam>[0-9]+|\?) : (?P<tok>[BF])\s*(?:#\s*(?P<note>.*))?$")`.
    - `parse_sheet` sætter `version=int(m["ver"])` for begge arter.
    - `_expected` giver `("O", r["interpretation_key"], r["interpretation_version"])`.
    - `render_sheet` skriver `O {key} {ver} {bog}/{fam}`, og `forslag` nøgles på `interpretation_key`.
    - En ny `_require_v2(rows)` kaster `SheetError("SHEET_CONTRACT_UNSUPPORTED")`, hvis `rows.get("contract") != "spouse-exception-rows-v2"`. Den kaldes først i `render_sheet`, `check_identity` og `sheet_sql`, så et v1-rækkefil gennem CLI'en giver koden og ikke en `KeyError` (Review Focus 4).
    - `o_by` nøgles på `interpretation_key`.
    - F-linjens SQL bliver

```python
sql.append(f"INSERT INTO applied SELECT 'F' FROM (SELECT private.append_relation_classification(ic.id, 'ordinal_beholdt', "
           f"{sql_literal(json.dumps(ev, sort_keys=True))}::jsonb) FROM private.interpretation_current ic "
           f"WHERE ic.interpretation_key='{l.item_id}'::uuid AND ic.version={int(l.version)}) x;")
```

      Ingen række ⇒ `SHEET_COUNT_MISMATCH`, som i dag.
  - **`spouse_exception_projection`:**
    - `cur` får `ic.version AS cur_version`.
    - `o_rows` udgiver `'interpretation_key',cur.interpretation_key::text,'interpretation_version',cur.cur_version` i stedet for `interpretation_id`. `state_sha256` fjernes fra objektet; `WHERE … h.l_sha=cur.state_sha256` bevares.
    - `ORDER BY cur.interpretation_key::text COLLATE "C"`.
    - Kontrakten bliver `'spouse-exception-rows-v2'`.
  - **`identity_control_rows.sql`:**
    - Efter `BEGIN;` tilføjes `SET LOCAL TimeZone='UTC';` og `SET LOCAL search_path=pg_catalog,public,private,extensions;`.
    - Linje 11: `jsonb_agg(DISTINCT a.vaerdi_tekst COLLATE "C" ORDER BY a.vaerdi_tekst COLLATE "C")`.
    - Linje 19: `ORDER BY sr.record_key COLLATE "C" LIMIT 1`.
    - Linje 56: `jsonb_agg(item ORDER BY item->>'kind' COLLATE "C", item->>'record_key' COLLATE "C", coalesce(item->>'source_persona_id',item->>'interpretation_key') COLLATE "C")`.
  - **`identity_sheet_rows.sql`:**
    - Øverst efter `SET default_transaction_read_only=on;` tilføjes `SET TimeZone='UTC';` og `SET search_path=pg_catalog,public,private,extensions;`. Filen har ingen `BEGIN`; hold det sådan.
    - Linje 23: `… DESC, ic.interpretation_key LIMIT 1`.
    - Linje 26: `ORDER BY ic.predicate COLLATE "C", ic.interpretation_key`.
  - **`persona_family_context`:** `jsonb_agg(DISTINCT o.konfidens COLLATE "C" ORDER BY o.konfidens COLLATE "C")`.
  - **`relation_persona_v3_input`:** `'previous'` bliver `jsonb_build_object('basis',i.evidence->>'basis','note',i.evidence->>'note')`.
  - **`relation_marriage_sheet_v3.py` l. 77:** `f"#   Tidligere afgørelse: {prev.get('basis')} · note: »{_ws(prev.get('note'))}«"`.
- [ ] **Step 4: Opdatér SQL-tests og e2e.** `test-spouse-exception-projection.sql` forventer `spouse-exception-rows-v2`, `interpretation_key` og ingen `state_sha256`. `test-spouse-exception-sheet.sh` skal bruge de nye O-linjer, som scriptet selv genererer via `render`, så kun forventede strenge ændres. `test-relation-persona-v3.sql` mister et eventuelt tjek af `decided_at`.
- [ ] **Step 5: Kør:**
  - pytest for alle arkværktøjer (`test_spouse_exception_sheet.py`, `test_identity_control_sheet.py`, `test_identity_decision_sheet.py`, `test_relation_marriage_sheet*.py`);
  - SQL-testene `test-spouse-exception-projection`, `test-identity-control-run`, `test-relation-persona-v3`;
  - e2e `bash tests/sql/test-spouse-exception-sheet.sh <db>` og `bash tests/sql/test-relation-marriage-sheet-v3.sh <db>`.

  Expected: alt OK.
- [ ] **Step 6: Commit** `feat(151): arkværktøjer uden tilfældige id'er og med platformsuafhængig sortering` (alle filer i Task 6).

---

### Task 7: Migrationsblok, paritet, opgraderingstest og hovedtest i CI

**Files:**
- Modify: `db-migrations.sql` (ny blok mellem `-- #244-blokken slutter her.` og `-- 5b-sektionen slutter her …`)
- Create: `tests/sql/inspect-5ab-function-parity.sql`
- Create: `tests/sql/test-indholds-id-upgrade.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: alle ændrede funktioner fra Task 1 og 3-6.
- Produces: `bash tests/sql/test-indholds-id-upgrade.sh <db>` → `UPGRADE_OK`; paritetsfil, der udskriver én linje pr. funktion: `signatur|prosecdef|proconfig|acl|body_sha256`.

- [ ] **Step 1: Paritetsfilen først (rød).** `tests/sql/inspect-5ab-function-parity.sql`:

```sql
\set ON_ERROR_STOP on
SELECT p.oid::regprocedure::text||'|'||p.prosecdef||'|'||coalesce(array_to_string(p.proconfig,','),'')||'|'||
       (SELECT string_agg(r||'='||has_function_privilege(r,p.oid,'EXECUTE'),',' ORDER BY r)
          FROM unnest(ARRAY['anon','authenticated','service_role']) r)||'|'||
       encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname,p.proname) IN (('private','content_uuid'),('private','decide_source_persona_identity'),
   ('private','identity_candidate_input'),('public','red_record_identity_candidates'),('private','write_relation_persona'),
   ('private','persona_family_context'),('public','red_register_identity_control_run'),
   ('private','spouse_exception_projection'),('private','relation_persona_v3_input'))
 ORDER BY 1 COLLATE "C";
```

  Byg en frisk base (bootstrap → `schema.sql` → `db-rls.sql`) og en migreret base (bootstrap → `schema.sql` fra `origin/main` → `db-rls.sql` → nuværende `db-migrations.sql` → `db-rls.sql`). Kør filen i begge og sammenlign.
  Expected: forskel, fordi migrationen endnu ikke har de nye kroppe.
- [ ] **Step 2: Migrationsblokken.** Indsæt over `-- 5b-sektionen slutter her`:

```sql
-- ===================================================================================
-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md): id'er og trækning af indholdet.
-- Kun CREATE OR REPLACE FUNCTION; kroppene er byte-identiske med schema.sql (paritet i CI).
-- ===================================================================================
```

  Kopiér derefter, i denne rækkefølge, de fulde definitioner fra `schema.sql` med deres `REVOKE`/`GRANT`-linjer:
  1. `private.content_uuid`
  2. `private.persona_family_context`
  3. `private.identity_candidate_input`
  4. `red_record_identity_candidates`
  5. `private.decide_source_persona_identity`
  6. `private.write_relation_persona`
  7. `red_register_identity_control_run`
  8. `private.spouse_exception_projection`
  9. `private.relation_persona_v3_input`

  Afslut med `-- Indholds-id-blokken slutter her.`
  Funktioner, der kaldes fra en SQL-funktion med `check_function_bodies`, skal stå efter det, de kalder. `content_uuid` er plpgsql, så rækkefølgen ovenfor er tilstrækkelig.
- [ ] **Step 3: Kør paritetsfilen igen** i den friske og den migrerede base. Expected: byte-identisk output (`diff` tom).
- [ ] **Step 4: Opgraderingstesten** `tests/sql/test-indholds-id-upgrade.sh`:

```bash
#!/usr/bin/env bash
# Indholds-id (#151, spec §5.5): opgradering fra prods træ 140a17b (deploy 2026-09-17, ingen 5a/5b-DDL).
# Migrationerne køres to gange; 5a/5b-testene, hovedtesten og db-verify køres på den opgraderede vej. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-140a17b}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do q -f "$f"; done
q -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'; q -f db-rls.sql
sed -n '/^-- BEGIN 5a-cutover/,/^-- END 5a-cutover/p' db-migrations.sql > "$tmp/cutover-5a.sql"
q -v cutover="$tmp/cutover-5a.sql" -f tests/sql/test-identity-cutover.sql
for t in test-content-uuid test-identity-decision test-identity-candidates test-identity-control-run test-relation-persona-writer \
         test-relation-persona-v3 test-spouse-exception-projection; do q -f "tests/sql/$t.sql"; done
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
bash tests/sql/test-indholds-id-determinism.sh "${1}_det" "upgrade:$base"
echo UPGRADE_OK
```

  Kør: `bash tests/sql/test-indholds-id-upgrade.sh t_up140`. Expected: `DETERMINISM_OK` og `UPGRADE_OK`.
  Fejler den i en opsætning, der ikke har med dette led at gøre (fx bootstrap mod det gamle træ eller ACL-porten), så ledger det som `Ruling:` med fejlteksten og den mindste rettelse i testscriptet. Ret ikke migrationerne for at få testen igennem uden at forelægge det.
- [ ] **Step 5: Hovedtesten grøn.** `bash tests/sql/test-indholds-id-determinism.sh t_det` → `DETERMINISM_OK`.
- [ ] **Step 6: CI.** I `ci.yml`:
  - i det job, der bygger `reimport_fresh_153` og `reimport_legacy_empty_153` (l. ~357-368), kør `inspect-5ab-function-parity.sql` i begge, og fejl jobbet, hvis outputtet afviger (`diff`);
  - i jobbet med `ci5b_2bii_sheet` (l. ~496-505): `bash tests/sql/test-indholds-id-determinism.sh ci_det`;
  - opgraderingstesten forbliver lokal, som `test-2bii-upgrade.sh`.

  Bekræft først, at CI's postgres-image har ICU (`SELECT count(*) FROM pg_collation WHERE collprovider='i'` > 0 i en CI-lignende container eller i jobbets første kørsel). Hvis ikke: ledger en ruling, og lad base B bruge `--locale=en_US.UTF-8` (libc).
- [ ] **Step 7: Hele den lokale CI:** alle 7 jobs i `ci.yml` (node, r, python og de 4 PostgreSQL-jobs), hvert job kørt med sine egne trin mod en lokal engangsklynge. Tidligere led genererede scripts til det i workspacet (`.superpowers/sdd/<plan>/ci/`); gør det samme her. Memory: kør hele jobbet, ikke kun de nye tests. Expected: 7/7 `CI_JOB_OK`.
- [ ] **Step 8: Commit** `feat(151): migrationsblok, paritet og opgraderingstest fra prods træ for id'er af indholdet`.

---

### Task 8: Dokumentation

**Files:**
- Modify: `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`, `docs/decisions.md`

- [ ] **Step 1: Statusrække.** Tilføj under 5b-rækkerne: »Id'er af indholdet (#151, forudsætning for overførslen) | `isoleret implementeret` (2026-10-21) | 8 rækkearter med id af indholdet, indholdsbaseret kontroltrækning, arkværktøjer uden tilfældige id'er og med `COLLATE "C"`; hovedtest i to baser (collation/tidszone/forhistorik) grøn; opgradering fra prods træ `140a17b` grøn. Ikke deployet; deployes i overførslens DDL-ceremoni.«
- [ ] **Step 2: Changelog-post** øverst, i samme form som #244's.
- [ ] **Step 3: Beslutningspost** øverst i `docs/decisions.md`: »#151: id'er af indholdet — forudsætning for 5a+5b-overførslen (2026-10-21)«. Indhold: valg A (serverside afledning), de 8 arter, trækning `-v2`, ark-SQL uden tilfældige id'er, og notatet til overførslens plan om `decision_interpretation_id` (spec §4 pkt. 6). Selve rettelsen af overførsels-spec'ens §7 hører til PR #250's gren og laves dér, ikke på denne gren.
- [ ] **Step 4: Commit** `docs(151): status, changelog og beslutning for id'er af indholdet`.

---

## Self-Review

| Spec | Plan |
| --- | --- |
| §3 afledning, 8 arter | Task 1 (hjælper), 3 (persona, omtale, hændelse), 4 (kørsel, kandidat), 5 (kontrol, stikprøve, forældrekort) |
| §3 kollision inkl. `unique_violation` | Task 3-5 tests og implementering |
| §3 trækning `-v2`, erratum og decisions | Task 5 |
| §3 fælles `decide_source_persona_identity` | Task 3 (alle oprindelser får hændelses-id af indholdet) |
| §4 pkt. 1-3 arkværktøjer | Task 6 |
| §4 pkt. 5 collation, brud og miljø | Task 6 (rækkefiler, projektioner), Task 4 (`identity_candidate_input`) |
| §4 pkt. 6 notat til overførslen | Task 8 |
| §5.1 hovedtest med fixturkontrakt | Task 2 (rød), Task 7 (grøn, CI) |
| §5.2 kollision | Task 3-5 |
| §5.3 arkværktøjer | Task 6 |
| §5.4 migrationsvej og paritet | Task 7 Step 1-3 |
| §5.5 opgradering fra `140a17b` med hovedtesten | Task 7 Step 4 |
| §5.6 lokal CI | Task 7 Step 7 |
| §6 modenhed og afgrænsning | Task 8 |

**Rækkefølge:** Task 2 er rød indtil Task 3-6 er gjort; Task 7 gør den grøn og kobler den på CI.

## Revision efter Fable-review (2026-10-21)

Dom: GO med rettelser (6 MAJOR, 13 MINOR). Indarbejdet: writer-bootstrap i basebygningen (M1); dumpet indlæses
med fixturhjælperne og `f2a_event_for_state` (M2); kandidaternes `corroboration_eligible` styrer stikprøven, og
`same` rammer afvigelsens ægtefælle (M3); forældrekort og kandidatkørsel 2 i kæden med opsætningsvagter (M4);
det påståede manglende komma i `inspect-reimport-writer-catalog.sql` var en fejllæsning af afkortet output og er
fjernet (M5); `test-identity-cutover` får sin `cutover`-variabel (M6); MINOR 2-6, 8-11 og 13 rettet i de
respektive tasks.
