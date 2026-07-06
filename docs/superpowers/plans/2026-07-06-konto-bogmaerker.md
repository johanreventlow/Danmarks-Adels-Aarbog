# Konto-bogmærker Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør bogmærker login-eksklusive og Supabase-synkroniserede (web + mobil), og erstat den lokale AsyncStorage/localStorage-lagring.

**Architecture:** En ny `bookmark`-tabel (RLS + eksplicitte grants, `user_id=auth.uid()`) erstatter lokal lagring. Hver platform får en `RemoteRepository` + en auth-gated `useBookmarks(session, canon)`-hook med race-guard (fokus-refetch klobrer ikke en optimistisk skrivning). Web får en minimal login-flade i den offentlige læser (mobil har den allerede).

**Tech Stack:** PostgreSQL/Supabase (RLS), TypeScript, `@supabase/supabase-js` (web + mobil), React/React Native, vitest (web) / jest (mobil).

## Global Constraints

- **Login-eksklusivt, ikke hybrid.** Ingen merge-logik, ingen offline-cache. Udlogget → tom liste, `canSave:false`.
- **Kun personer**, kanoniske (samme_som-collapsede) id'er.
- **`person_id` sendes altid som streng** til PostgREST — ALDRIG `Number(id)` (person.id er bigint; dual-review N2).
- **Eksplicit GRANT/REVOKE** på den nye tabel — RLS alene er ikke nok (repo-konvention + dual-review N1).
- **Idempotent DDL**: `CREATE TABLE IF NOT EXISTS`, `DROP POLICY IF EXISTS` (repo-konvention + dual-review N3).
- **Race-guard**: en fokus-refetch må ikke overskrive en igangværende optimistisk skrivning (dual-review H2).
- **Null-klient håndteres**: mobil `supabase` kan være `null` (offline-seed) → repository/hook må ikke crashe (dual-review N4).
- Hver task holder `tsc --noEmit` + eslint + hele jest/vitest-suiten grøn (mobil OG web).
- Kør mobil-kommandoer fra `mobile/`, web-kommandoer fra `web/`, DB-kommandoer fra repo-roden.
- Commit-footer: `Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR`. Ingen Claude-attribution-footers.
- Kilder: `docs/superpowers/specs/2026-07-06-konto-bogmaerker-design.md`, `docs/reviews/21-konto-bogmaerker-spec-dual-review.md`.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql` | `bookmark`-tabel + `ENABLE ROW LEVEL SECURITY` (source of truth) | 1 |
| `db-migrations.sql` | Idempotent mirror for allerede-deployet base | 1 |
| `db-rls.sql` | Grants + policies for `bookmark` | 1 |
| `db-verify.sql` | Task 13: RLS-isolation, dublet, cascade, anon-lukket | 1 |
| `web/src/data/bookmarks.ts` | `RemoteRepository` + auth-gated `useBookmarks` (omskrevet) | 2 |
| `web/src/data/__tests__/bookmarks.test.ts` | Opdateret test-suite | 2 |
| `web/src/Folgesvend.tsx` | Session-state + login-modal + wiring | 3, 4 |
| `web/src/components/BookmarksView.tsx` | Udlogget tom-tilstand | 4 |
| `mobile/src/lib/bookmarks.ts` | `RemoteRepository` + auth-gated `useBookmarks` (omskrevet) | 5 |
| `mobile/src/lib/__tests__/bookmarks.test.ts` | Opdateret test-suite | 5 |
| `mobile/src/app/(tabs)/index.tsx` | Session-wiring + `saveOrPrompt` | 6 |
| `mobile/src/app/bogmaerker.tsx` | Udlogget tom-tilstand + login-CTA | 6 |

---

## Task 1: DB-lag — `bookmark`-tabel, RLS, grants, verify

**Files:**
- Modify: `schema.sql` (tilføj tabel efter `suggestion`, ~linje 300)
- Modify: `db-migrations.sql` (idempotent mirror, tilføjes sidst)
- Modify: `db-rls.sql` (grants + policies, tilføjes efter `profiles`-blokken, ~linje 410)
- Modify: `db-verify.sql` (nyt "Task 13"-afsnit, tilføjes sidst)

**Interfaces:**
- Produces: tabellen `bookmark(id uuid, user_id uuid, person_id bigint, oprettet timestamptz)` + policies `bookmark_select_own`/`bookmark_insert_own`/`bookmark_delete_own` — dette er kontrakten Task 2 og 5's `RemoteRepository` forudsætter (`.from('bookmark').select('person_id')` / `.upsert({person_id})` / `.delete().eq('person_id', id)`).

- [ ] **Step 1: Tilføj tabellen i `schema.sql`**

Indsæt lige efter `suggestion`-tabellens lukkende `);` og de to `ENABLE ROW LEVEL SECURITY`-linjer (efter linje 304, før `CREATE TABLE family`):

```sql
CREATE TABLE bookmark (              -- login-eksklusive bogmærker (kun personer), spec 2026-07-06
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  oprettet  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, person_id)
);
-- RLS slås til ved oprettelse (deny-all indtil politikker + grants lander i db-rls.sql).
ALTER TABLE bookmark ENABLE ROW LEVEL SECURITY;
```

- [ ] **Step 2: Idempotent mirror i `db-migrations.sql`**

Tilføj sidst i filen:

```sql
-- 2026-07-06: konto-bogmærker — login-eksklusiv bookmark-tabel (design-spec 2026-07-06).
CREATE TABLE IF NOT EXISTS bookmark (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  oprettet  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, person_id)
);
ALTER TABLE bookmark ENABLE ROW LEVEL SECURITY;
```

- [ ] **Step 3: Grants + policies i `db-rls.sql`**

Indsæt efter `profiles`-blokken (efter `create policy self_read on public.profiles ...`, før RPC-grant-DO-blokken):

```sql
-- bookmark: login-eksklusive, egen-scoped (dual-review 21 N1 — eksplicit grant, RLS er ikke nok;
-- Supabase auto-grant'er default-privilegier til anon/authenticated på nye tabeller).
revoke all on table public.bookmark from anon, public;
grant select, insert, delete on table public.bookmark to authenticated;

drop policy if exists bookmark_select_own on public.bookmark;
create policy bookmark_select_own on public.bookmark
  for select to authenticated using (user_id = auth.uid());
drop policy if exists bookmark_insert_own on public.bookmark;
create policy bookmark_insert_own on public.bookmark
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists bookmark_delete_own on public.bookmark;
create policy bookmark_delete_own on public.bookmark
  for delete to authenticated using (user_id = auth.uid());
```

- [ ] **Step 4: Genopbyg lokal testbase frisk (matcher denne branch)**

Den eksisterende `daa_test` er forældet (mangler `media_variant` m.fl. fra nyere merges). Genopbyg fra bunden:

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:$PATH"
dropdb daa_test 2>/dev/null
createdb daa_test
cat > /tmp/00-supabase-shim.sql <<'EOF'
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
GRANT anon, authenticated TO CURRENT_USER;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT SELECT ON auth.users TO anon, authenticated;
EOF
psql -d daa_test -v ON_ERROR_STOP=1 -f /tmp/00-supabase-shim.sql
psql -d daa_test -v ON_ERROR_STOP=1 -f schema.sql
psql -d daa_test -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -d daa_test -f db-rls.sql 2>&1 | tail -20
```

Expected: alle tre kommandoer gennemfører uden `ERROR` (db-rls.sql kan mangle `ON_ERROR_STOP` — nogle politikker forudsætter allerede-kørte migrationer; se eksisterende brug af filen).

- [ ] **Step 5: Skriv + kør Task 13-verify-blokken**

Tilføj sidst i `db-verify.sql`:

```sql
-- ===== Task 13: bookmark — RLS-isolation, dublet-sikring, anon-lukket, cascade =====
DO $$
DECLARE cnt_a int; cnt_b int; insert_denied boolean := false; cnt_anon int;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-0000000000a1','a@test'),
    ('00000000-0000-0000-0000-0000000000a2','b@test')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO person(id) VALUES (-931),(-932) ON CONFLICT (id) DO NOTHING;

  -- Bruger A gemmer -931
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931);
  SELECT count(*) INTO cnt_a FROM bookmark WHERE person_id=-931;
  RESET ROLE;

  -- Bruger B ser IKKE A's bogmærke; forsøg på at skrive i A's navn afvises
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO cnt_b FROM bookmark WHERE person_id=-931;
  BEGIN
    INSERT INTO bookmark(user_id, person_id) VALUES ('00000000-0000-0000-0000-0000000000a1', -932);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN insert_denied := true;
  END;
  RESET ROLE;

  -- Anon kan hverken læse eller skrive
  SET LOCAL ROLE anon;
  SELECT count(*) INTO cnt_anon FROM bookmark WHERE person_id=-931;
  RESET ROLE;

  IF cnt_a <> 1 THEN RAISE EXCEPTION 'FEJL: bruger A ser ikke eget bogmærke (fik %)', cnt_a; END IF;
  IF cnt_b <> 0 THEN RAISE EXCEPTION 'FEJL: RLS-læk — bruger B ser bruger A''s bogmærke'; END IF;
  IF NOT insert_denied THEN RAISE EXCEPTION 'FEJL: WITH CHECK afviste ikke insert i fremmed navn'; END IF;
  IF cnt_anon <> 0 THEN RAISE EXCEPTION 'FEJL: anon kan læse bookmark (vent 0, fik %)', cnt_anon; END IF;

  -- Dubletsikring: samme (user,person) igen = no-op
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931) ON CONFLICT (user_id,person_id) DO NOTHING;
  RESET ROLE;

  -- Cascade: slet person -931 → bogmærket forsvinder
  DELETE FROM person WHERE id=-931;
  IF EXISTS (SELECT 1 FROM bookmark WHERE person_id=-931) THEN
    RAISE EXCEPTION 'FEJL: bookmark overlevede person-sletning (cascade virkede ikke)';
  END IF;

  DELETE FROM bookmark WHERE person_id IN (-931,-932);
  DELETE FROM person WHERE id IN (-931,-932);
  DELETE FROM auth.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2');
  RAISE NOTICE 'OK: bookmark RLS-isolation (egen-læs, fremmed-skriv afvist, anon blokeret) + cascade + dubletsikring';
END $$;
```

Kør KUN Task 13 (isoleret) mod den lokale base:

```bash
export PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:$PATH"
psql -d daa_test -f db-verify.sql 2>&1 | grep -A3 "Task 13" 
```

Expected: `NOTICE:  OK: bookmark RLS-isolation (egen-læs, fremmed-skriv afvist, anon blokeret) + cascade + dubletsikring` — ingen `ERROR` i outputtet for Task 13.

- [ ] **Step 6: Kør `get_advisors(security)` (bruger-gated prod-anvendelse senere)**

Dette step er en påmindelse, ikke en kommando her: når migrationen anvendes mod PROD (bruger-godkendt, separat trin), kør `mcp__supabase__get_advisors(type: 'security')` bagefter og luk evt. huller samme dag (jf. memory `koer-get-advisors-efter-ddl`).

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): bookmark-tabel — login-eksklusive konto-bogmærker (skive 1)

