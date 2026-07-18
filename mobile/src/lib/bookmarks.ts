// Bogmærke-lager (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: Supabase-backet
// repository + auth-gated hook. Erstatter AsyncStorage-PoC. person_id sendes ALTID som streng
// til PostgREST (bigint > 2^53 korrumperes af Number() — dual-review 21 N2).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
//
// Tager `userId: string | null` (IKKE et Session-objekt) — review 22 N1/kontrakt-konsistens
// med web-porten: en primitiv streng er referentielt stabil så længe brugeren er den samme
// (modsat et objekt-literal bygget ved kaldstedet).
export function useBookmarks(
  userId: string | null,
  canonicalIdById: Record<string, string>,
): { ids: Set<string>; has(id: string): boolean; canSave: boolean; ready: boolean; hydrationVersion: number; toggle(id: string): void; count: number } {
  const repoRef = useMemo(() => createRemoteBookmarkRepository(), []);
  const [idsList, setIdsList] = useState<string[]>([]);
  // Mutérbar side-kanal uden for render/state-cyklussen — useRef (ikke useMemo, som React
  // Compiler-lint'en behandler som immutabelt): pendingRef.current's INDHOLD muteres i effekt/
  // callbacks, aldrig selve .current under render (react-hooks/immutability + react-hooks/refs).
  const pendingRef = useRef<Set<string>>(new Set());
  const lastUserIdRef = useRef<string | null>(null); // seneste userId effekten faktisk fetchede for
  const [loadedFor, setLoadedFor] = useState<{
    userId: string;
    canonicalIdById: Record<string, string>;
  } | null>(null);
  const [hydrationVersion, setHydrationVersion] = useState(0);
  const canon = useMemo(() => (id: string) => canonicalIdById[id] ?? id, [canonicalIdById]);

  useEffect(() => {
    if (!userId) {
      // `ids` beregnes tom nedenfor. Hydreringsmarkøren skal dog nulstilles, så et senere
      // login som samme bruger ikke kan genbruge den afsluttede forrige session.
      lastUserIdRef.current = null;
      // eslint-disable-next-line react-hooks/set-state-in-effect -- sessionsikker reset ved logout
      setLoadedFor(null);
      return;
    }
    // Ryd KUN ved et REELT brugerskift (review 22 N2-mitigering), sporet via ref — ikke ved
    // hvert effekt-genkør (fx pga. en ustabil canonicalIdById-reference), som ellers ville
    // genskabe samme uendelig-render-loop-mønster som udlogget-grenen er hærdet mod.
    if (lastUserIdRef.current !== userId) {
      setIdsList((prev) => (prev.length === 0 ? prev : []));
    }
    lastUserIdRef.current = userId;
    let alive = true;
    void repoRef.list().then((raw) => {
      if (!alive) return;
      const norm = raw.map(canon);
      setIdsList((prev) => {
        const pending = pendingRef.current;
        const merged = norm.filter((id) => !pending.has(id) || prev.includes(id));
        for (const id of prev) if (pending.has(id) && !merged.includes(id)) merged.unshift(id);
        return sameOrder(merged, prev) ? prev : merged;
      });
      setLoadedFor({ userId, canonicalIdById });
      setHydrationVersion((version) => version + 1);
    });
    return () => { alive = false; };
  }, [userId, canon, canonicalIdById, repoRef]);

  // Afledt (ikke lagret): tom når udlogget, uanset hvad idsList internt måtte indeholde fra en
  // tidligere session — undgår enhver setState-i-effekt for logout-overgangen.
  const ready = userId == null || (
    loadedFor?.userId === userId && loadedFor.canonicalIdById === canonicalIdById
  );
  const ids = useMemo(
    () => (userId && ready ? new Set(idsList) : new Set<string>()),
    [userId, ready, idsList],
  );

  const toggle = useCallback(
    (id: string) => {
      if (!userId) return;
      const cid = canon(id);
      if (pendingRef.current.has(cid)) return; // review 22 M1: ignorér gentaget tryk mens in-flight
      const wasIn = ids.has(cid);
      pendingRef.current.add(cid);
      setIdsList((prev) => (wasIn ? prev.filter((x) => x !== cid) : [cid, ...prev]));
      const op = wasIn ? repoRef.remove(cid) : repoRef.add(cid);
      op.then(
        () => pendingRef.current.delete(cid),
        () => {
          pendingRef.current.delete(cid);
          setIdsList((prev) => (wasIn ? [cid, ...prev] : prev.filter((x) => x !== cid)));
        },
      );
    },
    [userId, canon, ids, repoRef],
  );

  const has = useCallback((id: string) => ids.has(canon(id)), [ids, canon]);

  // review 22 H1: count afledt af det session-gatede `ids` (IKKE rå idsList.length, som
  // forblev ikke-nulstillet efter logout og viste et stale badge-tal).
  return {
    ids, has, canSave: userId != null, ready, hydrationVersion, toggle, count: ids.size,
  };
}
