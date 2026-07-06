// Bogmærke-lager (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: Supabase-backet
// repository + auth-gated hook. Erstatter AsyncStorage-PoC. person_id sendes ALTID som streng
// til PostgREST (bigint > 2^53 korrumperes af Number() — dual-review 21 N2).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
  // Mutérbar side-kanal uden for render/state-cyklussen — useRef (ikke useMemo, som React
  // Compiler-lint'en behandler som immutabelt): pendingRef.current's INDHOLD muteres i effekt/
  // callbacks, aldrig selve .current under render (react-hooks/immutability + react-hooks/refs).
  const pendingRef = useRef<Set<string>>(new Set());
  const canon = useMemo(() => (id: string) => canonicalIdById[id] ?? id, [canonicalIdById]);

  useEffect(() => {
    // Ingen setState her: udlogget → ingen fetch, og `ids` beregnes tom nedenfor (afledt af
    // session, ikke lagret) — undgår react-hooks/set-state-in-effect OG den uendelige render-
    // loop en ustabil canonicalIdById-reference ellers ville give (fanget under web-portens
    // egen test-kørsel: OOM).
    if (!session) return;
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
    });
    return () => { alive = false; };
  }, [session, canon, repoRef]);

  // Afledt (ikke lagret): tom når udlogget, uanset hvad idsList internt måtte indeholde fra en
  // tidligere session — undgår enhver setState-i-effekt for logout-overgangen.
  const ids = useMemo(() => (session ? new Set(idsList) : new Set<string>()), [session, idsList]);

  const toggle = useCallback(
    (id: string) => {
      if (!session) return;
      const cid = canon(id);
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
    [session, canon, ids, repoRef],
  );

  const has = useCallback((id: string) => ids.has(canon(id)), [ids, canon]);

  return { ids, has, canSave: session != null, toggle, count: idsList.length };
}
