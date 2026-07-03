# Udledt slægtsnavn — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Udled og cache et efternavn ("Reventlow") for fødte medlemmer der mangler det i Dansk Adels
Aarbog, uden at overskrive bogens rå påstand (`visning_navn`), og uden at bryde TNG-QA (som selv
tilføjer "Reventlow" til `visning_navn`).

**Architecture:** `lineage.slaegtsnavn` (ny, nullable, den fortrydbare autoritative kilde) +
`person.visning_efternavn`/`visning_fuldt_navn` (nye cache-kolonner, envejs-projektion, aldrig
redigeret direkte). `regen_person_visning()` udvides med en fan-out-sikker CTE der slår personens
effektive families-efternavn op via linje-medlemskab (`person_external_id → lineage`, vandrer op ad
`parent_lineage_id` ved NULL) og en suffiks-token-match der afgør om efternavnet allerede står i
navnet. To nye triggere (på `person_external_id` og `lineage`) holder cachen synkron. Cyklus-sikre
graf-walkers (`lineage_ancestors`/`lineage_descendants`) genbruges BÅDE til skrive-tids
cyklus-forebyggelse OG til læse-tids opslag/subtræ-regen.

**Tech Stack:** PostgreSQL 17 (Supabase), PL/pgSQL, `db-migrations.sql` (idempotent), `db-verify.sql`
(DO-block-asserts). R (`post_load_fixup.R`) for reload-durabel `lineage.slaegtsnavn`-tildeling.
Frontend: `web/src/data/model.ts`, `mobile/src/data/load.ts`, redaktør-readers.

**Spec:** `docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md` (3× Codex-reviewet — §5,
§5.1, §5.2 dokumenterer alle reconciles. Læs den FØR implementering — denne plan implementerer §4
punkt for punkt og refererer tilbage til spec-afsnit).

## Global Constraints

- **Invariant 1 (påstande uforanderlige):** bogens navn-`assertion` ("Conrad") urøres. Ingen
  syntetisk påstand fabrikeres.
- **Invariant 4 (cache = envejs-projektion):** `visning_efternavn`/`visning_fuldt_navn` skrives KUN
  af `regen_person_visning()`, aldrig direkte. `visning_navn` er UÆNDRET (fortsat rå, kun bogens
  fornavne/mellemnavne) — TNG-QA læser den fortsat rå (spec §2 KRITISK-fund).
- **Skip-liste OBLIGATORISK (spec §4.4):** begge nye person-kolonner PÅ `version_pk_registry`
  skip_cols for `person` — ellers logger `log_change`-triggeren backfillen som ~580 autoritative
  `change_event`-rækker. `log_change()` har allerede indbygget no-op-skip (`v_foer=v_efter` efter
  skip-projektion, schema.sql:1146) — så korrekt skip-listering forhindrer BÅDE spurious logging OG
  (indirekte) unødige rækker i `change_event`.
- **Fortrydbarhed (spec §4.8):** cache-kolonnerne regenereres, restores ikke. Den autoritative
  fortrydbare enhed er `lineage.slaegtsnavn`-tildelingen (IKKE på skip-listen — versioneres normalt).
- **Cyklus/dybde-vagt (spec §4.7) SKAL raise, ikke stille trunkere.** Samme walk-funktion pr.
  retning bruges BÅDE af skrive-tids cyklus-forebyggelse OG læse-tids opslag/subtræ-regen.
- **Reload-durabilitet (advisor-fund, IKKE i de 3 Codex-passes):** `load_daa.R --force-reset`
  TRUNCATE CASCADE'r `lineage` — en rå prod-`UPDATE lineage SET slaegtsnavn=...` overlever IKKE
  næste reload. Tildelingen SKAL leve i `post_load_fixup.R` (samme mønster som lineage-navne),
  keyed på reload-invariante nøgler (`source_id`+`kode`), ikke `lineage.id`.
- **Sprog:** dansk i kommentarer, kolonnenavne, NOTICE-tekster.
- **Test mod LOKAL prod-kopi (`daa_test`), ALDRIG direkte mod prod.** Se `[[lokal-db-testbase]]`-
  hukommelsen for opsætning. Prod-migration+backfill er et EKSPLICIT STOP-GATE (Task 9) — kræver
  bruger-godkendelse før den køres (hard-to-reverse, delt system).
