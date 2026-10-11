# Trin 5b del 2a — bind afgjorte ægteskaber og forældre, vis kilden (#151) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De 203 ægteskaber med afgjorte parter og de 7 accepterede forældrepåstande i 2018-20 bindes til deres kanoniske familie, og læseren ser »Kilde: ‹udgave› · ‹post›« ved ægteskab og forældrelinje.

**Architecture:** En ny regeltype `structural_family` adskiller relationsbindinger fra assertion-vejen. Én privat tilstandsfunktion (`private.relation_binding_state`) definerer, hvad en relation er; maskinafgørelse, binding og offentlig læsning bruger den samme funktion og den samme hash, så en ændret identitet, part, påstandsversion eller familie skjuler kilden (reglen indgår bevidst ikke; spec §4.2). Afgørelse og binding er kildebundne, hash-autoriserede og tager kildelåsen og rækkelåse i fast orden. En offentlig `SECURITY DEFINER`-funktion udleverer kun etiketter bag publicerings- og familiegaten; web viser dem i `DetailPanel`.

**Tech Stack:** PostgreSQL/plpgsql (`schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`), SQL-tests med psql, TypeScript (`packages/core`, vitest), React (`web/`, vitest + Playwright).

**Spec:** `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md` (godkendt 2026-10-11, revideret efter Codex runde 1). Hovedspec: `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`.

## Global Constraints

- `schema.sql` er source of truth; `db-migrations.sql` er idempotent og køres to gange i CI (`CREATE OR REPLACE`, `IF NOT EXISTS`, `DROP … IF EXISTS`).
- 2a-blokke i `db-migrations.sql` indsættes **over** linjen `-- 5b-sektionen slutter her (nye 5b-blokke indsættes over denne linje).` (sidst i filen); i `schema.sql` tilføjes nye funktioner sidst i filen, mens ændringer af eksisterende tabeller/funktioner rettes på stedet.
- Nye `public.red_*`-navne: (1) `to_regprocedure('…')` i `v_authenticated` i `DO $public_red_revoke$` i `db-migrations.sql` (~linje 18752), (2) egen `REVOKE … FROM PUBLIC,anon,authenticated` + `GRANT EXECUTE … TO authenticated` efter definitionen, (3) `db-verify.sql`'s `$public_red_acl_verify$`-liste (~2927), (4) `db-rls.sql`'s allow-liste (`$redaction_rpc_allow_list$`, ~674). Mangler (1), fejler opgraderingen med `EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED` (memory: signaturændring kræver opgraderingstest).
- Nye `private`-tabeller tilføjes `db-rls.sql`'s master-array (~linje 22).
- Deterministisk orden: `ORDER BY … COLLATE "C"`; hashes via `private.reimport_canonical_json_sha256`. Databaseidentitet: `jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text`.
- Ingen værdier (navne, klausultekst, aktør-uuid) i stdout, log, chat, repo eller commits. Scripts printer kun tal og hashes. Filtrér aktør-uuid fra `set_config`-ekko (`\g /dev/null`).
- Node: `env -u NODE_OPTIONS`. Web-tests: dummy `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`. Psql lokalt: `PGHOST=/tmp`.
- SQL-fixtures kaldes som ejer **før** `SET LOCAL ROLE authenticated`; dblink-kald efter `RESET ROLE`.
- Commit pr. task, Conventional Commits på dansk, trailer `Claude-Session: https://claude.ai/code/session_011rKEYw62xDPse4zhLARtjo`, ingen Claude-attribution. Intet push uden projektejerens ja.
- **Frisk testbase** (som CI-jobbet `evidence-promotion-db`) — `fresh <db>`; contract-2-tests (som `writer-1939-v50-db`) — `fresh_v2 <db>`:
  ```bash
  export PGHOST=/tmp
  fresh() { createdb "$1" && for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "$f" >/dev/null || return 1; done; }
  fresh_v2() { fresh "$1" && psql -X -q -v ON_ERROR_STOP=1 -d "$1" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null; }
  ```
  Kun baser med præfikset `ci5b_` oprettes og droppes af planen.
- Arbejdsbaser: kun kopier (`createdb -T daa5b_bevis_20261010093638 daa5b_2a_<formål>_<ts>`); aldrig skrivning i `daa5b_bevis_*`, `daa2018f_*` eller prod.

## Review Focus

1. **Et nyt barn tilføjes familien efter bindingen** (2b/2c gør netop det) — ægteskabets kilde skal stadig vises; kun de bærende rækker indgår i tilstanden (Task 2, test `barn_uden_for_struktur`).
2. **Hovedpersonens identitet afgøres om efter bindingen** — kilden skal forsvinde, ikke vise den gamle families post (Task 5, test `ny_identitetsversion_skjuler`).
3. **Funktionen findes ikke i prod, når webkoden deployes** — panelet viser ingen kildelinje og ingen fejl (Task 7, test `rpc_fejl_giver_tom`).
4. **Personen har to ægteskaber med samme ægtefælle (to familier)** — hver kildelinje hører til sin egen familie; ingen sammenblanding (Task 6, test `to_familier_samme_par`).
5. **Afgørelsen køres mod en anden kilde end den forhåndsviste** — `RELATION_DECISION_SET_DRIFT`, 0 skrivninger (Task 3, test `anden_kilde`).

## File Structure

| Fil | Ansvar |
| --- | --- |
| `schema.sql`, `db-migrations.sql` | regeltype, tilstandsfunktion, klassifikationstabel, afgørelse, binding, offentlig læsefunktion |
| `db-rls.sql`, `db-verify.sql` | masterliste (inkl. M4), allow-liste, offentlige grants, asserts |
| `tests/sql/fixtures/relation-2a.sql` (ny) | 2a-fixtures: accepteret ægtefælle-identitet, publiceret post |
| `tests/sql/test-relation-binding.sql` (ny) | Task 1-4 (frisk schema-sti) inkl. to-sessionstests |
| `tests/sql/test-family-sources.sql` (ny) | Task 5 (contract 2) |
| `tests/sql/test-relation-binding-upgrade.sh` (ny) | opgraderingstest fra `ebf2022` |
| `packages/core/src/familieKilder.ts` (+ `__tests__/familieKilder.test.ts`) | familie-id'er for en person, kildelinje |
| `web/src/data/familySources.ts` (+ `__tests__/familySources.test.ts`) | RPC-kald, fejl ⇒ `[]` |
| `web/src/components/DetailPanel.tsx` (+ `__tests__/DetailPanel.familieKilder.test.tsx`) | visning og klik |
| `web/e2e/family-sources.spec.ts` | røgtest med mockede RPC-svar |
| `.github/workflows/ci.yml` | nye SQL-trin |
| `docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md` | færdigbevis (Task 8) |

---

### Task 0: Forudsætninger (intet skrives i delte baser)

**Files:** ingen repo-ændringer; ledger `.superpowers/sdd/2026-10-11-trin5b-2a-binding/progress.md` (gitignoreret).

- [ ] **Step 1: Bekræft udgangspunktet.** `git log --oneline -1` på grenen viser spec-commit'en; `git status` er rent.
- [ ] **Step 2: Bekræft målingerne fra spec §3 i bevisbasen (læse-kun).**

```bash
export PGHOST=/tmp
psql -X -At -d daa5b_bevis_20261010093638 <<'SQL'
BEGIN READ ONLY;
SELECT 'regel-checks', string_agg(conname, ',' ORDER BY conname) FROM pg_constraint
 WHERE conrelid='private.interpretation_promotion_rule'::regclass AND contype='c';
SELECT 'familiebindinger', count(*) FROM private.interpretation_promotion WHERE target_type='family';
SELECT 'kontrakt', public.narrative_record_contract_version();
SELECT 'vielse-fakta pr familie >1', count(*) FROM (SELECT subjekt_id FROM fact WHERE subjekt_type='family' AND faktatype='vielse' GROUP BY 1 HAVING count(*)>1) x;
ROLLBACK;
SQL
```
Expected: de fire CHECK-navne fra spec §4.1 findes; `familiebindinger|0`; `kontrakt|2`. Notér tallet for vielse-fakta >1 i ledgeren (de familier får `vielse_fact_id = null`).

- [ ] **Step 3: Notér i ledgeren** basenavn, commit og målingerne. Ingen commit.

---

### Task 1: Regeltypen `structural_family`

**Files:**
- Modify: `schema.sql` (tabellen ~1344; regelindsættelser ~1381; `interpretation_promotion_rule_current` ~1391; validatoren ~1400; `interpretation_predicate_promotable` ~1420; `add_interpretation_promotion_rule_version` ~1428; revoke-listen ~1857)
- Modify: `db-migrations.sql` (ny blok over 5b-slutlinjen), `db-verify.sql` (~4354 signatur; ny assert-blok sidst), `tests/sql/test-interpretation-predicate.sql` (uændret adfærd — kør den)
- Create: `tests/sql/test-relation-binding.sql`, `tests/sql/test-relation-binding-upgrade.sh`
- Modify: `.github/workflows/ci.yml` (job `evidence-promotion-db`, efter `test-relation-decision.sql`)

**Interfaces:**
- Produces: kolonnen `private.interpretation_promotion_rule.rule_mode text` ∈ `text_assertion|structural_family`; constraint `interpretation_promotion_rule_mode_check`; regler `relation-marriage-v1`/`relation-parent-v1` version 1 (`structural_family`, `active`, `requires_persona_identity=false`); `private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text,text DEFAULT 'text_assertion')`.

- [ ] **Step 1: Skriv den fejlende test** — opret `tests/sql/test-relation-binding.sql`:

```sql
-- Trin 5b del 2a (spec 2026-10-11): regeltype, tilstand, afgørelse og binding.
\set ON_ERROR_STOP on

-- ---------- Task 1: regeltypen structural_family ----------
BEGIN;
DO $rule_mode$
DECLARE v_err text;
BEGIN
  IF (SELECT attnotnull FROM pg_attribute WHERE attrelid='private.interpretation_promotion_rule'::regclass
       AND attname='expected_fact_type') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: expected_fact_type er stadig NOT NULL';
  END IF;
  IF (SELECT count(*) FROM private.interpretation_promotion_rule_current
       WHERE rule_key IN ('relation-marriage-v1','relation-parent-v1') AND rule_mode='structural_family'
         AND status='active' AND target_type='family' AND expected_fact_type IS NULL)<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relationsregler mangler';
  END IF;
  -- structural_family med assertion-mål afvises af CHECK'en
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('relation-marriage-v1',99,'relation.marriage','relation','assertion',NULL,'relation',false,false,true,'active','structural_family');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forkert mål godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- text_assertion uden faktatype afvises
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('person-name-v1',99,'person.name','property','assertion',NULL,'text',true,false,true,'active','text_assertion');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: assertion-regel uden faktatype godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- Triggeren er sit eget kontraktled (Codex plan-r1 #7): rækker der PASSERER mode-CHECK'en,
  -- men har et prædikat af forkert værdiart, afvises af triggeren med dens egen kode.
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('relation-marriage-v1',98,'relation.marriage','property','assertion','navn','text',true,false,true,'active','text_assertion');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relation som tekstregel godtaget af triggeren';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
      expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
    VALUES ('person-name-v1',98,'person.name','relation','family',NULL,'relation',false,false,true,'active','structural_family');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tekstprædikat som strukturregel godtaget af triggeren';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' THEN RAISE; END IF;
  END;
  -- versionsfunktionen: relation kun i structural_family
  BEGIN
    PERFORM private.add_interpretation_promotion_rule_version('relation-marriage-v1','relation.marriage','relation','family',
      NULL,'relation',false,false,true,'active');   -- default text_assertion
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relation som text_assertion godtaget';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH%' AND v_err NOT LIKE '%interpretation_promotion_rule_mode_check%' THEN RAISE; END IF;
  END;
  IF private.add_interpretation_promotion_rule_version('relation-marriage-v1','relation.marriage','relation','family',
       NULL,'relation',false,false,true,'active','structural_family')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ny structural_family-version';
  END IF;
  -- assertion-vejen ser aldrig relationsregler
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate_promotable WHERE predicate LIKE 'relation.%') THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: relationsregel i promotable';
  END IF;
  IF to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: gammel overload findes';
  END IF;
  RAISE NOTICE 'OK: regeltype structural_family';
END $rule_mode$;
ROLLBACK;
```

- [ ] **Step 2: Kør den og se den fejle**

```bash
fresh ci5b_2a_t1 && psql -X -q -d ci5b_2a_t1 -f tests/sql/test-relation-binding.sql
```
Expected: FAIL `RELATION_BINDING_TEST_FAILED: expected_fact_type er stadig NOT NULL`. (Parse-bevis: filen skal nå til den assertion; en syntaksfejl tidligere i filen er ikke et gyldigt rødt resultat.)

Note: BEFORE-triggeren kører før CHECK-constraints, så begge trigger-cases rammer triggeren både før og efter ændringen; de beviser, at den nye triggerkrop stadig afviser forkert værdiart. Bekræft efter Step 3, at fjernes triggerens værdiart-kontrol midlertidigt (lokalt, ikke committet), bliver mindst én af de to cases rød.

- [ ] **Step 3: Ret `schema.sql`.**

