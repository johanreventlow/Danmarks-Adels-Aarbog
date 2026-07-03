# Redaktionel identitets-sammenkædning (`samme_som`) — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give redaktøren en app-funktion til at markere to `person`-poster som samme fysiske person, så det (allerede live) frontend-collapse folder dem — med DB-håndhævede graf-invarianter, fortrydbart.

**Architecture:** En `BEFORE INSERT`-trigger på `relation` håndhæver samme_som-graf-invarianterne (unik sink, acyklisk) for ALLE skrive-veje. Ovenpå ligger to tynde, versionerede RPC'er (`red_samme_som` evidens-komplet opret, `red_fjern_samme_som` komplet slet). App-laget (web+mobile spejlet) tilføjer to `Change`-arter, en link-fetch, et rådgivende pre-flight-hint (genbruger `collapseSameAs`), og en UI-affordance i person-editorens relations-sektion.

**Tech Stack:** PostgreSQL/Supabase (plpgsql, SECURITY DEFINER, `begin_change_set`-versionering), TypeScript. Web: vitest (`cd web && npx vitest run`). Mobile: jest (`cd mobile && npx jest`). DB-verifikation: `db-verify.sql`-asserts mod en lokal prod-kopi (se memory `lokal-db-testbase`); **prod-apply er et separat bruger-godkendt trin** (som versionering-DB-laget).

**Spec:** `docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md` (dual-Codex-reviewet, 3 runder).

## Global Constraints

- **Enforcement-grænse = trigger**, ikke RPC (Codex-3): invarianten skal holde uanset skrive-vej.
- **Kun `afklaret` links foldes** — `red_samme_som` skriver conclusion `status='afklaret'` direkte (redaktion-only).
- **Retning:** `subjekt_id`=alias, `objekt_id`=kanonisk. Kanonisk = komponentens unikke sink.
- **Ingen citation** på manuelle links (change_set + `blaastemplet_af` er audit).
- **ID-allokering:** `(SELECT coalesce(max(id),0)+1 …)` — codebase-konvention; race mod andre `red_*` accepteret for v1 (spec §3, bruger-godkendt).
- **Advisory-lås:** `pg_advisory_xact_lock(hashtext('samme_som_mutation'))` i triggeren OG begge RPC'er (reentrant).
- **schema.sql = source of truth; db-migrations.sql = idempotent afstemning.** Al ny SQL i BEGGE.
- **App web+mobile spejles** (`redaktionWrite.ts` holdes i sync — filens header-note).
- **Commits:** Conventional Commits (dansk), ingen Claude-attribution, slut med `Claude-Session: https://claude.ai/code/session_019NyMwmmxpPrURv3zij7foJ`.

---

## Fil-struktur

| Fil | Ansvar |
|---|---|
| `schema.sql` (mod) | Trigger `enforce_samme_som_invariants` + `red_samme_som` + `red_fjern_samme_som` + guard i `red_relation` |
| `db-migrations.sql` (mod) | Idempotent kopi af samme SQL |
| `db-rls.sql` (mod) | `GRANT EXECUTE` på de to nye RPC'er til `authenticated` |
| `db-verify.sql` (mod) | Asserts: trigger-afvisninger, opret/idempotens/slet, fjern+fortryd |
| `web/src/data/redaktionWrite.ts` + `mobile/src/data/redaktionWrite.ts` (mod) | `Change`-arter `sammeSom`/`fjernSammeSom` |
| `web/src/data/redaktionRead.ts` + `mobile/src/data/redaktionRead.ts` (mod) | `fetchSammeSomLinks(personId)` |
| `web/src/data/sammeSomPreflight.ts` + `mobile/src/data/sammeSomPreflight.ts` (ny) | Rådgivende pre-flight via `collapseSameAs` |
| `web/src/Redaktion.tsx` + `mobile/src/app/redaktion/person/[id].tsx` (mod) | UI-affordance (manuel verifikation) |

---

## FASE A — DB-lag (trigger + RPC'er)