- **Commit-stil:** Conventional Commits, dansk. Ingen Claude-attribution-footer.

---

## Sådan køres tests

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:$PATH"
psql -d daa_test -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -d daa_test -v ON_ERROR_STOP=1 -f db-verify.sql 2>&1 | grep -E 'OK:|FEJL|EXCEPTION|NOTICE'
```

TDD-cyklus pr. task: tilføj assert-blok → kør (FEJL/mangler objekt) → tilføj migration → kør (OK).

---

## Filstruktur

| Fil | Ansvar | Ændring |
|---|---|---|
| `schema.sql` | Kanonisk skema | Nye kolonner/tabeller/funktioner/triggere, skip-liste-opdatering |
| `db-migrations.sql` | Idempotent afstemning | Spejl alle nye objekter |
| `db-verify.sql` | Verifikations-asserts | Assert-blok pr. task, udvid eksisterende skip-liste-assert |
| `R/daa-extract/post_load_fixup.R` (eller tilsvarende) | Reload-durabel `lineage.slaegtsnavn` | Ny idempotent sektion |
| `web/src/data/model.ts`, `mobile/src/data/load.ts` | Reader-adoption | select+map → `visning_fuldt_navn` (fallback `visning_navn`) |
| `web/src/data/redaktionRead.ts`, `mobile/src/data/redaktionRead.ts` | Proveniens-badge | vis rå + afledt når `visning_efternavn IS NOT NULL` |

---

## Task 1: Cyklus-sikre lineage-graf-walkers + BEFORE-cyklus-vagt

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`

**Interfaces:**
- `lineage_ancestors(p_lineage_id BIGINT) RETURNS BIGINT[]` — linjen selv + forældre opad
  (`parent_lineage_id`), ordnet mest-specifik→rod. RAISE EXCEPTION ved cyklus/dybde>50.
- `lineage_descendants(p_lineage_id BIGINT) RETURNS SETOF BIGINT` — linjen selv + hele undertræet
  (BFS). RAISE EXCEPTION ved gen-besøgt id (cyklus i en gyldig træ-struktur er pr. definition en
  fejl) eller >500 besøgte.
- `trg_lineage_prevent_cycle()` — BEFORE-trigger på `lineage(parent_lineage_id)`; genbruger
  `lineage_ancestors` til at afvise en tildeling der ville lukke en løkke.

- [ ] **Step 1: Failing assert i `db-verify.sql`**

```sql
-- ===== Udledt slægtsnavn Task 1: lineage-graf-walkers + cyklus-vagt =====
DO $$
DECLARE v_anc BIGINT[];
BEGIN
  IF to_regprocedure('lineage_ancestors(bigint)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors mangler';
  END IF;
  -- Reventlow-linje I (kode 'I') har ingen parent_lineage_id i dag → ancestors = [sig selv]
  SELECT lineage_ancestors(id) INTO v_anc FROM lineage WHERE kode='I' LIMIT 1;
  IF v_anc IS NULL OR array_length(v_anc,1) <> 1 THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors(I) skal returnere præcis [sig selv] uden forgrening, fik %', v_anc;
  END IF;
  RAISE NOTICE 'OK: lineage_ancestors basal';
END $$;

-- Cyklus-forebyggelse: konstruér A→B→A og verificér at sidste tildeling afvises.
DO $$
DECLARE v_a BIGINT; v_b BIGINT; v_source BIGINT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_a := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn) VALUES (v_a, v_source, '__TEST_A', 'Test A');
  v_b := v_a + 1;
  INSERT INTO lineage(id, source_id, kode, navn, parent_lineage_id) VALUES (v_b, v_source, '__TEST_B', 'Test B', v_a);
  BEGIN
    UPDATE lineage SET parent_lineage_id = v_b WHERE id = v_a;  -- ville lukke løkken A→B→A
    RAISE EXCEPTION 'FEJL: cyklus A→B→A blev IKKE afvist';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%cyklus%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: cyklus A→B→A korrekt afvist (%)', SQLERRM;
  END;
  DELETE FROM lineage WHERE id IN (v_a, v_b);
END $$;
```

- [ ] **Step 2: Kør — forventet FEJL (lineage_ancestors mangler)**

