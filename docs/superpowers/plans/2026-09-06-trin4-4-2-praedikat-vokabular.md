# Trin 4 · dagsværk 4.2: ét prædikat-navnerum — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Én tabel `private.interpretation_predicate` som eneste sandhed om, hvilke prædikater fortolkningslaget kender, med udsagnsform, §7.3-kategori og værdiform; promotion-reglerne og `interpretation` refererer den; extractoren læser en genereret, byte-verificeret fil i stedet for sin egen liste.

**Architecture:** Additiv DDL (tabel + seed + to FK'er + trigger for `value_kind`-binding + view), en `references/interpretation-predicates.json` der er en projektion af tabellen, et lille sync/check-script, og ombytning af `evidence_extract.ALLOWED_PREDICATES` til filen med `interpretation_kind` pr. prædikat. Ingen oversættelsestabel.

**Tech Stack:** PostgreSQL 17, psql-SQL-tests, Python 3 + pytest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §5.

## Global Constraints

- `schema.sql` = source of truth; `db-migrations.sql` idempotent (to kørsler).
- Promoverbarhed **udledes ved join** på `interpretation_promotion_rule_line.predicate`; tabellen har ingen `rule_key` (ingen cirkulær FK).
- `value_kind`-binding: en promotion-regel må kun findes for prædikater med `value_kind IN ('text','date_raw')`, og reglens `value_kind` skal være lig prædikatets (spec §5.1, fund 1). Værdier for `text`/`date_raw` er JSON-skalarer.
- "Prod har 0 fortolkninger" er en antagelse, der måles (læse-kun) før FK-migration; migrationen fejler hårdt, hvis en eksisterende `interpretation.predicate` ikke findes i tabellen.
- Ingen prod-mutation. Commits: ét pr. task, dansk Conventional Commit, ingen push. Gren `feat/147-praedikat-vokabular`.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, #147 leverance 3+4.
2. **Værdikædeled:** `proposed interpretations` (kontrolleret vokabular og dokumenterede mappingregler, målarkitekturens rækker "Proposed interpretations" og "Promotion").
3. **Generel/profil/legacy:** generel motor (tabel, fil, extractor). Ingen profil, ingen legacy.
4. **Redaktionel værdi:** §7.3's syv kategorier kan registreres adskilt; "samme slags"-forespørgsler over fortolkninger bliver pålidelige (invariant 9).
5. **Bevis:** migration + verify på restore; de fem regler løser via join; fil = tabel byte-identisk (CI-check mod database); `validate_output` afviser `life_event.birth` og accepterer `person.birth`; kind-afledning giver `event` for `event.marriage`.
6. **Erstatter:** `evidence_extract.ALLOWED_PREDICATES` som selvstændigt vokabular (reelt erstattet).

## Filoversigt

- Modify: `schema.sql` (efter `private.interpretation_promotion_rule_line` … `interpretation_promotion_rule` (linje 923-950): ny tabel før `rule_line`, FK'er, trigger, view; seed efter de eksisterende `INSERT INTO private.interpretation_promotion_rule_line` (linje 961))
- Modify: `db-migrations.sql` (ny blok før `$public_red_revoke$`)
- Modify: `db-rls.sql`, `db-verify.sql`
- Create: `tests/sql/test-interpretation-predicate.sql`
- Create: `.claude/skills/daa-extract/references/interpretation-predicates.json`
- Create: `.claude/skills/daa-extract/scripts/check_interpretation_predicates.py`
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py`, `test_evidence_extract.py`
- Modify: `.claude/skills/daa-extract/references/interpretation-schema.json` (version 1.1: værdiskemaer pr. `value_kind`)
- Modify: `.github/workflows/ci.yml` (postgres-job: check-script; pytest uændret)
- Modify: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md` → nyt dokument `docs/evidensbaseret-genimport/interpretation-predicate-147-rehearsal.md`, `docs/changelog.md`

## Prædikatseed (spec §5.2)

| predicate | kind | category | value_kind |
| --- | --- | --- | --- |
| person.name | property | NULL | text |
| person.name_part | property | NULL | name |
| person.name_variant | property | NULL | name |
| person.byname | property | NULL | text |
| person.identity | property | NULL | text |
| person.uncertainty | property | NULL | text |
| person.negation | property | NULL | text |
| person.unknown | property | NULL | text |
| person.birth | property | NULL | date_raw |
| person.baptism | property | NULL | date_raw |
| person.death | property | NULL | date_raw |
| person.burial | property | NULL | date_raw |
| person.title | property | titel | text |
| person.form_of_address | property | NULL | text |
| person.rank | property | militaer_rang | text |
| person.office | property | embede | text |
| person.court_office | property | hofstilling | text |
| person.occupation | property | erhverv | text |
| person.education | property | uddannelse | text |
| person.decoration | property | dekoration | text |
| person.estate | property | NULL | text |
| person.residence | property | NULL | text |
| person.military_service | property | NULL | text |
| person.publication | property | NULL | text |
| relation.marriage | relation | NULL | relation |
| relation.parent | relation | NULL | relation |
| relation.child | relation | NULL | relation |
| event.marriage | event | NULL | event |
| event.appointment | event | NULL | event |
| event.dismissal | event | NULL | event |
| event.acquisition | event | NULL | event |
| event.travel | event | NULL | event |
| mention.person | mention | NULL | mention |
| mention.place | mention | NULL | mention |
| mention.organisation | mention | NULL | mention |
| mention.estate | mention | NULL | mention |
| lineage.introduction | property | NULL | text |
| genealogy.generation_header | property | NULL | text |
| heraldry.description | property | NULL | text |
| heraldry.blazon | property | NULL | text |
| image.caption | property | NULL | text |
| reference.cross_reference | mention | NULL | mention |

Alle 42 rækker `status='active'`, `introduced_in='trin4-4.2'`. Kategorikoderne lægges i `private.vocab` (`scheme='interpretation_category'`: `titel`, `embede`, `hofstilling`, `militaer_rang`, `erhverv`, `uddannelse`, `dekoration`).

---

### Task 1: SQL-kontrakttest (fejler først)

**Files:**
- Create: `tests/sql/test-interpretation-predicate.sql`

- [ ] **Step 1: Skriv testen**

```sql
-- #147 4.2: ét prædikat-navnerum — tabel, FK'er, value_kind-binding, view.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'PREDICATE_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'PREDICATE_TEST_NO_ERROR: expected %', p_token;
END $$;

DO $t1_table_and_seed$
DECLARE v_n integer; v_pred text;
BEGIN
  IF to_regclass('private.interpretation_predicate') IS NULL THEN RAISE EXCEPTION 'PREDICATE_TABLE_MISSING'; END IF;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate WHERE status='active'; IF v_n<>42 THEN RAISE EXCEPTION 'PREDICATE_SEED_COUNT: %', v_n; END IF;
  FOREACH v_pred IN ARRAY ARRAY['person.name','person.byname','person.title','person.birth','person.death'] LOOP
    IF NOT EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_line l JOIN private.interpretation_predicate p ON p.predicate=l.predicate WHERE l.predicate=v_pred) THEN
      RAISE EXCEPTION 'PREDICATE_RULE_JOIN_MISSING: %', v_pred; END IF;
  END LOOP;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate_promotable; IF v_n<>5 THEN RAISE EXCEPTION 'PREDICATE_PROMOTABLE_VIEW: %', v_n; END IF;
  -- Reglens value_kind = prædikatets.
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_current r JOIN private.interpretation_predicate p ON p.predicate=r.predicate WHERE r.value_kind<>p.value_kind) THEN RAISE EXCEPTION 'PREDICATE_VALUE_KIND_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate WHERE category IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='interpretation_category' AND v.code=category)) THEN RAISE EXCEPTION 'PREDICATE_CATEGORY_UNSEEDED'; END IF;
  RAISE NOTICE 't1 table and seed OK';
END $t1_table_and_seed$;

DO $t2_fks_and_binding$
BEGIN
  -- Gamle extractor-navne findes ikke.
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate WHERE predicate IN ('life_event.birth','title.title','honour.honour')) THEN RAISE EXCEPTION 'PREDICATE_OLD_NAMES_PRESENT'; END IF;
  -- interpretation.predicate → FK.
  PERFORM pg_temp.expect_error($q$INSERT INTO private.interpretation(interpretation_key,version,source_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES(gen_random_uuid(),1,1,'property','life_event.birth','"1801"','1.1','model_inference',0.5,'proposed','model',gen_random_uuid())$q$,'insert or update on table "interpretation" violates foreign key constraint');
  -- rule_line.predicate → FK.
  PERFORM pg_temp.expect_error($q$INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('x-v1','person.nonexistent')$q$,'insert or update on table "interpretation_promotion_rule_line" violates foreign key constraint');
  -- Regel for et prædikat med objekt-værdiform afvises (value_kind-binding).
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('event-marriage-test','event.marriage');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('event-marriage-test','event.marriage','property','assertion','navn','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH');
  -- Regel med forkert value_kind for et text-prædikat afvises.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('office-test','person.office');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('office-test','person.office','property','assertion','titel','date_raw',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH');
  -- Korrekt value_kind går igennem.
  PERFORM private.add_interpretation_promotion_rule_version('office-test','person.office','property','assertion','titel','text',true,false,true,'active');
  RAISE NOTICE 't2 fks and binding OK';
END $t2_fks_and_binding$;
ROLLBACK;
```

- [ ] **Step 2: Kør og se den fejle** (base som i plan 4.1a Task 2 Step 2)

```bash
psql -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-predicate.sql
```

Forventet: FAIL `PREDICATE_TABLE_MISSING`.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add tests/sql/test-interpretation-predicate.sql
git commit -m "test(db): kontrakttest for prædikattabellen (#147 4.2) — fejler før DDL"
```

---

### Task 2: DDL i `schema.sql` + migration

**Files:**
- Modify: `schema.sql` (indsæt tabel + vocab-seed **før** linje 923; FK på `rule_line` som `ALTER TABLE` efter linje 928; seed af 42 rækker efter linje 960 men **før** `INSERT INTO private.interpretation_promotion_rule_line` (linje 961), fordi FK'en kræver prædikaterne først; trigger + FK på `interpretation` efter `interpretation`-tabellen; view efter `interpretation_promotion_rule_current` (linje ~981))
- Modify: `db-migrations.sql`

- [ ] **Step 1: DDL**

```sql
-- ---------- #147 4.2: ÉT PRÆDIKAT-NAVNERUM ----------
INSERT INTO private.vocab(scheme,code,label) VALUES
  ('interpretation_category','titel','Adelig eller standsmæssig titel (§7.3)'),
  ('interpretation_category','embede','Embede (§7.3)'),
  ('interpretation_category','hofstilling','Hofstilling (§7.3)'),
  ('interpretation_category','militaer_rang','Militær rang (§7.3)'),
  ('interpretation_category','erhverv','Erhverv eller civil stilling (§7.3)'),
  ('interpretation_category','uddannelse','Uddannelse eller grad (§7.3)'),
  ('interpretation_category','dekoration','Dekoration eller æresbevisning (§7.3)');

CREATE TABLE private.interpretation_predicate (
  predicate           text PRIMARY KEY CHECK (predicate ~ '^[a-z_]+\.[a-z_]+$'),
  interpretation_kind text NOT NULL CHECK (interpretation_kind IN ('property','relation','event','mention')),
  category            text,
  value_kind          text NOT NULL CHECK (value_kind IN ('text','date_raw','name','event','relation','mention')),
  status              text NOT NULL CHECK (status IN ('active','retired')),
  introduced_in       text NOT NULL CHECK (btrim(introduced_in)<>''),
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION private.validate_interpretation_predicate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
BEGIN
  IF NEW.category IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='interpretation_category' AND code=NEW.category) THEN
    RAISE EXCEPTION 'EVIDENCE_PREDICATE_CATEGORY_UNKNOWN: %', NEW.category;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_interpretation_predicate_validate BEFORE INSERT OR UPDATE ON private.interpretation_predicate
  FOR EACH ROW EXECUTE FUNCTION private.validate_interpretation_predicate();

INSERT INTO private.interpretation_predicate(predicate,interpretation_kind,category,value_kind,status,introduced_in) VALUES
  ('person.name','property',NULL,'text','active','trin4-4.2'),
  ('person.name_part','property',NULL,'name','active','trin4-4.2'),
  ('person.name_variant','property',NULL,'name','active','trin4-4.2'),
  ('person.byname','property',NULL,'text','active','trin4-4.2'),
  ('person.identity','property',NULL,'text','active','trin4-4.2'),
  ('person.uncertainty','property',NULL,'text','active','trin4-4.2'),
  ('person.negation','property',NULL,'text','active','trin4-4.2'),
  ('person.unknown','property',NULL,'text','active','trin4-4.2'),
  ('person.birth','property',NULL,'date_raw','active','trin4-4.2'),
  ('person.baptism','property',NULL,'date_raw','active','trin4-4.2'),
  ('person.death','property',NULL,'date_raw','active','trin4-4.2'),
  ('person.burial','property',NULL,'date_raw','active','trin4-4.2'),
  ('person.title','property','titel','text','active','trin4-4.2'),
  ('person.form_of_address','property',NULL,'text','active','trin4-4.2'),
  ('person.rank','property','militaer_rang','text','active','trin4-4.2'),
  ('person.office','property','embede','text','active','trin4-4.2'),
  ('person.court_office','property','hofstilling','text','active','trin4-4.2'),
  ('person.occupation','property','erhverv','text','active','trin4-4.2'),
  ('person.education','property','uddannelse','text','active','trin4-4.2'),
  ('person.decoration','property','dekoration','text','active','trin4-4.2'),
  ('person.estate','property',NULL,'text','active','trin4-4.2'),
  ('person.residence','property',NULL,'text','active','trin4-4.2'),
  ('person.military_service','property',NULL,'text','active','trin4-4.2'),
  ('person.publication','property',NULL,'text','active','trin4-4.2'),
  ('relation.marriage','relation',NULL,'relation','active','trin4-4.2'),
  ('relation.parent','relation',NULL,'relation','active','trin4-4.2'),
  ('relation.child','relation',NULL,'relation','active','trin4-4.2'),
  ('event.marriage','event',NULL,'event','active','trin4-4.2'),
  ('event.appointment','event',NULL,'event','active','trin4-4.2'),
  ('event.dismissal','event',NULL,'event','active','trin4-4.2'),
  ('event.acquisition','event',NULL,'event','active','trin4-4.2'),
  ('event.travel','event',NULL,'event','active','trin4-4.2'),
  ('mention.person','mention',NULL,'mention','active','trin4-4.2'),
  ('mention.place','mention',NULL,'mention','active','trin4-4.2'),
  ('mention.organisation','mention',NULL,'mention','active','trin4-4.2'),
  ('mention.estate','mention',NULL,'mention','active','trin4-4.2'),
  ('lineage.introduction','property',NULL,'text','active','trin4-4.2'),
  ('genealogy.generation_header','property',NULL,'text','active','trin4-4.2'),
  ('heraldry.description','property',NULL,'text','active','trin4-4.2'),
  ('heraldry.blazon','property',NULL,'text','active','trin4-4.2'),
  ('image.caption','property',NULL,'text','active','trin4-4.2'),
  ('reference.cross_reference','mention',NULL,'mention','active','trin4-4.2');
```

Efter `interpretation_promotion_rule_line`-tabellen (linje 928):

```sql
ALTER TABLE private.interpretation_promotion_rule_line
  ADD CONSTRAINT interpretation_promotion_rule_line_predicate_fk FOREIGN KEY (predicate) REFERENCES private.interpretation_predicate(predicate);
```

I `private.add_interpretation_promotion_rule_version` (linje 984-1005), efter `IF v_predicate<>p_predicate THEN ...`:

```sql
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_predicate pr WHERE pr.predicate=p_predicate AND pr.status='active' AND pr.value_kind=p_value_kind AND pr.value_kind IN ('text','date_raw')) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH';
  END IF;
```

Samme kontrol som en trigger på `private.interpretation_promotion_rule` (BEFORE INSERT), så de fem seed-rækker (linje 968-978) og enhver direkte INSERT også er dækket — seed-rækkerne opfylder den (alle `text`/`date_raw`).

Efter `interpretation`-tabellen: `ALTER TABLE private.interpretation ADD CONSTRAINT interpretation_predicate_fk FOREIGN KEY (predicate) REFERENCES private.interpretation_predicate(predicate);` — placér efter tabeldefinitionen, men da prædikattabellen står senere i filen end `interpretation` (linje 860), flyttes hele 4.2-blokken (vocab-seed, tabel, seed) til **før** `CREATE TABLE private.interpretation` (linje 860); FK'erne på `rule_line` og `interpretation` tilføjes umiddelbart efter de respektive tabeller.

View efter `interpretation_promotion_rule_current`:

```sql
CREATE VIEW private.interpretation_predicate_promotable WITH (security_invoker=true) AS
SELECT p.predicate, p.interpretation_kind, p.category, p.value_kind, r.rule_key, r.rule_version, r.expected_fact_type
  FROM private.interpretation_predicate p
  JOIN private.interpretation_promotion_rule_line l ON l.predicate=p.predicate
  JOIN private.interpretation_promotion_rule_current r ON r.rule_key=l.rule_key
 WHERE p.status='active' AND r.status='active';
```

- [ ] **Step 2: Migration**

Blok i `db-migrations.sql`: `CREATE TABLE IF NOT EXISTS`, seed `ON CONFLICT (predicate) DO NOTHING`, vocab-seed `ON CONFLICT DO NOTHING`, inventering:

```sql
DO $predicate_inventory$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(DISTINCT predicate, ', ') INTO v_missing FROM private.interpretation i
   WHERE NOT EXISTS (SELECT 1 FROM private.interpretation_predicate p WHERE p.predicate=i.predicate);
  IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'PREDICATE_MIGRATION_UNSEEDED_PREDICATES: %', v_missing; END IF;
  SELECT string_agg(DISTINCT predicate, ', ') INTO v_missing FROM private.interpretation_promotion_rule_line l
   WHERE NOT EXISTS (SELECT 1 FROM private.interpretation_predicate p WHERE p.predicate=l.predicate);
  IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'PREDICATE_MIGRATION_UNSEEDED_RULE_LINES: %', v_missing; END IF;
END $predicate_inventory$;
```

FK'er med `IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='…')`-guard, `CREATE OR REPLACE` for `add_interpretation_promotion_rule_version` og trigger-funktionen, `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`, `CREATE OR REPLACE VIEW`.

- [ ] **Step 3: Kør Task 1 + promotion-suiten på begge stier**

```bash
psql -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-predicate.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql
```

Forventet: grønt (promotion-suiten bruger kun de fem seedede prædikater). Fejler `db-verify`'s egne interpretation-fixtures (linje 3590-3760) på FK'en, er det fordi de bruger et ikke-seedet prædikat: læs hvilket, og tilføj det til seed'et **kun** hvis det er et ægte prædikat; ellers ret fixturen til et seedet.

- [ ] **Step 4: db-rls + db-verify + commit**

`db-rls.sql`: `REVOKE ALL ON FUNCTION private.validate_interpretation_predicate() FROM PUBLIC,anon,authenticated,service_role; REVOKE ALL ON TABLE private.interpretation_predicate FROM PUBLIC,anon,authenticated;`
`db-verify.sql`: blok, der asserterer tabel, 42 aktive rækker, begge FK'er, view med 5 rækker, `value_kind`-paritet regel↔prædikat, og at `add_interpretation_promotion_rule_version`'s definition indeholder `EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH`.

```bash
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): private.interpretation_predicate — ét navnerum med value_kind-binding til reglerne (#147 4.2)"
```

---

### Task 3: Genereret fil + check-script

**Files:**
- Create: `.claude/skills/daa-extract/references/interpretation-predicates.json`
- Create: `.claude/skills/daa-extract/scripts/check_interpretation_predicates.py`
- Modify: `.github/workflows/ci.yml` (postgres-jobbet `evidence promotion · PostgreSQL 17`: nyt trin efter `test-evidence-promotion.sql` på frisk sti)

- [ ] **Step 1: Filformat**

```json
{
  "schema_version": "interpretation-predicates-1.0",
  "predicates": [
    {"predicate": "person.name", "interpretation_kind": "property", "category": null, "value_kind": "text", "promotable": true},
    ...
  ]
}
```

Sorteret på `predicate` (bytesortering), én række pr. aktiv tabelrække, `promotable` = findes i `interpretation_predicate_promotable`.

- [ ] **Step 2: Check-script**

```python
#!/usr/bin/env python3
"""Byte-verificér references/interpretation-predicates.json mod databasen (#147 4.2).
Bruger psql via PG*-miljøet. --write regenererer filen fra databasen."""
from __future__ import annotations
import argparse, json, subprocess, sys
from pathlib import Path
FILE = Path(__file__).resolve().parents[1] / "references" / "interpretation-predicates.json"
SQL = """SELECT coalesce(json_agg(json_build_object('predicate',p.predicate,'interpretation_kind',p.interpretation_kind,'category',p.category,
  'value_kind',p.value_kind,'promotable',EXISTS(SELECT 1 FROM private.interpretation_predicate_promotable v WHERE v.predicate=p.predicate))
  ORDER BY p.predicate COLLATE "C"),'[]'::json) FROM private.interpretation_predicate p WHERE p.status='active'"""

def from_db() -> dict:
    out = subprocess.run(["psql", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-c", SQL], capture_output=True, text=True, check=True).stdout.strip()
    return {"schema_version": "interpretation-predicates-1.0", "predicates": json.loads(out)}

def render(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--write", action="store_true"); args = parser.parse_args()
    expected = render(from_db())
    if args.write:
        FILE.write_text(expected, encoding="utf-8"); print("written", len(json.loads(expected)["predicates"])); return
    actual = FILE.read_text(encoding="utf-8") if FILE.exists() else ""
    if actual != expected:
        print("PREDICATE_FILE_DRIFT: kør check_interpretation_predicates.py --write mod en base med gældende schema", file=sys.stderr); raise SystemExit(2)
    print("PREDICATE_FILE_OK")

if __name__ == "__main__": main()
```

- [ ] **Step 3: Generér filen mod den lokale testbase, verificér, tilføj CI-trin**

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/check_interpretation_predicates.py --write
/usr/bin/python3 .claude/skills/daa-extract/scripts/check_interpretation_predicates.py   # PREDICATE_FILE_OK
```

I `ci.yml`, postgres-jobbet "Evidens-hardening på frisk schema-sti", efter `test-evidence-promotion.sql`-linjen:

```yaml
          python3 .claude/skills/daa-extract/scripts/check_interpretation_predicates.py
```

(jobbet har allerede `PG*`-env og `psql`; bekræft at `python3` findes i det job — ellers tilføj `actions/setup-python` som i pytest-jobbet.)

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/references/interpretation-predicates.json .claude/skills/daa-extract/scripts/check_interpretation_predicates.py .github/workflows/ci.yml
git commit -m "feat(evidens): genereret prædikatfil med byte-check mod databasen i CI (#147 4.2)"
```

---

### Task 4: Extractoren læser filen; kind-afledning; værdiskemaer

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py` (linje 20-40 `ALLOWED_PREDICATES`, 195-215 `build_interpretation_candidates`)
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_extract.py` (12 forekomster af gamle navne)
- Modify: `.claude/skills/daa-extract/references/interpretation-schema.json`

**Interfaces:**
- Produces: `evidence_extract.PREDICATES: dict[str, dict]` (fra filen), `ALLOWED_PREDICATES = frozenset(PREDICATES)`, `predicate_kind(predicate) -> str`, `validate_claim_value(predicate, value) -> None` (skalar for `text`/`date_raw`; objekt med `raw` for øvrige; kaster `EXTRACTION_CLAIM_VALUE_INVALID`). 4.3's `validate_record_claims` genbruger de to sidste.

- [ ] **Step 1: Fejlende tests**

```python
def test_predicates_come_from_generated_file():
    assert "person.birth" in evidence_extract.ALLOWED_PREDICATES
    assert "life_event.birth" not in evidence_extract.ALLOWED_PREDICATES
    assert evidence_extract.predicate_kind("event.marriage") == "event"
    assert evidence_extract.predicate_kind("relation.marriage") == "relation"
    assert evidence_extract.predicate_kind("mention.place") == "mention"
    assert evidence_extract.predicate_kind("person.title") == "property"


@pytest.mark.parametrize("predicate,value,ok", [
    ("person.birth", "12. maj 1801", True),
    ("person.birth", {"raw": "12. maj 1801"}, False),
    ("person.name_part", {"raw": "Bravo", "normalized": "Bravo"}, True),
    ("person.name_part", "Bravo", False),
    ("event.marriage", {"raw": "Gift 1830 m. Charlie", "date_raw": "1830", "participants": []}, True),
    ("event.marriage", {"normalized": "x"}, False),
])
def test_claim_value_form_follows_value_kind(predicate, value, ok):
    if ok:
        evidence_extract.validate_claim_value(predicate, value)
    else:
        with pytest.raises(evidence_extract.ExtractionError, match="EXTRACTION_CLAIM_VALUE_INVALID"):
            evidence_extract.validate_claim_value(predicate, value)
```

Omdøb i de eksisterende tests: `life_event.birth`→`person.birth`, `life_event.death`→`person.death`, `title.title`→`person.title`, `rank.rank`→`person.rank`, `office.office`→`person.office`, `honour.honour`→`person.decoration`, `form_of_address.form_of_address`→`person.form_of_address`, `relationship.*`→`relation.*`, `education.education`→`person.education`, `estate.estate`→`person.estate`, `residence.residence`→`person.residence`, `military_service.military_service`→`person.military_service`, `publication.publication`→`person.publication`. Tests, der forventede `kind == "event"` for `life_event.*`, forventer nu `property` for `person.birth` (det er en egenskab med `date_raw`) — det er spec'ens beslutning, ikke en testfejl.

- [ ] **Step 2: Implementér**

```python
PREDICATES_FILE = ROOT / ".claude/skills/daa-extract/references/interpretation-predicates.json"


def _load_predicates() -> dict[str, dict[str, Any]]:
    payload = json.loads(PREDICATES_FILE.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "interpretation-predicates-1.0":
        raise ExtractionError("EXTRACTION_PREDICATE_FILE_INVALID")
    return {row["predicate"]: row for row in payload["predicates"]}


PREDICATES = _load_predicates()
ALLOWED_PREDICATES = frozenset(PREDICATES)
SCALAR_VALUE_KINDS = {"text", "date_raw"}


def predicate_kind(predicate: str) -> str:
    if predicate not in PREDICATES:
        raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
    return PREDICATES[predicate]["interpretation_kind"]


def validate_claim_value(predicate: str, value: Any) -> None:
    kind = PREDICATES.get(predicate, {}).get("value_kind")
    if kind is None:
        raise ExtractionError("EXTRACTION_PREDICATE_INVALID")
    if kind in SCALAR_VALUE_KINDS:
        if not isinstance(value, str) or not value.strip():
            raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")
        return
    if not isinstance(value, Mapping) or not isinstance(value.get("raw"), str) or not value["raw"].strip():
        raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")
    if "normalized" in value and value["normalized"] is not None and not isinstance(value["normalized"], str):
        raise ExtractionError("EXTRACTION_CLAIM_VALUE_INVALID")
```

Fjern den hårdkodede `ALLOWED_PREDICATES`-literal. I `validate_output`: efter `if "value" not in claim`, tilføj `validate_claim_value(predicate, claim["value"])`. I `build_interpretation_candidates`: erstat familie-gættet med `kind = predicate_kind(predicate)`.

I `interpretation-schema.json`: bump `$id` til `…-1.1.json`, tilføj `"value_kind"` som valgfrit felt og `"$defs"` med skemaer `text` (string), `date_raw` (string), `name`/`event`/`relation`/`mention` (object, `required: ["raw"]`, `raw` string, `normalized` string|null, `additionalProperties: true`). Tilføj i `test_evidence_extract.py` en test, der loader skemaet og asserterer, at `$defs` har de seks nøgler.

- [ ] **Step 3: Kør hele Python-suiten**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
```

Forventet: grøn (3 skips som før).

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/evidence_extract.py .claude/skills/daa-extract/scripts/test_evidence_extract.py .claude/skills/daa-extract/references/interpretation-schema.json
git commit -m "feat(evidens): extractoren læser prædikattabellens fil; kind- og værdiform pr. prædikat (#147 4.2)"
```

---

### Task 5: Rigtig kørsel på restore + rapport

**Files:**
- Create: `docs/evidensbaseret-genimport/interpretation-predicate-147-rehearsal.md`
- Modify: `docs/changelog.md`

- [ ] **Step 1: Mål antagelsen læse-kun, migrér, verificér**

```bash
set -euo pipefail; umask 077; export PGTZ=UTC PGDATABASE="$DB"   # restore fra 4.1a/4.1c
psql -X -Atc "SELECT count(*) FROM private.interpretation"                       # forventet 0 (antagelse målt)
psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql 2>&1 | grep -E 'OK: #147|ERROR'
psql -X -Atc "SELECT (SELECT count(*) FROM private.interpretation_predicate WHERE status='active'),(SELECT count(*) FROM private.interpretation_predicate_promotable)"   # 42|5
/usr/bin/python3 .claude/skills/daa-extract/scripts/check_interpretation_predicates.py   # PREDICATE_FILE_OK
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql 2>&1 | tail -3
```

Samme antagelsesmåling køres **læse-kun mod prod** (`BEGIN READ ONLY; SELECT count(*) FROM private.interpretation; ROLLBACK`) og noteres i rapporten, før nogen prod-GO overvejes.

- [ ] **Step 2: Rapport + changelog + commit**

Rapporten indeholder: dump-SHA, tal fra Step 1, prod-måling (kun tallet), og bekræftelse af at 4.1's klausuler i restoren er uberørte (`count(*) WHERE observation_kind='clause'` før/efter).

```bash
git branch --show-current
git add docs/evidensbaseret-genimport/interpretation-predicate-147-rehearsal.md docs/changelog.md
git commit -m "docs(genimport): 4.2 prædikatnavnerum migreret og verificeret på restore (#147)"
```

---

## Selvreview-checkliste

- [ ] Ingen mapping-tabel; extractoren bruger databasens navne.
- [ ] `value_kind`-binding håndhæves både i `add_interpretation_promotion_rule_version` og som trigger på `interpretation_promotion_rule`.
- [ ] Filen er byte-identisk med tabellen i CI (frisk sti) — og `--write` er den eneste måde, filen ændres på.
- [ ] Alle 12 gamle prædikatnavne i tests er omdøbt; ingen `life_event.`/`title.title` i repo uden for historiske docs.
