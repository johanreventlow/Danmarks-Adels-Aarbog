# Versionering + Hyperlinks — DB-lag Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg Postgres/Supabase-laget for (1) en fuld, fortryd-bar redaktionel ændringshistorik og (2) hyperlinks i fri-tekst med afledt nævne-indeks — additivt ovenpå den eksisterende evidensmodel.

**Architecture:** En hybrid change-set-log: hver `red_*`-RPC åbner et re-entrant `change_set` via en transaktions-lokal session-variabel; en generisk row-level-trigger (`log_change`) snapshotter før/efter-tilstand af hver rørt række til `change_event`, styret af et table→PK/skip-kolonne-registry. Restore inverse-applier et change_set i én transaktion med optimistisk verifikation. Hyperlinks lagres som inline-tokens i teksten og projiceres til et regenereret `text_mention`-indeks via en parser-funktion.

**Tech Stack:** PostgreSQL 15 (Supabase), PL/pgSQL, `db-migrations.sql` (idempotent), `db-verify.sql` (DO-block-asserts kørt via `psql` mod en branch/kopi-base).

## Global Constraints

- **Source of truth:** alle skema-objekter tilføjes BÅDE i `schema.sql` (kanonisk) OG som idempotent blok i `db-migrations.sql` (afstemmer deployet base). (CLAUDE.md §5)
- **Idempotens:** hver migration kan køres flere gange uden fejl (`CREATE ... IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS` før `CREATE TRIGGER`).
- **Påstande er uforanderlige:** rettelser = ny påstand + ny konklusion, aldrig `UPDATE assertion` (invariant #1; lukker spec-B5).
- **Cache-felter (`person.visning_*`) redigeres/versioneres aldrig:** afledt envejs-projektion (invariant #4; spec-B8).
- **Rolle-gating:** enhver skrive-RPC starter med `IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;` (eksisterende mønster).
- **ID-tildeling:** følg basens eksisterende `(SELECT coalesce(max(id),0)+1 FROM <tabel>)`-mønster (single-writer-PoC).
- **Ingen secrets i kode/git:** DB-forbindelse via `~/.Renviron`/miljøvariabel. (CLAUDE.md §7)
- **Test mod KOPI/branch-base, aldrig prod** (db-verify.sql-header).
- **Sprog:** dansk i kommentarer, kolonnenavne, NOTICE-tekster (matcher kodebasen).
- **Commit-stil:** Conventional Commits, dansk. Ingen Claude-attribution-footer. Afslut commit-besked med `Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd`.

**Spec:** `docs/superpowers/specs/2026-06-30-versionering-og-hyperlinks-design.md` (beslutninger B1-B12, findings-sporing Bilag A).

---

## Sådan køres tests

`db-verify.sql` udvides task-for-task med DO-block-asserts. Kør hele filen mod en branch/kopi-base:

```bash
# Forbindelse fra miljø (Session pooler, sslmode=require). Eksempel:
psql "$SUPABASE_DB_URL_BRANCH" -v ON_ERROR_STOP=1 -f db-migrations.sql
psql "$SUPABASE_DB_URL_BRANCH" -v ON_ERROR_STOP=1 -f db-verify.sql 2>&1 | grep -E 'OK:|FEJL|EXCEPTION|NOTICE'
```

Et assert er en `DO $$ ... RAISE NOTICE 'OK: ...' / RAISE EXCEPTION 'FEJL: ...' ... $$`-blok. TDD-cyklus pr. task: tilføj assert → kør (FEJL, objekt mangler) → tilføj migration → kør (OK).

**Redaktion-happy-path:** SQL Editor/`psql` kører som ejer → `auth.uid()` er NULL → `current_rolle()='medlem'`. For at teste redaktion-stier wrappes happy-path-asserts i `SET LOCAL ROLE` ikke nok (RPC'er er SECURITY DEFINER og tjekker `current_rolle()`). Brug i stedet en midlertidig profil-seed mønster pr. assert:

```sql
-- happy-path-skabelon: seed redaktion for en kendt uid, kør, ryd op i samme txn
DO $$
DECLARE v_uid uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- current_rolle() læser auth.uid(); i SQL Editor er den NULL, så vi kan ikke
  -- forfalske auth.uid() uden GUC. I stedet testes redaktion-stier ved at kalde
  -- den interne logik via SECURITY DEFINER fra en seedet redaktion-session i app-
  -- laget (fremtidig jest), ELLER ved midlertidigt at overstyre current_rolle.
  NULL;
END $$;
```

Fordi `current_rolle()` afhænger af `auth.uid()`, defineres en **test-bypass**: I `db-verify.sql` oprettes øverst en GUC-baseret override som `current_rolle()` allerede respekterer? Den gør den ikke i dag. Derfor: happy-path for skrive-RPC'er verificeres ved at kalde funktionerne **som funktionsejer med en seedet profil** via følgende mønster, der sætter en rigtig række i `profiles` for en fast uid og bruger `set_config('request.jwt.claim.sub', uid, true)` (SupabDjango GoTrue-mønster som `auth.uid()` læser):

```sql
DO $$
DECLARE v_uid uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true); -- auth.uid() læser denne
  INSERT INTO profiles(id, rolle, email) VALUES (v_uid,'redaktion','test@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  -- ... kald RPC, assert ...
END $$;
```

> Verificér i Task 1's assert at `set_config('request.jwt.claim.sub', ...)` faktisk får `auth.uid()` til at returnere uid'en på jeres Supabase-version; hvis ikke, falder happy-path-asserts tilbage til app-lagets jest (noteret pr. task).

---

## Filstruktur

| Fil | Ansvar | Ændring |
|---|---|---|
| `schema.sql` | Kanonisk skema | Tilføj: registry-tabel, `change_set`, `change_event`, `text_mention`, alle funktioner/triggere |
| `db-migrations.sql` | Idempotent afstemning | Spejl alle nye objekter idempotent |
| `db-verify.sql` | Verifikations-asserts | Tilføj assert-blok pr. task |
| `db-rls.sql` | RLS-politikker (review-artefakt) | Tilføj deny-all + grants for historik-tabeller (Task 11) |

Ingen app/TS-filer i denne plan (spec §5.4 — separat plan).

---

## Task 1: Table→PK/skip-kolonne-registry

**Files:**
- Modify: `schema.sql` (ny sektion efter `vocab`)
- Modify: `db-migrations.sql` (ny idempotent blok)
- Test: `db-verify.sql` (ny assert-blok "Versionering Task 1")

**Interfaces:**
- Produces: tabel `version_pk_registry(tabel text PK, pk_cols text[], skip_cols text[])`; seeded for alle versionerede tabeller (spec §4.3.1).

- [ ] **Step 1: Skriv failing assert i `db-verify.sql`**

```sql
-- ===== Versionering Task 1: PK-registry =====
DO $$
BEGIN
  IF to_regclass('public.version_pk_registry') IS NULL THEN
    RAISE EXCEPTION 'FEJL: version_pk_registry mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='family_member'
                 AND pk_cols = ARRAY['family_id','person_id','rolle']) THEN
    RAISE EXCEPTION 'FEJL: family_member composite PK ikke registreret korrekt';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='person'
                 AND skip_cols @> ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel']) THEN
    RAISE EXCEPTION 'FEJL: person visning_* ikke i skip_cols';
  END IF;
  RAISE NOTICE 'OK: version_pk_registry seeded';
END $$;
```

- [ ] **Step 2: Kør for at se den fejle**

Run: `psql "$SUPABASE_DB_URL_BRANCH" -v ON_ERROR_STOP=1 -f db-verify.sql`
Expected: `ERROR: FEJL: version_pk_registry mangler`

- [ ] **Step 3: Tilføj tabel + seed i `schema.sql`**

```sql
-- ---------- VERSIONERING: PK/skip-kolonne-registry ----------
-- Styrer den generiske log_change-trigger: hvilke kolonner udgør PK (→ row_pk)
-- og hvilke kolonner springes over i snapshot (afledt cache; spec-B8/B11).
CREATE TABLE IF NOT EXISTS version_pk_registry (
  tabel     TEXT PRIMARY KEY,
  pk_cols   TEXT[] NOT NULL,
  skip_cols TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('person',             ARRAY['id'], ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel']),
  ('person_external_id', ARRAY['person_id','source_id'], '{}'),
  ('family',             ARRAY['id'], '{}'),
  ('family_member',      ARRAY['family_id','person_id','rolle'], '{}'),
  ('fact',               ARRAY['id'], '{}'),
  ('relation',           ARRAY['id'], '{}'),
  ('assertion',          ARRAY['id'], '{}'),
  ('conclusion',         ARRAY['id'], '{}'),
  ('citation',           ARRAY['id'], '{}'),
  ('narrative',          ARRAY['id'], '{}'),
  ('note',               ARRAY['id'], '{}'),
  ('source',             ARRAY['id'], '{}'),
  ('repository',         ARRAY['id'], '{}'),
  ('place',              ARRAY['id'], '{}'),
  ('organisation',       ARRAY['id'], '{}'),
  ('estate',             ARRAY['id'], '{}'),
  ('media',              ARRAY['id'], '{}'),
  ('historical_event',   ARRAY['id'], '{}'),
  ('coat_of_arms',       ARRAY['id'], '{}'),
  ('lineage',            ARRAY['id'], '{}'),
  ('vocab',              ARRAY['scheme','code'], '{}'),
  ('profiles',           ARRAY['id'], ARRAY['email','rolle'])  -- versionér kun reventlow_person_id-binding (spec §4.3.1)
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;
```

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`**

Kopiér NØJAGTIGT samme `CREATE TABLE IF NOT EXISTS` + `INSERT ... ON CONFLICT`-blok ind i `db-migrations.sql` under en ny kommentar-overskrift `-- 2026-06-30: versionering — PK-registry`.

- [ ] **Step 5: Kør asserts (OK)**

Run: `psql "$SUPABASE_DB_URL_BRANCH" -v ON_ERROR_STOP=1 -f db-migrations.sql && psql "$SUPABASE_DB_URL_BRANCH" -v ON_ERROR_STOP=1 -f db-verify.sql 2>&1 | grep 'Task 1'`
Expected: `NOTICE: OK: version_pk_registry seeded`

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — table→PK/skip-kolonne-registry

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 2: `change_set` + `change_event` tabeller

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Produces: tabel `change_set` (kolonner pr. spec §4.1) og `change_event` (spec §4.2); indeks på `change_event(change_set_id, seq)` og `change_set(subjekt_type, subjekt_id)`.

- [ ] **Step 1: Skriv failing assert**

```sql
-- ===== Versionering Task 2: change_set/change_event =====
DO $$
BEGIN
  IF to_regclass('public.change_set') IS NULL OR to_regclass('public.change_event') IS NULL THEN
    RAISE EXCEPTION 'FEJL: change_set/change_event mangler';
  END IF;
  -- actor_id skal være ON DELETE SET NULL (spec-B3/H6)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.referential_constraints rc
    JOIN information_schema.key_column_usage k ON k.constraint_name=rc.constraint_name
    WHERE k.table_name='change_set' AND k.column_name='actor_id' AND rc.delete_rule='SET NULL') THEN
    RAISE EXCEPTION 'FEJL: change_set.actor_id mangler ON DELETE SET NULL';
  END IF;
  RAISE NOTICE 'OK: change_set/change_event findes m. korrekt actor-FK';
END $$;
```

- [ ] **Step 2: Kør → FEJL** (`change_set/change_event mangler`)

- [ ] **Step 3: Tilføj tabeller i `schema.sql`**

```sql
-- ---------- VERSIONERING: change_set / change_event ----------
CREATE TABLE IF NOT EXISTS change_set (
  id                BIGINT PRIMARY KEY,
  actor_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,  -- frosne felter er autoritative (B3)
  actor_navn        TEXT,
  actor_rolle       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  operation         TEXT,
  summary           TEXT,
  subjekt_type      TEXT,
  subjekt_id        BIGINT,
  subjekt_synlighed TEXT,                       -- frosset: 'offentlig'|'levende'|'privat' (C1-sti)
  reverterer_id     BIGINT REFERENCES change_set(id)  -- dette sæt fortrød hvilket (reversal-kæde; M3)
);

CREATE TABLE IF NOT EXISTS change_event (
  id            BIGINT PRIMARY KEY,
  change_set_id BIGINT NOT NULL REFERENCES change_set(id),
  seq           INT NOT NULL,
  tabel         TEXT NOT NULL,
  row_pk        JSONB NOT NULL,
  op            TEXT NOT NULL CHECK (op IN ('INSERT','UPDATE','DELETE')),
  foer          JSONB,
  efter         JSONB
);

CREATE INDEX IF NOT EXISTS ix_change_event_set  ON change_event(change_set_id, seq);
CREATE INDEX IF NOT EXISTS ix_change_set_subjekt ON change_set(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_change_set_revert  ON change_set(reverterer_id);
```

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`** (samme blok under `-- 2026-06-30: versionering — change_set/change_event`).

- [ ] **Step 5: Kør asserts → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — change_set/change_event tabeller

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 3: `begin_change_set` (re-entrant) + synligheds-beregning

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `change_set` (Task 2), `current_rolle()`, `profiles`.
- Produces: `begin_change_set(operation text, summary text, subjekt_type text, subjekt_id bigint) RETURNS bigint` — re-entrant (B7); sætter `app.change_set_id` + `app.change_seq`. Hjælper `_subjekt_synlighed(stype text, sid bigint) RETURNS text`.

- [ ] **Step 1: Skriv failing assert (re-entrancy)**

```sql
-- ===== Versionering Task 3: begin_change_set re-entrant =====
DO $$
DECLARE a bigint; b bigint;
BEGIN
  PERFORM set_config('app.change_set_id', '', true);  -- nulstil
  a := begin_change_set('test_op','sum','person',1);
  b := begin_change_set('indre_op','sum2','person',1); -- nested → skal genbruge a
  IF a <> b THEN RAISE EXCEPTION 'FEJL: nested begin_change_set gav nyt id (% <> %)', a, b; END IF;
  IF current_setting('app.change_set_id', true) <> a::text THEN
    RAISE EXCEPTION 'FEJL: session-variabel ikke sat'; END IF;
  DELETE FROM change_set WHERE id=a;  -- oprydning
  PERFORM set_config('app.change_set_id', '', true);
  RAISE NOTICE 'OK: begin_change_set er re-entrant';
END $$;
```

- [ ] **Step 2: Kør → FEJL** (funktion findes ikke)

- [ ] **Step 3: Tilføj funktioner i `schema.sql`**

```sql
-- ---------- VERSIONERING: begin_change_set ----------
-- Synligheds-klasse på subjektet, frosset på commit-tid (C1-sti for fremtidig
-- medlems-historik). Kun person har levende/privat; øvrige = 'offentlig'.
CREATE OR REPLACE FUNCTION _subjekt_synlighed(p_type text, p_id bigint)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN p_type='person' THEN (
      SELECT CASE WHEN coalesce(pr.privat,false) THEN 'privat'
                  WHEN coalesce(pr.levende,false) THEN 'levende'
                  ELSE 'offentlig' END
      FROM person pr WHERE pr.id=p_id)
    ELSE 'offentlig' END;
$$;

-- Re-entrant: yderste kald ejer change_set'et; indre kald genbruger det aktive (B7).
CREATE OR REPLACE FUNCTION begin_change_set(
  p_operation text, p_summary text, p_subjekt_type text DEFAULT NULL, p_subjekt_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing text; v_id bigint; v_uid uuid; v_navn text; v_rolle text;
BEGIN
  v_existing := current_setting('app.change_set_id', true);
  IF v_existing IS NOT NULL AND v_existing <> '' THEN
    RETURN v_existing::bigint;  -- genbrug aktivt sæt; opret intet, nulstil intet
  END IF;
  v_uid := auth.uid();
  SELECT coalesce(p.email, v_uid::text), p.rolle INTO v_navn, v_rolle
    FROM profiles p WHERE p.id = v_uid;
  v_navn  := coalesce(v_navn, 'ukendt');
  v_rolle := coalesce(v_rolle, 'medlem');
  v_id := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed)
    VALUES (v_id, v_uid, v_navn, v_rolle, p_operation, p_summary,
            p_subjekt_type, p_subjekt_id, _subjekt_synlighed(p_subjekt_type, p_subjekt_id));
  PERFORM set_config('app.change_set_id', v_id::text, true);
  PERFORM set_config('app.change_seq', '0', true);
  RETURN v_id;
END $$;
```

> **Bemærk navn-kilde:** Task 10 tilføjer `profiles.navn`; indtil da bruges `email`. Når Task 10 er kørt, ændres `coalesce(p.email, ...)` til `coalesce(p.navn, p.email, v_uid::text)`. Det er noteret i Task 10.

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`** (begge `CREATE OR REPLACE FUNCTION` — de er selv-idempotente).

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — re-entrant begin_change_set + synligheds-snapshot

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 4: Generisk `log_change`-trigger + tilknytning

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `version_pk_registry` (T1), `change_event` (T2), `app.change_set_id`/`app.change_seq` (T3).
- Produces: `log_change() RETURNS trigger`; triggere `trg_log_<tabel>` på alle registrerede tabeller. Hjælper `_row_pk(p_tabel text, p_row jsonb) RETURNS jsonb`.

- [ ] **Step 1: Skriv failing assert (logning kun når change_set aktiv; skip visning_*)**

```sql
-- ===== Versionering Task 4: log_change trigger =====
DO $$
DECLARE cs bigint; n int; ev change_event;
BEGIN
  -- (a) UDEN aktivt change_set: en UPDATE logges IKKE (bulk-load-sti)
  PERFORM set_config('app.change_set_id','',true);
  UPDATE person SET status=status WHERE id=(SELECT id FROM person LIMIT 1);
  -- (b) MED aktivt change_set: en ægte ændring logges
  cs := begin_change_set('test_log','t','person',NULL);
  UPDATE person SET status='__verify__' WHERE id=(SELECT id FROM person LIMIT 1);
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs AND tabel='person';
  IF n <> 1 THEN RAISE EXCEPTION 'FEJL: forventede 1 person-event, fik %', n; END IF;
  -- (c) visning_* ekskluderet fra snapshot
  SELECT * INTO ev FROM change_event WHERE change_set_id=cs AND tabel='person' LIMIT 1;
  IF ev.efter ? 'visning_navn' THEN RAISE EXCEPTION 'FEJL: visning_navn ikke ekskluderet'; END IF;
  -- (d) kun-visning-ændring logges IKKE
  UPDATE person SET visning_navn='__x__' WHERE id=(ev.row_pk->>'id')::bigint;
  IF (SELECT count(*) FROM change_event WHERE change_set_id=cs AND tabel='person') <> 1 THEN
    RAISE EXCEPTION 'FEJL: kun-cache-ændring blev logget'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';  -- rul alt tilbage (vi muterede rigtige rækker)
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: log_change logger korrekt (rullet tilbage)';
    ELSE RAISE; END IF;
END $$;
```

> Hele blokken kører i én implicit txn; den afsluttende `RAISE EXCEPTION 'ROLLBACK_TEST_OK'` ruller mutationerne tilbage, så rigtige data ikke ændres.

- [ ] **Step 2: Kør → FEJL** (trigger findes ikke → `n=0`)

- [ ] **Step 3: Tilføj trigger-funktion + hjælper i `schema.sql`**

```sql
-- ---------- VERSIONERING: generisk log_change ----------
-- Byg kanonisk row_pk fra registry'ets pk_cols.
CREATE OR REPLACE FUNCTION _row_pk(p_tabel text, p_row jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_object_agg(k, p_row->k), '{}'::jsonb)
  FROM version_pk_registry r, unnest(r.pk_cols) k
  WHERE r.tabel = p_tabel;
$$;

CREATE OR REPLACE FUNCTION log_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cs text; v_seq int; v_skip text[];
  v_foer jsonb; v_efter jsonb;
BEGIN
  v_cs := current_setting('app.change_set_id', true);
  IF v_cs IS NULL OR v_cs = '' THEN RETURN NULL; END IF;  -- bulk-load-sti: ingen logning

  SELECT skip_cols INTO v_skip FROM version_pk_registry WHERE tabel = TG_TABLE_NAME;
  v_skip := coalesce(v_skip, '{}');

  -- projektion: fjern skip-kolonner (afledt cache; B8)
  v_foer  := CASE WHEN TG_OP='INSERT' THEN NULL ELSE (to_jsonb(OLD) - v_skip) END;
  v_efter := CASE WHEN TG_OP='DELETE' THEN NULL ELSE (to_jsonb(NEW) - v_skip) END;

  -- no-op-skip: hvis kun skip-kolonner ændrede sig (fx ren cache-regen), log intet
  IF TG_OP='UPDATE' AND v_foer = v_efter THEN RETURN NULL; END IF;

  v_seq := coalesce(nullif(current_setting('app.change_seq', true),''),'0')::int + 1;
  PERFORM set_config('app.change_seq', v_seq::text, true);

  INSERT INTO change_event(id, change_set_id, seq, tabel, row_pk, op, foer, efter)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event),
          v_cs::bigint, v_seq, TG_TABLE_NAME,
          _row_pk(TG_TABLE_NAME, coalesce(to_jsonb(NEW), to_jsonb(OLD))),
          TG_OP, v_foer, v_efter);
  RETURN NULL;
END $$;
```

- [ ] **Step 4: Tilknyt trigger til alle registrerede tabeller (idempotent loop)**

Tilføj i `schema.sql` OG `db-migrations.sql`:

```sql
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tabel FROM version_pk_registry LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_log_%1$s ON %1$I', r.tabel);
    EXECUTE format('CREATE TRIGGER trg_log_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I '
                || 'FOR EACH ROW EXECUTE FUNCTION log_change()', r.tabel);
  END LOOP;
END $$;
```

- [ ] **Step 5: Kør assert → OK** (`OK: log_change logger korrekt (rullet tilbage)`)

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — generisk log_change-trigger m. kolonne-projektion

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 5: Wire `begin_change_set` ind i eksisterende `red_*`-RPC'er

**Files:**
- Modify: `schema.sql` (alle `red_*`-funktioner), `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `begin_change_set` (T3).
- Produces: hver `red_*`-skrive-RPC åbner et change_set som første handling efter rolle-tjek.

- [ ] **Step 1: Skriv failing assert (én RPC grupperer sine rækker i ét change_set)**

```sql
-- ===== Versionering Task 5: RPC-wiring =====
DO $$
DECLARE r jsonb; cs bigint; n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','__verify__',NULL,NULL,NULL,NULL,'testkilde');
  -- find seneste change_set og tæl events (fact+assertion+citation+conclusion = 4)
  SELECT max(id) INTO cs FROM change_set;
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs;
  IF n < 4 THEN RAISE EXCEPTION 'FEJL: red_opret_fakta grupperede ikke 4 rækker (fik %)', n; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: RPC grupperer rækker i ét change_set';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør → FEJL** (`n=0`, ingen change_set åbnet)

- [ ] **Step 3: Tilføj `begin_change_set`-kald i hver skrive-RPC**

I `schema.sql`, indsæt som FØRSTE linje efter `IF current_rolle() <> 'redaktion' ... END IF;` i hver af: `red_upsert_fakta`, `red_tilfoej_oplysning`, `red_opret_fakta`, `red_set_konklusion`, `red_edit_oplysning`, `red_slet_oplysning`, `red_set_koen`, `red_set_privat`, `red_slet_person`, `red_upsert_narrativ`, `red_relation`, `red_slet_relation`, `red_tilfoej_relation`, `red_opret_union`, `red_set_familie_konfidens`, `red_slet_familie_link`, `red_tilfoej_barn`.

Mønster (tilpas `summary` + subjekt pr. funktion):

```sql
  PERFORM begin_change_set('red_opret_fakta',
    format('Oprettede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id),
    p_subjekt_type, p_subjekt_id);
```

For funktioner uden subjekt-args (fx `red_set_konklusion(p_assertion_id)`): udled subjekt fra assertion'ens fact, ellers send NULL:

```sql
  PERFORM begin_change_set('red_set_konklusion', format('Satte konklusion til oplysning %s', p_assertion_id), NULL, NULL);
```

> `red_suggest` versioneres IKKE (staging; ikke i registry) → tilføj IKKE `begin_change_set` der.

- [ ] **Step 4: Spejl alle ændrede funktioner idempotent i `db-migrations.sql`** (`CREATE OR REPLACE FUNCTION` er selv-idempotent — kopiér de opdaterede definitioner).

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — åbn change_set i alle red_*-RPC'er

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 6: `red_edit_oplysning` → append (uforanderlige påstande)

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `begin_change_set` (T3), `assertion`/`conclusion`.
- Produces: `red_edit_oplysning` opretter NY assertion + re-peger konklusion via intern logik (ikke nested RPC — B7); gammel assertion bevares.

- [ ] **Step 1: Skriv failing assert (gammel assertion bevares; ny vælges)**

```sql
-- ===== Versionering Task 6: red_edit_oplysning append =====
DO $$
DECLARE v_fact bigint; v_old bigint; v_concl_valgt bigint; n_before int; n_after int; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','gammel',NULL,NULL,NULL,NULL,'k');
  v_old := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT count(*) INTO n_before FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_edit_oplysning(v_old, 'rettet', NULL, NULL);
  SELECT count(*) INTO n_after FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  IF n_after <> n_before + 1 THEN RAISE EXCEPTION 'FEJL: edit oprettede ikke ny assertion (% -> %)', n_before, n_after; END IF;
  IF NOT EXISTS (SELECT 1 FROM assertion WHERE id=v_old AND vaerdi_tekst='gammel') THEN
    RAISE EXCEPTION 'FEJL: gammel assertion blev muteret/slettet'; END IF;
  SELECT valgt_assertion_id INTO v_concl_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=v_concl_valgt) <> 'rettet' THEN
    RAISE EXCEPTION 'FEJL: konklusion peger ikke på ny værdi'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: red_edit_oplysning er append';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør → FEJL** (nuværende `red_edit_oplysning` muterer in-place → `n_after = n_before`)

- [ ] **Step 3: Omskriv `red_edit_oplysning` i `schema.sql`**

```sql
-- Append-baseret edit: bevarer den gamle påstand (invariant #1), opretter ny + re-peger
-- konklusion via INTERN logik (ikke red_set_konklusion-RPC → undgår nested change_set, B7).
CREATE OR REPLACE FUNCTION red_edit_oplysning(
  p_assertion_id bigint, p_vaerdi text, p_date_raw text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_tt text; v_tid bigint; v_old assertion; v_new bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_edit_oplysning', format('Rettede oplysning %s', p_assertion_id), NULL, NULL);
  SELECT * INTO v_old FROM assertion WHERE id=p_assertion_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, date_min, date_max,
                        date_qualifier, date_raw, calendar, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), v_old.target_type, v_old.target_id,
            p_vaerdi, v_old.date_min, v_old.date_max, v_old.date_qualifier,
            coalesce(p_date_raw, v_old.date_raw), v_old.calendar, false)
    RETURNING id INTO v_new;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_new, NULL,
            coalesce(p_kilde_fritekst, '(kilde mangler)'))
    RETURNING id INTO v_cit;

  -- intern re-peg (ikke RPC): kun hvis den gamle påstand var den valgte
  UPDATE conclusion SET valgt_assertion_id=v_new, blaastemplet_naar=current_date
    WHERE target_type=v_old.target_type AND target_id=v_old.target_id
      AND valgt_assertion_id=p_assertion_id;
  IF NOT FOUND THEN
    INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_old.target_type, v_old.target_id,
              v_new, 'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id) DO UPDATE SET valgt_assertion_id=v_new, blaastemplet_naar=current_date;
  END IF;

  RETURN jsonb_build_object('ny_assertion_id', v_new, 'citation_id', v_cit);
END $$;
```

> **Returtype-skift:** gammel signatur returnerede `void`; ny returnerer `jsonb`. `CREATE OR REPLACE` afviser returtype-ændring → migrationen skal `DROP FUNCTION IF EXISTS red_edit_oplysning(bigint,text,text,text);` FØR `CREATE`. App-laget (jest-mock i `mobile/src/data/redaktionWrite.ts`) skal opdateres til at læse `ny_assertion_id` — noteres i den separate app-plan; bryder ikke DB-asserts.

- [ ] **Step 4: I `db-migrations.sql`: `DROP FUNCTION IF EXISTS` + ny definition**

```sql
-- 2026-06-30: red_edit_oplysning skifter void -> jsonb (append)
DROP FUNCTION IF EXISTS red_edit_oplysning(bigint, text, text, text);
-- (efterfulgt af CREATE OR REPLACE FUNCTION ... fra Step 3)
```

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "refactor(db): red_edit_oplysning append-baseret (uforanderlige påstande)

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 7: Generiske restore-hjælpere (`_version_upsert_row`, `_version_delete_row`)

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `version_pk_registry` (T1).
- Produces: `_version_upsert_row(p_tabel text, p_row jsonb)` (insert-or-update til nøjagtig snapshot-tilstand); `_version_delete_row(p_tabel text, p_pk jsonb)`; `_version_current_row(p_tabel text, p_pk jsonb) RETURNS jsonb` (nuværende projicerede række eller NULL).

- [ ] **Step 1: Skriv failing assert (round-trip på en testtabel-række)**

```sql
-- ===== Versionering Task 7: restore-hjælpere =====
DO $$
DECLARE v_id bigint; cur jsonb;
BEGIN
  v_id := (SELECT coalesce(max(id),0)+1 FROM note);
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','A','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'A' THEN RAISE EXCEPTION 'FEJL: upsert insert virkede ikke'; END IF;
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','B','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'B' THEN RAISE EXCEPTION 'FEJL: upsert update virkede ikke'; END IF;
  PERFORM _version_delete_row('note', jsonb_build_object('id',v_id));
  IF _version_current_row('note', jsonb_build_object('id',v_id)) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: delete virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore-hjælpere round-trip';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør → FEJL** (funktioner findes ikke)

- [ ] **Step 3: Tilføj hjælpere i `schema.sql`**

```sql
-- ---------- VERSIONERING: restore-hjælpere ----------
-- WHERE-klausul fra pk-jsonb med korrekt type-cast pr. kolonne (via udt_name).
CREATE OR REPLACE FUNCTION _version_pk_where(p_tabel text, p_pk jsonb)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT string_agg(format('%I = (%L)::%s', c.column_name, p_pk->>c.column_name, c.udt_name), ' AND ')
  FROM version_pk_registry r, unnest(r.pk_cols) k
  JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name=p_tabel AND c.column_name=k
  WHERE r.tabel=p_tabel;
$$;

CREATE OR REPLACE FUNCTION _version_current_row(p_tabel text, p_pk jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_skip text[]; v_row jsonb;
BEGIN
  SELECT coalesce(skip_cols,'{}') INTO v_skip FROM version_pk_registry WHERE tabel=p_tabel;
  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk))
    INTO v_row;
  IF v_row IS NULL THEN RETURN NULL; END IF;
  RETURN v_row - v_skip;  -- samme projektion som log_change