### Task 1: Trigger `enforce_samme_som_invariants` + `red_relation`-guard

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-verify.sql`

**Interfaces:**
- Produces: trigger `trg_enforce_samme_som BEFORE INSERT ON relation` der `RAISE`r ved G0 (self-link), G3 (multi-sink), G4 (alias er kanonisk), G5 (cyklus). `red_relation` afviser `rolle='samme_som'`.

- [ ] **Step 1: Skriv trigger-funktion + trigger i `schema.sql`** (indsæt nær de øvrige `red_*`-relation-funktioner)

```sql
-- samme_som-invariant-håndhævelse (spec 2026-07-02, Codex-3): gælder ALLE insert-veje (RPC/undo/
-- load-script/manuel), ikke kun red_samme_som. Grafen skal være træer med præcis én sink pr. komponent.
CREATE OR REPLACE FUNCTION enforce_samme_som_invariants() RETURNS trigger
LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_cur bigint; v_steps int := 0;
BEGIN
  IF NEW.rolle <> 'samme_som' OR NEW.subjekt_type <> 'person' OR NEW.objekt_type <> 'person' THEN
    RETURN NEW; -- ikke et person→person samme_som — rør ikke
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation')); -- serialisér samme_som-inserts
  IF NEW.subjekt_id = NEW.objekt_id THEN
    RAISE EXCEPTION 'samme_som: kan ikke linke en person til sig selv';
  END IF;
  -- G3 out-degree ≤ 1: alias peger ikke allerede på en ANDEN kanonisk (multi-sink).
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND subjekt_id = NEW.subjekt_id AND objekt_id <> NEW.objekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede alias for en anden (ville give multi-sink)', NEW.subjekt_id;
  END IF;
  -- G4 alias er ikke en eksisterende kanonisk (sink): ville stille re-roote en komponent.
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND objekt_id = NEW.subjekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede kanonisk for andre — skift retning via fjern+genopret', NEW.subjekt_id;
  END IF;
  -- G5 acyklisk: følg kanonisk-pointere fra objekt; hvis subjekt nås, lukker den nye kant en cyklus.
  v_cur := NEW.objekt_id;
  WHILE v_cur IS NOT NULL LOOP
    IF v_cur = NEW.subjekt_id THEN RAISE EXCEPTION 'samme_som: kanten ville lukke en cyklus'; END IF;
    v_steps := v_steps + 1;
    IF v_steps > 10000 THEN RAISE EXCEPTION 'samme_som: for lang kæde (mulig eksisterende cyklus)'; END IF;
    SELECT objekt_id INTO v_cur FROM relation WHERE rolle='samme_som' AND subjekt_type='person'
      AND objekt_type='person' AND subjekt_id = v_cur LIMIT 1;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_samme_som ON relation;
CREATE TRIGGER trg_enforce_samme_som BEFORE INSERT ON relation
  FOR EACH ROW WHEN (NEW.rolle = 'samme_som') EXECUTE FUNCTION enforce_samme_som_invariants();
```

- [ ] **Step 2: Tilføj `rolle='samme_som'`-guard i `red_relation`** (`schema.sql`, i funktionens top efter rolle-tjek)

Find `CREATE OR REPLACE FUNCTION red_relation(` og indsæt lige efter `IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;`:

```sql
  IF p_rolle = 'samme_som' THEN RAISE EXCEPTION 'Brug red_samme_som til identitets-links'; END IF;
```

- [ ] **Step 3: Kopiér trigger + guard idempotent til `db-migrations.sql`**

Indsæt samme `CREATE OR REPLACE FUNCTION enforce_samme_som_invariants` + `DROP TRIGGER IF EXISTS`/`CREATE TRIGGER`-blok, og den samme `red_relation`-guard-linje (via en `CREATE OR REPLACE`-gentagelse af hele `red_relation` med guarden — kopiér den nuværende `red_relation`-krop fra schema.sql og tilføj guard-linjen).

- [ ] **Step 4: Skriv db-verify-asserts** (`db-verify.sql`, ny sektion "Task N: samme_som-invarianter")

```sql
-- samme_som trigger-enforcement (spec 2026-07-02). Bruger to vilkårlige eksisterende person-id'er.
DO $$
DECLARE a bigint; b bigint; c bigint;
BEGIN
  SELECT id INTO a FROM person ORDER BY id LIMIT 1;
  SELECT id INTO b FROM person WHERE id <> a ORDER BY id LIMIT 1;
  SELECT id INTO c FROM person WHERE id NOT IN (a,b) ORDER BY id LIMIT 1;

  -- G0 self-link afvises
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),'person',a,'person',a,'samme_som');
    RAISE EXCEPTION 'FAIL: self-link blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; END;

  -- red_relation afviser samme_som (kræver redaktion-rolle-kontekst; her testes kun exception-teksten
  -- hvis rolle-gaten passeres — ellers dækket af app-testen). Springes hvis ikke redaktion.

  RAISE NOTICE 'OK: samme_som trigger G0 håndhævet';
