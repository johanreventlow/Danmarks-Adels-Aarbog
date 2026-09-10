# Trin 4 · dagsværk 4.2: ét prædikat-navnerum — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Én tabel `private.interpretation_predicate` som eneste sandhed om, hvilke prædikater fortolkningslaget kender, med udsagnsform, §7.3-kategori og værdiform; promotion-reglerne og `interpretation` refererer den; extractoren læser en genereret, byte-verificeret fil i stedet for sin egen liste.

**Architecture:** Additiv DDL (tabel + seed + ÉN komposit-FK på `interpretation` (revision R2/R4) + trigger for `value_kind`-binding + view), en `references/interpretation-predicates.json` der er en projektion af tabellen, et lille sync/check-script, og ombytning af `evidence_extract.ALLOWED_PREDICATES` til filen med `interpretation_kind` pr. prædikat. Ingen oversættelsestabel.

**Tech Stack:** PostgreSQL 17, psql-SQL-tests, Python 3 + pytest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §5.

> **Linjetal** i denne plan gælder `origin/main` ved `6770451`; efter 4.1a-4.1c er `schema.sql` forskudt. Brug de navngivne ankre.

## Revision 2 (2026-09-10) — efter anden læsning, otte blokerende fund

> Denne revision er **bindende** og går forud for teksten længere nede, hvor de er uenige.
> Anledningen er en uafhængig gennemlæsning (Codex `gpt-5.6-sol`), der gav NO-GO, plus
> egne målinger mod `main` efter 4.1a/4.1b. Hvert punkt nedenfor er efterprøvet i koden,
> ikke sluttet fra planen.

### R1. Prædikat-inventaret var ufuldstændigt — og tre navne kan ikke seedes

**Målt:** ud over de fire fixture-prædikater, planen nævnte, indsætter `db-verify.sql` også
`death_date` (linje 3645 og 3661), `fake_approval` (3753) og `terminal_status` (3794) i
`private.interpretation`. Ingen af dem har punktum, så de bryder PK-CHECK'et
`^[a-z_]+(\.[a-z_]+)+$` og kan ikke seedes uændret. Planens egen kontrakttest bruger
tilsvarende `assertion`.

**Hvorfor det er blokerende, ikke kosmetisk:** `db-verify.sql` kører **mod prod**. Den
første `death_date`-insert ligger i en `BEGIN … EXCEPTION`-blok, der forventer præcis
`EVIDENCE_INTERPRETATION_OBSERVATION_REQUIRED`; en FK-overtrædelse ville fyre først og få
den negative test til at melde »fortolkning uden observation blev ikke afvist«. Den anden
insert skal derimod lykkes. En FK på `predicate` stopper altså produktionsverifikationen.

**Besluttet:** de tre navne omdøbes i `db-verify.sql` til punktumformen `verify.death_date`,
`verify.fake_approval`, `verify.terminal_status`, og kontrakttestens `assertion` til
`verify.assertion`. Efterprøvet: navnene optræder aldrig i en assertion — `v_terminal_status`
er en anden variabel om status, ikke om prædikatet — så omdøbningen er mekanisk og ændrer
ingen testsemantik. Formatinvarianten bevares dermed, i stedet for at blive slækket for at
rumme fixtures.

**Fixture-seed bliver dermed otte, ikke fire:** `person.name.relation`,
`verify.person.name.no_bulk`, `verify.person.name.principal`, `verify.concurrent.name`,
`verify.death_date`, `verify.fake_approval`, `verify.terminal_status`, `verify.assertion` —
alle `status='active'`, `introduced_in='db-verify-fixture'`, `value_kind='text'`,
`interpretation_kind='property'`.

**Krav til Task 2:** før FK'en tilføjes, køres en fuldstændig optælling af enhver
prædikat-værdi, der indsættes i `private.interpretation` og
`interpretation_promotion_rule_line` i `db-verify.sql` og hele `tests/sql/`. Dukker et navn
op, der ikke er seedet, er det en stopport — ikke noget, der seedes stiltiende bagefter.