RLS + eksplicit grant/revoke (dual-review N1) + idempotent DDL (N3).
Task 13 i db-verify.sql: RLS-isolation, dublet-sikring, anon-lukket, cascade.
Verificeret lokalt mod frisk daa_test (schema.sql+db-migrations.sql+db-rls.sql).
Ikke anvendt mod prod endnu (kræver bruger-godkendelse).

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Task 2: Web — `RemoteRepository` + auth-gated `useBookmarks`

**Files:**
- Modify: `web/src/data/bookmarks.ts` (omskriv `createLocalBookmarkStore`+`useBookmarks`; behold `buildBookmarkList` uændret)
- Modify: `web/src/data/__tests__/bookmarks.test.ts`

**Interfaces:**
- Consumes: `web/src/supabase.ts` (`supabase`-klient, kaster ved manglende env — findes altid i denne kontekst).
- Produces:
  - `export interface BookmarkRepository { list(): Promise<string[]>; add(personId: string): Promise<void>; remove(personId: string): Promise<void>; }`
  - `export function createRemoteBookmarkRepository(): BookmarkRepository`
  - `export function useBookmarks(session: { userId: string } | null, canon: (id: string) => string): { ids: Set<string>; has(id: string): boolean; canSave: boolean; toggle(id: string): void }`
  - `buildBookmarkList` uændret (Task 4 bruger den stadig).