END $$;
```

(G3/G4/G5 verificeres bedst i sekvens efter `red_samme_som` findes — flyt de asserts til Task 2's verify når RPC'en kan oprette et gyldigt første led. Her dækkes G0 + at triggeren overhovedet fyrer.)

- [ ] **Step 5: Kør verify mod lokal prod-kopi**

Run: `psql "$LOCAL_TESTBASE" -f db-migrations.sql && psql "$LOCAL_TESTBASE" -f db-verify.sql`
Expected: `NOTICE: OK: samme_som trigger G0 håndhævet`, ingen `FAIL`. (Lokal testbase: se memory `lokal-db-testbase`; stå op hvis ikke kørende.)

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): samme_som-invariant-trigger + red_relation-guard (Task 1)"
```

---

### Task 2: `red_samme_som` RPC

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`

**Interfaces:**
- Consumes: trigger fra Task 1.
- Produces: `red_samme_som(p_alias_id bigint, p_objekt_id bigint) RETURNS bigint` — opretter relation+assertion+afklaret-conclusion; idempotent på præcis retning; redaktion-gated.

- [ ] **Step 1: Skriv `red_samme_som` i `schema.sql`**

```sql
-- Opret et redaktionelt identitets-link (spec 2026-07-02). Tynd, evidens-komplet wrapper ovenpå
-- invariant-triggeren. Idempotent på præcis retning (FØR change_set → ingen tom audit ved gentagelse).
CREATE OR REPLACE FUNCTION red_samme_som(p_alias_id bigint, p_objekt_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_alias_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_alias_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_objekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_objekt_id; END IF;
  -- G2 idempotens (præcis retning) FØR begin_change_set.
  SELECT id INTO v_rel FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=p_alias_id AND objekt_id=p_objekt_id LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  PERFORM begin_change_set('red_samme_som',
    format('Markerede person %s som samme som %s', p_alias_id, p_objekt_id), 'person', p_objekt_id);
  -- Triggeren validerer G0/G3/G4/G5 på denne INSERT.
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_alias_id, 'person', p_objekt_id, 'samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'relation', v_rel, 'samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitetssammenkædning');
  RETURN v_rel;
END $$;
```

- [ ] **Step 2: Kopiér idempotent til `db-migrations.sql`** (samme `CREATE OR REPLACE FUNCTION`-blok).

- [ ] **Step 3: GRANT i `db-rls.sql`** (ved de øvrige `GRANT EXECUTE … red_* TO authenticated`)

```sql
GRANT EXECUTE ON FUNCTION red_samme_som(bigint, bigint) TO authenticated;
```

- [ ] **Step 4: db-verify-asserts** (`db-verify.sql`, udvid Task 1-sektionen — kræver redaktion-rolle; kør efter at `current_rolle()` kan sættes til 'redaktion' i testbasen via auth-shim, ellers test G3/G4/G5 med bare INSERTs mod triggeren)

```sql
-- G3/G4/G5 via bare INSERT mod triggeren (uafhængig af rolle). Rollback så basen ikke muteres.
DO $$
DECLARE a bigint; b bigint; c bigint; r1 bigint;
BEGIN
  SELECT id INTO a FROM person ORDER BY id LIMIT 1;
  SELECT id INTO b FROM person WHERE id <> a ORDER BY id LIMIT 1;
  SELECT id INTO c FROM person WHERE id NOT IN (a,b) ORDER BY id LIMIT 1;
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),'person',a,'person',b,'samme_som') RETURNING id INTO r1;
  -- G3: a→c afvises (a allerede alias for b)
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),'person',a,'person',c,'samme_som');
    RAISE EXCEPTION 'FAIL: G3 multi-sink accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; END;
  -- G4: b→c afvises (b er kanonisk for a)
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),'person',b,'person',c,'samme_som');
    RAISE EXCEPTION 'FAIL: G4 re-root accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; END;
  -- G5: b→a afvises (cyklus a→b→a)
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),'person',b,'person',a,'samme_som');
    RAISE EXCEPTION 'FAIL: G5 cyklus accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: G3/G4/G5 håndhævet';
  RAISE EXCEPTION 'ROLLBACK_TEST'; -- fortryd test-inserts