- [ ] **Step 3: Tilføj funktioner + trigger i `schema.sql`** (sektion efter `lineage`-tabellen)

```sql
-- ---------- UDLEDT SLÆGTSNAVN: cyklus-sikre lineage-graf-walkers ----------
-- Bruges BÅDE til skrive-tids cyklus-forebyggelse (BEFORE-trigger) OG læse-tids
-- efternavns-opslag/subtræ-regen (spec 2026-07-03-udledt-slaegtsnavn-design.md §4.7 Pass 2/3).
-- RAISE EXCEPTION ved cyklus/dybde-overskridelse — trunkerer ALDRIG stille.
CREATE OR REPLACE FUNCTION lineage_ancestors(p_lineage_id BIGINT)
RETURNS BIGINT[] LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_path BIGINT[] := ARRAY[]::BIGINT[];
  v_current BIGINT := p_lineage_id;
BEGIN
  WHILE v_current IS NOT NULL LOOP
    IF v_current = ANY(v_path) THEN
      RAISE EXCEPTION 'lineage_ancestors: cyklus detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_path,1) IS NOT NULL AND array_length(v_path,1) > 50 THEN
      RAISE EXCEPTION 'lineage_ancestors: dybde-grænse (50) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_path := v_path || v_current;
    SELECT parent_lineage_id INTO v_current FROM lineage WHERE id = v_current;
  END LOOP;
  RETURN v_path;
END $$;

CREATE OR REPLACE FUNCTION lineage_descendants(p_lineage_id BIGINT)
RETURNS SETOF BIGINT LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_visited BIGINT[] := ARRAY[]::BIGINT[];
  v_queue BIGINT[] := ARRAY[p_lineage_id];
  v_current BIGINT; v_child BIGINT;
BEGIN
  WHILE array_length(v_queue,1) IS NOT NULL LOOP
    v_current := v_queue[1];
    v_queue := v_queue[2:array_length(v_queue,1)];
    IF v_current = ANY(v_visited) THEN
      RAISE EXCEPTION 'lineage_descendants: cyklus/gen-besøg detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_visited,1) IS NOT NULL AND array_length(v_visited,1) > 500 THEN
      RAISE EXCEPTION 'lineage_descendants: dybde-grænse (500) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_visited := v_visited || v_current;
    RETURN NEXT v_current;
    FOR v_child IN SELECT id FROM lineage WHERE parent_lineage_id = v_current LOOP
      v_queue := v_queue || v_child;
    END LOOP;
  END LOOP;
  RETURN;
END $$;

CREATE OR REPLACE FUNCTION trg_lineage_prevent_cycle()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.parent_lineage_id IS NOT NULL AND NEW.id = ANY(lineage_ancestors(NEW.parent_lineage_id)) THEN
    RAISE EXCEPTION 'lineage: parent_lineage_id-tildeling ville skabe en cyklus (lineage % → %)', NEW.id, NEW.parent_lineage_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_cycle_guard ON lineage;
CREATE TRIGGER trg_lineage_cycle_guard
  BEFORE INSERT OR UPDATE OF parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_lineage_prevent_cycle();
```

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`** (samme funktioner, `CREATE OR REPLACE`
  er allerede idempotent; triggeren via `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`)

- [ ] **Step 5: Kør asserts (OK) + commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): udledt slægtsnavn — cyklus-sikre lineage-graf-walkers"
```

---

## Task 2: `lineage.slaegtsnavn` + `person.visning_efternavn`/`visning_fuldt_navn` + skip-liste

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`

- [ ] **Step 1: Failing assert**

```sql
-- ===== Task 2: nye kolonner + skip-liste =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lineage' AND column_name='slaegtsnavn') THEN
    RAISE EXCEPTION 'FEJL: lineage.slaegtsnavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_efternavn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_efternavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_fuldt_navn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_fuldt_navn mangler';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM version_pk_registry WHERE tabel='person'
      AND skip_cols @> ARRAY['visning_efternavn','visning_fuldt_navn']
  ) THEN
    RAISE EXCEPTION 'FEJL: visning_efternavn/visning_fuldt_navn ikke i person skip_cols (OBLIGATORISK, spec §4.4)';
  END IF;
  RAISE NOTICE 'OK: nye kolonner + skip-liste';