END $$;

-- Upsert til nøjagtig snapshot-tilstand. Manglende (skip-)kolonner → NULL (cache regenereres efter).
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_pk_cols text; v_set text;
BEGIN
  SELECT string_agg(quote_ident(k),',') INTO v_pk_cols
    FROM version_pk_registry r, unnest(r.pk_cols) k WHERE r.tabel=p_tabel;
  SELECT string_agg(format('%I = excluded.%I', column_name, column_name), ',') INTO v_set
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name=p_tabel;
  EXECUTE format(
    'INSERT INTO %1$I SELECT (jsonb_populate_record(null::%1$I, $1)).* ON CONFLICT (%2$s) DO UPDATE SET %3$s',
    p_tabel, v_pk_cols, v_set) USING p_row;
END $$;

CREATE OR REPLACE FUNCTION _version_delete_row(p_tabel text, p_pk jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('DELETE FROM %I WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk));
END $$;
```

> **Antagelse der verificeres i Step 5:** `_version_upsert_row` mod en tabel hvor en delvis (skip-projiceret) `foer` mangler `visning_*` sætter dem NULL. Det er kun et problem for `person`; restore (Task 8) kalder `regen_person_visning` bagefter. For øvrige tabeller er `foer` fuld.

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`.**

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — generiske restore-hjælpere (upsert/delete/current)

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 8: `red_fortryd_change_set` (restore, én transaktion, optimistisk)

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `change_set`/`change_event` (T2), restore-hjælpere (T7), `begin_change_set` (T3), `regen_person_visning` (eksisterende).
- Produces: `red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false) RETURNS jsonb`.

- [ ] **Step 1: Skriv failing assert (round-trip + konflikt-afvisning)**

```sql
-- ===== Versionering Task 8: restore =====
DO $$
DECLARE r jsonb; v_fact bigint; v_aid bigint; cs bigint; v_val text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  -- opret en oplysning (change_set #1)
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','original',NULL,NULL,NULL,NULL,'k');
  v_aid := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT max(id) INTO cs FROM change_set;
  -- fortryd #1 → fact/assertion/citation/conclusion skal forsvinde igen
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  IF EXISTS (SELECT 1 FROM assertion WHERE id=v_aid) THEN
    RAISE EXCEPTION 'FEJL: restore slettede ikke den oprettede assertion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=cs) THEN
    RAISE EXCEPTION 'FEJL: ingen reversal-change_set oprettet'; END IF;
  -- dobbelt-fortryd af samme sæt skal afvises
  BEGIN
    PERFORM red_fortryd_change_set(cs, false);
    RAISE EXCEPTION 'FEJL: dobbelt-fortryd blev ikke afvist';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores egen fejl → propagér
  END;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore round-trip + dobbelt-fortryd afvist';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør → FEJL** (funktion findes ikke)

- [ ] **Step 3: Tilføj `red_fortryd_change_set` i `schema.sql`**

```sql
-- ---------- VERSIONERING: restore ----------
CREATE OR REPLACE FUNCTION red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  ev change_event; v_new_cs bigint; v_orig change_set;
  v_cur jsonb; v_pids bigint[] := '{}'; v_narr bigint[] := '{}'; v_notes bigint[] := '{}';
  v_div int := 0; pid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT * INTO v_orig FROM change_set WHERE id=p_change_set_id;
  IF v_orig.id IS NULL THEN RAISE EXCEPTION 'FEJL: change_set % findes ikke', p_change_set_id; END IF;
  -- allerede reverteret? (reversal-kæde; M3)
  IF EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=p_change_set_id) THEN
    RAISE EXCEPTION 'FEJL: change_set % er allerede fortrudt', p_change_set_id;
  END IF;

  -- åbn reversal-sæt (re-entrant: triggere fanger ikke restore-DML ind under DET, da vi
  -- bevidst NULLER app.change_set_id under selve inverse — se nedenfor). Vi logger restore
  -- som ÉT change_set uden child-events for ikke at dobbelt-logge; reversal-kæden er sporet.
  PERFORM set_config('app.change_set_id','',true);  -- undgå at inverse-DML re-logges
  v_new_cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed, reverterer_id)
    VALUES (v_new_cs, auth.uid(),
            coalesce((SELECT email FROM profiles WHERE id=auth.uid()), 'ukendt'),
            current_rolle(), 'fortryd',
            format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
            v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id);

  -- inverse-apply i OMVENDT seq-orden, alt i denne ene transaktion
  FOR ev IN SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq DESC LOOP
    -- optimistisk verifikation (B9): nuværende tilstand skal matche hvad sættet efterlod
    v_cur := _version_current_row(ev.tabel, ev.row_pk);
    IF ev.op IN ('INSERT','UPDATE') THEN
      IF v_cur IS DISTINCT FROM ev.efter THEN
        v_div := v_div + 1;
        IF NOT p_force THEN
          RAISE EXCEPTION 'FEJL: nyere ændring rører %/% — afvist (brug force)', ev.tabel, ev.row_pk;
        END IF;
      END IF;
    END IF;
    -- anvend inverse
    IF ev.op='INSERT' THEN
      PERFORM _version_delete_row(ev.tabel, ev.row_pk);
    ELSIF ev.op='DELETE' THEN
      PERFORM _version_upsert_row(ev.tabel, ev.foer);
    ELSE  -- UPDATE
      PERFORM _version_upsert_row(ev.tabel, ev.foer);
    END IF;
    -- saml berørte for cache/indeks-regen
    IF ev.tabel='person'    THEN v_pids := v_pids || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='conclusion' THEN
      SELECT f.subjekt_id INTO pid FROM fact f
        WHERE f.id=(coalesce(ev.foer,ev.efter)->>'target_id')::bigint AND f.subjekt_type='person';
      IF pid IS NOT NULL THEN v_pids := v_pids || pid; END IF;
    END IF;
    IF ev.tabel='narrative' THEN v_narr := v_narr || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='note'      THEN v_notes := v_notes || (ev.row_pk->>'id')::bigint; END IF;
  END LOOP;

  -- regenerér afledte projektioner ÉN gang (B8 + hyperlinks)
  FOREACH pid IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(v_pids) x) LOOP
    PERFORM regen_person_visning(pid);
  END LOOP;
  -- text_mention regenereres af mention-trigger ved narrativ/note-skrivning (Task 10);
  -- ved restore kalder vi den eksplicit (funktion tilføjes i Task 10):
  PERFORM _regen_mentions_for('narrative', n) FROM unnest(v_narr) n;
  PERFORM _regen_mentions_for('note', n)      FROM unnest(v_notes) n;

  IF v_div > 0 THEN
    UPDATE change_set SET summary = summary || format(' [%s divergenser tvunget]', v_div) WHERE id=v_new_cs;
  END IF;
  RETURN jsonb_build_object('reversal_change_set', v_new_cs, 'divergenser', v_div);