EXCEPTION WHEN others THEN
  IF SQLERRM <> 'ROLLBACK_TEST' THEN RAISE; END IF;
END $$;
```

- [ ] **Step 5: Kør verify** — `psql "$LOCAL_TESTBASE" -f db-migrations.sql && psql "$LOCAL_TESTBASE" -f db-verify.sql`. Expected: `OK: G3/G4/G5 håndhævet`, ingen `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): red_samme_som RPC + G3/G4/G5-verify (Task 2)"
```

---

### Task 3: `red_fjern_samme_som` RPC

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`

**Interfaces:**
- Produces: `red_fjern_samme_som(p_relation_id bigint) RETURNS void` — validerer person→person samme_som, sletter komplet evidens (citation→conclusion→assertion→note→relation), versioneret.

- [ ] **Step 1: Skriv `red_fjern_samme_som` i `schema.sql`**

```sql
-- Fjern et identitets-link (spec 2026-07-02). Genbruger red_slet_relation's KOMPLETTE evidens-sletning
-- (de eksisterende links har citations). Egen change_set (ikke nested).
CREATE OR REPLACE FUNCTION red_fjern_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=p_relation_id AND rolle='samme_som'
                AND subjekt_type='person' AND objekt_type='person') THEN
    RAISE EXCEPTION 'Relation % er ikke et person→person samme_som-link', p_relation_id;
  END IF;
  PERFORM begin_change_set('red_fjern_samme_som', format('Fjernede samme_som-link %s', p_relation_id), NULL, NULL);
  DELETE FROM citation   WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;
```

- [ ] **Step 2: Kopiér idempotent til `db-migrations.sql`.**

- [ ] **Step 3: GRANT i `db-rls.sql`**

```sql
GRANT EXECUTE ON FUNCTION red_fjern_samme_som(bigint) TO authenticated;
```

- [ ] **Step 4: db-verify-assert** — validér at ikke-samme_som-relation afvises (bar test, rolle-uafhængig hvis testbasen kan sætte redaktion; ellers dokumentér som app-/manuel-verificeret). Tilføj notat: **fjern + fortryd af de 2 eksisterende links (Conrad relation 972, Detlef 973) verificeres manuelt mod en kopi** — de HAR citations, så det tester den komplette sekvens + `red_fortryd_change_set`-restore.

- [ ] **Step 5: Kør verify** — som Task 2. Expected: ingen `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): red_fjern_samme_som RPC (komplet evidens-slet) (Task 3)"
```

- [ ] **Step 7: (GATE) Prod-apply** — **STOP: kræver bruger-godkendelse.** Anvend trigger + 3 RPC'er + guard + grants mod prod-Supabase (via MCP `apply_migration` eller psql), kør `db-verify.sql` mod prod. Som versionering-DB-laget: applied atomisk efter review.

---

## FASE B — App data-lag (web + mobile spejlet)

### Task 4: `redaktionWrite` Change-arter `sammeSom` + `fjernSammeSom`