END $$;
```

- [ ] **Step 2: Kør — forventet FEJL**

- [ ] **Step 3: Migration i `schema.sql`** (inline i `CREATE TABLE lineage`/`person` for nye
  deploys + som `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` i `db-migrations.sql` for eksisterende
  base — samme mønster som `db-migrations.sql`'s øvrige additive kolonner)

```sql
-- I schema.sql: lineage-tabellen udvides
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS slaegtsnavn TEXT;  -- families-efternavn, NULL=udeledt/ukendt
-- person-tabellen udvides (fortsat envejs-cache — invariant 4)
ALTER TABLE person ADD COLUMN IF NOT EXISTS visning_efternavn  TEXT;  -- afledt slægtsnavn; NULL = ikke afledt
ALTER TABLE person ADD COLUMN IF NOT EXISTS visning_fuldt_navn TEXT;  -- visning_navn (+ ' ' + visning_efternavn)

-- skip-liste-opdatering (OBLIGATORISK — ellers ~580 spurious change_event ved backfill)
UPDATE version_pk_registry
  SET skip_cols = (SELECT array_agg(DISTINCT c) FROM unnest(skip_cols || ARRAY['visning_efternavn','visning_fuldt_navn']) c)
  WHERE tabel = 'person';
```

(I `schema.sql`s `CREATE TABLE lineage`/`person`-blokke tilføjes kolonnerne direkte for helt nye
deploys; `db-migrations.sql` bruger `ALTER ... ADD COLUMN IF NOT EXISTS` + samme `UPDATE
version_pk_registry`-linje for at afstemme en allerede-deployet base — begge stier idempotente.)

- [ ] **Step 4: Udvid db-verify.sql's EKSISTERENDE skip-liste-assert** (~linje 314, nævnt i spec
  §4.4) til også at dække de to nye kolonner, ikke kun `visning_navn`.

- [ ] **Step 5: Kør asserts (OK) + commit**

---

## Task 3: Normalisering + suffiks-token-match (spec §4.6)

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`

**Interfaces:**
- `slaegtsnavn_normaliser(s TEXT) RETURNS TEXT[]` — NFC/case-fold + whitespace-kollaps +
  bindestreg-varianter→`-`; split på whitespace (bindestreg bevaret internt i hvert token).
- `slaegtsnavn_suffiks_match(navn TEXT, slaegtsnavn TEXT) RETURNS BOOLEAN` — TRUE hvis navnets
  AFSLUTTENDE token-sekvens == efternavnets token-sekvens.

- [ ] **Step 1: Failing assert — de 5 verificerede eksempler fra spec §4.6**

```sql
-- ===== Task 3: normalisering + suffiks-match =====
DO $$
BEGIN
  IF NOT slaegtsnavn_suffiks_match('Detlef von Reventlow', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Detlef von Reventlow" burde matche "Reventlow" (partikel)';
  END IF;
  IF slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt-Laurvig-Lehn') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" må IKKE matche "Ahlefeldt-Laurvig-Lehn" (rod ≠ gren-variant)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" burde matche rod "Ahlefeldt"';
  END IF;
  IF slaegtsnavn_suffiks_match('Anna Reventlow Hansen', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Anna Reventlow Hansen" må IKKE matche (Reventlow er mellemnavn, ikke suffiks)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X von Brockdorff', 'von Brockdorff') THEN
    RAISE EXCEPTION 'FEJL: "X von Brockdorff" burde matche fler-ords-efternavnet "von Brockdorff"';
  END IF;
  RAISE NOTICE 'OK: suffiks-token-match (5/5 spec-eksempler)';
END $$;
```

- [ ] **Step 2: Kør — forventet FEJL (funktion mangler)**

- [ ] **Step 3: Implementér i `schema.sql`**