END $$;
```

> **Afhængighed:** `_regen_mentions_for(text,bigint)` defineres i Task 10. Indtil Task 10 er kørt, vil restore af et narrativ/note-event fejle på den linje. Implementér Task 8's kerne nu; de to `_regen_mentions_for`-linjer udkommenteres til Task 10 er klar (genaktivér i Task 10 Step 4). Task 8's assert rører kun fakta → upåvirket.

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`** (med de to mention-linjer udkommenteret indtil Task 10).

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): versionering — red_fortryd_change_set (optimistisk, én txn)

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 9: Token-parser-funktion (hyperlinks)

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Produces: `parse_mentions(p_tekst text) RETURNS TABLE(maal_type text, maal_id bigint)` — udtrækker gyldige tokens pr. grammatik (spec §5.1); ignorerer malformede/ukendte typer.

- [ ] **Step 1: Skriv failing assert**

```sql
-- ===== Hyperlinks Task 9: parse_mentions =====
DO $$
DECLARE n int; got record;
BEGIN
  -- gyldigt token + malformet + ukendt type + escaped pipe i visningstekst
  SELECT count(*) INTO n FROM parse_mentions(
    'Se [[person:482|Chr. D. Reventlow]] og [[estate:7|Christianssæde]]. '
    || 'Malformet [[person:abc|x]] ukendt [[ufo:1|y]] escaped [[person:9|a\|b]].');
  IF n <> 3 THEN RAISE EXCEPTION 'FEJL: forventede 3 gyldige mentions, fik %', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM parse_mentions('[[person:482|x]]') WHERE maal_type='person' AND maal_id=482) THEN
    RAISE EXCEPTION 'FEJL: token ikke parset korrekt'; END IF;
  RAISE NOTICE 'OK: parse_mentions';
END $$;
```