**Files:**
- Modify: `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts`
- Test: `web/src/data/__tests__/redaktionWrite.test.ts`, `mobile/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Produces: `Change.art` udvidet med `'sammeSom' | 'fjernSammeSom'`. `buildRpcCall` mapper `sammeSom` `{payload:{aliasId,objektId}}` → `red_samme_som` og `fjernSammeSom` `{relationId}` → `red_fjern_samme_som`.

- [ ] **Step 1: Skriv de fejlende tests** (begge filer, samme indhold — spejl)

```ts
test('sammeSom → red_samme_som(p_alias_id,p_objekt_id)', () => {
  const call = buildRpcCall({ art: 'sammeSom', subjektType: 'person', subjektId: '255',
    payload: { aliasId: '255', objektId: '392' } } as never);
  expect(call).toEqual({ fn: 'red_samme_som', args: { p_alias_id: 255, p_objekt_id: 392 } });
});
test('fjernSammeSom → red_fjern_samme_som(p_relation_id)', () => {
  const call = buildRpcCall({ art: 'fjernSammeSom', subjektType: 'person', subjektId: '392',
    relationId: '972' } as never);
  expect(call).toEqual({ fn: 'red_fjern_samme_som', args: { p_relation_id: 972 } });
});
```

- [ ] **Step 2: Kør — fejler.** Run: `cd web && npx vitest run redaktionWrite` → FAIL (art ukendt / null). Samme mobile.

- [ ] **Step 3: Udvid `Change.art`-unionen** (begge filer): tilføj `| 'sammeSom' | 'fjernSammeSom'`.

- [ ] **Step 4: Tilføj til `buildRpcCall`** (begge filer, før `return null`)

```ts
  if (c.art === 'sammeSom') {
    const p = c.payload || {};
    if (p.aliasId == null || p.objektId == null) return null;
    return { fn: 'red_samme_som', args: { p_alias_id: Number(p.aliasId), p_objekt_id: Number(p.objektId) } };
  }
  if (c.art === 'fjernSammeSom') {
    if (c.relationId == null) return null;
    return { fn: 'red_fjern_samme_som', args: { p_relation_id: Number(c.relationId) } };
  }
```

- [ ] **Step 5: Sikr at `planCall` router disse direkte (ikke `red_suggest`)** — de er "kendte arter" (buildRpcCall≠null), så eksisterende rolle-routing sender redaktion direkte. Ingen ændring nødvendig; verificér i test at redaktion-rolle giver det direkte kald.

- [ ] **Step 6: Kør + commit.** Run: `cd web && npx vitest run redaktionWrite` og `cd mobile && npx jest redaktionWrite` → PASS.

```bash
git add web/src/data/redaktionWrite.ts mobile/src/data/redaktionWrite.ts \
        web/src/data/__tests__/redaktionWrite.test.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(app): redaktionWrite sammeSom/fjernSammeSom Change-arter (Task 4)"