```sql
-- ---------- UDLEDT SLÆGTSNAVN: normalisering + suffiks-match (spec §4.6) ----------
CREATE OR REPLACE FUNCTION slaegtsnavn_normaliser(s TEXT)
RETURNS TEXT[] LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_split_to_array(
    trim(regexp_replace(regexp_replace(lower(s), '[‐‑–]', '-', 'g'), '\s+', ' ', 'g')),
    '\s+'
  );
$$;

-- Suffiks-token-sekvens-match: navnets AFSLUTTENDE tokens == efternavnets tokens. Dækker
-- fler-ords-efternavne ("von Brockdorff") og undgår falsk skip når efternavnet er et mellemnavn.
CREATE OR REPLACE FUNCTION slaegtsnavn_suffiks_match(navn TEXT, slaegtsnavn TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE n_tokens TEXT[]; s_tokens TEXT[]; n_len INT; s_len INT;
BEGIN
  IF navn IS NULL OR slaegtsnavn IS NULL THEN RETURN FALSE; END IF;
  n_tokens := slaegtsnavn_normaliser(navn);
  s_tokens := slaegtsnavn_normaliser(slaegtsnavn);
  n_len := coalesce(array_length(n_tokens,1),0);
  s_len := coalesce(array_length(s_tokens,1),0);
  IF s_len = 0 OR n_len < s_len THEN RETURN FALSE; END IF;
  RETURN n_tokens[n_len - s_len + 1 : n_len] = s_tokens;
END $$;
```

- [ ] **Step 4: Spejl i `db-migrations.sql`, kør asserts (OK), commit**

---

## Task 4: `lineage_effective_slaegtsnavn` + karantæne-tabel + `regen_person_visning()`-udvidelse

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`

Dette er kerne-tasken (spec §4.5). Genskriver `regen_person_visning(pid)` til at sætte
`visning_efternavn`/`visning_fuldt_navn` efter prioritetsordenen i spec §4.5 trin 3, med:
fan-out-sikker CTE (§4.5 Pass 3-struktur), `IS DISTINCT FROM`-idempotens-guard (§4.8), og
tvetydig-karantæne med egen idempotens-nøgle (§4.8 Pass 3).

- [ ] **Step 1: Failing asserts** (5 scenarier fra spec §8: enkelt-fornavn, flere-fornavne,
  mellemnavn/Iuel, allerede-Reventlow/NULL, indgift-ægtefælle/NULL — plus fan-out→karantæne)

```sql
-- ===== Task 4: regen_person_visning-udvidelse =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_navn TEXT; v_efternavn TEXT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  -- Testlinje med kendt efternavn
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_L', 'Test-linje', 'Reventlow');

  -- (a) enkelt-fornavn, født medlem uden efternavn i visning_navn
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Conrad');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_L', 999);
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn <> 'Reventlow' OR v_fuldt <> 'Conrad Reventlow' THEN
    RAISE EXCEPTION 'FEJL: (a) enkelt-fornavn — fik efternavn=% fuldt=%', v_efternavn, v_fuldt;
  END IF;

  -- (d) allerede indeholder efternavnet → NULL, uændret visning_navn
  UPDATE person SET visning_navn = 'Detlef von Reventlow' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Detlef von Reventlow' THEN
    RAISE EXCEPTION 'FEJL: (d) allerede-Reventlow skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  -- (e) indgift-ægtefælle uden external_id → NULL
  DELETE FROM person_external_id WHERE person_id=v_p;
  UPDATE person SET visning_navn='Anna Ingift' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Anna Ingift' THEN
    RAISE EXCEPTION 'FEJL: (e) indgift skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: regen_person_visning — (a)/(d)/(e) scenarier';
END $$;

-- Fan-out → karantæne (to distinkte linjer, to distinkte efternavne)
DO $$
DECLARE v_source BIGINT; v_l1 BIGINT; v_l2 BIGINT; v_p BIGINT; v_efternavn TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_l1 := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l1, v_source, '__TEST_FO1', 'A', 'Alfa');
  v_l2 := v_l1 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l2, v_source, '__TEST_FO2', 'B', 'Beta');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Fanout Person');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_FO1', 1);
  -- to external_id-rækker for SAMME source er umuligt (PK person_id,source_id) — simulér fan-out
  -- via to sources i stedet, som join'et reelt skal håndtere generisk.
  DECLARE v_source2 BIGINT := (SELECT coalesce(max(id),0)+1 FROM source);
  BEGIN
    INSERT INTO source(id, slags, titel) VALUES (v_source2, 'DAA-udgave', 'Test-udgave 2');
    INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l2+1, v_source2, '__TEST_FO2', 'B2', 'Beta');
    INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source2, '__TEST_FO2', 1);
  END;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn INTO v_efternavn FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: fan-out (2 distinkte efternavne) skal give NULL, fik %', v_efternavn;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL: fan-out skal logges i slaegtsnavn_karantaene';
  END IF;
  -- idempotens: kør regen igen, karantæne-rækken må ikke duplikeres
  PERFORM regen_person_visning(v_p);
  IF (SELECT count(*) FROM slaegtsnavn_karantaene WHERE person_id=v_p) <> 1 THEN
    RAISE EXCEPTION 'FEJL: karantæne-log er ikke idempotent (upsert)';
  END IF;
  DELETE FROM slaegtsnavn_karantaene WHERE person_id=v_p;
  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id IN (v_l1, v_l2, v_l2+1);
  DELETE FROM source WHERE id=v_source2;
  RAISE NOTICE 'OK: fan-out → karantæne + idempotens';