- [ ] **Step 2: Kør → FEJL** (funktion findes ikke)

- [ ] **Step 3: Tilføj `parse_mentions` i `schema.sql`**

```sql
-- ---------- HYPERLINKS: token-parser ----------
-- Grammatik (spec §5.1): [[<type>:<id>|<visningstekst>]]
--   type ∈ fast vokabular; id = heltal uden foranstillede nuller; visningstekst vilkårlig
--   (| [ ] escapes som \| \[ \]). Malformet/ukendt type → ignoreres.
CREATE OR REPLACE FUNCTION parse_mentions(p_tekst text)
RETURNS TABLE(maal_type text, maal_id bigint) LANGUAGE sql IMMUTABLE AS $$
  SELECT m[1] AS maal_type, m[2]::bigint AS maal_id
  FROM regexp_matches(
    coalesce(p_tekst,''),
    -- type-gruppe begrænset til vokabularet; id uden foranstillet nul (0 eller 1-9…)
    '\[\[(person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage):(0|[1-9][0-9]*)\|',
    'g'
  ) AS m;
$$;
```

> Parseren matcher kun token-HOVEDET (type:id|) — nok til indeksering; den fulde escaping-håndtering af visningsteksten hører til app-rendereren (separat plan). Malformet id (`abc`) og ukendt type (`ufo`) matcher ikke regex'en → ignoreres, som krævet.