```

---

### Task 5: `fetchSammeSomLinks` (eksisterende links pr. person)

**Files:**
- Modify: `web/src/data/redaktionRead.ts`, `mobile/src/data/redaktionRead.ts`
- Test: `web/src/data/__tests__/redaktionRead.test.ts` (hvis mock-infra findes; ellers ren transform-test)

**Interfaces:**
- Produces: `fetchSammeSomLinks(personId: string): Promise<{ relationId: string; retning: 'alias'|'kanonisk'; modpartId: string }[]>` — henter samme_som-relationer hvor personen er subjekt ELLER objekt.

- [ ] **Step 1: Skriv en ren transform-helper + test** (så logikken er netværksfri testbar; spejl mobile)

I `redaktionRead.ts`, tilføj en ren funktion der klassificerer rå rækker:

```ts
export type SammeSomLink = { relationId: string; retning: 'alias' | 'kanonisk'; modpartId: string };
// rows: samme_som-relationer der involverer personId. retning=alias hvis personId er subjekt (peger på
// en kanonisk), kanonisk hvis personId er objekt (andre peger på den).
export function mapSammeSomLinks(personId: string,
  rows: { id: number|string; subjekt_id: number|string; objekt_id: number|string }[]): SammeSomLink[] {
  return rows.map((r) => String(r.subjekt_id) === personId
    ? { relationId: String(r.id), retning: 'alias' as const, modpartId: String(r.objekt_id) }
    : { relationId: String(r.id), retning: 'kanonisk' as const, modpartId: String(r.subjekt_id) });
}
```

Test:
```ts
test('mapSammeSomLinks klassificerer retning', () => {
  const rows = [{ id: 972, subjekt_id: 255, objekt_id: 392 }, { id: 5, subjekt_id: 40, objekt_id: 255 }];
  expect(mapSammeSomLinks('255', rows)).toEqual([
    { relationId: '972', retning: 'alias', modpartId: '392' },
    { relationId: '5', retning: 'kanonisk', modpartId: '40' },
  ]);
});
```

- [ ] **Step 2: Kør — fejler** (funktion ej eksporteret). `cd web && npx vitest run redaktionRead`.

- [ ] **Step 3: Implementér `mapSammeSomLinks` (ovenfor) + en fetch-wrapper**

```ts
export async function fetchSammeSomLinks(personId: string): Promise<SammeSomLink[]> {
  const { data } = await supabase.from('relation').select('id,subjekt_id,objekt_id')
    .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person')
    .or(`subjekt_id.eq.${Number(personId)},objekt_id.eq.${Number(personId)}`);
  return mapSammeSomLinks(personId, (data ?? []) as never);
}
```

- [ ] **Step 4: Kør + commit.** Run: `cd web && npx vitest run redaktionRead` og mobile → PASS.

```bash
git add web/src/data/redaktionRead.ts mobile/src/data/redaktionRead.ts web/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(app): fetchSammeSomLinks + retnings-mapping (Task 5)"
```

---

### Task 6: Rådgivende pre-flight (`sammeSomPreflight`)

**Files:**
- Create: `web/src/data/sammeSomPreflight.ts`, `mobile/src/data/sammeSomPreflight.ts`
- Test: `web/src/data/__tests__/sammeSomPreflight.test.ts`, `mobile/src/data/__tests__/sammeSomPreflight.test.ts`

**Interfaces:**
- Consumes: `collapseSameAs`, `SameAsEdge`, `Db` fra data-laget.
- Produces: `previewSammeSom(rawDb: Db, existingEdges: SameAsEdge[], hypotetisk: SameAsEdge): { folder: boolean; grund: string | null }` — kører `collapseSameAs` med den hypotetiske kant og rapporterer om dens komponent ville blive karantæneret.

- [ ] **Step 1: Skriv de fejlende tests** (spejl web+mobile)

```ts
import { previewSammeSom } from '../sammeSomPreflight';
import type { Db, AppPerson } from '../types';
const P = (id: string, o: Partial<AppPerson> = {}): AppPerson =>
  ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o });

test('rent link folder → folder=true', () => {
  const db: Db = { persons: [P('a'), P('b')], unions: [], parentChild: [] };
  expect(previewSammeSom(db, [], { alias: 'a', canonical: 'b' })).toEqual({ folder: true, grund: null });
});
test('køn-konflikt → folder=false med grund', () => {
  const db: Db = { persons: [P('a', { koen: 'mand' }), P('b', { koen: 'kvinde' })], unions: [], parentChild: [] };
  const r = previewSammeSom(db, [], { alias: 'a', canonical: 'b' });
  expect(r.folder).toBe(false);
  expect(r.grund).toMatch(/køn/i);
});
```

- [ ] **Step 2: Kør — fejler** (modul findes ikke).

- [ ] **Step 3: Implementér** (`sammeSomPreflight.ts`, identisk web+mobile)

```ts
import { collapseSameAs } from './collapseSameAs';
import type { Db, SameAsEdge } from './types';

// Rådgivende (spec §6): kører collapse med den hypotetiske kant på REDAKTIONS-datasættet og rapporterer om
// kantens komponent ville blive karantæneret (køn/levetid/konkurrerende forældre). Ikke autoritativt —
// offentlig visning kan afvige pga. RLS/completeness. DB-triggeren håndhæver graf-invarianterne.
export function previewSammeSom(
  rawDb: Db,
  existingEdges: SameAsEdge[],
  hypotetisk: SameAsEdge,
): { folder: boolean; grund: string | null } {
  const r = collapseSameAs(rawDb, [...existingEdges, hypotetisk], new Map());
  const medlemmer = new Set([hypotetisk.alias, hypotetisk.canonical]);
  const karantæne = r.quarantined.find((q) => q.members.some((m) => medlemmer.has(m)));
  return karantæne ? { folder: false, grund: karantæne.reason } : { folder: true, grund: null };
}
```

- [ ] **Step 4: Kør + commit.** Run: `cd web && npx vitest run sammeSomPreflight` og mobile → PASS.

```bash
git add web/src/data/sammeSomPreflight.ts mobile/src/data/sammeSomPreflight.ts \
        web/src/data/__tests__/sammeSomPreflight.test.ts mobile/src/data/__tests__/sammeSomPreflight.test.ts