- [ ] **Step 1: Skriv de fejlende tests (mock supabase-klienten)**

Erstat hele `web/src/data/__tests__/bookmarks.test.ts` med:

```ts
// @vitest-environment jsdom
import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { buildBookmarkList, useBookmarks } from '../bookmarks';
import type { Model, ModelPerson } from '../types';

// In-memory fake af supabase.from('bookmark')-kæden. Delt mutabel tilstand pr. test.
let rows: { user_id: string; person_id: string }[] = [];
let failNextWrite = false;

vi.mock('../../supabase', () => ({
  supabase: {
    from: (table: string) => {
      if (table !== 'bookmark') throw new Error('uventet tabel: ' + table);
      return {
        select: () => ({
          order: () => Promise.resolve({ data: rows.map((r) => ({ person_id: r.person_id })), error: null }),
        }),
        upsert: (row: { person_id: string }) => {
          if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
          if (!rows.some((r) => r.person_id === row.person_id)) rows.unshift({ user_id: 'u1', person_id: row.person_id });
          return Promise.resolve({ error: null });
        },
        delete: () => ({
          eq: (_col: string, id: string) => {
            if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
            rows = rows.filter((r) => r.person_id !== id);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  },
}));

function person(id: string): ModelPerson {
  return { id, name: 'P' + id, born: null, died: null, years: '', title: '', bio: '', privat: false, parentId: null, spouse: '' };
}
function makeModel(persons: ModelPerson[]): Model {
  return {
    persons, byId: Object.fromEntries(persons.map((p) => [p.id, p])),
    indexes: { spousesBy: {}, childIdx: {}, parentsByChild: {}, childrenByUnion: {}, unionById: {}, konfByEdge: {} },
  };
}

beforeEach(() => { rows = []; failNextWrite = false; });

describe('useBookmarks — udlogget', () => {
  it('tom liste, canSave=false, toggle er no-op', () => {
    const { result } = renderHook(() => useBookmarks(null, (id) => id));
    expect(result.current.ids.size).toBe(0);
    expect(result.current.canSave).toBe(false);
    act(() => result.current.toggle('1'));
    expect(result.current.ids.size).toBe(0);
  });
});

describe('useBookmarks — logget ind', () => {
  const session = { userId: 'u1' };

  it('henter list() ved mount', async () => {
    rows = [{ user_id: 'u1', person_id: '42' }];
    const { result } = renderHook(() => useBookmarks(session, (id) => id));
    await waitFor(() => expect(result.current.ids.has('42')).toBe(true));
    expect(result.current.canSave).toBe(true);
  });

  it('toggle gemmer optimistisk + persisterer (person_id som streng)', async () => {
    const { result } = renderHook(() => useBookmarks(session, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    act(() => result.current.toggle('99999999999999'));
    expect(result.current.ids.has('99999999999999')).toBe(true);
    await waitFor(() => expect(rows.some((r) => r.person_id === '99999999999999')).toBe(true));
  });

  it('rollback ved skrivefejl', async () => {
    const { result } = renderHook(() => useBookmarks(session, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    failNextWrite = true;
    act(() => result.current.toggle('1'));
    expect(result.current.ids.has('1')).toBe(true); // optimistisk
    await waitFor(() => expect(result.current.ids.has('1')).toBe(false)); // rullet tilbage
  });

  it('kanoniciserer via canon', async () => {
    rows = [{ user_id: 'u1', person_id: 'alias1' }];
    const canon = (id: string) => (id === 'alias1' ? 'canon1' : id);
    const { result } = renderHook(() => useBookmarks(session, canon));
    await waitFor(() => expect(result.current.ids.has('canon1')).toBe(true));
  });
});

describe('buildBookmarkList (uændret)', () => {
  it('filtrerer ukendte id\'er', () => {
    const model = makeModel([person('1')]);
    const groups = buildBookmarkList(['1', '999'], model, 'navn');
    expect(groups[0].people.map((p) => p.id)).toEqual(['1']);
  });
});
```

- [ ] **Step 2: Kør — verificér FAIL**

Run: `cd web && npx vitest run src/data/__tests__/bookmarks.test.ts`
Expected: FAIL — `createLocalBookmarkStore`/gammel API findes stadig, ny signatur mangler.

- [ ] **Step 3: Omskriv `web/src/data/bookmarks.ts`**

Erstat filens øverste del (alt FØR `export type BookmarkSort` — behold `BookmarkSort`/`buildBookmarkList` uændret nedenunder):