- [ ] **Step 4: Spejl idempotent i `db-migrations.sql`.**

- [ ] **Step 5: Kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): hyperlinks — parse_mentions token-parser

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 10: `text_mention`-indeks + regenererings-trigger

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, (genaktivér linjer i Task 8)
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `parse_mentions` (T9).
- Produces: tabel `text_mention` (PK pr. spec §5.3); `_regen_mentions_for(p_kilde_type text, p_kilde_id bigint)`; trigger `trg_mentions_narrative`/`trg_mentions_note`. Tilføjer `profiles.navn`.

- [ ] **Step 1: Skriv failing assert (replace-semantik + dedup)**

```sql
-- ===== Hyperlinks Task 10: text_mention =====
DO $$
DECLARE v_nid bigint; n int;
BEGIN
  PERFORM set_config('app.change_set_id','',true);  -- bulk-sti, ingen versionering af testdata
  v_nid := (SELECT coalesce(max(id),0)+1 FROM narrative);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst)
    VALUES (v_nid,'person',1,'[[person:1|a]] og [[person:1|igen]] og [[estate:2|g]]');
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 2 THEN RAISE EXCEPTION 'FEJL: forventede 2 dedup-mentions, fik %', n; END IF;  -- person:1 dedup
  UPDATE narrative SET tekst='[[lineage:5|x]]' WHERE id=v_nid;  -- replace
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 1 OR NOT EXISTS (SELECT 1 FROM text_mention WHERE kilde_id=v_nid AND maal_type='lineage') THEN
    RAISE EXCEPTION 'FEJL: replace-semantik virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: text_mention dedup + replace';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør → FEJL** (tabel/trigger mangler)

- [ ] **Step 3: Tilføj tabel, regen-funktion, triggere + `profiles.navn` i `schema.sql`**

```sql
-- ---------- HYPERLINKS: text_mention (afledt indeks) ----------
CREATE TABLE IF NOT EXISTS text_mention (
  kilde_type TEXT NOT NULL,            -- 'narrative' | 'note'
  kilde_id   BIGINT NOT NULL,
  maal_type  TEXT NOT NULL,
  maal_id    BIGINT NOT NULL,
  PRIMARY KEY (kilde_type, kilde_id, maal_type, maal_id)
);
CREATE INDEX IF NOT EXISTS ix_text_mention_maal ON text_mention(maal_type, maal_id);