END $$;
```

- [ ] **Step 2: Kør — forventet FEJL**

- [ ] **Step 3: Implementér**

```sql
CREATE TABLE IF NOT EXISTS slaegtsnavn_karantaene (
  person_id  BIGINT PRIMARY KEY REFERENCES person(id),
  n_distinct INT NOT NULL,
  noteret_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION lineage_effective_slaegtsnavn(p_lineage_id BIGINT)
RETURNS TEXT LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT l.slaegtsnavn
  FROM unnest(lineage_ancestors(p_lineage_id)) WITH ORDINALITY AS anc(id, ord)
  JOIN lineage l ON l.id = anc.id
  WHERE l.slaegtsnavn IS NOT NULL
  ORDER BY anc.ord
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_n_distinct INT;
BEGIN
  WITH navn_agg AS (
    SELECT
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')  AS navn,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='fødsel') AS foedt,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='død')    AS doed,
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='titel') AS titel
    FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN assertion  a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.subjekt_id = pid
  ),
  efternavn_cte AS (
    -- Én række pr. person_id (fan-out-vagt — spec §4.5 Pass 2/3): join'et kan i fremtiden fane ud
    -- (flere sources/linjer pr. person). GROUP BY garanterer én-til-én join mod navn_agg.
    SELECT pei.person_id,
           count(DISTINCT lineage_effective_slaegtsnavn(l.id)) AS n_distinct,
           min(lineage_effective_slaegtsnavn(l.id))            AS slaegtsnavn
    FROM person_external_id pei
    JOIN lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
    WHERE pei.person_id = pid
    GROUP BY pei.person_id
  ),
  final AS (
    SELECT
      navn_agg.navn, navn_agg.foedt, navn_agg.doed, navn_agg.titel,
      efternavn_cte.n_distinct,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(efternavn_cte.n_distinct,0) <> 1 THEN NULL
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, efternavn_cte.slaegtsnavn) THEN NULL
        ELSE efternavn_cte.slaegtsnavn
      END AS efternavn,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(efternavn_cte.n_distinct,0) <> 1 THEN navn_agg.navn
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, efternavn_cte.slaegtsnavn) THEN navn_agg.navn
        ELSE navn_agg.navn || ' ' || efternavn_cte.slaegtsnavn
      END AS fuldt
    FROM navn_agg LEFT JOIN efternavn_cte ON true
  )
  UPDATE person p SET
    visning_navn = final.navn, visning_foedt = final.foedt, visning_doed = final.doed,
    visning_titel = final.titel, visning_efternavn = final.efternavn, visning_fuldt_navn = final.fuldt
  FROM final
  WHERE p.id = pid
    AND (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn, p.visning_fuldt_navn)
        IS DISTINCT FROM (final.navn, final.foedt, final.doed, final.titel, final.efternavn, final.fuldt);

  SELECT n_distinct INTO v_n_distinct FROM (
    SELECT count(DISTINCT lineage_effective_slaegtsnavn(l.id)) AS n_distinct
    FROM person_external_id pei JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
    WHERE pei.person_id = pid
  ) sub;

  IF v_n_distinct > 1 THEN
    INSERT INTO slaegtsnavn_karantaene(person_id, n_distinct) VALUES (pid, v_n_distinct)
      ON CONFLICT (person_id) DO UPDATE SET n_distinct=excluded.n_distinct, noteret_at=now();
  ELSE
    DELETE FROM slaegtsnavn_karantaene WHERE person_id = pid;  -- selv-helbred hvis tvetydigheden er løst
  END IF;