### R2. Præcis én fremmednøgle

Planen modsagde sig selv: arkitekturresuméet lovede »to FK'er«, og Task 2's filoversigt bad
om en FK på `interpretation_promotion_rule_line`, mens Global Constraints og DDL-teksten
forbød den. **Besluttet:** der er **én** FK, på `private.interpretation(predicate)`. På
`rule_line.predicate` er der ingen FK — netop fordi db-verify's negative fixtures skal kunne
indsætte et bevidst ukendt prædikat dér. Begge de modstridende steder rettes.

### R3. `verify-%` må ikke kunne springe typebindingen over

Planen sprang **både** kendt-prædikat- og `value_kind`-kontrollen over for ethvert
`rule_key LIKE 'verify-%'`. Det er en brugbar bypass: den ægte promotionvej læser
`interpretation_promotion_rule_current` uden at udelukke `verify-%`, og regel-tabellens eget
CHECK kræver kun `text` eller `date_raw`, ikke lighed med prædikattabellen.

**Besluttet:** eksistens og `value_kind`-lighed håndhæves for **alle** regler, uden
undtagelse. Det eneste, `verify-%` må, er at pege på et fixture-prædikat
(`introduced_in='db-verify-fixture'`); almindelige regler skal pege på et ikke-fixture
prædikat. **Efterprøvet gennemførligt:** alle tre eksisterende `verify-`regler bruger
`value_kind='text'`, og de fem rigtige regler matcher deres prædikaters `value_kind`
(`person.name`/`byname`/`title` = `text`, `person.birth`/`death` = `date_raw`).

### R4. `interpretation_kind` skal bindes, ellers holder planens eget mål ikke

Målet siger, at tabellen er **eneste sandhed** om prædikatets udsagnsform. Med en FK kun på
`predicate` beholder `private.interpretation` sit uafhængige fireværdi-CHECK, så
`predicate='person.name'` med `interpretation_kind='event'` fortsat accepteres.

**Besluttet:** `UNIQUE (predicate, interpretation_kind)` på prædikattabellen og en
komposit-FK fra `private.interpretation(predicate, interpretation_kind)`. Før migrationen
inventeres eksisterende par (læse-kun), og migrationen fejler hårdt på et par, tabellen ikke
kender.

### R5. FK-migrationens guard skal ramme den rigtige constraint

`IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='…')` er utilstrækkelig:
constraintnavne er ikke databaseglobalt unikke, og guarden ser hverken relation, kolonner
eller `convalidated`. En efterladt `NOT VALID`-constraint eller en navnekollision ville få
migrationen til at springe valideringen over i stilhed.

**Besluttet:** guard på `conrelid`, `confrelid` og kolonnesættet; en eksisterende korrekt
men `NOT VALID` constraint valideres eksplicit; forkert definition er en stopport; til sidst
asserteres `convalidated=true`.

### R6. Kontrakttestens FK-probe skal kun være ugyldig ét sted

Testens negative FK-insert bruger `source_id=1` og et tilfældigt `extraction_run_id`, mens
tabellen kræver en gyldig source og et gyldigt `(extraction_run_id, source_id)`-par. På
frisk-skema-stien seedes ingen source, så testen ville fejle af den forkerte grund.

**Besluttet:** testen opretter gyldige source-, run- og persona-præmisser inde i sin egen
transaktion, så prædikat-FK'en er den eneste ugyldige værdi. Testen tilføjes til **både**
frisk-skema-stien og den kumulative migrationssti i CI.

### R7. Python-omlægningen kunne ikke blive grøn

Omdøbningslisten udelod `life_event.baptism` og `life_event.burial`, som begge findes i den
aktuelle test. Og fordi størstedelen af bulklisten bliver til `person.*`, mens validatoren
kræver en gyldig persona for alle `person.*`, ville testens bulkprøve uden persona-id fejle.

**Besluttet:** begge omdøbninger medtages, og bulkprøven bygges med en fuld
persona-/mention-/observationskæde — eller splittes, så `person.*`-claims har persona og de
øvrige ikke.