git commit -m "feat(app): rådgivende samme_som pre-flight via collapse (Task 6)"
```

---

## FASE C — UI

### Task 7: UI-affordance i person-editorens relations-sektion

**Files:**
- Modify: `web/src/Redaktion.tsx`, `mobile/src/app/redaktion/person/[id].tsx`
- Test: manuel (web-browser + Expo) — ingen ren enhedstest for skærmen.

**Interfaces:**
- Consumes: `Change`-arter (Task 4), `fetchSammeSomLinks` (Task 5), `previewSammeSom` (Task 6), eksisterende `PersonPicker` + dry-run/preview-flow (`submitChange`/`planCall`).

- [ ] **Step 1: "Marker som samme person…"-knap** i relations-sektionen → åbner `PersonPicker`.

- [ ] **Step 2: Retningsvælger** — vis begge personer (navn/år/linje) + hvem der er kanonisk; default = den redigerede person = kanonisk; "Byt retning"-knap. Byg `Change { art:'sammeSom', payload:{ aliasId, objektId } }`.

- [ ] **Step 3: Pre-flight-hint** — kald `previewSammeSom(redaktionDb, eksisterendeKanter, hypotetisk)`; hvis `!folder`, vis mærket advarsel: `⚠ Foldes ikke endnu — {grund}. (redaktionel projektion — offentlig visning kan afvige)`. Ikke-blokerende.

- [ ] **Step 4: Send gennem dry-run/preview → LIVE** (eksisterende `submitChange`-flow).

- [ ] **Step 5: Liste + fjern** — vis `fetchSammeSomLinks(personId)` med modpart-navn + retning; fjern-knap bygger `Change { art:'fjernSammeSom', relationId }` → preview → LIVE.

- [ ] **Step 6: Manuel verifikation** — web-browser + Expo: link Conrad (III-58) til V-1 via UI (dry-run vis `red_samme_som`-kald; én godkendt LIVE), bekræft at offentlig visning folder ved reload; fjern igen + fortryd. Notér i commit.

- [ ] **Step 7: Commit**

```bash
git add web/src/Redaktion.tsx "mobile/src/app/redaktion/person/[id].tsx"
git commit -m "feat(app): UI til redaktionel samme_som-linking + fjern (Task 7)"
```

---

## Self-review-noter

- **Spec-dækning:** §2 (ansvarsfordeling)→Task 1 (trigger) + 2/3 (RPC) + 6 (pre-flight); §3 (evidens-kontrakt)→Task 2; §4 (invarianter/trigger/retning)→Task 1+2; §5 (slet)→Task 3; §6 (pre-flight)→Task 6; §7 (app-lag)→Task 4/5/7; §8 (RLS)→Task 2/3 grants + redaktion-gate; §9 (test)→Task 1-6 asserts+tests.
- **Type-konsistens:** `red_samme_som(bigint,bigint)`, `red_fjern_samme_som(bigint)`, `Change.art` `sammeSom`/`fjernSammeSom`, `previewSammeSom`/`fetchSammeSomLinks`/`mapSammeSomLinks` — ens web+mobile.
- **DB-test-realitet:** trigger-invarianterne (G0/G3/G4/G5) testes rolle-uafhængigt via bare INSERT mod triggeren (Task 1/2 verify) — dækker kernen uden en redaktion-rolle-shim. RPC'ernes rolle-gate + evidens-skrivning + fjern+fortryd verificeres manuelt mod prod-kopi (Task 3 Step 4) + i app-test (Task 4). Prod-apply er et eksplicit bruger-gate (Task 3 Step 7).
- **Kendt begrænsning (bruger-godkendt):** `max(id)+1` race mod andre `red_*` (spec §3/H2) — accepteret v1.
