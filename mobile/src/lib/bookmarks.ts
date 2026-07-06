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
    if (!session) {
      // Funktionel updater: returnér SAMME reference når allerede tom, så React bail'er i stedet
      // for at re-rendere — ellers giver en ustabil canonicalIdById-reference (fx et inline {}
      // hos kaldstedet) en uendelig effekt-loop (setIdsList([]) → nyt canon-ref → effekt igen).
      // Fanget empirisk under web-portens egen test-kørsel (OOM); rettet her fra start.
      setIdsList((prev) => (prev.length === 0 ? prev : []));
      return;
    }
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