```ts
// Bogmærke-lager (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: Supabase-backet
// repository + auth-gated hook. Erstatter den lokale localStorage-PoC (web v3 Slice 1).
// person_id sendes ALTID som streng til PostgREST (bigint > 2^53 korrumperes af Number() —
// dual-review 21 N2).
import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../supabase';
import { compareDanish } from '../lib/collation';
import type { Model, ModelPerson } from './types';

export interface BookmarkRepository {
  list(): Promise<string[]>;
  add(personId: string): Promise<void>;
  remove(personId: string): Promise<void>;
}

export function createRemoteBookmarkRepository(): BookmarkRepository {
  return {
    list: async () => {
      const { data, error } = await supabase.from('bookmark').select('person_id').order('oprettet', { ascending: false });
      if (error || !data) return [];
      return data.map((r: { person_id: string | number }) => String(r.person_id));
    },
    add: async (personId) => {
      const { error } = await supabase.from('bookmark').upsert(
        { person_id: personId },
        { onConflict: 'user_id,person_id', ignoreDuplicates: true },
      );
      if (error) throw new Error(error.message);
    },
    remove: async (personId) => {
      const { error } = await supabase.from('bookmark').delete().eq('person_id', personId);
      if (error) throw new Error(error.message);
    },
  };
}

function sameOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

// Auth-gated hook. Udlogget: tom, canSave=false, toggle no-op (kaldstedet gater FØR toggle —
// se onRequireLogin-mønstret i Folgesvend.tsx). Logget-ind: hent-ved-mount, optimistisk toggle
// m. write-generation-guard (H2): et in-flight-refetch klobrer ikke en igangværende skrivning.
export function useBookmarks(
  session: { userId: string } | null,
  canon: (id: string) => string,
): { ids: Set<string>; has(id: string): boolean; canSave: boolean; toggle(id: string): void } {
  const repoRef = useMemo(() => createRemoteBookmarkRepository(), []);
  const [idsList, setIdsList] = useState<string[]>([]);
  const pendingRef = useMemo(() => new Set<string>(), []); // id'er med in-flight write (H2-guard)

  useEffect(() => {
    if (!session) { setIdsList([]); return; }
    let alive = true;
    void repoRef.list().then((raw) => {
      if (!alive) return;
      const norm = raw.map(canon);
      // Merge: behold optimistisk tilstand for id'er der har en in-flight write (H2).
      setIdsList((prev) => {
        const merged = norm.filter((id) => !pendingRef.has(id) || prev.includes(id));
        for (const id of prev) if (pendingRef.has(id) && !merged.includes(id)) merged.unshift(id);
        return sameOrder(merged, prev) ? prev : merged;
      });
    });
    return () => { alive = false; };
  }, [session, canon, repoRef, pendingRef]);

  const ids = useMemo(() => new Set(idsList), [idsList]);

  const toggle = useCallback(
    (id: string) => {
      if (!session) return; // no-op udlogget — kaldstedet skal gate FØR dette kaldes
      const cid = canon(id);
      const wasIn = ids.has(cid);
      pendingRef.add(cid);
      setIdsList((prev) => (wasIn ? prev.filter((x) => x !== cid) : [cid, ...prev]));
      const op = wasIn ? repoRef.remove(cid) : repoRef.add(cid);
      op.then(
        () => pendingRef.delete(cid),
        () => {
          pendingRef.delete(cid);
          setIdsList((prev) => (wasIn ? [cid, ...prev] : prev.filter((x) => x !== cid))); // rollback
        },
      );
    },
    [session, canon, ids, repoRef, pendingRef],
  );

  return { ids, has: (id) => ids.has(canon(id)), canSave: session != null, toggle };
}
```

- [ ] **Step 4: Kør — verificér PASS**

Run: `cd web && npx vitest run src/data/__tests__/bookmarks.test.ts`
Expected: PASS.

- [ ] **Step 5: Typecheck**

Run: `cd web && npx tsc -b --noEmit 2>&1 | grep -v Folgesvend` (Folgesvend.tsx-fejl forventes indtil Task 3; ignorér dem her)

- [ ] **Step 6: Commit**

```bash
git add web/src/data/bookmarks.ts web/src/data/__tests__/bookmarks.test.ts
git commit -m "feat(bogmaerker): web RemoteRepository + auth-gated useBookmarks (skive 2)

Erstatter localStorage-lager. Session-gated (canSave), optimistisk toggle m.
pending-guard (dual-review H2: fokus-refetch klobrer ikke in-flight write).
person_id sendes som streng (N2). buildBookmarkList uændret.

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Task 3: Web — login-session i den offentlige læser

**Files:**
- Modify: `web/src/Folgesvend.tsx`

**Interfaces:**
- Consumes: `signIn`, `signOut`, `currentSession`, `type RedSession` fra `./data/auth` (allerede eksisterende).
- Produces: lokal state `session: RedSession | null`, `loginOpen: boolean` — bruges af Task 4.

- [ ] **Step 1: Tilføj import + session-state**

Find linje 17-19 (`import { useBookmarks, type BookmarkSort } from './data/bookmarks';`) og tilføj lige efter:

```tsx
import { signIn, signOut, currentSession, type RedSession } from './data/auth';
```

Find linje ~93 (`const [meId, setMeId] = useState<string | null>(...)`) og tilføj lige efter:

```tsx
  const [session, setSession] = useState<RedSession | null>(null);
  const [loginOpen, setLoginOpen] = useState(false);
  const [login, setLogin] = useState<{ email: string; pw: string; err: string; busy: boolean }>(
    { email: '', pw: '', err: '', busy: false },
  );
  useEffect(() => {
    void currentSession().then(setSession);
  }, []);
  const doLogin = async () => {
    if (!login.email.trim() || !login.pw) { setLogin((l) => ({ ...l, err: 'Udfyld e-mail og adgangskode' })); return; }
    setLogin((l) => ({ ...l, busy: true, err: '' }));
    try {
      const s = await signIn(login.email, login.pw);
      setSession(s);
      setLoginOpen(false);
      setLogin({ email: '', pw: '', err: '', busy: false });
    } catch (e) {
      setLogin((l) => ({ ...l, busy: false, err: e instanceof Error ? e.message : 'Login fejlede' }));
    }
  };
  const doLogout = async () => { await signOut(); setSession(null); };