-- Erstat HELE projektionen for én kilde-række (dedup via PK).
CREATE OR REPLACE FUNCTION _regen_mentions_for(p_kilde_type text, p_kilde_id bigint)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_tekst text;
BEGIN
  DELETE FROM text_mention WHERE kilde_type=p_kilde_type AND kilde_id=p_kilde_id;
  IF p_kilde_type='narrative' THEN SELECT tekst INTO v_tekst FROM narrative WHERE id=p_kilde_id;
  ELSIF p_kilde_type='note'   THEN SELECT indhold INTO v_tekst FROM note WHERE id=p_kilde_id; END IF;
  IF v_tekst IS NULL THEN RETURN; END IF;
  INSERT INTO text_mention(kilde_type, kilde_id, maal_type, maal_id)
    SELECT p_kilde_type, p_kilde_id, maal_type, maal_id FROM parse_mentions(v_tekst)
    ON CONFLICT DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION trg_regen_mentions()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_kilde text := TG_TABLE_NAME;  -- 'narrative' | 'note'
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM text_mention WHERE kilde_type=v_kilde AND kilde_id=OLD.id;
  ELSE
    PERFORM _regen_mentions_for(v_kilde, NEW.id);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_mentions_narrative ON narrative;
CREATE TRIGGER trg_mentions_narrative AFTER INSERT OR UPDATE OR DELETE ON narrative
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();
DROP TRIGGER IF EXISTS trg_mentions_note ON note;
CREATE TRIGGER trg_mentions_note AFTER INSERT OR UPDATE OR DELETE ON note
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();