END $$;
```

> **Bemærk:** `efternavn_cte` og den efterfølgende `v_n_distinct`-genberegning duplikerer
> fan-out-optællingen. Accepteret bevidst (læsbarhed > at presse alt ind i én CTE-kæde med
> `RETURNING`) — begge udtryk er identiske og billige (0 multi-medlemskaber i praksis i dag).

- [ ] **Step 4: Spejl i `db-migrations.sql`, kør asserts (OK), commit**

---

## Task 5: Invalidation-triggere (spec §4.7)

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`

- [ ] **Step 1: Failing assert** — opret et nyt `person_external_id` for en eksisterende person og
  verificér at `visning_fuldt_navn` opdateres UDEN eksplicit `regen_person_visning`-kald; opdatér
  `lineage.slaegtsnavn` og verificér subtræ-regen.

- [ ] **Step 2: Kør — forventet FEJL**

- [ ] **Step 3: Implementér**

```sql
CREATE OR REPLACE FUNCTION trg_regen_from_external_id()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN PERFORM regen_person_visning(NEW.person_id); END IF;
  IF TG_OP IN ('DELETE','UPDATE') THEN PERFORM regen_person_visning(OLD.person_id); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_external_id_regen ON person_external_id;
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR UPDATE OR DELETE ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();

CREATE OR REPLACE FUNCTION trg_regen_from_lineage()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_lid BIGINT; v_pid BIGINT;
BEGIN
  IF (NEW.slaegtsnavn IS DISTINCT FROM OLD.slaegtsnavn) OR (NEW.parent_lineage_id IS DISTINCT FROM OLD.parent_lineage_id) THEN
    FOR v_lid IN SELECT id FROM lineage_descendants(NEW.id) LOOP
      FOR v_pid IN
        SELECT DISTINCT pei.person_id FROM person_external_id pei
        JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
        WHERE l.id = v_lid
      LOOP
        PERFORM regen_person_visning(v_pid);
      END LOOP;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_regen ON lineage;
CREATE TRIGGER trg_lineage_regen
  AFTER UPDATE OF slaegtsnavn, parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_lineage();
```

- [ ] **Step 4: Spejl i `db-migrations.sql`, kør asserts (OK), commit**

---

## Task 6: Empirisk verifikation mod ALLE 923 personer (lokal kopi)

**Files:** ingen kode — kun `psql`-udforskning mod `daa_test` (redskabet til at bekræfte spec §2's
empiriske tabel stadig holder, og at backfillen opfører sig som forventet FØR den køres mod prod)

- [ ] **Step 1:** Sæt `lineage.slaegtsnavn='Reventlow'` på alle 5 Reventlow-linjer i `daa_test`
  (midlertidigt, til dette verifikationstrin — den DURABLE tildeling laves i Task 7's
  `post_load_fixup.R`, ikke her).
- [ ] **Step 2:** `SELECT regen_person_visning(id) FROM person;` (backfill-dry-run, `daa_test`).
- [ ] **Step 3:** Verificér tallene fra spec §2 stadig holder (± drift siden 2026-07-03):
  - Fødte medlemmer uden "Reventlow" i `visning_navn` → nu har `visning_efternavn='Reventlow'`.
  - De ~11 "von/de Reventlow" → `visning_efternavn IS NULL`, `visning_fuldt_navn=visning_navn`.
  - Ingen uventede `slaegtsnavn_karantaene`-rækker (0 forventet, jf. "medlemskab entydigt i dag").
- [ ] **Step 4:** Kør TNG-QA's matcher-trin (`R/tng-qa/04-match.R`) mod `daa_test` og verificér at
  match-nøglerne er UÆNDREDE (den læser fortsat rå `visning_navn`, ikke de nye kolonner).
- [ ] **Step 5:** `ROLLBACK`/nulstil `daa_test` til ren backfill-fri tilstand (eller blot lad
  ændringerne stå — `daa_test` er en engangs-kopi, ingen grund til at rulle tilbage medmindre
  Task 7 skal testes på en frisk kopi).

---

## Task 7: `post_load_fixup.R` — reload-durabel `lineage.slaegtsnavn`-tildeling