### R8. Byte-checket skal dække begge CI-stier

Planen lagde checket alene på »Evidens-hardening på frisk schema-sti«. CI har også en
kumulativ migrationssti, hvor en forskel i migrationsseed eller view kunne passere
ubemærket, selv om den genererede fil kommer fra frisk `schema.sql`.

**Besluttet:** checkerens ikke-skrivende tilstand køres efter **begge** stier.

### Rækkefølge efter revisionen

Task 1's kontrakttest er allerede skrevet og verificeret rød (`PREDICATE_TABLE_MISSING`);
den skal rettes efter R1 og R6, før Task 2 begynder. Task 2 udvides med R1's fuldstændige
optælling som stopport, R2's ene FK, R3's undtagelsesfri håndhævelse, R4's komposit-binding
og R5's guard. Task 3-4 følger R7 og R8.

---

## Global Constraints

- `schema.sql` = source of truth; `db-migrations.sql` idempotent (to kørsler).
- Promoverbarhed **udledes ved join** på `interpretation_promotion_rule_line.predicate`; tabellen har ingen `rule_key` (ingen cirkulær FK).
- **db-verify's syntetiske prædikater.** `db-verify.sql` kører mod prod og indsætter bevidst syntetiske prædikater som negative promotion-fixtures: i `rule_line` (`person.name.relation`, `verify.person.name.no_bulk`, `verify.person.name.principal`; søg `verify-relation-target`, `verify-name-no-bulk`) **og i `private.interpretation`** (`verify.person.name.no_bulk`, `verify.person.name.principal`, `verify.concurrent.name`; søg `verify.concurrent.name`). `rule_line.predicate` er UNIQUE, så fixtures kan ikke genbruge seedede prædikater. Derfor: (1) ingen FK på `rule_line.predicate`; (2) FK'en på `interpretation.predicate` bevares, og de fire `verify.*`/`person.name.relation`-prædikater seedes som `status='active'`, `introduced_in='db-verify-fixture'`, `value_kind='text'`, så fixtures kan indsættes; PK-CHECK'et tillader flerleddede navne (`^[a-z_]+(\.[a-z_]+)+$`); (3) "42 aktive"-asserter og den genererede fil filtrerer på `introduced_in<>'db-verify-fixture'`; (4) guardene i `add_interpretation_promotion_rule_version` og triggeren springes helt over for `rule_key LIKE 'verify-%'` (både ukendt-prædikat og `value_kind`-kontrollen), så db-verify's negative tests fortsat rammer de fejl, de er skrevet til; (5) db-verify-assert: alle aktive regler med `rule_key NOT LIKE 'verify-%'` peger på et seedet, ikke-fixture-prædikat med samme `value_kind`.
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