-- profiles.navn (kilde til frosset actor_navn; spec §6)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS navn TEXT;
```

- [ ] **Step 4: Opdatér `begin_change_set` navn-kilde + genaktivér Task 8's mention-linjer**

I `begin_change_set` (schema.sql + db-migrations.sql): skift
`SELECT coalesce(p.email, v_uid::text), p.rolle` → `SELECT coalesce(p.navn, p.email, v_uid::text), p.rolle`.
I `red_fortryd_change_set`: fjern udkommenteringen af de to `_regen_mentions_for`-linjer (de virker nu).

- [ ] **Step 5: Spejl alt idempotent i `db-migrations.sql` + kør assert → OK**

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): hyperlinks — text_mention-indeks + regen-trigger + profiles.navn

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 11: RLS — deny-all historik + redaktion-only læse-API + mention-gating

**Files:**
- Modify: `db-rls.sql`, `schema.sql` (læse-API-funktioner), `db-migrations.sql`
- Test: `db-verify.sql`

**Interfaces:**
- Consumes: `change_set`/`change_event` (T2), `text_mention` (T10), `person_offentlig` (eksisterende i db-rls.sql), `current_rolle()`.
- Produces: RLS deny-all på historik-tabeller; `hist_for_subjekt(p_type text, p_id bigint) RETURNS SETOF change_set` (redaktion-only); `hist_events(p_change_set_id bigint) RETURNS SETOF change_event` (redaktion-only); view `red_doede_links`; RLS-politik på `text_mention` (dobbelt-gating, M4).

- [ ] **Step 1: Skriv failing assert (medlem nægtes; redaktion får; døde links)**

```sql
-- ===== Task 11: historik-RLS + døde links =====
DO $$
DECLARE n int;
BEGIN
  IF to_regclass('public.red_doede_links') IS NULL THEN
    RAISE EXCEPTION 'FEJL: red_doede_links view mangler'; END IF;
  -- hist_for_subjekt skal RAISE for ikke-redaktion (SQL Editor = medlem)
  BEGIN
    PERFORM * FROM hist_for_subjekt('person', 1);
    RAISE EXCEPTION 'FEJL: hist_for_subjekt tillod ikke-redaktion';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores assert-fejl propagerer
  END;
  RAISE NOTICE 'OK: historik-API redaktion-gated + døde-links-view findes';
