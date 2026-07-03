// Bogmærke-lager (web v3 Slice 1 — spec §3.1/§3.2). localStorage-adapter (PoC), spejler
// `meId`-mønstret i Folgesvend.tsx. En bruger-scoped, persisteret backend er iboende asynkron
// (auth-scope, mutation-latency) og designes som egen async repository-kontrakt i Slice 2 —
// dette modul er grænsen for løftet nu: al localStorage-adgang bag ét sted.
import { useEffect, useMemo, useRef, useState } from 'react';
import { compareDanish } from '../lib/collation';
import type { Model, ModelPerson } from './types';

export const BOOKMARKS_KEY = 'daa_bookmarks';

export interface BookmarkStore {
  list(): string[]; // kanoniske person-id'er, seneste-tilføjet-først
  has(id: string): boolean;
  toggle(id: string): string[]; // returnerer ny liste
}

function safeRead(): string[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = window.localStorage.getItem(BOOKMARKS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

function safeWrite(ids: string[]): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(BOOKMARKS_KEY, JSON.stringify(ids));
  } catch {
    // bogmærker er ikke-kritisk PoC-funktion — fejl ved skrivning skal ikke crashe UI'et
  }
}

export function createLocalBookmarkStore(): BookmarkStore {
  return {
    list: () => safeRead(),
    has: (id) => safeRead().includes(id),
    toggle: (id) => {
      const current = safeRead();
      const next = current.includes(id) ? current.filter((x) => x !== id) : [id, ...current];
      safeWrite(next);
      return next;
    },
  };
}

// Dedupikér en id-liste (newest-first) til kanoniske id'er. Første forekomst pr. kanonisk id
// vinder (listen er allerede newest-først), så "nyeste vinder"-reglen holder uden ekstra sortering.
function canonicalize(raw: string[], canon: (id: string) => string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of raw) {
    const cid = canon(id);
    if (!seen.has(cid)) { seen.add(cid); out.push(cid); }
  }
  return out;
}
function sameOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

// React-hook — kilde til sandhed i UI'et. Re-normaliserer den gemte liste gennem canon() ved
// mount og hver gang canon-mappet ændrer identitet (async canon-load / recollapse — spec §3.1).
export function useBookmarks(canon: (id: string) => string): {
  ids: Set<string>;
  has(id: string): boolean;
  toggle(id: string): void;
} {
  const storeRef = useRef<BookmarkStore | null>(null);
  if (!storeRef.current) storeRef.current = createLocalBookmarkStore();
  const store = storeRef.current;

  const [idsList, setIdsList] = useState<string[]>(() => store.list());

  useEffect(() => {
    const raw = store.list();
    const migrated = canonicalize(raw, canon);
    if (!sameOrder(migrated, raw)) safeWrite(migrated);
    setIdsList((prev) => (sameOrder(migrated, prev) ? prev : migrated));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canon]);

  const ids = useMemo(() => new Set(idsList), [idsList]);

  return {
    ids,
    has: (id) => ids.has(canon(id)),
    toggle: (id) => {
      const cid = canon(id);
      setIdsList(store.toggle(cid));
    },
  };
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