- Modify: `schema.sql` — hele 4.2-blokken (vocab-seed, tabel, triggere, prædikat-seed) indsættes **umiddelbart før** `CREATE TABLE private.interpretation` (søg det), fordi `interpretation` skal kunne referere den; FK'en på `interpretation` som `ALTER TABLE` umiddelbart efter `interpretation`-tabellen; regel-triggeren efter `interpretation_promotion_rule`; view'et efter `interpretation_promotion_rule_current`.
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
  SELECT count(*) INTO v_n FROM private.interpretation_predicate WHERE status='active' AND introduced_in<>'db-verify-fixture'; IF v_n<>42 THEN RAISE EXCEPTION 'PREDICATE_SEED_COUNT: %', v_n; END IF;
  SELECT count(*) INTO v_n FROM private.interpretation_predicate WHERE introduced_in='db-verify-fixture'; IF v_n<>4 THEN RAISE EXCEPTION 'PREDICATE_FIXTURE_SEED_COUNT: %', v_n; END IF;
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
    VALUES(gen_random_uuid(),1,1,'property','life_event.birth','"1801"','1.1','model_inference',0.5,'proposed','model',gen_random_uuid())$q$,'insert or update on table "interpretation" violates foreign key constraint "interpretation_predicate_fk"');
  -- rule_line har bevidst ingen FK (db-verify's syntetiske fixtures), men en regel på et ukendt prædikat afvises.
  INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES('x-v1','person.nonexistent');
  PERFORM pg_temp.expect_error($q$SELECT private.add_interpretation_promotion_rule_version('x-v1','person.nonexistent','property','assertion','navn','text',true,false,true,'active')$q$,'EVIDENCE_PROMOTION_RULE_PREDICATE_UNKNOWN');
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
- Modify: `schema.sql` (indsæt tabel + vocab-seed **før** linje 923; INGEN FK på `rule_line` (revision R2); seed af 42 rækker efter linje 960 men **før** `INSERT INTO private.interpretation_promotion_rule_line` (linje 961), fordi FK'en kræver prædikaterne først; trigger + FK på `interpretation` efter `interpretation`-tabellen; view efter `interpretation_promotion_rule_current` (linje ~981))
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
  predicate           text PRIMARY KEY CHECK (predicate ~ '^[a-z_]+(\.[a-z_]+)+$'),
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
-- Referencetabel: kun status må ændres (active→retired), aldrig slettes; RLS som de øvrige private tabeller.
CREATE FUNCTION private.reject_interpretation_predicate_mutation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'EVIDENCE_PREDICATE_DELETE_FORBIDDEN'; END IF;
  IF NEW.predicate<>OLD.predicate OR NEW.interpretation_kind<>OLD.interpretation_kind OR NEW.value_kind<>OLD.value_kind
     OR NEW.category IS DISTINCT FROM OLD.category OR NEW.introduced_in<>OLD.introduced_in THEN
    RAISE EXCEPTION 'EVIDENCE_PREDICATE_IMMUTABLE_FIELD';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_interpretation_predicate_mutation BEFORE UPDATE OR DELETE ON private.interpretation_predicate
  FOR EACH ROW EXECUTE FUNCTION private.reject_interpretation_predicate_mutation();
CREATE TRIGGER trg_interpretation_predicate_truncate BEFORE TRUNCATE ON private.interpretation_predicate
  FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation();
ALTER TABLE private.interpretation_predicate ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.interpretation_predicate FROM PUBLIC,anon,authenticated;

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
  ('reference.cross_reference','mention',NULL,'mention','active','trin4-4.2'),
  -- db-verify's syntetiske fixtures (kører mod prod; se Global Constraints). Ikke i den genererede fil.
  ('person.name.relation','property',NULL,'text','active','db-verify-fixture'),
  ('verify.person.name.no_bulk','property',NULL,'text','active','db-verify-fixture'),
  ('verify.person.name.principal','property',NULL,'text','active','db-verify-fixture'),
  ('verify.concurrent.name','property',NULL,'text','active','db-verify-fixture');
```

Ingen FK på `interpretation_promotion_rule_line` (se Global Constraints). I `private.add_interpretation_promotion_rule_version` (søg funktionsnavnet), efter `IF v_predicate<>p_predicate THEN ...`:

```sql
  -- db-verify's negative fixtures (rule_key 'verify-%') skal ramme de fejl, de tester, ikke disse guards.
  IF p_rule_key NOT LIKE 'verify-%' THEN
    IF NOT EXISTS (SELECT 1 FROM private.interpretation_predicate pr WHERE pr.predicate=p_predicate AND pr.status='active' AND pr.introduced_in<>'db-verify-fixture') THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_PREDICATE_UNKNOWN';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM private.interpretation_predicate pr WHERE pr.predicate=p_predicate AND pr.value_kind=p_value_kind AND pr.value_kind IN ('text','date_raw')) THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH';
    END IF;
  END IF;
```

Samme to kontroller som trigger `private.validate_interpretation_promotion_rule_predicate()` BEFORE INSERT på `private.interpretation_promotion_rule` (undtagelsen `verify-%` gælder db-verify's egne negative fixtures og dokumenteres i triggerens kommentar). De fem seed-rækker (søg `('person-name-v1',1,'person.name'`) opfylder begge.

Efter `interpretation`-tabellen: `ALTER TABLE private.interpretation ADD CONSTRAINT interpretation_predicate_fk FOREIGN KEY (predicate) REFERENCES private.interpretation_predicate(predicate);` (prædikatblokken står allerede før `interpretation`, jf. filoversigten). Før FK'en: `grep -nE "INSERT INTO private\.interpretation\(" db-verify.sql tests/sql/*.sql` og kontrollér, at hver fixtures prædikat er seedet: de fem regel-prædikater plus de fire `db-verify-fixture`-prædikater (målt 2026-09-06: `verify.person.name.no_bulk`, `verify.person.name.principal`, `verify.concurrent.name` i `db-verify.sql`). Dukker et nyt syntetisk prædikat op, seedes det som `db-verify-fixture`.

View efter `interpretation_promotion_rule_current`:

```sql
CREATE VIEW private.interpretation_predicate_promotable WITH (security_invoker=true) AS
SELECT p.predicate, p.interpretation_kind, p.category, p.value_kind, r.rule_key, r.rule_version, r.expected_fact_type
  FROM private.interpretation_predicate p
  JOIN private.interpretation_promotion_rule_line l ON l.predicate=p.predicate
  JOIN private.interpretation_promotion_rule_current r ON r.rule_key=l.rule_key
 WHERE p.status='active' AND p.introduced_in<>'db-verify-fixture' AND r.status='active' AND r.rule_key NOT LIKE 'verify-%';
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

Forventet: grønt (promotion-suiten bruger kun de fem seedede prædikater). Kør også `tests/sql/run-db-verify-disposable.sql`: fejler en af db-verify's `INSERT INTO private.interpretation(...)`-fixtures på `interpretation_predicate_fk`, bruger den et ikke-seedet prædikat — ret fixturen til et seedet prædikat (den er syntetisk), medmindre det er et ægte prædikat, der mangler i §5.2; så tilføjes det i seed'et med begrundelse.

- [ ] **Step 4: db-rls + db-verify + commit**

`db-rls.sql`: `REVOKE ALL ON FUNCTION private.validate_interpretation_predicate(), private.reject_interpretation_predicate_mutation(), private.validate_interpretation_promotion_rule_predicate() FROM PUBLIC,anon,authenticated,service_role; REVOKE ALL ON TABLE private.interpretation_predicate FROM PUBLIC,anon,authenticated;`
`db-verify.sql`: blok, der asserterer tabel, 42 aktive ikke-fixture-rækker + 4 fixture-rækker, FK'en `interpretation_predicate_fk`, view med 5 rækker, `value_kind`-paritet regel↔prædikat for `rule_key NOT LIKE 'verify-%'`, at alle sådanne aktive regler peger på et seedet ikke-fixture-prædikat, RLS + mutations-trigger på tabellen, og at `add_interpretation_promotion_rule_version`'s definition indeholder både `EVIDENCE_PROMOTION_RULE_PREDICATE_UNKNOWN` og `EVIDENCE_PROMOTION_RULE_VALUE_KIND_MISMATCH`. Kør derefter `tests/sql/run-db-verify-disposable.sql` og bekræft, at db-verify's egne `verify-%`-fixtures stadig passerer.

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

Sorteret på `predicate` (bytesortering), én række pr. aktiv tabelrække med `introduced_in<>'db-verify-fixture'` (fixture-prædikaterne er ikke en del af extractorens vokabular), `promotable` = findes i `interpretation_predicate_promotable`.

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
  ORDER BY p.predicate COLLATE "C"),'[]'::json) FROM private.interpretation_predicate p WHERE p.status='active' AND p.introduced_in<>'db-verify-fixture'"""

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
psql -X -Atc "SELECT (SELECT count(*) FROM private.interpretation_predicate WHERE status='active' AND introduced_in<>'db-verify-fixture'),(SELECT count(*) FROM private.interpretation_predicate_promotable)"   # 42|5
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