Tabellen (~1344) bliver:
```sql
CREATE TABLE private.interpretation_promotion_rule (
  rule_key                      text NOT NULL CHECK (btrim(rule_key)<>''),
  rule_version                  integer NOT NULL CHECK (rule_version>=1),
  predicate                     text NOT NULL CHECK (btrim(predicate)<>''),
  interpretation_kind           text NOT NULL,
  target_type                   text NOT NULL,
  expected_fact_type            text,
  value_kind                    text NOT NULL,
  requires_persona_identity     boolean NOT NULL DEFAULT true,
  requires_principal_placement  boolean NOT NULL DEFAULT false,
  bulk_eligible                 boolean NOT NULL DEFAULT true,
  status                        text NOT NULL CHECK (status IN ('active','retired')),
  created_at                    timestamptz NOT NULL DEFAULT now(),
  -- Trin 5b 2a: sidst, så `SELECT *`-viewet har samme kolonneorden på frisk og opgraderet base.
  rule_mode                     text NOT NULL DEFAULT 'text_assertion',
  PRIMARY KEY (rule_key,rule_version),
  UNIQUE (predicate,rule_version),
  FOREIGN KEY (rule_key,predicate)
    REFERENCES private.interpretation_promotion_rule_line(rule_key,predicate),
  CONSTRAINT interpretation_promotion_rule_mode_check CHECK (
    (rule_mode='text_assertion' AND interpretation_kind='property' AND target_type='assertion'
       AND expected_fact_type IN ('navn','tilnavn','titel','fødsel','død') AND value_kind IN ('text','date_raw'))
    OR (rule_mode='structural_family' AND interpretation_kind='relation' AND target_type='family'
       AND expected_fact_type IS NULL AND value_kind='relation'))
);
```
Efter de eksisterende regelindsættelser (~1389) og `rule_line`-indsættelsen tilføjes:
```sql
INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES
  ('relation-marriage-v1','relation.marriage'),
  ('relation-parent-v1','relation.parent');
INSERT INTO private.interpretation_promotion_rule(
  rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
  value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode
) VALUES
  ('relation-marriage-v1',1,'relation.marriage','relation','family',NULL,'relation',false,false,true,'active','structural_family'),
  ('relation-parent-v1',1,'relation.parent','relation','family',NULL,'relation',false,false,true,'active','structural_family');
```
(Indsættelsen skal stå **efter** `trg_interpretation_promotion_rule_predicate` er oprettet, eller valideres af Step 3's nye trigger-krop; flyt den ellers ned under triggeren.)

Validatoren (~1400), anden betingelse erstattes:
```sql
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_predicate pr
                  WHERE pr.predicate=NEW.predicate AND pr.value_kind=NEW.value_kind
                    AND ((NEW.rule_mode='text_assertion' AND pr.value_kind IN ('text','date_raw'))
                      OR (NEW.rule_mode='structural_family' AND pr.value_kind='relation'
                          AND pr.interpretation_kind='relation'))) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH';
  END IF;
```
`interpretation_predicate_promotable` (~1420) får `AND r.rule_mode='text_assertion'` i `WHERE`.

`add_interpretation_promotion_rule_version` (~1428): ny sidste parameter `p_rule_mode text DEFAULT 'text_assertion'`, samme value_kind-betingelse som triggeren (med `p_*`), og `rule_mode` i `INSERT`-kolonnelisten med `p_rule_mode`. Revoke-listen (~1857) får den nye signatur `(text,text,text,text,text,text,boolean,boolean,boolean,text,text)`.

- [ ] **Step 4: Migrationen** — i `db-migrations.sql` over 5b-slutlinjen:

```sql
-- ===================================================================================
-- Trin 5b del 2a (#151, spec 2026-10-11): strukturelle familiebindinger.
-- ===================================================================================
ALTER TABLE private.interpretation_promotion_rule ADD COLUMN IF NOT EXISTS rule_mode text NOT NULL DEFAULT 'text_assertion';
ALTER TABLE private.interpretation_promotion_rule ALTER COLUMN expected_fact_type DROP NOT NULL;
ALTER TABLE private.interpretation_promotion_rule
  DROP CONSTRAINT IF EXISTS interpretation_promotion_rule_interpretation_kind_check,
  DROP CONSTRAINT IF EXISTS interpretation_promotion_rule_target_type_check,
  DROP CONSTRAINT IF EXISTS interpretation_promotion_rule_expected_fact_type_check,
  DROP CONSTRAINT IF EXISTS interpretation_promotion_rule_value_kind_check,
  DROP CONSTRAINT IF EXISTS interpretation_promotion_rule_mode_check;
ALTER TABLE private.interpretation_promotion_rule ADD CONSTRAINT interpretation_promotion_rule_mode_check CHECK (
  (rule_mode='text_assertion' AND interpretation_kind='property' AND target_type='assertion'
     AND expected_fact_type IN ('navn','tilnavn','titel','fødsel','død') AND value_kind IN ('text','date_raw'))
  OR (rule_mode='structural_family' AND interpretation_kind='relation' AND target_type='family'
     AND expected_fact_type IS NULL AND value_kind='relation'));
CREATE OR REPLACE VIEW private.interpretation_promotion_rule_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON(rule_key) * FROM private.interpretation_promotion_rule
ORDER BY rule_key,rule_version DESC;
REVOKE ALL ON TABLE private.interpretation_promotion_rule_current FROM PUBLIC,anon,authenticated;
```
Derefter: `CREATE OR REPLACE FUNCTION private.validate_interpretation_promotion_rule_predicate()` med samme krop som Step 3; `CREATE OR REPLACE VIEW private.interpretation_predicate_promotable` med filteret (samme kolonner som i dag); `DROP FUNCTION IF EXISTS private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text);` og den nye funktion med `REVOKE EXECUTE … FROM PUBLIC,anon,authenticated`; regellinjerne med `ON CONFLICT (rule_key) DO NOTHING` og regelversionerne med `ON CONFLICT (rule_key,rule_version) DO NOTHING`.

- [ ] **Step 5: `db-verify.sql`** — ret ~4354 til den nye 11-parameter-signatur (kaldene ~4885-4911 og ~5328 og `tests/sql/test-interpretation-predicate.sql:51-64` virker uændret via standardværdien — kør dem), og tilføj sidst en blok:

```sql
DO $relation_binding_rule_verify$
BEGIN
  IF (SELECT attnotnull FROM pg_attribute WHERE attrelid='private.interpretation_promotion_rule'::regclass AND attname='expected_fact_type')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_rule'::regclass
                     AND conname='interpretation_promotion_rule_mode_check')
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_rule'::regclass
                 AND conname IN ('interpretation_promotion_rule_interpretation_kind_check','interpretation_promotion_rule_target_type_check',
                                 'interpretation_promotion_rule_expected_fact_type_check','interpretation_promotion_rule_value_kind_check'))
     OR to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)') IS NOT NULL
     OR (SELECT count(*) FROM private.interpretation_promotion_rule_current
          WHERE rule_key IN ('relation-marriage-v1','relation-parent-v1') AND rule_mode='structural_family' AND status='active')<>2
     OR EXISTS (SELECT 1 FROM private.interpretation_predicate_promotable WHERE predicate LIKE 'relation.%') THEN
    RAISE EXCEPTION 'RELATION_BINDING_RULE_CONTRACT_INVALID';
  END IF;
END $relation_binding_rule_verify$;
```

- [ ] **Step 6: Kør testene**

```bash
dropdb ci5b_2a_t1; fresh ci5b_2a_t1 && psql -X -q -d ci5b_2a_t1 -f tests/sql/test-relation-binding.sql \
 && psql -X -q -d ci5b_2a_t1 -f tests/sql/test-interpretation-predicate.sql \
 && psql -X -q -d ci5b_2a_t1 -f tests/sql/test-evidence-promotion.sql \
 && psql -X -q -d ci5b_2a_t1 -f tests/sql/run-db-verify-disposable.sql
```
Expected: `OK: regeltype structural_family`; de øvrige grønne.

- [ ] **Step 7: Opgraderingstest** — opret `tests/sql/test-relation-binding-upgrade.sh`:

```bash
#!/usr/bin/env bash
# Trin 5b 2a: db-migrations + db-rls på en base bygget fra ebf2022 (ændret tabel og ændret signatur).
set -euo pipefail
db=${1:?database}; base=${2:-ebf2022}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$f" >/dev/null
done
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-relation-binding.sql
# De eksisterende text/date-regler virker stadig funktionelt efter opgraderingen (spec §8).
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-evidence-promotion.sql
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-interpretation-predicate.sql
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/run-db-verify-disposable.sql
echo UPGRADE_OK
```
Run: `bash tests/sql/test-relation-binding-upgrade.sh ci5b_2a_up` → Expected: `UPGRADE_OK`. (Kun lokalt; CI kører frisk sti.)

- [ ] **Step 8: CI-trin** — i `.github/workflows/ci.yml`, job `evidence-promotion-db`, efter `test-relation-decision.sql`: `psql -v ON_ERROR_STOP=1 -f tests/sql/test-relation-binding.sql`.

- [ ] **Step 9: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql tests/sql/test-relation-binding.sql tests/sql/test-relation-binding-upgrade.sh .github/workflows/ci.yml
git commit -m "feat(151): regeltypen structural_family adskilt fra assertion-vejen (5b 2a)"
```

---

### Task 2: Bindingens tilstand, klassifikationer og ét familiemål pr. fortolkning

**Files:**
- Modify: `schema.sql` (sidst), `db-migrations.sql` (2a-blokken), `db-rls.sql` (master-array ~22: `relation_classification_event`, `identity_control_exclusion`, `identity_control_parent_card`, `identity_control_parent_event`), `db-verify.sql` (2a-assertblokken)
- Create: `tests/sql/fixtures/relation-2a.sql`
- Modify: `tests/sql/test-relation-binding.sql`

**Interfaces:**
- Consumes: `private.interpretation_party_current`, `private.source_persona_identity`, `public.family_member`, regelviewet fra Task 1.
- Produces:
  - `private.relation_binding_state(p_interpretation_id uuid) RETURNS jsonb` — `NULL` eller `{contract:'relation-binding-state-v1', interpretation:{interpretation_id, interpretation_key, version, status, predicate, source_id}, parties:[{party_role, version, source_persona_id, identity_version, decision_status, canonical_person_id}], family:{family_id, rows:[[person_id, rolle, ordinal, konfidens]]}, counterpart_person_id, book_ordinal, family_ordinal}`. Reglen indgår ikke (spec §4.2, r2-M3).
  - `private.relation_binding_state_sha256(p_interpretation_id uuid) RETURNS text` (NULL ved NULL-tilstand).
  - Tabel `private.relation_classification_event` (med `interpretation_id`, `interpretation_version`, `state_sha256`) og `private.append_relation_classification(p_interpretation_id uuid, p_classification text, p_evidence jsonb) RETURNS integer` (ny `seq`; nøgle, version og tilstandshash udledes af serveren).
  - Indeks `interpretation_promotion_one_family_per_interpretation`.
  - Fixtures `pg_temp.f2a_marriage(...)`, `pg_temp.f2a_parent(...)`, `pg_temp.f2a_publish(...)`.

- [ ] **Step 1: Fixtures** — opret `tests/sql/fixtures/relation-2a.sql` (indlæses efter `relation-5b.sql`):

```sql
-- Trin 5b 2a: fixtures oven på relation-5b.sql. Kaldes som ejer.
-- Identitetsstate og -event skal være konsistente (deferred constraint-triggere identity_state_has_event /
-- identity_event_is_projected, schema.sql ~1822). Testene kører `SET CONSTRAINTS ALL IMMEDIATE;` efter
-- fixture-opbygningen, så en umulig tilstand fejler i testen og ikke skjules af ROLLBACK (Codex plan-r1 #5).

-- f5b_post skriver kun hovedpersonens state-række; denne helper skriver den matchende event (samme felter).
CREATE OR REPLACE FUNCTION pg_temp.f2a_event_for_state(p_persona uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
  SELECT i.source_persona_id,i.canonical_person_id,i.decision_status,i.version,i.evidence,i.decided_by,i.decided_by_name,i.decided_at
    FROM private.source_persona_identity i
   WHERE i.source_persona_id=p_persona
     AND NOT EXISTS (SELECT 1 FROM private.source_persona_identity_event e
                      WHERE e.source_persona_id=i.source_persona_id AND e.version=i.version);
$$;

-- Et ægteskab: hovedpersonens post, en ægteskabspåstand med ægtefælle-persona og begge identiteter
-- accepteret, og en kanonisk familie med begge som partnere (ordinal p_famord, bogens nummer p_bookord).
CREATE OR REPLACE FUNCTION pg_temp.f2a_marriage(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_spouse bigint,
  p_actor uuid,p_bookord int DEFAULT 1,p_famord int DEFAULT 1,p_make_family boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; c jsonb; v_persona uuid; v_fam bigint; v_text text:='Anna Alfa. Gift med Bo Beta.';
  v_at timestamptz:=clock_timestamp();   -- ét tidsstempel: event og state skal være identiske
BEGIN
  p:=pg_temp.f5b_post(p_source,p_src,p_key,v_text,ARRAY['Anna Alfa.','Gift med Bo Beta.'],p_principal,p_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  v_persona:=pg_temp.f5b_spouse(p_source,p_src,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',p_bookord);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_persona,p_spouse,'accepted',1,'{"fixture":"2a"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v_persona,p_spouse,'accepted',1,'{"fixture":"2a"}',p_actor,'fixture',v_at);
  IF p_make_family THEN v_fam:=pg_temp.f5b_family(p_principal,p_spouse,p_famord); END IF;
  RETURN jsonb_build_object('post',p,'claim',c,'spouse_persona',v_persona,'family',v_fam);
END $$;

-- En accepteret forælderpåstand: barnets post, forælderens post, familien (forælder partner, barn barn),
-- påstanden afgjort som i del 1 (principal + parent-part, status accepted gennem red_decide_interpretation).
CREATE OR REPLACE FUNCTION pg_temp.f2a_parent(p_source bigint,p_src jsonb,p_child bigint,p_parent bigint,p_other bigint,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE pc jsonb; pp jsonb; c jsonb; v_fam bigint; v_new uuid;
BEGIN
  pp:=pg_temp.f5b_post(p_source,p_src,'PAR-'||p_parent,'Far Alfa.',ARRAY['Far Alfa.'],p_parent,p_actor);
  pc:=pg_temp.f5b_post(p_source,p_src,'BARN-'||p_child,'Barn Alfa. søn af Far.',ARRAY['Barn Alfa.','søn af Far.'],p_child,p_actor);
  PERFORM pg_temp.f2a_event_for_state((pp->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((pc->>'principal')::uuid);
  v_fam:=pg_temp.f5b_family(p_parent,p_other,1);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,p_child,'barn');
  c:=pg_temp.f5b_claim(p_source,p_src,'relation.parent',(pc->'clauses'->>1)::uuid,'søn af Far.');
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(pc->>'principal')::uuid,11,'relation_persona',gen_random_uuid());
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_relation_interpretation((c->>'key')::uuid,1,'same',v_fam,'fixture','{}');
  RESET ROLE;
  RETURN jsonb_build_object('child_post',pc,'parent_post',pp,'claim',c,'family',v_fam);
END $$;

-- Publicerer en post (kontrakt 2) gennem de rigtige redaktions-RPC'er. Afprøvet 2026-10-11 i en frisk
-- contract-2-base: kræver accepteret record- og persona-placering (principal_member) med helposten som grundlag.
CREATE OR REPLACE FUNCTION pg_temp.f2a_publish(p_source bigint,p_src jsonb,p_post jsonb,p_person bigint,p_actor uuid,p_text text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_header uuid; v_rp uuid:=gen_random_uuid(); v_pp uuid:=gen_random_uuid(); h text; r jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lineage_scheme WHERE id=p_source) THEN
    INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES (p_source,'2a slægt '||p_source,'2a slægt '||p_source,'2a-slaegt'||abs(p_source));
    INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (p_source,p_source,p_source,'stamtavle','2a scheme');
    INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (p_source,p_source,p_source,'A','Linje A',1);
  END IF;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id)
    VALUES ((p_post->>'occ')::uuid,'header',10,10,1000,1004,substr(p_text,1,4),'clear','fixture',(p_src->>'run')::uuid) RETURNING id INTO v_header;
  INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
    VALUES (v_rp,(p_post->>'record')::uuid,p_source,v_header,'accepted');
  INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_rp,1,'accepted','{"basis":"2a fixture"}','migration','fixture');
  INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_pp,(p_post->>'principal')::uuid,v_rp,'principal_member',(p_post->>'helpost')::uuid,'accepted');
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_pp,1,'accepted','{"basis":"2a fixture"}','migration','fixture');
  h:=private.narrative_record_state(p_person,p_source,p_post->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  r:=public.red_upsert_person_narrative_record(p_person,p_source,p_post->>'key',p_text,false,h);
  -- upsert og publicering er hver sin redaktionshandling; change_set-id'et er transaktionslokalt.
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_publicer_person_narrative_record(p_person,p_source,p_post->>'key',r->>'state_sha256');
  RESET ROLE;
END $$;
```
Hver testblok kører `SET CONSTRAINTS ALL IMMEDIATE;` som første sætning i sin `DO`-blok efter fixture-kaldene er gjort (dvs. lige før de første asserts), så deferred identitets- og andre constraint-triggere fyrer i testen. Fejler en del 1-fixture (`relation-5b.sql`) dér, rettes 2a-fixturen (ikke del 1's), og fundet noteres i ledgeren.

Bemærk: `f5b_post` bruger altid samme to klausuler; `f2a_marriage` giver derfor post-teksten fast. Brug forskellige `p_key` pr. kald.

- [ ] **Step 2: Skriv den fejlende test** — tilføj til `tests/sql/test-relation-binding.sql`:

```sql
-- ---------- Task 2: bindingens tilstand ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $binding_state$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0201'; s jsonb; m jsonb; m2 jsonb; par jsonb; st jsonb; h1 text; v_err text;
  v_fam2 bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES
    (-2201,false,false,'2a'),(-2202,false,false,'2a'),(-2203,false,false,'2a'),(-2204,false,false,'2a'),
    (-2205,false,false,'2a'),(-2206,false,false,'2a'),(-2207,false,false,'2a');
  s:=pg_temp.f5b_source(-2201);
  m:=pg_temp.f2a_marriage(-2201,s,'M-1',-2201,-2202,v_actor,2,1);
  SET CONSTRAINTS ALL IMMEDIATE;   -- fixturen skal være en mulig, committbar tilstand
  st:=private.relation_binding_state((m->'claim'->>'id')::uuid);
  IF st IS NULL OR st->>'contract'<>'relation-binding-state-v1' OR (st->'family'->>'family_id')::bigint<>(m->>'family')::bigint
     OR jsonb_array_length(st->'family'->'rows')<>2 OR (st->>'book_ordinal')::int<>2 OR (st->>'family_ordinal')::int<>1
     OR jsonb_array_length(st->'parties')<>2 OR st ? 'rule' OR (st->>'counterpart_person_id')::bigint<>-2202 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilstand %', st IS NULL;
  END IF;
  h1:=private.relation_binding_state_sha256((m->'claim'->>'id')::uuid);
  -- barn_uden_for_struktur: et nyt barn ændrer ikke tilstanden
  INSERT INTO family_member(family_id,person_id,rolle) VALUES ((m->>'family')::bigint,-2203,'barn');
  IF private.relation_binding_state_sha256((m->'claim'->>'id')::uuid) IS DISTINCT FROM h1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: barn ændrede tilstanden';
  END IF;
  -- omstridt på en bærende række ⇒ NULL
  UPDATE family_member SET konfidens='omstridt' WHERE family_id=(m->>'family')::bigint AND person_id=-2202;
  IF private.relation_binding_state((m->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: omstridt godtaget';
  END IF;
  UPDATE family_member SET konfidens=NULL WHERE family_id=(m->>'family')::bigint AND person_id=-2202;
  -- to familier med samme par ⇒ NULL; bagefter fjernes den ekstra familie igen, så klassifikationsdelen
  -- nedenfor arbejder på en entydig struktur (Codex plan-r1 #1)
  v_fam2:=pg_temp.f5b_family(-2201,-2202,2);
  IF private.relation_binding_state((m->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: flere familier godtaget';
  END IF;
  DELETE FROM family_member WHERE family_id=v_fam2;
  DELETE FROM family WHERE id=v_fam2;
  IF private.relation_binding_state_sha256((m->'claim'->>'id')::uuid) IS DISTINCT FROM h1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: tilstanden vendte ikke tilbage efter oprydning';
  END IF;
  -- ingen familie ⇒ NULL
  m2:=pg_temp.f2a_marriage(-2201,s,'M-2',-2204,-2205,v_actor,1,1,false);
  IF private.relation_binding_state((m2->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ingen familie godtaget';
  END IF;
  -- forælder: principal er barn, forælderen partner
  par:=pg_temp.f2a_parent(-2201,s,-2206,-2207,NULL,v_actor);
  st:=private.relation_binding_state((SELECT id FROM private.interpretation_current WHERE interpretation_key=(par->'claim'->>'key')::uuid));
  IF st IS NULL OR st->'interpretation'->>'status'<>'accepted' OR (st->'family'->>'family_id')::bigint<>(par->>'family')::bigint
     OR (st->>'counterpart_person_id')::bigint<>-2207 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forældertilstand';
  END IF;
  -- klassifikation: append-only med fortløbende seq
  IF private.append_relation_classification((m->'claim'->>'id')::uuid,'ordinal_afvigelse','{"x":1}')<>1
     OR private.append_relation_classification((m->'claim'->>'id')::uuid,'ordinal_afvigelse','{"x":2}')<>2
     OR (SELECT count(*) FROM private.relation_classification_event
          WHERE interpretation_key=(m->'claim'->>'key')::uuid AND interpretation_id=(m->'claim'->>'id')::uuid
            AND interpretation_version=1 AND state_sha256 ~ '^[0-9a-f]{64}$')<>2 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: klassifikationens seq og versionsbinding';
  END IF;
  -- en ikke-gældende version kan ikke klassificeres
  BEGIN
    PERFORM private.append_relation_classification(gen_random_uuid(),'ordinal_afvigelse','{"x":4}');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ukendt fortolkning';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_CLASSIFICATION_NOT_CURRENT%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE private.relation_classification_event SET evidence='{"y":1}' WHERE interpretation_key=(m->'claim'->>'key')::uuid;
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: klassifikation kunne ændres';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err LIKE 'RELATION_BINDING_TEST_FAILED%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM private.append_relation_classification((m->'claim'->>'id')::uuid,'noget_andet','{"x":3}');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: ukendt klassifikation';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'OK: bindingens tilstand og klassifikationer';
END $binding_state$;
ROLLBACK;
```

- [ ] **Step 3: Kør og se den fejle** — `dropdb ci5b_2a_t1; fresh ci5b_2a_t1 && psql -X -q -d ci5b_2a_t1 -f tests/sql/test-relation-binding.sql` → FAIL `function private.relation_binding_state(uuid) does not exist`.

- [ ] **Step 4: Implementér** — i `schema.sql` (sidst) og i `db-migrations.sql`'s 2a-blok (identisk tekst):

```sql
CREATE OR REPLACE FUNCTION private.relation_binding_state(p_interpretation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_i private.interpretation%ROWTYPE; v_role text; v_parties jsonb;
  v_a bigint; v_b bigint; v_fams bigint[]; v_rows jsonb; v_book integer; v_famord integer;
BEGIN
  SELECT * INTO v_i FROM private.interpretation WHERE id=p_interpretation_id;
  IF NOT FOUND OR v_i.predicate NOT IN ('relation.marriage','relation.parent') THEN RETURN NULL; END IF;
  v_role:=CASE v_i.predicate WHEN 'relation.marriage' THEN 'spouse' ELSE 'parent' END;
  SELECT jsonb_agg(jsonb_build_object('party_role',pc.party_role,'version',pc.version,
           'source_persona_id',pc.source_persona_id::text,'identity_version',i.version,
           'decision_status',i.decision_status,'canonical_person_id',i.canonical_person_id)
         ORDER BY pc.party_role COLLATE "C")
    INTO v_parties
    FROM private.interpretation_party_current pc
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id
   WHERE pc.interpretation_key=v_i.interpretation_key AND pc.party_role IN ('principal',v_role);
  IF coalesce(jsonb_array_length(v_parties),0)<>2
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_parties) x
                 WHERE x->>'decision_status' IS DISTINCT FROM 'accepted' OR x->>'canonical_person_id' IS NULL) THEN
    RETURN NULL;
  END IF;
  SELECT (x->>'canonical_person_id')::bigint INTO v_a FROM jsonb_array_elements(v_parties) x WHERE x->>'party_role'='principal';
  SELECT (x->>'canonical_person_id')::bigint INTO v_b FROM jsonb_array_elements(v_parties) x WHERE x->>'party_role'=v_role;
  IF v_a=v_b THEN RETURN NULL; END IF;
  SELECT array_agg(a.family_id ORDER BY a.family_id) INTO v_fams
    FROM public.family_member a
    JOIN public.family_member b ON b.family_id=a.family_id AND b.person_id=v_b AND b.rolle='partner'
   WHERE a.person_id=v_a AND a.rolle=CASE v_role WHEN 'spouse' THEN 'partner' ELSE 'barn' END;
  IF coalesce(cardinality(v_fams),0)<>1 THEN RETURN NULL; END IF;
  SELECT jsonb_agg(jsonb_build_array(fm.person_id,fm.rolle,fm.ordinal,fm.konfidens) ORDER BY fm.person_id,fm.rolle COLLATE "C")
    INTO v_rows
    FROM public.family_member fm
   WHERE fm.family_id=v_fams[1]
     AND ((fm.person_id=v_a AND fm.rolle=CASE v_role WHEN 'spouse' THEN 'partner' ELSE 'barn' END)
       OR (fm.person_id=v_b AND fm.rolle='partner'));
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_rows) x WHERE x->>3='omstridt') THEN RETURN NULL; END IF;
  IF v_role='spouse' THEN
    SELECT pc.marriage_ordinal INTO v_book FROM private.interpretation_party_current pc
     WHERE pc.interpretation_key=v_i.interpretation_key AND pc.party_role='spouse';
    SELECT fm.ordinal INTO v_famord FROM public.family_member fm
     WHERE fm.family_id=v_fams[1] AND fm.person_id=v_a AND fm.rolle='partner';
  END IF;
  RETURN jsonb_build_object('contract','relation-binding-state-v1',
    'interpretation',jsonb_build_object('interpretation_id',v_i.id::text,'interpretation_key',v_i.interpretation_key::text,
      'version',v_i.version,'status',v_i.status,'predicate',v_i.predicate,'source_id',v_i.source_id),
    'parties',v_parties,
    'family',jsonb_build_object('family_id',v_fams[1],'rows',v_rows),'counterpart_person_id',v_b,
    'book_ordinal',v_book,'family_ordinal',v_famord);
END $$;
REVOKE ALL ON FUNCTION private.relation_binding_state(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.relation_binding_state_sha256(p_interpretation_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  SELECT CASE WHEN s IS NULL THEN NULL ELSE private.reimport_canonical_json_sha256(s) END
    FROM (SELECT private.relation_binding_state(p_interpretation_id) s) x;
$$;
REVOKE ALL ON FUNCTION private.relation_binding_state_sha256(uuid) FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS private.relation_classification_event (
  interpretation_key    uuid NOT NULL,
  seq                   integer NOT NULL CHECK (seq>=1),
  interpretation_id     uuid NOT NULL REFERENCES private.interpretation(id),
  interpretation_version integer NOT NULL CHECK (interpretation_version>=1),
  state_sha256          text NOT NULL CHECK (state_sha256 ~ '^[0-9a-f]{64}$'),
  classification     text NOT NULL CONSTRAINT relation_classification_event_kind_check
                       CHECK (classification IN ('ordinal_afvigelse')),
  evidence           jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object' AND evidence<>'{}'::jsonb),
  created_by         uuid NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (interpretation_key,seq)
);
DO $relation_classification_table$
BEGIN
  DROP TRIGGER IF EXISTS trg_relation_classification_event_append_only ON private.relation_classification_event;
  CREATE TRIGGER trg_relation_classification_event_append_only BEFORE UPDATE OR DELETE ON private.relation_classification_event
    FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
  DROP TRIGGER IF EXISTS trg_relation_classification_event_append_only_truncate ON private.relation_classification_event;
  CREATE TRIGGER trg_relation_classification_event_append_only_truncate BEFORE TRUNCATE ON private.relation_classification_event
    FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation();
  ALTER TABLE private.relation_classification_event ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON TABLE private.relation_classification_event FROM PUBLIC,anon,authenticated;
END $relation_classification_table$;

-- Spec §4.5 (r2-M2): klassifikationen bindes til den gældende version og dens tilstand; en klassifikation
-- er kun gældende, mens begge stadig er de aktuelle.
CREATE OR REPLACE FUNCTION private.append_relation_classification(p_interpretation_id uuid,p_classification text,p_evidence jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_i private.interpretation%ROWTYPE; v_seq integer; v_state text;
BEGIN
  -- Serialisér pr. påstand: lås den (gældende) fortolkningsrække før max(seq)+1.
  SELECT * INTO v_i FROM private.interpretation WHERE id=p_interpretation_id FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM private.interpretation_current c
                               WHERE c.interpretation_key=v_i.interpretation_key AND c.id=v_i.id) THEN
    RAISE EXCEPTION 'RELATION_CLASSIFICATION_NOT_CURRENT';
  END IF;
  v_state:=private.relation_binding_state_sha256(v_i.id);
  IF v_state IS NULL THEN RAISE EXCEPTION 'RELATION_CLASSIFICATION_STRUCTURE_INVALID'; END IF;
  SELECT coalesce(max(seq),0)+1 INTO v_seq FROM private.relation_classification_event WHERE interpretation_key=v_i.interpretation_key;
  INSERT INTO private.relation_classification_event(interpretation_key,seq,interpretation_id,interpretation_version,
    state_sha256,classification,evidence,created_by)
    VALUES (v_i.interpretation_key,v_seq,v_i.id,v_i.version,v_state,p_classification,p_evidence,
            coalesce(auth.uid(),'00000000-0000-0000-0000-000000000000'::uuid));
  RETURN v_seq;
END $$;
REVOKE ALL ON FUNCTION private.append_relation_classification(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS interpretation_promotion_one_family_per_interpretation
  ON private.interpretation_promotion(interpretation_id) WHERE target_type='family';
```
I `schema.sql` skrives tabellen som `CREATE TABLE` (uden `IF NOT EXISTS`) som resten af filen. Tilføj de fire tabelnavne til `db-rls.sql`'s master-array.

- [ ] **Step 5: `db-verify.sql`** — tilføj til 2a-blokken (ny `DO $relation_binding_state_verify$`): tabellen har RLS slået til, `has_table_privilege('anon'|'authenticated', …, 'SELECT')` er falsk, begge append-only-triggere findes, indekset findes og er unikt/partielt, og de tre kontroltabeller fra M4 har RLS. Fejlkode `RELATION_BINDING_STATE_CONTRACT_INVALID`.

- [ ] **Step 6: Kør** — samme kommando som Step 3 + `run-db-verify-disposable.sql` → `OK: bindingens tilstand og klassifikationer`.

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/fixtures/relation-2a.sql tests/sql/test-relation-binding.sql
git commit -m "feat(151): bindingens tilstand, klassifikationer og ét familiemål pr. fortolkning (5b 2a)"
```

---

### Task 3: Maskinel afgørelse af ægteskaber

**Files:** `schema.sql`, `db-migrations.sql` (2a-blok + `$public_red_revoke$`), `db-rls.sql` (allow-liste), `db-verify.sql` (`$public_red_acl_verify$`), `tests/sql/test-relation-binding.sql`

**Interfaces:**
- Consumes: Task 2's funktioner; `public.red_decide_interpretation(uuid,integer,text,jsonb)`; `private.lock_family_rows(bigint[])`.
- Produces:
  - `private.relation_decision_set(p_source_id bigint) RETURNS jsonb` `{items, count, ordinal_deviations, set_sha256}`.
  - `public.red_preview_relation_decisions(p_source_id bigint) RETURNS jsonb` `{count, ordinal_deviations, set_sha256}`.
  - `public.red_decide_relation_interpretations(p_source_id bigint, p_expect_set_sha256 text) RETURNS integer`.
  - Evidens på afgørelsen: `{method:'family-structure-v1', basis:'family_structure', family_id, state_sha256}`.

- [ ] **Step 1: Skriv den fejlende test** — tilføj:

```sql
-- ---------- Task 3: maskinel afgørelse af ægteskaber ----------
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0301'; s jsonb; s2 jsonb; m1 jsonb; m2 jsonb; m3 jsonb; o jsonb; pv jsonb; n int; v_err text; v_state1 text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'2a' FROM generate_series(-2310,-2301) g;
  s:=pg_temp.f5b_source(-2301);
  s2:=pg_temp.f5b_source(-2302);
  m1:=pg_temp.f2a_marriage(-2301,s,'D-1',-2301,-2302,v_actor,1,1);   -- egnet
  m2:=pg_temp.f2a_marriage(-2301,s,'D-2',-2303,-2304,v_actor,2,1);   -- egnet, ordinal-afvigelse
  m3:=pg_temp.f2a_marriage(-2301,s,'D-3',-2305,-2306,v_actor,1,1,false); -- ingen familie
  o:=pg_temp.f2a_marriage(-2302,s2,'D-4',-2307,-2308,v_actor,1,1);   -- anden kilde
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2301);
  RESET ROLE;
  v_state1:=private.relation_binding_state_sha256((m1->'claim'->>'id')::uuid);   -- proposed-versionens tilstand
  SET LOCAL ROLE authenticated;
  IF (pv->>'count')::int<>2 OR (pv->>'ordinal_deviations')::int<>1 OR pv->>'set_sha256' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: preview %', pv->>'count';
  END IF;
  -- anden_kilde: kildens hash kan ikke bruges mod en anden kilde
  BEGIN
    PERFORM red_decide_relation_interpretations(-2302,pv->>'set_sha256');
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anden kilde godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_DECISION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_decide_relation_interpretations(-2301,repeat('0',64));
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: forkert hash godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'RELATION_DECISION_SET_DRIFT%' THEN RAISE; END IF;
  END;
  n:=red_decide_relation_interpretations(-2301,pv->>'set_sha256');
  RESET ROLE;
  IF n<>2
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>'accepted'
     OR (SELECT decision_evidence->>'method' FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>'family-structure-v1'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m3->'claim'->>'key')::uuid)<>'proposed'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(o->'claim'->>'key')::uuid)<>'proposed'
     OR (SELECT count(*) FROM private.relation_classification_event WHERE interpretation_key=(m2->'claim'->>'key')::uuid AND classification='ordinal_afvigelse')<>1
     OR (SELECT count(*) FROM private.relation_classification_event WHERE interpretation_key=(m1->'claim'->>'key')::uuid)<>0 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelser';
  END IF;
  -- afgørelsens state_sha256 er hashen af den forhåndsviste (proposed) tilstand, som previewet autoriserede
  IF (SELECT decision_evidence->>'state_sha256' FROM private.interpretation_current WHERE interpretation_key=(m1->'claim'->>'key')::uuid)
     IS DISTINCT FROM v_state1 THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelsens tilstandshash';
  END IF;
  -- anon/ikke-redaktion afvises
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM red_preview_relation_decisions(-2301);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: anon kunne kalde';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  RAISE NOTICE 'OK: maskinel afgørelse af ægteskaber';
END $relation_decide$;
ROLLBACK;
```

- [ ] **Step 2: Kør og se den fejle** → `function red_preview_relation_decisions(integer) does not exist`.

- [ ] **Step 3: Implementér** (schema.sql sidst + 2a-blokken):

```sql
CREATE OR REPLACE FUNCTION private.relation_decision_set(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_items jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(x.item ORDER BY x.k COLLATE "C"),'[]'::jsonb) INTO v_items
    FROM (SELECT ic.interpretation_key::text AS k,
                 jsonb_build_object('state',st.s,'classification',
                   CASE WHEN (st.s->>'book_ordinal')::int IS DISTINCT FROM (st.s->>'family_ordinal')::int
                        THEN 'ordinal_afvigelse' END) AS item
            FROM private.interpretation_current ic
            CROSS JOIN LATERAL (SELECT private.relation_binding_state(ic.id) AS s) st
           WHERE ic.source_id=p_source_id AND ic.predicate='relation.marriage' AND ic.status='proposed'
             AND st.s IS NOT NULL) x;
  RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items),
    'ordinal_deviations',(SELECT count(*) FROM jsonb_array_elements(v_items) i WHERE i->>'classification' IS NOT NULL),
    'set_sha256',private.reimport_canonical_json_sha256(jsonb_build_object('contract','relation-decision-set-v1',
      'database_identity',jsonb_build_object('database_name',current_database(),
        'system_identifier',(pg_control_system()).system_identifier::text)::text,
      'source_id',p_source_id,'items',v_items)));
END $$;
REVOKE ALL ON FUNCTION private.relation_decision_set(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.red_preview_relation_decisions(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  v:=private.relation_decision_set(p_source_id);
  RETURN v-'items';
END $$;
REVOKE ALL ON FUNCTION public.red_preview_relation_decisions(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_preview_relation_decisions(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.red_decide_relation_interpretations(p_source_id bigint,p_expect_set_sha256 text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_set jsonb; r record; v_new uuid; v_n integer:=0; v_key uuid;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  -- Låseorden (spec §4.3, som red_corroborate_family_identities): eksklusiv kildelås →
  -- fortolkningsrækker (sorteret) → person/familie/medlemmer (lock_family_rows).
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||p_source_id::text,0));
  PERFORM 1 FROM private.interpretation i
   WHERE i.id IN (SELECT ic.id FROM private.interpretation_current ic
                   WHERE ic.source_id=p_source_id AND ic.predicate='relation.marriage' AND ic.status='proposed')
   ORDER BY i.id FOR UPDATE;
  PERFORM private.lock_family_rows(ARRAY(
    SELECT DISTINCT i.canonical_person_id
      FROM private.interpretation_current ic
      JOIN private.interpretation_party_current pc ON pc.interpretation_key=ic.interpretation_key AND pc.party_role IN ('principal','spouse')
      JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
     WHERE ic.source_id=p_source_id AND ic.predicate='relation.marriage' AND ic.status='proposed'
     ORDER BY 1));
  v_set:=private.relation_decision_set(p_source_id);
  IF v_set->>'set_sha256' IS DISTINCT FROM p_expect_set_sha256 THEN RAISE EXCEPTION 'RELATION_DECISION_SET_DRIFT'; END IF;
  FOR r IN SELECT x FROM jsonb_array_elements(v_set->'items') x LOOP
    v_key:=(r.x#>>'{state,interpretation,interpretation_key}')::uuid;
    v_new:=public.red_decide_interpretation((r.x#>>'{state,interpretation,interpretation_id}')::uuid,
      (r.x#>>'{state,interpretation,version}')::integer,'accepted',
      jsonb_build_object('method','family-structure-v1','basis','family_structure',
        'family_id',(r.x#>>'{state,family,family_id}')::bigint,
        'state_sha256',private.reimport_canonical_json_sha256(r.x->'state')));
    IF r.x->>'classification' IS NOT NULL THEN
      PERFORM private.append_relation_classification(v_new,r.x->>'classification',jsonb_build_object(
        'book_ordinal',(r.x#>>'{state,book_ordinal}')::int,'family_ordinal',(r.x#>>'{state,family_ordinal}')::int,
        'family_id',(r.x#>>'{state,family,family_id}')::bigint,'decision_interpretation_id',v_new::text));
    END IF;
    v_n:=v_n+1;
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.red_decide_relation_interpretations(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_decide_relation_interpretations(bigint,text) TO authenticated;
```
Note: afgørelsens `state_sha256` er hashen af den **forhåndsviste** (proposed) tilstand — den bindes til det, previewet autoriserede. Bindingen (Task 4) gemmer den accepterede versions tilstand.

Registrér de to nye `red_*`-navne de fire steder (Global Constraints).

- [ ] **Step 4: To-sessionstest** — tilføj efter `ROLLBACK;`:

```sql
-- To sessioner: en samtidig family_member-indsættelse for en part venter på afgørelsens låse.
INSERT INTO person(id,levende,privat,status) VALUES (-2391,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
CREATE EXTENSION IF NOT EXISTS dblink;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide_lock$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0391'; s jsonb; m jsonb; pv jsonb; v_err text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2392,false,false,'2a');
  s:=pg_temp.f5b_source(-2391);
  m:=pg_temp.f2a_marriage(-2391,s,'L-1',-2391,-2392,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2391);
  PERFORM red_decide_relation_interpretations(-2391,pv->>'set_sha256');
  RESET ROLE;
  BEGIN
    PERFORM dblink_connect('l2a',v_conn);
    PERFORM * FROM dblink('l2a','SET lock_timeout=''300ms''; INSERT INTO family(id,type) VALUES (-2391,''vielse''); '
      ||'INSERT INTO family_member(family_id,person_id,rolle) VALUES (-2391,-2391,''partner''); SELECT ''x''') AS t(x text);
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: indsættelse ventede ikke';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    PERFORM dblink_disconnect('l2a');
    IF v_err NOT LIKE '%lock timeout%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: afgørelsens låse blokerer familieændringer';
END $relation_decide_lock$;
ROLLBACK;
DELETE FROM person WHERE id=-2391;

-- To sessioner, modsat retning (spec §8, Codex plan-r1 #8): en identitetsgenafgørelse er i gang i den anden
-- session — den har taget identitetswriterens personlås (private.lock_family_rows, schema.sql ~8315) på
-- ægtefællen — og afgørelsen må vente/fejle lukket med 0 delvise afgørelser. Ægtefællen committes først,
-- så dblink-sessionen kan låse den (mønster: test-identity-decision.sql:186).
INSERT INTO person(id,levende,privat,status) VALUES (-2394,false,false,'2a lock') ON CONFLICT (id) DO NOTHING;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $relation_decide_lock_identity$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0393'; s jsonb; m jsonb; pv jsonb; v_state text;
  v_conn text:=format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                      split_part(current_setting('unix_socket_directories'),',',1));
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-2393,false,false,'2a');
  s:=pg_temp.f5b_source(-2393);
  m:=pg_temp.f2a_marriage(-2393,s,'L-2',-2393,-2394,v_actor,1,1);
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-2393);
  RESET ROLE;
  PERFORM dblink_connect('l2a_id',v_conn);
  PERFORM dblink_exec('l2a_id','BEGIN');
  PERFORM * FROM dblink('l2a_id','SELECT private.lock_family_rows(ARRAY[-2394]::bigint[])::text') AS t(x text);
  BEGIN
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_decide_relation_interpretations(-2393,pv->>'set_sha256');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    PERFORM dblink_exec('l2a_id','ROLLBACK'); PERFORM dblink_disconnect('l2a_id'); RAISE;
  END;
  PERFORM dblink_exec('l2a_id','ROLLBACK'); PERFORM dblink_disconnect('l2a_id');
  IF v_state IS DISTINCT FROM '55P03'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid)<>'proposed'
     OR EXISTS (SELECT 1 FROM private.relation_classification_event WHERE interpretation_key=(m->'claim'->>'key')::uuid) THEN
    RAISE EXCEPTION 'RELATION_BINDING_TEST_FAILED: afgørelsen ventede ikke på identitetsskrivningen eller efterlod delvise writes (%)', v_state;
  END IF;
  RAISE NOTICE 'OK: afgørelsen venter på en samtidig identitetsgenafgørelse';
END $relation_decide_lock_identity$;
ROLLBACK;
DELETE FROM person WHERE id=-2394;
```

`40P01` (deadlock) fremprovokeres ikke bevidst: en deterministisk deadlock kræver asynkron dblink og to
interleavede låsefølger og bliver flaky. Begge udfald — `55P03` her og `40P01` — afbryder hele
transaktionen ved samme mekanisme, og »0 delvise writes« efter afbruddet er det, testen beviser
(beslutning ved plan-r1-rettelsen; noteres i reviewloggen).

- [ ] **Step 5: Kør** → `OK: maskinel afgørelse af ægteskaber`, `OK: afgørelsens låse …`, `OK: afgørelsen venter …`; kør også `run-db-verify-disposable.sql`.
- [ ] **Step 6: Commit** — `git commit -m "feat(151): maskinel afgørelse af ægteskaber bundet til kilde og tilstand (5b 2a)"` (stage de rørte filer eksplicit).

---

### Task 4: Binding (`structural_family`-promotion)

**Files:** `schema.sql`, `db-migrations.sql` (2a-blok + `$public_red_revoke$`), `db-rls.sql`, `db-verify.sql`, `tests/sql/test-relation-binding.sql`

**Interfaces:**
- Consumes: Task 2-3.
- Produces:
  - `private.preview_relation_promotions(p_source_id bigint, p_items jsonb, p_lock boolean) RETURNS jsonb` `{items:[{item_ordinal, interpretation_id, family_id, eligible, reason_code, rule_key, rule_version, state_sha256, vielse_fact_id}], preview_sha256}`.
  - `public.red_preview_relation_promotions(p_source_id bigint, p_items jsonb) RETURNS jsonb` (samme, `p_lock=false`).
  - `public.red_promote_relation_interpretations_batch(p_source_id bigint, p_items jsonb, p_preview_sha256 text) RETURNS uuid` (batch-id).
  - Promotion-evidens `{promotion_kind:'structural_family', family_id, vielse_fact_id, state_sha256, preview_sha256}`.
  - Kolonnen `private.interpretation_promotion_batch.items_sha256 text` (NULL for assertion-batches) og replay: samme `preview_sha256` + samme item-digest ⇒ samme batch-id; anden digest ⇒ `RELATION_PROMOTION_REPLAY_MISMATCH` (spec §4.4, r2-M4).

- [ ] **Step 1: Skriv den fejlende test** — tilføj en blok `$relation_promote$` der:
  1. opretter et ægteskab (`f2a_marriage`) og afgør det via Task 3, og en forælder (`f2a_parent`);
  2. bygger `items` = `[{interpretation_id: <gældende id>, family_id}]` for begge;
  3. `red_preview_relation_promotions(src, items)` ⇒ begge `eligible`, `preview_sha256` 64 hex;
  4. negativt: et element med forkert `family_id` ⇒ `RELATION_PROMOTION_FAMILY_MISMATCH`; et ikke-gældende id (versionen før afgørelsen) ⇒ `RELATION_PROMOTION_NOT_CURRENT`; en `proposed` påstand ⇒ `RELATION_PROMOTION_NOT_ACCEPTED`; samme element to gange ⇒ `RELATION_PROMOTION_DUPLICATE_ITEM`; anden kilde ⇒ `RELATION_PROMOTION_SOURCE_MISMATCH`; forkert form (`[{"interpretation_id":"x"}]`) ⇒ undtagelsen `RELATION_PROMOTION_ITEMS_INVALID`;
  5. `red_promote_relation_interpretations_batch(src, items, repeat('0',64))` ⇒ `RELATION_PROMOTION_PREVIEW_STALE`;
  6. med rigtig hash ⇒ batch-id; 2 rækker i `interpretation_promotion` med `target_type='family'`, `evidence->>'state_sha256'` = `private.relation_binding_state_sha256(id)`, `evidence ? 'vielse_fact_id'`;
  7. **replay:** samme kald igen (samme elementer, samme previewhash) ⇒ samme batch-id og 0 nye rækker; samme previewhash med et andet element-array ⇒ `RELATION_PROMOTION_REPLAY_MISMATCH`; nyt preview af samme elementer ⇒ hvert element `RELATION_PROMOTION_ALREADY_APPLIED`;
  8. den gamle assertion-batch: `red_preview_interpretation_promotions('[{"interpretation_id":"<ægteskabets id>","target_type":"assertion","target_id":1}]')` ⇒ elementets `reason_code` = `EVIDENCE_PROMOTION_RULE_NOT_ACTIVE`;
  9. en direkte `INSERT` af en anden familiebinding for samme `interpretation_id` som ejer ⇒ `unique_violation`;
  10. **vielsesfaktum i previewet** (Codex plan-r1 #9): et nyt ægteskab uden vielsesfakta → preview (`vielse_fact_id` null) → indsæt som ejer ét `fact(subjekt_type='family', subjekt_id=<familie>, faktatype='vielse')` → batch med den gamle previewhash ⇒ `RELATION_PROMOTION_PREVIEW_STALE`; nyt preview ⇒ `vielse_fact_id` = faktummets id, og bindingens `evidence->>'vielse_fact_id'` er det samme id;
  11. `family_id` med 19 cifre uden for bigint (`9999999999999999999`) ⇒ `RELATION_PROMOTION_ITEMS_INVALID` (ikke en rå castfejl).

Fixture-kaldene efterfølges af `SET CONSTRAINTS ALL IMMEDIATE;` som i Task 2-3.

Skriv blokken i samme stil som Task 3 (`BEGIN … EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS … IF v_err NOT LIKE '<KODE>%' THEN RAISE; END IF; END;`), og slut med `RAISE NOTICE 'OK: binding af relationer';`.

- [ ] **Step 2: Kør og se den fejle** → `function red_preview_relation_promotions(integer, jsonb) does not exist`.

- [ ] **Step 3: Implementér** (først kolonnen: `ALTER TABLE private.interpretation_promotion_batch ADD COLUMN IF NOT EXISTS items_sha256 text CHECK (items_sha256 IS NULL OR items_sha256 ~ '^[0-9a-f]{64}$');` i migrationen og som kolonne i `schema.sql`'s tabel; batch-tabellen er append-only, så kolonnen sættes kun ved indsættelse):

```sql
CREATE OR REPLACE FUNCTION private.preview_relation_promotions(p_source_id bigint,p_items jsonb,p_lock boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_items jsonb;
BEGIN
  IF jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_items) e(item)
        WHERE jsonb_typeof(e.item)<>'object'
           OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(e.item) k)<>ARRAY['family_id','interpretation_id']
           OR jsonb_typeof(e.item->'interpretation_id')<>'string'
           OR e.item->>'interpretation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           OR jsonb_typeof(e.item->'family_id')<>'number' OR e.item->>'family_id' !~ '^-?[0-9]{1,19}$') THEN
    RAISE EXCEPTION 'RELATION_PROMOTION_ITEMS_INVALID';
  END IF;
  -- 19 cifre kan stadig ligge uden for bigint; castet range-checker og giver samme fejlkode.
  BEGIN
    PERFORM (e.item->>'family_id')::bigint FROM jsonb_array_elements(p_items) e(item);
  EXCEPTION WHEN numeric_value_out_of_range THEN RAISE EXCEPTION 'RELATION_PROMOTION_ITEMS_INVALID';
  END;
  IF p_lock THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||p_source_id::text,0));
    PERFORM 1 FROM private.interpretation i
     WHERE i.id IN (SELECT ic.id FROM private.interpretation_current ic
                     JOIN private.interpretation q ON q.interpretation_key=ic.interpretation_key
                    WHERE q.id IN (SELECT (e.item->>'interpretation_id')::uuid FROM jsonb_array_elements(p_items) e(item)))
     ORDER BY i.id FOR UPDATE;
    PERFORM private.lock_family_rows(ARRAY(
      SELECT DISTINCT (pty->>'canonical_person_id')::bigint
        FROM jsonb_array_elements(p_items) e(item)
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(private.relation_binding_state((e.item->>'interpretation_id')::uuid)->'parties','[]'::jsonb)) pty
       WHERE pty->>'canonical_person_id' IS NOT NULL ORDER BY 1));
  END IF;
  WITH parsed AS (
    SELECT ord::integer AS item_ordinal,(e.item->>'interpretation_id')::uuid AS interpretation_id,
           (e.item->>'family_id')::bigint AS family_id,
           count(*) OVER (PARTITION BY (e.item->>'interpretation_id')::uuid) AS dup
      FROM jsonb_array_elements(p_items) WITH ORDINALITY e(item,ord)
  ), checked AS (
    SELECT p.*,q.id AS requested_id,q.source_id,q.predicate,cur.id AS current_id,cur.status,
           r.rule_key,r.rule_version,r.rule_mode,r.status AS rule_status,
           private.relation_binding_state(p.interpretation_id) AS st,
           EXISTS (SELECT 1 FROM private.interpretation_promotion x
                    WHERE x.interpretation_id=p.interpretation_id AND x.target_type='family') AS bound
      FROM parsed p
      LEFT JOIN private.interpretation q ON q.id=p.interpretation_id
      LEFT JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key
      LEFT JOIN private.interpretation_promotion_rule_line l ON l.predicate=q.predicate
      LEFT JOIN private.interpretation_promotion_rule_current r ON r.rule_key=l.rule_key
  ), judged AS (
    SELECT c.*,CASE
      WHEN c.requested_id IS NULL THEN 'RELATION_PROMOTION_NOT_FOUND'
      WHEN c.source_id<>p_source_id THEN 'RELATION_PROMOTION_SOURCE_MISMATCH'
      WHEN c.current_id<>c.interpretation_id THEN 'RELATION_PROMOTION_NOT_CURRENT'
      WHEN c.status<>'accepted' THEN 'RELATION_PROMOTION_NOT_ACCEPTED'
      WHEN c.rule_key IS NULL OR c.rule_mode<>'structural_family' OR c.rule_status<>'active' THEN 'RELATION_PROMOTION_RULE_NOT_ACTIVE'
      WHEN c.st IS NULL THEN 'RELATION_PROMOTION_STRUCTURE_INVALID'
      WHEN (c.st#>>'{family,family_id}')::bigint<>c.family_id THEN 'RELATION_PROMOTION_FAMILY_MISMATCH'
      WHEN c.dup>1 THEN 'RELATION_PROMOTION_DUPLICATE_ITEM'
      WHEN c.bound THEN 'RELATION_PROMOTION_ALREADY_APPLIED'
    END AS reason_code
      FROM checked c
  )
  SELECT jsonb_agg(jsonb_build_object('item_ordinal',j.item_ordinal,'interpretation_id',j.interpretation_id::text,
           'family_id',j.family_id,'eligible',j.reason_code IS NULL,'reason_code',j.reason_code,
           'rule_key',j.rule_key,'rule_version',j.rule_version,
           'state_sha256',CASE WHEN j.st IS NULL THEN NULL ELSE private.reimport_canonical_json_sha256(j.st) END,
           -- Codex plan-r1 #9: vielsesfaktummet er en del af det autoriserede preview; skrivningen bruger
           -- previewets værdi, så det gemte = det hashede. Entydigt ellers null.
           'vielse_fact_id',CASE WHEN j.predicate='relation.marriage' THEN
              (SELECT CASE WHEN count(*)=1 THEN min(f.id) END FROM public.fact f
                WHERE f.subjekt_type='family' AND f.subjekt_id=j.family_id AND f.faktatype='vielse') END)
         ORDER BY j.item_ordinal)
    INTO v_items FROM judged j;
  RETURN jsonb_build_object('items',v_items,'preview_sha256',private.reimport_canonical_json_sha256(jsonb_build_object(
    'contract','relation-promotion-preview-v1',
    'database_identity',jsonb_build_object('database_name',current_database(),
      'system_identifier',(pg_control_system()).system_identifier::text)::text,
    'source_id',p_source_id,'items',v_items)));
END $$;
REVOKE ALL ON FUNCTION private.preview_relation_promotions(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.red_preview_relation_promotions(p_source_id bigint,p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  RETURN private.preview_relation_promotions(p_source_id,p_items,false);
END $$;
REVOKE ALL ON FUNCTION public.red_preview_relation_promotions(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_preview_relation_promotions(bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.red_promote_relation_interpretations_batch(p_source_id bigint,p_items jsonb,p_preview_sha256 text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_actor_name text; v_preview jsonb; v_reason text; v_profile jsonb; v_batch uuid;
  v_items_sha text; v_old_items text;
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text) INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL OR coalesce(p_preview_sha256,'') !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'RELATION_PROMOTION_INVALID'; END IF;
  -- Replay (spec §4.4): kildelåsen først, så et samtidigt kald ser den committede batch.
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||p_source_id::text,0));
  v_items_sha:=private.reimport_canonical_json_sha256(p_items);
  SELECT id,items_sha256 INTO v_batch,v_old_items FROM private.interpretation_promotion_batch
   WHERE preview_hash=p_preview_sha256 AND items_sha256 IS NOT NULL;
  IF v_batch IS NOT NULL THEN
    IF v_old_items IS DISTINCT FROM v_items_sha THEN RAISE EXCEPTION 'RELATION_PROMOTION_REPLAY_MISMATCH'; END IF;
    RETURN v_batch;
  END IF;
  v_preview:=private.preview_relation_promotions(p_source_id,p_items,true);
  IF v_preview->>'preview_sha256'<>p_preview_sha256 THEN RAISE EXCEPTION 'RELATION_PROMOTION_PREVIEW_STALE'; END IF;
  SELECT i->>'reason_code' INTO v_reason FROM jsonb_array_elements(v_preview->'items') i
   WHERE NOT (i->>'eligible')::boolean ORDER BY (i->>'item_ordinal')::int LIMIT 1;
  IF v_reason IS NOT NULL THEN RAISE EXCEPTION '%',v_reason; END IF;
  -- Samme profilform som den eksisterende promotion-writer (schema.sql ~9098): ét par pr. element,
  -- sorteret efter regel og version (Codex plan-r1 #10).
  SELECT coalesce(jsonb_agg(jsonb_build_object('rule_key',i->>'rule_key','rule_version',(i->>'rule_version')::int)
           ORDER BY i->>'rule_key',(i->>'rule_version')::int),'[]'::jsonb)
    INTO v_profile FROM jsonb_array_elements(v_preview->'items') i;
  INSERT INTO private.interpretation_promotion_batch(rule_profile_hash,preview_hash,promoted_by,promoted_by_name,requested_count,items_sha256)
  VALUES (private.reimport_canonical_json_sha256(jsonb_build_object('contract','relation-promotion-profile-v1',
            'preview_hash',p_preview_sha256,'rule_profile',v_profile)),
          p_preview_sha256,v_actor,v_actor_name,jsonb_array_length(v_preview->'items'),v_items_sha)
  RETURNING id INTO v_batch;
  INSERT INTO private.interpretation_promotion(interpretation_id,rule_key,rule_version,batch_id,target_type,target_id,evidence,
    promoted_by,promoted_by_name)
  SELECT (i->>'interpretation_id')::uuid,i->>'rule_key',(i->>'rule_version')::int,v_batch,'family',(i->>'family_id')::bigint,
         jsonb_build_object('promotion_kind','structural_family','family_id',(i->>'family_id')::bigint,
           'vielse_fact_id',(i->>'vielse_fact_id')::bigint,
           'state_sha256',i->>'state_sha256','preview_sha256',p_preview_sha256),
         v_actor,v_actor_name
    FROM jsonb_array_elements(v_preview->'items') i;
  RETURN v_batch;
END $$;
REVOKE ALL ON FUNCTION public.red_promote_relation_interpretations_batch(bigint,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_promote_relation_interpretations_batch(bigint,jsonb,text) TO authenticated;
```
Registrér de to nye `red_*`-navne de fire steder.

- [ ] **Step 4: To-sessionstests** (Codex plan-r1 #8; mønster som Task 3 Step 4, med de involverede personer committet før `BEGIN` og slettet efter `ROLLBACK`):
  - **(a) family_member-write venter på bindingen:** hovedsessionen har kørt `red_promote_relation_interpretations_batch` (ikke committet); dblink-sessionen forsøger `INSERT INTO family_member(...)` for en committet part med `lock_timeout=300ms` ⇒ `lock timeout`.
  - **(b) konkurrerende promotion:** dblink-sessionen holder kildelåsen (`BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:<kilde>',0))`) som en anden batch gør; hovedsessionen kalder `red_promote_relation_interpretations_batch` med `SET LOCAL lock_timeout='300ms'` i en indre blok ⇒ SQLSTATE `55P03`; derefter 0 rækker i `interpretation_promotion` med `target_type='family'` for elementerne og 0 nye `interpretation_promotion_batch` med previewhashen.
  - **(c) identitetsgenafgørelse:** dblink-sessionen holder `private.lock_family_rows(ARRAY[<committet part>])`; hovedsessionen kalder batchen ⇒ `55P03` og 0 bindinger/batches.
  Slut med `RAISE NOTICE 'OK: bindingens låse'`. (40P01 provokeres ikke; se Task 3 Step 4.)
- [ ] **Step 4b: `db-verify.sql`** (Codex plan-r1 #16) — ny blok `$relation_promotion_verify$`: kolonnen `private.interpretation_promotion_batch.items_sha256` findes, er `text`, nullable og har en CHECK med `^[0-9a-f]{64}$`; `to_regprocedure` findes for `private.preview_relation_promotions(bigint,jsonb,boolean)`, `public.red_preview_relation_promotions(bigint,jsonb)` og `public.red_promote_relation_interpretations_batch(bigint,jsonb,text)`; de to `public`-funktioner er `prosecdef`, `authenticated` har EXECUTE og `anon` har ikke; den private har ingen EXECUTE for `anon`/`authenticated`. Fejlkode `RELATION_PROMOTION_CONTRACT_INVALID`.
- [ ] **Step 5: Kør** → `OK: binding af relationer`; `run-db-verify-disposable.sql` grøn.
- [ ] **Step 6: Commit** — `feat(151): strukturel binding af afgjorte relationer til familien (5b 2a)`.

---

### Task 5: Offentlig læsefunktion `public_family_sources`

**Files:** `schema.sql`, `db-migrations.sql` (2a-blok), `db-rls.sql` (~1192: REVOKE/GRANT-blokken for offentlige læsefunktioner), `db-verify.sql`, Create `tests/sql/test-family-sources.sql`, `.github/workflows/ci.yml` (job `writer-1939-v50-db`, efter `test-family-corroboration.sql`)

**Interfaces:**
- Consumes: Task 2-4; `public.person_daa_narrative_publication_allowed(bigint)`, `public.family_offentlig(bigint)`, `private.narrative_publication_event`.
- Produces: `public.public_family_sources(p_family_ids bigint[]) RETURNS TABLE(family_id bigint, slags text, counterpart_person_id bigint, source_record_ref uuid, source_label text, record_label text, citation_label text)`.

- [ ] **Step 1: Skriv den fejlende test** — `tests/sql/test-family-sources.sql`. Struktur (Codex plan-r1 #6): én frisk, bundet og publiceret fixture pr. negativ gate; hver case assertér først, at rækken **er synlig**, foretager præcis én gyldig ændring gennem den rigtige writer (eller som ejer, hvor ingen writer findes), og assertér derefter 0 rækker. Så kan én gate ikke skjule en anden.

```sql
-- Trin 5b 2a, Task 5: public_family_sources (kontrakt 2). Kører i writer-1939-v50-db.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Ét bundet og publiceret ægteskab i egen kilde p_base: personer p_base (hovedperson) og p_base-1 (ægtefælle).
CREATE OR REPLACE FUNCTION pg_temp.f2a_bound(p_base bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; m jsonb; pv jsonb; items jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'2a'),(p_base-1,false,false,'2a');
  s:=pg_temp.f5b_source(p_base);
  m:=pg_temp.f2a_marriage(p_base,s,'B'||p_base,p_base,p_base-1,p_actor,1,1);
  PERFORM pg_temp.f2a_publish(p_base,s,m->'post',p_base,p_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_base);
  PERFORM red_decide_relation_interpretations(p_base,pv->>'set_sha256');
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',(m->>'family')::bigint)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_base,items);
  PERFORM red_promote_relation_interpretations_batch(p_base,items,pv->>'preview_sha256');
  RESET ROLE;
  RETURN m||jsonb_build_object('source',s);
END $$;

-- Antal synlige rækker for familien som anon.
CREATE OR REPLACE FUNCTION pg_temp.f2a_visible(p_fam bigint) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[p_fam]);
  RESET ROLE;
  RETURN n;
END $$;

DO $family_sources$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002a0501'; m jsonb; par jsonb; pv jsonb; items jsonb; n int; r record;
  v_fam bigint; v_pfam bigint; v_par2 jsonb; v_v2 uuid; v_sha text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);

  -- (1) lykkelig sti: ægteskab + forælder
  m:=pg_temp.f2a_bound(-2502,v_actor);
  v_fam:=(m->>'family')::bigint;
  INSERT INTO person(id,levende,privat,status) VALUES (-2506,false,false,'2a'),(-2507,false,false,'2a'),(-2508,false,false,'2a');
  par:=pg_temp.f2a_parent(-2502,m->'source',-2506,-2507,-2508,v_actor);
  PERFORM pg_temp.f2a_publish(-2502,m->'source',par->'child_post',-2506,v_actor,'Barn Alfa. søn af Far.');
  v_pfam:=(par->>'family')::bigint;
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',v_pfam)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(par->'claim'->>'key')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-2502,items);
  PERFORM red_promote_relation_interpretations_batch(-2502,items,pv->>'preview_sha256');
  RESET ROLE;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[v_fam,v_pfam]);
  IF n<>2 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: % rækker', n; END IF;
  SELECT * INTO r FROM public.public_family_sources(ARRAY[v_fam]);
  -- r2-M1: fødselsfamilien har to forældre (-2507, -2508), men kun påstanden om -2507 er bundet ⇒ præcis én række
  IF r.slags<>'aegteskab' OR r.source_record_ref IS DISTINCT FROM (SELECT public_ref FROM private.source_record WHERE id=(m->'post'->>'record')::uuid)
     OR nullif(r.record_label,'') IS NULL OR nullif(r.source_label,'') IS NULL OR r.counterpart_person_id<>-2503
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[v_pfam]))<>1
     OR (SELECT slags FROM public.public_family_sources(ARRAY[v_pfam]))<>'foraelder'
     OR (SELECT counterpart_person_id FROM public.public_family_sources(ARRAY[v_pfam]))<>-2507 THEN
    RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: lykkelig sti';
  END IF;
  RESET ROLE;

  -- (2) kontrakt 1 (Codex plan-r1 #13): samme gyldige binding, kontrakten midlertidigt 1 ⇒ 0 rækker
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 1 $c$;
  IF pg_temp.f2a_visible(v_fam)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: kontrakt 1'; END IF;
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 2 $c$;
  IF pg_temp.f2a_visible(v_fam)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: kontrakt 2 tilbage'; END IF;

  -- (3) levende barn i familien
  m:=pg_temp.f2a_bound(-2512,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (3) ikke synlig før'; END IF;
  INSERT INTO person(id,levende,privat,status) VALUES (-2519,true,false,'2a');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES ((m->>'family')::bigint,-2519,'barn');
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: levende barn'; END IF;

  -- (4) staged ægtefælle
  m:=pg_temp.f2a_bound(-2522,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (4) ikke synlig før'; END IF;
  UPDATE person SET staged=true WHERE id=-2523;   -- ægtefællen = p_base-1
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: staged'; END IF;

  -- (5) ny identitetsversion gennem identitetswriteren (samme person, version 2)
  m:=pg_temp.f2a_bound(-2532,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (5) ikke synlig før'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM private.decide_source_persona_identity((m->>'spouse_persona')::uuid,-2533,1,'accepted',
    '{"basis":"web_detail","note":"2a ny version"}','human');
  SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: ny identitetsversion'; END IF;

  -- (6) upubliceret post (tilbagetrukket gennem redaktions-RPC'en)
  m:=pg_temp.f2a_bound(-2542,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (6) ikke synlig før'; END IF;
  v_sha:=private.narrative_record_state(-2542,-2542,m->'post'->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_tilbagetraek_person_narrative_record(-2542,-2542,m->'post'->>'key',v_sha);
  RESET ROLE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: upubliceret'; END IF;

  -- (7) afvist påstand: ingen writer laver en ny version af en accepteret påstand i dag, så den skrives som ejer
  -- (version 2, samme nøgle, med sin supporting-observation); afviser triggerne en direkte 'rejected'-version,
  -- skrives version 2 som 'proposed' og afgøres 'rejected' gennem red_decide_interpretation.
  m:=pg_temp.f2a_bound(-2552,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (7) ikke synlig før'; END IF;
  v_v2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
    value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT v_v2,ic.interpretation_key,ic.version+1,ic.source_id,ic.source_persona_id,ic.interpretation_kind,ic.predicate,
         ic.value,ic.schema_version,ic.derivation_kind,ic.confidence,'proposed',ic.method,ic.extraction_run_id
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT v_v2,io.observation_id,io.evidence_role,io.ordinal FROM private.interpretation_observation io
     WHERE io.interpretation_id=(m->'claim'->>'id')::uuid;
  SET LOCAL ROLE authenticated;
  PERFORM red_decide_interpretation(v_v2,(SELECT version FROM private.interpretation WHERE id=v_v2),'rejected','{"note":"2a afvist"}');
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: afvist påstand'; END IF;

  -- (8) to supporting-observationer på den bundne version ⇒ 0 (r2-M6)
  m:=pg_temp.f2a_bound(-2562,v_actor); SET CONSTRAINTS ALL IMMEDIATE;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>1 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: (8) ikke synlig før'; END IF;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT ic.id,(m->'post'->'clauses'->>0)::uuid,'supporting',2
      FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  IF pg_temp.f2a_visible((m->>'family')::bigint)<>0 THEN RAISE EXCEPTION 'FAMILY_SOURCES_TEST_FAILED: to observationer'; END IF;

  RAISE NOTICE 'OK: public_family_sources og gaten';
END $family_sources$;
ROLLBACK;
```
Empiriske justeringer, der er tilladt uden ny plan: hvis `red_decide_interpretation`'s første parameter er den **gældende** id (ikke versionsnummer), eller dens evidens kræver andre felter, så tilpas kaldet i (7) til dens signatur (`schema.sql` ~8150); hvis `interpretation_observation` er append-only med en trigger, der afviser en anden supporting-række til en eksisterende fortolkning, så lav (8) med en ny fortolkningsversion med to observationer. Ingen af casene må fjernes; noteres i ledgeren.

- [ ] **Step 2: Kør og se den fejle** — `fresh_v2 ci5b_2a_v2 && psql -X -q -d ci5b_2a_v2 -f tests/sql/test-family-sources.sql` → `function public.public_family_sources(bigint[]) does not exist`.

- [ ] **Step 3: Implementér**:

```sql
CREATE OR REPLACE FUNCTION public.public_family_sources(p_family_ids bigint[])
RETURNS TABLE(family_id bigint, slags text, counterpart_person_id bigint, source_record_ref uuid, source_label text, record_label text, citation_label text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF public.narrative_record_contract_version()<2 OR p_family_ids IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH b AS (
    SELECT p.target_id AS fam,p.interpretation_id,p.evidence->>'state_sha256' AS bound_sha,
           cur.predicate,cur.source_id,private.relation_binding_state(p.interpretation_id) AS st
      FROM private.interpretation_promotion p
      JOIN private.interpretation_promotion_rule r
        ON r.rule_key=p.rule_key AND r.rule_version=p.rule_version AND r.rule_mode='structural_family'
      JOIN private.interpretation q ON q.id=p.interpretation_id
      JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key
     WHERE p.target_type='family' AND p.target_id=ANY(p_family_ids)
       AND cur.id=p.interpretation_id AND cur.status='accepted'
  ), ok AS (
    SELECT b.* FROM b
     WHERE b.st IS NOT NULL
       AND private.reimport_canonical_json_sha256(b.st)=b.bound_sha
       AND (b.st#>>'{family,family_id}')::bigint=b.fam
       AND public.family_offentlig(b.fam)
  ), rec AS (
    -- Spec §5.1 trin 3 (r2-M6): præcis én supporting-observation og præcis én accepteret anchor.
    SELECT ok.*,
           (SELECT array_agg(a.source_record_id)
              FROM private.interpretation_observation io
              JOIN private.source_observation o ON o.id=io.observation_id
              JOIN private.source_record_anchor_current a ON a.occurrence_id=o.occurrence_id AND a.decision_status='accepted'
             WHERE io.interpretation_id=ok.interpretation_id AND io.evidence_role='supporting') AS recs,
           (SELECT count(*) FROM private.interpretation_observation io
             WHERE io.interpretation_id=ok.interpretation_id AND io.evidence_role='supporting') AS n_support
      FROM ok
  ), pub AS (
    SELECT rec.fam,rec.predicate,rec.st,sr.public_ref,nrp.id AS binding_id,nrp.narrative_id
      FROM rec
      JOIN private.source_record sr ON sr.id=rec.recs[1] AND sr.source_id=rec.source_id
      JOIN private.narrative_record_publication nrp ON nrp.source_record_id=sr.id AND nrp.status='published'
     WHERE rec.n_support=1 AND cardinality(rec.recs)=1
       AND (SELECT count(*) FROM private.narrative_record_publication x
             WHERE x.source_record_id=sr.id AND x.status='published')=1
  )
  SELECT pub.fam,CASE pub.predicate WHEN 'relation.marriage' THEN 'aegteskab' ELSE 'foraelder' END,
         (pub.st->>'counterpart_person_id')::bigint,pub.public_ref,
         ev.after_state #>> '{source,source_label}',ev.after_state #>> '{labels,record_label}',
         ev.after_state #>> '{labels,citation_label}'
    FROM pub
    JOIN public.narrative n ON n.id=pub.narrative_id
    JOIN LATERAL (SELECT e.after_state FROM private.narrative_publication_event e
                   WHERE e.binding_id=pub.binding_id ORDER BY e.stream_version DESC,e.id DESC LIMIT 1) ev ON true
   WHERE public.person_daa_narrative_publication_allowed(n.id)
     AND n.subjekt_type='person'
     AND n.subjekt_id IN (SELECT (x->>'canonical_person_id')::bigint FROM jsonb_array_elements(pub.st->'parties') x)
   ORDER BY 1,2,3;
END $$;
REVOKE ALL ON FUNCTION public.public_family_sources(bigint[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.public_family_sources(bigint[]) TO anon,authenticated;
```
Tilføj den til `db-rls.sql`'s REVOKE/GRANT-blok for offentlige læsefunktioner (~1192). `db-verify.sql`: ny blok `$family_sources_verify$` — `prosecdef`, `proconfig = {search_path=pg_catalog}`, `pg_get_function_result` = `TABLE(family_id bigint, slags text, counterpart_person_id bigint, source_record_ref uuid, source_label text, record_label text, citation_label text)`, definitionen indeholder `person_daa_narrative_publication_allowed`, `family_offentlig`, `relation_binding_state` og `narrative_record_contract_version()`, `anon`/`authenticated` har EXECUTE, `PUBLIC` har ikke.

- [ ] **Step 4: Kør** → `OK: public_family_sources og gaten`; kør også `test-relation-binding.sql` og `run-db-verify-disposable.sql` i v2-basen.
- [ ] **Step 5: CI** — job `writer-1939-v50-db`, nyt trin efter »Family corroboration SQL (5b)«:

```yaml
      - name: Familiekilder SQL (5b 2a)
        env: {PGPASSWORD: postgres}
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-family-sources.sql
```
- [ ] **Step 6: Commit** — `feat(151): offentlig kildevisning for bundne familier bag publicerings- og familiegaten (5b 2a)`.

---

### Task 6: Kerne — familie-id'er og kildelinje (`packages/core`)

**Files:** Create `packages/core/src/familieKilder.ts`, `packages/core/src/__tests__/familieKilder.test.ts`; Modify `packages/core/src/index.ts` (eksport).

**Interfaces:**
- Consumes: `ModelIndexes` (`unionById`, `childrenByUnion`, `parentsByChild`) fra `packages/core/src/types.ts`.
- Produces:
  ```ts
  export type FamilieKilde = { familyId: string; slags: 'aegteskab' | 'foraelder'; counterpartPersonId: string;
    sourceRecordRef: string | null; sourceLabel: string; recordLabel: string; citationLabel: string };
  export function familieIderForPerson(indexes: ModelIndexes, focusId: string): { aegteskaber: { spouseId: string | null; familyId: string }[]; foraeldreFamilie: string | null };
  export function kildeLinje(k: FamilieKilde): string;   // 'Kilde: ‹sourceLabel› · ‹recordLabel›'
  export function mapFamilieKilder(rows: unknown): FamilieKilde[];   // ugyldige rækker droppes
  ```

- [ ] **Step 1: Skriv de fejlende tests**

```ts
import { describe, expect, it } from 'vitest';
import { buildModel } from '../buildModel';
import { familieIderForPerson, kildeLinje, mapFamilieKilder } from '../familieKilder';

const persons = ['1', '2', '3', '4'].map((id) => ({ id, name: `P${id}` })) as never[];

describe('familieIderForPerson', () => {
  it('giver familie-id pr. ægteskab og fødselsfamilien', () => {
    const m = buildModel(persons, [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
    ] as never, [{ child: '3', parent: '1', union: 'f10' }, { child: '3', parent: '2', union: 'f10' }] as never);
    expect(familieIderForPerson(m.indexes, '1').aegteskaber).toEqual([{ spouseId: '2', familyId: '10' }]);
    expect(familieIderForPerson(m.indexes, '3').foraeldreFamilie).toBe('10');
    expect(familieIderForPerson(m.indexes, '4')).toEqual({ aegteskaber: [], foraeldreFamilie: null });
  });
  it('to_familier_samme_par: hver familie for sig', () => {
    const m = buildModel(persons, [
      { id: 'f10', p1: '1', p2: '2', p2_name: null, year: null },
      { id: 'f11', p1: '1', p2: '2', p2_name: null, year: null },
    ] as never, [] as never);
    expect(familieIderForPerson(m.indexes, '2').aegteskaber.map((a) => a.familyId).sort()).toEqual(['10', '11']);
  });
});

describe('kildeLinje og mapFamilieKilder', () => {
  it('former linjen og dropper ugyldige rækker', () => {
    const rows = mapFamilieKilder([
      { family_id: 10, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: 'r', source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' },
      { family_id: 11, slags: 'noget', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 2', citation_label: 'c' },
      { family_id: '9007199254740993', slags: 'foraelder', counterpart_person_id: '9007199254740995', source_record_ref: null, source_label: 'DAA X', record_label: 'Post 3', citation_label: 'c' },
      // Et tal over 2^53 kan allerede have mistet præcision i JSON.parse ⇒ droppes (fail closed).
      { family_id: 9007199254740993, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 4', citation_label: 'c' },
      { family_id: '10x', slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: null, source_label: 'DAA X', record_label: 'Post 5', citation_label: 'c' },
      null,
    ]);
    expect(rows).toHaveLength(2);
    expect(rows[1].familyId).toBe('9007199254740993');   // strenge bevares; aldrig Number()
    expect(rows[1].counterpartPersonId).toBe('9007199254740995');
    expect(kildeLinje(rows[0])).toBe('Kilde: DAA X · Post 1');
  });
});
```
Tilpas `buildModel`-kaldets argumenter til den faktiske signatur i `packages/core/src/buildModel.ts` (læs den først; testen skal bruge den rigtige form).

- [ ] **Step 2: Kør og se den fejle** — `env -u NODE_OPTIONS npm run test -w @daa/core -- familieKilder` → FAIL (modul findes ikke).

- [ ] **Step 3: Implementér** `packages/core/src/familieKilder.ts`:

```ts
// Trin 5b 2a: kilder på ægteskab og forældrelinje (spec §5.2). Familie-id'et udledes af modellens
// unions ('f' + family_id) — spousesBy bærer det ikke, og to ægteskaber med samme par er to familier.
import type { ModelIndexes } from './types';

export type FamilieKilde = {
  familyId: string; slags: 'aegteskab' | 'foraelder'; counterpartPersonId: string; sourceRecordRef: string | null;
  sourceLabel: string; recordLabel: string; citationLabel: string;
};

const famId = (unionId: string): string | null => (unionId.startsWith('f') ? unionId.slice(1) : null);

export function familieIderForPerson(indexes: ModelIndexes, focusId: string) {
  const aegteskaber: { spouseId: string | null; familyId: string }[] = [];
  for (const u of Object.values(indexes.unionById)) {
    const id = famId(u.id);
    if (!id) continue;
    if (u.p1 === focusId) aegteskaber.push({ spouseId: u.p2 ?? null, familyId: id });
    else if (u.p2 === focusId) aegteskaber.push({ spouseId: u.p1, familyId: id });
  }
  let foraeldreFamilie: string | null = null;
  const forælder = indexes.parentsByChild[focusId]?.[0];
  if (forælder) {
    for (const [unionKey, børn] of Object.entries(indexes.childrenByUnion[forælder] ?? {})) {
      if (børn.includes(focusId)) { foraeldreFamilie = famId(unionKey); break; }
    }
  }
  return { aegteskaber, foraeldreFamilie };
}

export function kildeLinje(k: FamilieKilde): string {
  return `Kilde: ${k.sourceLabel} · ${k.recordLabel}`;
}

// Id'er er decimalstrenge (modellens konvention, jf. web/src/data/model.ts' number | string). PostgREST
// serialiserer bigint som JSON-tal; et tal godtages kun som sikkert heltal (ellers kan JSON.parse allerede
// have afrundet det), en streng kun som decimal. Aldrig Number() på en streng (spec §5.2; Codex plan-r1 #11).
function idTekst(v: unknown): string | null {
  if (typeof v === 'string') return /^-?\d{1,19}$/.test(v) ? v : null;
  if (typeof v === 'number') return Number.isSafeInteger(v) ? String(v) : null;
  return null;
}

export function mapFamilieKilder(rows: unknown): FamilieKilde[] {
  if (!Array.isArray(rows)) return [];
  const ud: FamilieKilde[] = [];
  for (const r of rows as Record<string, unknown>[]) {
    if (!r || (r.slags !== 'aegteskab' && r.slags !== 'foraelder')) continue;
    if (typeof r.source_label !== 'string' || typeof r.record_label !== 'string') continue;
    const familyId = idTekst(r.family_id);
    const counterpartPersonId = idTekst(r.counterpart_person_id);
    if (!familyId || !counterpartPersonId) continue;
    ud.push({
      familyId, slags: r.slags, counterpartPersonId,
      sourceRecordRef: typeof r.source_record_ref === 'string' ? r.source_record_ref : null,
      sourceLabel: r.source_label, recordLabel: r.record_label, citationLabel: typeof r.citation_label === 'string' ? r.citation_label : '',
    });
  }
  return ud;
}
```
Eksportér fra `packages/core/src/index.ts`.

- [ ] **Step 4: Kør** — `env -u NODE_OPTIONS npm run test -w @daa/core` → grøn; `npx tsc --noEmit -p packages/core` grøn.
- [ ] **Step 5: Commit** — `feat(151): familie-id'er og kildelinje i kernen (5b 2a)`.

---

### Task 7: Web — hent og vis kilden

**Files:** Create `web/src/data/familySources.ts`, `web/src/data/__tests__/familySources.test.ts`, `web/src/components/__tests__/DetailPanel.familieKilder.test.tsx`, `web/e2e/family-sources.spec.ts`; Modify `web/src/components/DetailPanel.tsx`.

**Interfaces:**
- Consumes: Task 6; `PersonDetailData.bioVersions[].recordRef` (v2: `source_record_ref`).
- Produces: `fetchFamilySources(familyIds: string[]): Promise<FamilieKilde[]>`.

- [ ] **Step 1: Fejlende datatest** (`familySources.test.ts`, mønster fra `feedAux.test.ts`):

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';
let rpc = vi.fn();
vi.mock('../../supabase', () => ({ supabase: { rpc: (n: string, a: unknown) => rpc(n, a) } }));
const { fetchFamilySources } = await import('../familySources');
beforeEach(() => { rpc = vi.fn(); });

describe('fetchFamilySources', () => {
  it('kalder RPC med numeriske id'er og former rækkerne', async () => {
    rpc.mockResolvedValueOnce({ data: [{ family_id: 10, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: 'r', source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' }], error: null });
    const ud = await fetchFamilySources(['10', 'x', '10']);
    expect(rpc).toHaveBeenCalledWith('public_family_sources', { p_family_ids: ['10'] });
    expect(ud[0].recordLabel).toBe('Post 1');
  });
  it('rpc_fejl_giver_tom', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Could not find the function' } });
    expect(await fetchFamilySources(['10'])).toEqual([]);
    rpc.mockRejectedValueOnce(new Error('net'));
    expect(await fetchFamilySources(['10'])).toEqual([]);
  });
  it('ingen id'er ⇒ intet kald', async () => {
    expect(await fetchFamilySources([])).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Kør og se den fejle** — `env -u NODE_OPTIONS VITE_SUPABASE_URL=http://x VITE_SUPABASE_ANON_KEY=x npm run test -w web -- familySources`.

- [ ] **Step 3: Implementér** `web/src/data/familySources.ts`:

```ts
// Trin 5b 2a: kilder på ægteskab/forældrelinje. Fejl (fx funktionen findes ikke endnu i prod) giver
// en tom liste — panelet må aldrig brydes af en manglende kildelinje (spec §5.2).
import { mapFamilieKilder, type FamilieKilde } from '@daa/core';
import { supabase } from '../supabase';

export async function fetchFamilySources(familyIds: string[]): Promise<FamilieKilde[]> {
  // Decimalstrenge hele vejen; PostgREST caster dem til bigint[] (spec §5.2, r2-m1).
  const ids = [...new Set(familyIds.filter((id) => /^-?\d{1,19}$/.test(id)))];
  if (!ids.length) return [];
  try {
    const client = supabase as unknown as { rpc: (n: string, a: unknown) => Promise<{ data: unknown; error: unknown }> };
    const res = await client.rpc('public_family_sources', { p_family_ids: ids });
    return res.error ? [] : mapFamilieKilder(res.data);
  } catch {
    return [];
  }
}
```

- [ ] **Step 4: Fejlende komponenttest** (`DetailPanel.familieKilder.test.tsx`): mock `../../data/familySources` til at returnere en ægteskabskilde for familie `10` og en forælderkilde for familie `20`; render `DetailPanel` med en model (person 1 gift med 2 i `f10`, barn af 5+6 i `f20`) og `detail.bioVersions` med `recordRef: 'r1'`. Forvent:
  - teksten `Kilde: DAA X · Post 1` under »gift med« og `Kilde: DAA X · Post 2` ved forælder 5 (`counterpartPersonId: '5'`), men **ikke** ved forælder 6;
  - ægteskabskilden med `sourceRecordRef: 'r1'` er en knap (rolle `button`), og klik vælger versionen (versionsvælgerens aktive element skifter);
  - forælderkilden med `sourceRecordRef: 'r9'` (ikke i `bioVersions`) er ren tekst (ingen `button`);
  - uden kilder vises ingen `Kilde:`-tekst.
  Byg modellen med `buildModel` som i Task 6, og læs eksisterende komponenttests (fx `KildepersonaKo.test.tsx`) for render-hjælperen.

- [ ] **Step 5: Implementér i `DetailPanel.tsx`**:
  - `import { familieIderForPerson, kildeLinje, type FamilieKilde } from '@daa/core';` og `import { fetchFamilySources } from '../data/familySources';`
  - Før den betingede `return null` (Rules of Hooks): `const [familieKilder, setFamilieKilder] = useState<FamilieKilde[]>([]);` og en `useEffect` på `[focusId, model]`, der beregner `familieIderForPerson(model.indexes, focusId)`, kalder `fetchFamilySources([...aegteskaber.map((a) => a.familyId), foraeldreFamilie].filter((id): id is string => id !== null))` (type guard — `filter(Boolean)` snævrer ikke `string | null` ind under `strict`; Codex plan-r1 #3) og sætter state (med en `aktiv`-flag, så et svar for en tidligere person ignoreres).
  - En lille komponent `KildeLinjeVisning({ kilde, versions, onVælg })`: findes `versions.findIndex(v => v.recordRef === kilde.sourceRecordRef)` ≥ 0, rendres en `<button type="button">` med `kildeLinje(kilde)`, der kalder `setBioVersionIdx(idx)`; ellers en `<span>`. Stil: `fontFamily: T.sans, fontSize: 11.5, color: T.muted2`.
  - Under hver ægtefælle i »gift med«: kilder med `slags==='aegteskab'`, `familyId` i den ægtefælles familie-id'er og `counterpartPersonId` = ægtefællen eller den viste person. Under »Barn af«: ved hver forælder `pa` kun kilden med `slags==='foraelder'`, `familyId===foraeldreFamilie` og `counterpartPersonId===pa.id` — aldrig samme kilde ved begge forældre (spec §5.2, r2-M1).

- [ ] **Step 6: Kør** — web-vitest grøn; `env -u NODE_OPTIONS npx tsc --noEmit -p web` grøn.

- [ ] **Step 7: Playwright** — `web/e2e/family-sources.spec.ts` med **én** hermetisk catch-all `page.route('**/rest/v1/**', …)` som i `web/e2e/feed.spec.ts:9` (Codex plan-r1 #12):
  - stien efter `/rest/v1/` dispatches: `rpc/narrative_record_contract_version` ⇒ `2`; `rpc/public_person_bio_source_versions_v2` ⇒ læs `route.request().postDataJSON().p_person_ids` og returnér versionen med `source_record_ref: 'r1'` **kun** hvis listen indeholder `1` (ellers `[]`); `rpc/public_family_sources` ⇒ én `aegteskab`-række for den familie, hvor person 1 og 2 er partnere i `TABLE_FIXTURES`, med `source_record_ref: 'r1'`; øvrige `rpc/*` ⇒ `[]`; tabeller ⇒ `TABLE_FIXTURES[tabel] ?? []`. Catch-all'en betyder, at intet PostgREST-kald kan nå nettet. Kroppen af hvert `public_family_sources`-kald gemmes i et array.
  - Gå til `/person/1`: teksten `Kilde: DAA 2012-14 · Post 1` er en `button`. Gå til `/person/2`: samme tekst findes og er **ikke** en `button` (person 2 har ingen bio-version med `r1`).
  - Til sidst: mindst ét `public_family_sources`-kald er registreret, og alle dets `p_family_ids` er decimalstrenge (`typeof === 'string'`) — decimalstrengkravet bevist hen over netværksgrænsen.
  Læs først `TABLE_FIXTURES` (`web/e2e/fixtures.ts`) for et par med en fælles familie; brug dets id'er i stedet for 1/2, hvis fixturen har andre. Kør: `env -u NODE_OPTIONS npm run e2e -w web -- family-sources`.

- [ ] **Step 8: Commit** — `feat(151): kildelinje ved ægteskab og forældrelinje i detaljepanelet (5b 2a)`.

---

### Task 8: Lokal CI, advisors og færdigbevis i bevisbasen

**Files:** Create `docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md`; Modify `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`; scripts i `~/.private/5b-2a/` (0700, ikke i repo).

- [ ] **Step 1: Hele CI lokalt** — genafspil jobbene `evidence-promotion-db`, `writer-1939-v50-db`, `node` (core, feed, web, mobil-tsc) og `python` som i `.github/workflows/ci.yml` (memory: kør hele CI-jobbet lokalt), plus `bash tests/sql/test-relation-binding-upgrade.sh ci5b_2a_up` og Playwright (`env -u NODE_OPTIONS npm run e2e -w web -- family-sources`; kun lokalt, spec §8). Alle grønne. Drop `ci5b_2a_*`-baserne bagefter (de er oprettet af planen) — inkl. spike-basen `ci5b_2a_spike` fra planlægningen.
- [ ] **Step 2: Arbejdsbase** — `ts=$(date +%Y%m%d%H%M%S); createdb -T daa5b_bevis_20261010093638 daa5b_2a_bevis_$ts`; løft med `db-migrations.sql` + `db-rls.sql`; kør `db-verify.sql` → `VERIFY_OK`.
- [ ] **Step 3: Før-hashes** — aggregat-hashes med `SET TimeZone='UTC'` og tabellens egen primærnøgle som sortering (Codex plan-r1 #4; `family_member` har ingen `id`):
  ```sql
  SELECT 'person',       md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.person t
  UNION ALL SELECT 'family',       md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.family t
  UNION ALL SELECT 'family_member',md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.family_id,t.person_id,t.rolle COLLATE "C")) FROM public.family_member t
  UNION ALL SELECT 'fact',         md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.fact t
  UNION ALL SELECT 'assertion',    md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.assertion t
  UNION ALL SELECT 'citation',     md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.citation t
  UNION ALL SELECT 'conclusion',   md5(string_agg(to_jsonb(t)::text,'' ORDER BY t.id)) FROM public.conclusion t;
  ```
  (`person.updated_at` o.l. ændres ikke af 2a's writers; ændres en hash alligevel, er det et fund, ikke støj.) Desuden output af `public_person_bio_source_versions_v2` som `anon` for et fast sæt på 50 personer (de laveste id'er i kilde 1).
- [ ] **Step 4: Afgørelse** — som redaktionsaktør (`request.jwt.claim.sub` sat, ekko til `/dev/null`): `red_preview_relation_decisions(1)` ⇒ forvent `count=203`, `ordinal_deviations=3`; `red_decide_relation_interpretations(1, <hash>)` ⇒ `203`. Notér hash og digest af sorterede `interpretation_key`.
- [ ] **Step 5: Binding** — byg `items` for de 203 accepterede ægteskaber + 7 accepterede forældre (gældende id + familie fra `relation_binding_state`), og skriv **før bindingen** et manifest (`~/.private/5b-2a/manifest.json`, 0600) med de sorterede tupler `(interpretation_id, family_id, rule_key, rule_version, state_sha256)` fra previewet og dets SHA-256. Preview ⇒ 210 egnede; batch ⇒ batch-id; identisk retry ⇒ samme batch-id, 0 nye rækker. Efter bindingen: digest af de samme tupler læst fra `interpretation_promotion` = manifestets digest (spec §7.2, r2-M5).
- [ ] **Step 6: Efter-hashes og læsning** — aggregat-hashes uændrede; `public_family_sources` som `anon` for de 210 familier ⇒ 210 rækker; digest af `(family_id, slags, source_record_ref)`; v2-outputtet for de 50 personer uændret.
- [ ] **Step 7: Negativtests i separate kopier** (`daa5b_2a_neg{A..D}_$ts`): forkert set-hash; forkert previewhash; familie ændret efter preview; levende medlem skjuler. Kopierne omdøbes bagefter til `slet_<mmdd>__…` (karantæne, sletning kun efter måling + ja).
- [ ] **Step 8: Advisors** (spec §8, Codex plan-r1 #14) — `get_advisors` læser Supabase-projektets egen base og kan ikke pege på en lokal restore-kopi; 2a's DDL rammer først Supabase ved overførslen. I færdigbeviset står derfor: `db-verify.sql` = `VERIFY_OK` i bevisbasen (inkl. ACL- og `prosecdef`-asserts for de nye funktioner), og **`get_advisors` = udestår, køres som gate i overførslens runbook umiddelbart efter DDL**. Det er en afvigelse fra specens ordlyd og forelægges projektejeren ved plan-godkendelsen; uden accept markeres rapporten `partial`.
- [ ] **Step 9: Rapport** — skriv `relationspersonas-5b-2a-bevis.md` efter mønstret i del 1-rapporten: grundlag (basenavn, commit, fil-hashes, databaseidentitet), afgørelse, binding, 0 kanonisk delta, læsefunktion, negativtests, webspor (CI-testene), review. Kun tal og hashes. Opdatér `status.md` (5b 2a bevist i restore, ikke deployet) og `changelog.md`.
- [ ] **Step 10: Commit** — `docs(151): færdigbevis for 5b 2a i restore`.

---

## Selvreview-checkliste (udført ved planlægningen)

- **Spec-dækning:** §4.1 → Task 1; §4.2 → Task 2; §4.3 → Task 3; §4.4 → Task 4; §4.5 → Task 2; §4.6 (M4) → Task 2; §5.1 → Task 5; §5.2 → Task 6-7; §6 → Global Constraints + Task 2/5; §7 → Task 8; §8 → Task 1-7 (opgradering Task 1, to-session Task 3-4, vitest/Playwright Task 6-7).
- **Navne på tværs:** `relation_binding_state`/`_sha256` (Task 2) bruges af Task 3-5; `preview_relation_promotions` (Task 4); `FamilieKilde`/`mapFamilieKilder` (Task 6) bruges af Task 7.
- **Kendte usikkerheder, der afgøres empirisk i tasken:** placeringen af regelindsættelsen i `schema.sql` (Task 1 Step 3), testgrebet for »ny identitetsversion« (Task 5 Step 1-note), `buildModel`'s præcise signatur (Task 6 Step 1).

## Plan-review runde 1 (Codex gpt-5.6-sol, 2026-10-11): NO-GO, 4 BLOCKER / 10 MAJOR / 2 MINOR

Alle fund er efterprøvet mod koden og rettet i planen ovenfor:

| # | Fund | Rettelse |
| --- | --- | --- |
| B1 | Task 2: ekstra familie gjorde tilstanden NULL før klassifikationstesten | familien slettes igen, og tilstanden skal vende tilbage til `h1` |
| B2 | Task 3: syntaksfejl i `DECLARE` | rettet; parse-bevis kræves i Task 1 Step 2 |
| B3 | Task 7: `filter(Boolean)` under `strict` | type guard `(id): id is string => id !== null` |
| B4 | Task 8: `family_member` har ingen `id` | eksakte queries med tabellens egen nøgle |
| M5 | fixturer byggede identitetsstate uden event (deferred triggere skjult af ROLLBACK) | `f2a_event_for_state`, ét tidsstempel i `f2a_marriage`, `SET CONSTRAINTS ALL IMMEDIATE` efter fixturer |
| M6 | gate-tests delte fixture og brugte ugyldig `version=2`-opdatering | én frisk fixture pr. gate (synlig → én gyldig mutation → 0); identitet gennem `decide_source_persona_identity`; afvist påstand via ny proposed version + `red_decide_interpretation` |
| M7 | triggerens værdiart-validering var ikke mutationstestet | to direkte INSERTs, der passerer mode-CHECK'en og fejler i triggeren |
| M8 | spec §8's samtidighedsmatrix ikke dækket | Task 3: identitetsgenafgørelse (dblink holder `lock_family_rows`); Task 4: family_member-write, konkurrerende promotion, identitetsgenafgørelse; alle med 0 delvise writes. `40P01` provokeres bevidst ikke (flaky); afbruddet er samme rollback-mekanisme |
| M9 | `vielse_fact_id` kunne drive uden at ændre previewhashen | indgår i preview-elementerne og hashen; skrivningen bruger previewets værdi; ny test |
| M10 | `rule_profile_hash` afveg fra den eksisterende form | ét par pr. element, `ORDER BY rule_key, rule_version` |
| M11 | bigint-id'er som JSON-tal; SQL afviste 19 cifre | mapperen godtager decimalstrenge eller sikre heltal (ellers droppes rækken); SQL `{1,19}` + range-checket cast; Playwright beviser strenge over nettet |
| M12 | Playwright ikke hermetisk; person 2 inkonsistent | én catch-all `**/rest/v1/**`; bio-versionen kun for person 1 (læser request-body) |
| M13 | kontrakt-1-gaten utestet | samme gyldige binding med kontrakten midlertidigt 1 (transaktionel `CREATE OR REPLACE`) ⇒ 0 rækker |
| M14 | `get_advisors` erstattet af `db-verify` | kan ikke pege på en lokal base; afvigelsen forelægges projektejeren, ellers rapport `partial` |
| m15 | arkitekturteksten nævnte »regel« som stale-udløser | rettet (reglen indgår bevidst ikke) |
| m16 | ingen catalog-verifikation af `items_sha256` og de nye signaturer | Task 4 Step 4b |