```

> **Bemærk:** verificér at `useEffect` allerede er importeret fra `'react'` øverst i filen (den er, filen bruger `useEffect` andre steder for path-state).

- [ ] **Step 2: Tilføj login-modal (JSX)**

Find `<SlaegtPicker open={slaegtOpen} ... />` (linje ~465) og tilføj EFTER den lukkende `/>`:

```tsx
      {loginOpen && (
        <div onClick={() => setLoginOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(20,17,13,.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 200 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ width: 380, maxWidth: '100%', background: T.paper, borderRadius: 16, border: '1px solid rgba(34,31,26,.14)', boxShadow: '0 24px 60px rgba(0,0,0,.3)', padding: '22px 24px 20px' }}>
            <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600 }}>Log ind</div>
            <div style={{ fontSize: 12, color: T.muted, marginTop: 3, marginBottom: 15 }}>Log ind for at gemme bogmærker på tværs af dine enheder.</div>
            <input value={login.email} onChange={(e) => setLogin((l) => ({ ...l, email: e.target.value }))} placeholder="din@email.dk" style={{ width: '100%', fontSize: 13, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none' }} />
            <input value={login.pw} type="password" onChange={(e) => setLogin((l) => ({ ...l, pw: e.target.value }))} style={{ width: '100%', fontSize: 13, color: '#221f1a', background: '#fff', border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 10px', outline: 'none', marginTop: 11 }} />
            {login.err && <div style={{ fontSize: 11.5, color: T.red, marginTop: 9 }}>{login.err}</div>}
            <div style={{ display: 'flex', gap: 9, marginTop: 16, justifyContent: 'flex-end' }}>
              <div onClick={() => setLoginOpen(false)} style={{ fontSize: 12, fontWeight: 600, color: T.muted, padding: '8px 13px', cursor: 'pointer' }}>Annullér</div>
              <div onClick={doLogin} style={{ fontSize: 12, fontWeight: 600, color: '#fbf8f1', background: T.bordeaux, borderRadius: 7, padding: '8px 13px', cursor: 'pointer' }}>{login.busy ? 'Logger ind…' : 'Log ind'}</div>
            </div>
          </div>
        </div>
      )}
```

- [ ] **Step 3: Typecheck**

Run: `cd web && npx tsc -b --noEmit`
Expected: kun fejl relateret til Task 4's endnu-manglende wiring (ubrugte `doLogout`/`session` er OK indtil da — hvis tsc klager over ubrugte, tilføj et midlertidigt `void session; void doLogout;` — fjernes i Task 4).

- [ ] **Step 4: Commit**

```bash
git add web/src/Folgesvend.tsx
git commit -m "feat(bogmaerker): web login-session + modal i den offentlige læser (skive 3)

Genbruger eksisterende data/auth.ts (signIn/signOut/currentSession). Ingen ny
auth-mekanik — kun session-state + minimal modal (stil fra Redaktion.tsx).
Wiring til bogmærker følger i næste task.

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Task 4: Web — wire session ind i bogmærker + gate UI

**Files:**
- Modify: `web/src/Folgesvend.tsx`
- Modify: `web/src/components/BookmarksView.tsx`

**Interfaces:**
- Consumes: `session`/`loginOpen`/`setLoginOpen` fra Task 3; `useBookmarks(session, canon)` fra Task 2.

- [ ] **Step 1: Opdatér `useBookmarks`-kaldet + tilføj `saveOrPrompt`**

Find linje 117 (`const bookmarks = useBookmarks(canon);`) og erstat med:

```tsx
  const bookmarks = useBookmarks(session ? { userId: session.userId } : null, canon);
  const saveOrPrompt = useCallback(
    (id: string) => { if (bookmarks.canSave) bookmarks.toggle(id); else setLoginOpen(true); },
    [bookmarks],
  );
```

> **Bemærk:** `useCallback` skal allerede være importeret (filen bruger den til `canon`, linje 113).

- [ ] **Step 2: Erstat alle `bookmarks.toggle`-kald med `saveOrPrompt`**

Find og erstat (grep `bookmarks.toggle` i filen — 4 forekomster udover hook-kaldet selv):
- Linje ~362: `trailing={<BookmarkFlag active onClick={() => bookmarks.toggle(id)} />}` → `onClick={() => saveOrPrompt(id)}`
- Linje ~442: `onToggleBookmark={bookmarks.toggle}` (TreeView-prop) → `onToggleBookmark={saveOrPrompt}`
- Linje ~447: `onRemove={bookmarks.toggle}` (BookmarksView-prop) → `onRemove={saveOrPrompt}`
- Linje ~460: `onToggleBookmark={() => bookmarks.toggle(focusId)}` → `onToggleBookmark={() => saveOrPrompt(focusId)}`

Ingen ændring nødvendig for `bookmarks.has` (virker uændret: altid `false` når udlogget, hvilket er korrekt UI).

- [ ] **Step 3: BookmarksView udlogget tom-tilstand**

I `web/src/components/BookmarksView.tsx`, tilføj en `loggedIn`-prop og differentiér tom-teksten:

```tsx
export function BookmarksView({ model, ids, sort, setSort, onPick, onRemove, loggedIn, onRequireLogin }: {
  model: Model; ids: string[]; sort: BookmarkSort; setSort: (s: BookmarkSort) => void;
  onPick: (id: string) => void; onRemove: (id: string) => void;
  loggedIn: boolean; onRequireLogin: () => void;
}) {
```

Erstat tom-tilstands-blokken (`{total === 0 ? (...) : (...)}`s første gren):

```tsx
      {total === 0 ? (
        <div style={{ border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 20, background: T.paper, fontSize: 13, color: T.muted3, textAlign: 'center' }}>
          {loggedIn ? (
            'Ingen bogmærker endnu — tryk flaget på en person for at gemme den her.'
          ) : (
            <>
              Log ind for at samle dine bogmærker på tværs af dine enheder.
              <div onClick={onRequireLogin} style={{ marginTop: 10, display: 'inline-block', fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>Log ind ›</div>
            </>
          )}
        </div>
      ) : (
```

- [ ] **Step 4: Wire de nye props ved kaldsstedet i `Folgesvend.tsx`**

Find linje 447 igen (efter Step 2's ændring) og udbyg propsene:

```tsx
: mode === 'bookmarks' ? (model ? <BookmarksView model={model} ids={bookmarkIds} sort={bmSort} setSort={setBmSort} onPick={pickBookmark} onRemove={saveOrPrompt} loggedIn={bookmarks.canSave} onRequireLogin={() => setLoginOpen(true)} /> : <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>)
```

- [ ] **Step 5: Typecheck + hele test-suiten**

Run: `cd web && npx tsc -b --noEmit && npx vitest run`
Expected: tsc rent, alle tests grønne.

- [ ] **Step 6: Commit**

```bash
git add web/src/Folgesvend.tsx web/src/components/BookmarksView.tsx
git commit -m "feat(bogmaerker): web UX-wiring — saveOrPrompt gater alle gem-steder (skive 4)

Udlogget tap → login-modal (ikke stille no-op). BookmarksView differentierer
tom-tilstand (ingen bogmærker vs. log-ind-CTA).

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Task 5: Mobil — `RemoteRepository` + auth-gated `useBookmarks`

**Files:**
- Modify: `mobile/src/lib/bookmarks.ts` (omskriv; drop `AsyncStorage`/`nextBookmarks`/`canonicalize`/`createLocalBookmarkStore`)
- Modify: `mobile/src/lib/__tests__/bookmarks.test.ts`

**Interfaces:**
- Consumes: `mobile/src/lib/supabase.ts` (`supabase: SupabaseClient | null`, `supabaseEnabled: boolean`).
- Produces:
  - `export interface BookmarkRepository { list(): Promise<string[]>; add(personId: string): Promise<void>; remove(personId: string): Promise<void>; }`
  - `export function createRemoteBookmarkRepository(): BookmarkRepository`
  - `export function useBookmarks(session: import('@supabase/supabase-js').Session | null, canonicalIdById: Record<string,string>): { ids: Set<string>; has(id: string): boolean; canSave: boolean; toggle(id: string): void; count: number }`

- [ ] **Step 1: Skriv de fejlende tests (mock `../supabase`)**

Erstat hele `mobile/src/lib/__tests__/bookmarks.test.ts` med:

```ts
import { act, renderHook, waitFor } from '@testing-library/react-native';
import { useBookmarks, createRemoteBookmarkRepository } from '../bookmarks';

let rows: { user_id: string; person_id: string }[] = [];
let failNextWrite = false;

jest.mock('../supabase', () => ({
  supabase: {
    from: (table: string) => {
      if (table !== 'bookmark') throw new Error('uventet tabel: ' + table);
      return {
        select: () => ({
          order: () => Promise.resolve({ data: rows.map((r) => ({ person_id: r.person_id })), error: null }),
        }),
        upsert: (row: { person_id: string }) => {
          if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
          if (!rows.some((r) => r.person_id === row.person_id)) rows.unshift({ user_id: 'u1', person_id: row.person_id });
          return Promise.resolve({ error: null });
        },
        delete: () => ({
          eq: (_col: string, id: string) => {
            if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
            rows = rows.filter((r) => r.person_id !== id);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  },
  supabaseEnabled: true,
}));

const SESSION = { user: { id: 'u1' } } as unknown as import('@supabase/supabase-js').Session;

beforeEach(() => { rows = []; failNextWrite = false; });

describe('createRemoteBookmarkRepository', () => {
  it('list/add/remove sender person_id som streng', async () => {
    const repo = createRemoteBookmarkRepository();
    await repo.add('99999999999999');
    expect(await repo.list()).toEqual(['99999999999999']);
    await repo.remove('99999999999999');
    expect(await repo.list()).toEqual([]);
  });
});

describe('useBookmarks — udlogget', () => {
  it('tom liste, canSave=false, toggle no-op', () => {
    const { result } = renderHook(() => useBookmarks(null, {}));
    expect(result.current.ids.size).toBe(0);
    expect(result.current.canSave).toBe(false);
    act(() => result.current.toggle('1'));
    expect(result.current.ids.size).toBe(0);
  });
});

describe('useBookmarks — logget ind', () => {
  it('henter list() ved mount', async () => {
    rows = [{ user_id: 'u1', person_id: '42' }];
    const { result } = renderHook(() => useBookmarks(SESSION, {}));
    await waitFor(() => expect(result.current.has('42')).toBe(true));
    expect(result.current.canSave).toBe(true);
  });

  it('toggle optimistisk + rollback ved fejl', async () => {
    const { result } = renderHook(() => useBookmarks(SESSION, {}));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    failNextWrite = true;
    act(() => result.current.toggle('1'));
    expect(result.current.has('1')).toBe(true);
    await waitFor(() => expect(result.current.has('1')).toBe(false));
  });

  it('kanoniciserer via canonicalIdById-map', async () => {
    rows = [{ user_id: 'u1', person_id: 'alias1' }];
    const { result } = renderHook(() => useBookmarks(SESSION, { alias1: 'canon1' }));
    await waitFor(() => expect(result.current.has('canon1')).toBe(true));
  });
});
```

> **Bemærk til implementer:** hvis `@testing-library/react-native` ikke er installeret (bekræftet manglende i skive 1-4's plan), tilføj den: `npm install --save-dev @testing-library/react-native` i `mobile/`. Den er nødvendig her for at teste selve hook'en (skive 1-4's `bookmarks.test.ts` undgik dette ved kun at teste det rene lager — nu er der ingen "rent lager" tilbage at teste isoleret, da hele repository-laget er netværks-async).

- [ ] **Step 2: Kør — verificér FAIL**

Run: `cd mobile && npx jest lib/__tests__/bookmarks.test.ts`
Expected: FAIL — modulet eksporterer stadig den gamle API.

- [ ] **Step 3: Omskriv `mobile/src/lib/bookmarks.ts`**

```ts
// Bogmærke-lager (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: Supabase-backet
// repository + auth-gated hook. Erstatter AsyncStorage-PoC. person_id sendes ALTID som streng
// til PostgREST (bigint > 2^53 korrumperes af Number() — dual-review 21 N2).
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';

export interface BookmarkRepository {
  list(): Promise<string[]>;
  add(personId: string): Promise<void>;
  remove(personId: string): Promise<void>;
}

// Null-klient (dual-review N4): mobil `supabase` er null uden env (offline-seed). Tom liste,
// no-op writes — ingen crash.
export function createRemoteBookmarkRepository(): BookmarkRepository {
  return {
    list: async () => {
      if (!supabase) return [];
      const { data, error } = await supabase.from('bookmark').select('person_id').order('oprettet', { ascending: false });
      if (error || !data) return [];
      return data.map((r: { person_id: string | number }) => String(r.person_id));
    },
    add: async (personId) => {
      if (!supabase) return;
      const { error } = await supabase.from('bookmark').upsert(
        { person_id: personId },
        { onConflict: 'user_id,person_id', ignoreDuplicates: true },
      );
      if (error) throw new Error(error.message);
    },
    remove: async (personId) => {
      if (!supabase) return;
      const { error } = await supabase.from('bookmark').delete().eq('person_id', personId);
      if (error) throw new Error(error.message);
    },
  };
}

function sameOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

// Auth-gated hook. Udlogget: tom, canSave=false, toggle no-op. Logget-ind: hent-ved-mount,
// optimistisk toggle m. write-generation-guard (dual-review H2): et in-flight-refetch klobrer
// ikke en igangværende skrivning. Dep = canonicalIdById-MAPPET (ikke funktionsreference).
export function useBookmarks(
  session: Session | null,
  canonicalIdById: Record<string, string>,
): { ids: Set<string>; has(id: string): boolean; canSave: boolean; toggle(id: string): void; count: number } {
  const repoRef = useMemo(() => createRemoteBookmarkRepository(), []);
  const [idsList, setIdsList] = useState<string[]>([]);
  const pendingRef = useMemo(() => new Set<string>(), []);
  const canon = useMemo(() => (id: string) => canonicalIdById[id] ?? id, [canonicalIdById]);

  useEffect(() => {
    if (!session) { setIdsList([]); return; }
    let alive = true;
    void repoRef.list().then((raw) => {
      if (!alive) return;
      const norm = raw.map(canon);
      setIdsList((prev) => {
        const merged = norm.filter((id) => !pendingRef.has(id) || prev.includes(id));
        for (const id of prev) if (pendingRef.has(id) && !merged.includes(id)) merged.unshift(id);
        return sameOrder(merged, prev) ? prev : merged;
      });
    });
    return () => { alive = false; };
  }, [session, canon, repoRef, pendingRef]);

  const ids = useMemo(() => new Set(idsList), [idsList]);

  const toggle = useCallback(
    (id: string) => {
      if (!session) return;
      const cid = canon(id);
      const wasIn = ids.has(cid);
      pendingRef.add(cid);
      setIdsList((prev) => (wasIn ? prev.filter((x) => x !== cid) : [cid, ...prev]));
      const op = wasIn ? repoRef.remove(cid) : repoRef.add(cid);
      op.then(
        () => pendingRef.delete(cid),
        () => {
          pendingRef.delete(cid);
          setIdsList((prev) => (wasIn ? [cid, ...prev] : prev.filter((x) => x !== cid)));
        },
      );
    },
    [session, canon, ids, repoRef, pendingRef],
  );

  const has = useCallback((id: string) => ids.has(canon(id)), [ids, canon]);

  return { ids, has, canSave: session != null, toggle, count: idsList.length };
}
```

- [ ] **Step 4: Kør — verificér PASS**

Run: `cd mobile && npx jest lib/__tests__/bookmarks.test.ts`
Expected: PASS.

- [ ] **Step 5: Typecheck + hele suiten**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: tsc rent (forvent midlertidige fejl i `index.tsx`/`bogmaerker.tsx` pga. gammel `useBookmarks(canonMap)`-signatur — løses i Task 6).

- [ ] **Step 6: Commit**

```bash
git add mobile/src/lib/bookmarks.ts mobile/src/lib/__tests__/bookmarks.test.ts mobile/package.json mobile/package-lock.json
git commit -m "feat(bogmaerker): mobil RemoteRepository + auth-gated useBookmarks (skive 5)

Erstatter AsyncStorage-lager. Session-gated (canSave), optimistisk toggle m.
pending-guard (dual-review H2). Null-klient håndteret (N4). person_id som streng (N2).

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Task 6: Mobil — wire session + gate UX

**Files:**
- Modify: `mobile/src/app/(tabs)/index.tsx`
- Modify: `mobile/src/app/bogmaerker.tsx`

**Interfaces:**
- Consumes: `useStore((s) => s.session)` (allerede i storen), `useBookmarks(session, canonicalIdById)` fra Task 5.

- [ ] **Step 1: Opdatér `index.tsx`**

Find (fra tidligere skive):
```ts
  const canonMap = useStore((s) => s.canonicalIdById);
```
Tilføj lige efter:
```ts
  const session = useStore((s) => s.session);
```

Find:
```ts
  const { has, toggle, count } = useBookmarks(canonMap);
```
Erstat med:
```ts
  const { has, toggle, canSave, count } = useBookmarks(session, canonMap);
  const saveOrPrompt = useCallback(
    (id: string) => { if (canSave) toggle(id); else router.push('/konto'); },
    [canSave, toggle, router],
  );
```

Find `renderItem`-funktionens `onSave={toggle}` (i `FeedCardView`-kaldet) og erstat med `onSave={saveOrPrompt}`. Opdatér `useCallback`-dependency-arrayet for `renderItem` fra `[has, toggle, openCard]` til `[has, saveOrPrompt, openCard]`.

> **Bemærk:** `useCallback` er allerede importeret (bruges til `openCard`/`renderItem`).

- [ ] **Step 2: Opdatér `bogmaerker.tsx`**

Erstat hele filen:

```tsx
// Bogmærker-skærm (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: udlogget viser tom-
// tilstand med login-CTA i stedet for en liste.
import { useRouter } from 'expo-router';
import { useMemo } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../components/InitialBadge';
import { LoadGate } from '../components/LoadGate';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { useBookmarks } from '../lib/bookmarks';
import { useStore } from '../store/useStore';
import { Border, Colors } from '../theme/tokens';

export default function BogmaerkerScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const canonMap = useStore((s) => s.canonicalIdById);
  const session = useStore((s) => s.session);
  const { ids, canSave } = useBookmarks(session, canonMap);

  const people = useMemo(
    () => (model ? [...ids].map((id) => model.byId[id]).filter(Boolean) : []),
    [ids, model],
  );

  return (
    <LoadGate>
      <ScrollView
        style={{ flex: 1, backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top + 12, paddingHorizontal: 18, paddingBottom: 30 }}>
        {!canSave ? (
          <View style={{ marginTop: 24 }}>
            <Body size={13} color={Colors.textSecondary2}>
              Log ind for at samle dine bogmærker på tværs af dine enheder.
            </Body>
            <Pressable onPress={() => router.push('/konto')} style={{ marginTop: 12 }}>
              <BtnLabel size={13} color={Colors.bordeaux}>Log ind ›</BtnLabel>
            </Pressable>
          </View>
        ) : people.length === 0 ? (
          <Body size={13} color={Colors.textSecondary2} style={{ marginTop: 24 }}>
            Du har endnu ikke gemt nogen blade. Tryk bogmærke-ikonet på et kort i feedet.
          </Body>
        ) : (
          <>
            <Body size={13} color={Colors.textSecondary2} style={{ marginBottom: 14 }}>
              Blade du har gemt fra feedet.
            </Body>
            {people.map((p) => (
              <Pressable
                key={p.id}
                onPress={() => router.push(`/person/${p.id}`)}
                style={{
                  flexDirection: 'row', alignItems: 'center', gap: 13, paddingVertical: 12,
                  borderBottomWidth: 1, borderBottomColor: Border.faint,
                }}>
                <InitialBadge name={p.name} size={42} bg={Colors.beige2} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={18} style={{ lineHeight: 19 }}>{p.name}</Serif>
                  {p.years ? <Body size={11.5} color={Colors.textSecondary2}>{p.years}</Body> : null}
                </View>
                <Serif size={18} color="#bcae93">›</Serif>
              </Pressable>
            ))}
          </>
        )}
      </ScrollView>
    </LoadGate>
  );
}
```

- [ ] **Step 3: Typecheck + hele suiten**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: tsc rent, alle tests grønne.

- [ ] **Step 4: Simulator-verifikation**

Kør appen i iOS-simulatoren (jf. tidligere etableret mønster: `npx expo start --port 8081` + `xcrun simctl launch`). Log ind via Konto-fanen; bekræft: gem-ikon på et feed-kort virker (badge opdaterer); log ud → forsidens badge forsvinder og gem-ikon-tap ruter til Konto; Bogmærker-skærm viser login-CTA udlogget.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/app/\(tabs\)/index.tsx mobile/src/app/bogmaerker.tsx
git commit -m "feat(bogmaerker): mobil UX-wiring — session-gated gem + login-CTA (skive 6)

Udlogget tap på gem-ikon ruter til Konto (ikke stille no-op). Bogmærker-skærm
viser login-CTA udlogget i stedet for tom liste.

Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR"
```

---

## Verifikation (afsluttende)

- [ ] `cd web && npx tsc -b --noEmit && npx vitest run` — grøn.
- [ ] `cd mobile && npx tsc --noEmit && npx jest` — grøn.
- [ ] `psql -d daa_test -f db-verify.sql 2>&1 | grep -c FEJL` → 0 for Task 13 (øvrige pre-eksisterende forventede fejl jf. filens header uændret).
- [ ] iOS-simulator + browser: gem på én "enhed" (logget ind), se på en anden (samme konto) — cross-device bekræftet.
- [ ] Opdater `docs/changelog.md` + `docs/decisions.md` + memory (link til [[folgesvend-v3-feed-drawer-bogmaerker]]).
- [ ] **Prod-anvendelse af DB-migrationen kræver eksplicit bruger-godkendelse** (git-gate) — ikke en del af denne plans automatiske scope.

---

## Self-review-noter (udført ved skrivning)

- **Spec-dækning:** §4 (DB) → Task 1; §5 (repository/hook) → Task 2+5; §6 (web-login) → Task 3; §7 (UX-wiring) → Task 4+6; §8 (test) → alle tasks' Step 1-2/4-5; §9 (risici N1-N5/H1-H2/M1-M2/L1) → indarbejdet inline (grants i Task 1, race-guard i Task 2+5, streng-id i Task 2+5, null-klient i Task 5).
- **Type-konsistens:** `BookmarkRepository`/`useBookmarks`-signaturen er identisk på tværs af Task 2 og 5 (kun `session`-typen differentierer: `{userId:string}|null` web vs. `Session|null` mobil, som matcher hver platforms eksisterende auth-type).
- **Kendt afgrænsning:** web's Task 3-login er en minimal modal (ikke en fuld konto-flade som mobil's Konto-fane) — bevidst, jf. spec §6 "minimalt".
