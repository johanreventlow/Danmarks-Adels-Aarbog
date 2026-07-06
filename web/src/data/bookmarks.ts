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
    if (!session) {
      // Funktionel updater: returnér SAMME reference når allerede tom, så React bail'er i stedet
      // for at re-rendere — ellers giver en ustabil canon-reference (uden useCallback hos
      // kaldstedet) en uendelig effekt-loop (setIdsList([]) → nyt canon-ref → effekt igen).
      setIdsList((prev) => (prev.length === 0 ? prev : []));
      return;
    }
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

export type BookmarkSort = 'linje' | 'navn';

// Ren funktion til den fulde bogmærke-visning (sortérbar), testbar uden komponent (spec §3.2).
export function buildBookmarkList(
  ids: string[],
  model: Model,
  sort: BookmarkSort,
): { linje: string | null; navn: string; people: ModelPerson[] }[] {
  const people = ids.map((id) => model.byId[id]).filter((p): p is ModelPerson => p != null);

  if (sort === 'navn') {
    return [{ linje: null, navn: '', people: [...people].sort((a, b) => compareDanish(a.name, b.name)) }];
  }

  // sort === 'linje': lineage.byPerson er string[] uden primær-markør — personen placeres
  // deterministisk i gruppen for sin FØRSTE linje-kode (ren display-placering, ikke en
  // påstand om primaritet). Personer uden nogen linje-kode havner i "Uden linje" sidst.
  const byPerson = model.lineage?.byPerson ?? {};
  const linjeNavn = model.lineage?.navn ?? {};
  const grouped = new Map<string, ModelPerson[]>();
  const uden: ModelPerson[] = [];
  for (const p of people) {
    const codes = byPerson[p.id];
    const kode = codes && codes.length > 0 ? codes[0] : null;
    if (kode == null) { uden.push(p); continue; }
    if (!grouped.has(kode)) grouped.set(kode, []);
    grouped.get(kode)!.push(p);
  }
  const kodeOrder = [...grouped.keys()].sort(compareDanish);
  const result = kodeOrder.map((kode) => ({
    linje: kode,
    navn: linjeNavn[kode] ?? `Linje ${kode}`,
    people: grouped.get(kode)!.sort((a, b) => compareDanish(a.name, b.name)),
  }));
  if (uden.length > 0) {
    result.push({ linje: 'Uden linje', navn: 'Uden linje', people: uden.sort((a, b) => compareDanish(a.name, b.name)) });
  }
  return result;
}