**Files:** `R/daa-extract/post_load_fixup.R` (eller den fil der allerede sætter lineage-navne —
verificér eksakt filnavn/sti i repo'et, spec/changelog nævner "genoprettet i idempotent
post_load_fixup.R" for lineage-navne tidligere)

- [ ] **Step 1:** Find den eksisterende lineage-navn-tildelings-sektion (samme fil sætter allerede
  `lineage.navn` idempotent efter et `--force-reset`-reload — se changelog 2026-07-02 "Redaktør-
  profil + lineage-navne genoprettet i idempotent post_load_fixup.R").
- [ ] **Step 2:** Tilføj en tilsvarende idempotent sektion der sætter
  `UPDATE lineage SET slaegtsnavn='Reventlow' WHERE source_id=<Reventlow-source> AND kode IN ('I','II','III','IV','V')`
  — keyed på `source_id`+`kode` (reload-invariant), IKKE `lineage.id` (som kan skifte ved reload).
- [ ] **Step 3:** Kør scriptet mod `daa_test` (ELLER en frisk `--force-reset`-kopi hvis tiden
  tillader) og verificér idempotens (kør 2×, samme slutresultat, ingen fejl).
- [ ] **Step 4: Commit**

```bash
git add R/daa-extract/post_load_fixup.R
git commit -m "feat(r): reload-durabel lineage.slaegtsnavn-tildeling (post_load_fixup.R)"
```

---

## Task 8: Frontend reader-adoption (web + mobile)

**Files:** `web/src/data/model.ts`, `mobile/src/data/load.ts`, `web/src/data/redaktionRead.ts`,
`mobile/src/data/redaktionRead.ts`

- [ ] **Step 1:** `model.ts`/`load.ts`: udvid select til at inkludere `visning_efternavn` (kun til
  badge-brug, se nedenfor) og skift navne-mapping fra `visning_navn` til
  `visning_fuldt_navn ?? visning_navn` (fallback — midlertidig kompat, spec §4.9).
- [ ] **Step 2:** `redaktionRead.ts` (web+mobile): vis rå `visning_navn` OG et badge "efternavn
  afledt af linje" når `visning_efternavn IS NOT NULL` (proveniens/gennemsigtighed, spec §4.4
  punkt 2).
- [ ] **Step 3:** `R/tng-qa/*` — INGEN ændring (bevidst, spec §2 KRITISK — de læser fortsat rå
  `visning_navn`). Verificér ved grep at ingen af disse filer refererer de nye kolonner.
- [ ] **Step 4:** TDD: web+mobile enhedstest på map-funktionen (fallback når `visning_fuldt_navn`
  er NULL pre-backfill, korrekt værdi post-backfill).
- [ ] **Step 5:** `tsc --noEmit` + hele test-suiten (web + mobile) grøn.
- [ ] **Step 6: Commit**

---

## Task 9: STOP-GATE — prod-migration + backfill (kræver eksplicit bruger-godkendelse)

**IKKE udført autonomt.** Når Task 1-8 er grønne lokalt (`daa_test`) og på main-branchen som PR/
merge-klar, præsentér for brugeren:

1. Diff af `schema.sql`/`db-migrations.sql` (additive, non-breaking).
2. Backfill-recept (spec §4.8): én transaktion, `REPEATABLE READ`/`SERIALIZABLE` isolation (eller
   eksplicit rækkelås), `SELECT regen_person_visning(id) FROM person;` — idempotent, fortrydbart
   via at rydde `lineage.slaegtsnavn` + re-regenerere (IKKE et `change_set`-restore — cache
   restores ikke, den regenereres, spec §4.8).
3. Cutover-orden (spec §4.9, mirroring flere-narrativer-mønsteret): additive kolonner til prod →
   deploy readers (fallback `visning_fuldt_navn ?? visning_navn`, sikkert FØR backfill) → backfill
   → fulde navne dukker op.
4. TNG-QA regression: kør match-suiten EFTER backfill, bekræft grøn (spec §7).

Afvent EKSPLICIT bruger-godkendelse før `mcp__supabase__apply_migration`/`execute_sql` mod prod
(global regel §5 git-gates + "Executing actions with care" — hard-to-reverse, delt system).