END $$;
```

- [ ] **Step 2: Kør → FEJL** (view/funktion mangler)

- [ ] **Step 3: Tilføj læse-API + view i `schema.sql`**

```sql
-- ---------- VERSIONERING: redaktion-only historik-API (B10) ----------
CREATE OR REPLACE FUNCTION hist_for_subjekt(p_type text, p_id bigint)
RETURNS SETOF change_set LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_set
    WHERE subjekt_type=p_type AND subjekt_id=p_id ORDER BY created_at DESC;
END $$;

CREATE OR REPLACE FUNCTION hist_events(p_change_set_id bigint)
RETURNS SETOF change_event LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq;
END $$;

-- Døde links: mentions hvis mål ikke længere findes (kun person/estate vist; udvid efter behov).
CREATE OR REPLACE VIEW red_doede_links WITH (security_invoker = true) AS
SELECT m.* FROM text_mention m
WHERE (m.maal_type='person' AND NOT EXISTS (SELECT 1 FROM person  p WHERE p.id=m.maal_id))
   OR (m.maal_type='estate' AND NOT EXISTS (SELECT 1 FROM estate  e WHERE e.id=m.maal_id))
   OR (m.maal_type='lineage' AND NOT EXISTS (SELECT 1 FROM lineage l WHERE l.id=m.maal_id));
```

- [ ] **Step 4: Tilføj RLS-politikker i `db-rls.sql`**

```sql
-- ---------- VERSIONERING + MENTIONS: RLS ----------
-- Historik-tabeller: deny-all for anon/authenticated; al adgang via SECURITY DEFINER-API (B10).
ALTER TABLE change_set   ENABLE ROW LEVEL SECURITY;
ALTER TABLE change_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON change_set, change_event FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION hist_for_subjekt(text,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION hist_events(bigint)            TO authenticated;
GRANT EXECUTE ON FUNCTION red_fortryd_change_set(bigint,boolean) TO authenticated;

-- text_mention: dobbelt-gating (M4) — kilde-tekst OG mål synlig.
ALTER TABLE text_mention ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tm_read ON text_mention;
CREATE POLICY tm_read ON text_mention FOR SELECT TO anon, authenticated
USING (
  -- kilde-tekst synlig (person-bundet narrativ/note → personens synlighed; ikke-privat)
  CASE kilde_type
    WHEN 'narrative' THEN EXISTS (SELECT 1 FROM narrative n WHERE n.id=kilde_id
       AND coalesce(n.privat,false)=false
       AND (n.subjekt_type<>'person' OR person_offentlig(n.subjekt_id)))
    WHEN 'note' THEN EXISTS (SELECT 1 FROM note nt WHERE nt.id=kilde_id
       AND coalesce(nt.privat,false)=false
       AND (nt.target_type<>'person' OR person_offentlig(nt.target_id)))
    ELSE false END
  AND
  -- mål synlig (person → person_offentlig; øvrige entiteter offentlige i PoC)
  (maal_type<>'person' OR person_offentlig(maal_id))
);
```

> `red_doede_links` er redaktions-værktøj; eksponér kun via redaktion-session. `security_invoker=true` sikrer at `text_mention`-politikken (og dermed synlighed) håndhæves når viewet læses som ikke-ejer.

- [ ] **Step 5: Kør assert → OK**

Run: `psql "$SUPABASE_DB_URL_BRANCH" -f db-migrations.sql && psql "$SUPABASE_DB_URL_BRANCH" -f db-rls.sql && psql "$SUPABASE_DB_URL_BRANCH" -f db-verify.sql 2>&1 | grep 'Task 11'`

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): RLS — deny-all historik + redaktion-only API + mention-gating + døde-links

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Self-Review (udført)

**Spec-dækning:**
- B1 ekshaustivt scope → T1 registry + T4 trigger-loop ✓ · B2 hybrid → T3/T4 ✓ · B3 frosset actor + SET NULL → T2/T3 ✓ · B4 inline-token → T9 ✓ · B5 append → T6 ✓ · B6/B9 optimistisk konflikt → T8 ✓ · B7 re-entrant → T3 ✓ · B8 kolonne-projektion → T1/T4/T7 ✓ · B10 redaktion-only historik → T11 ✓ · B11 PK-registry → T1 ✓ · B12 eksport (ingen DB-handling; app-lag) — noteret, ingen task ✓ · C1 synligheds-snapshot → T3 ✓ · C2/H3 scope inkl. profiles/person_external_id → T1 ✓ · M1 én txn → T8 ✓ · M2 PK-registry → T1 ✓ · M3 reversal-kæde → T2/T8 ✓ · M4 dobbelt-gating → T11 ✓ · M5 token-grammatik → T9 ✓ · L1 text_mention PK → T10 ✓
- H5 (FK-sikker restore via RPC-invariant): dækket af T8's omvendt-seq + eksisterende children-first-delete; **restore-test pr. destruktiv RPC** anbefales udvidet (T8-assert dækker fakta-stien; tilføj person-slet-restore-assert hvis tid).

**Type-konsistens:** `_regen_mentions_for(text,bigint)` defineret T10, kaldt T8 (forward-ref håndteret via udkommenterings-note). `parse_mentions` returkolonner `maal_type/maal_id` matcher T10-INSERT. `red_edit_oplysning` returtype-skift (void→jsonb) håndteret med `DROP FUNCTION` i T6.

**Placeholder-scan:** ingen TBD/TODO; al SQL er komplet.

**Kendt app-lag-afhængighed (uden for denne plan):** `red_edit_oplysning`s nye `jsonb`-retur skal afspejles i `mobile/src/data/redaktionWrite.ts` + jest. Hører til app-planen.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-30-versionering-hyperlinks-db-lag.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

> **Forudsætning for begge:** en branch/kopi-Supabase-base + `$SUPABASE_DB_URL_BRANCH` i miljøet (aldrig prod). Uden den kan asserts ikke køres → execution bør vente til basen er klar.
