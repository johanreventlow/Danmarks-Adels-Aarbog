// Bogmærke-lager (spec §6, dual-review 20 BM1/BM2). Async AsyncStorage-repo + synkron
// render-state-hook. Spejler web/src/data/bookmarks.ts, men async: web-storet var synkront
// (useState-init + sync toggle); AsyncStorage kræver async-lager + optimistisk hook-state +
// race-sikker mutation. Alle bogmærke-id'er er kanoniske (samme_som-collapset).
import { useEffect, useMemo, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

export const BOOKMARKS_KEY = 'daa_bookmarks';

async function safeRead(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(BOOKMARKS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

async function safeWrite(ids: string[]): Promise<void> {
  try {
    await AsyncStorage.setItem(BOOKMARKS_KEY, JSON.stringify(ids));
  } catch {
    // bogmærker er ikke-kritisk PoC-funktion — skrivefejl må ikke crashe UI'et
  }
}

export interface BookmarkStore {
  list(): Promise<string[]>;
  toggle(id: string): Promise<string[]>;
}

export function createLocalBookmarkStore(): BookmarkStore {
  return {
    list: () => safeRead(),
    toggle: async (id) => {
      const cur = await safeRead();
      const next = cur.includes(id) ? cur.filter((x) => x !== id) : [id, ...cur];
      await safeWrite(next);
      return next;
    },
  };
}

// Modul-singleton: lageret er tilstandsløst (rene closures over AsyncStorage), så det behøver
// ikke pr.-komponent-instans. Undgår ref-adgang under render (react-hooks/refs).
const defaultStore = createLocalBookmarkStore();

// Nyeste-først dedup til kanoniske id'er (første forekomst vinder — listen er allerede
// nyeste-først, så "nyeste vinder" holder uden ekstra sortering).
export function canonicalize(raw: string[], canon: (id: string) => string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of raw) {
    const cid = canon(id);
    if (!seen.has(cid)) {
      seen.add(cid);
      out.push(cid);
    }
  }
  return out;
}

function sameOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

// Hook — kilde til sandhed i UI'et. Holder ids i state (synkron render-adgang via has()).
// Dep = canonicalIdById-MAPPET (ikke en funktionsreference): den stabile Zustand-canonicalId
// ville aldrig signalere recollapse (dual-review BM2/D).
export function useBookmarks(canonicalIdById: Record<string, string>): {
  ids: Set<string>;
  has(id: string): boolean;
  toggle(id: string): void;
  count: number;
} {
  const [idsList, setIdsList] = useState<string[]>([]);
  const canon = useMemo(() => (id: string) => canonicalIdById[id] ?? id, [canonicalIdById]);

  // Hydrering + re-normalisering: kør når mappet skifter identitet (recollapse).
  useEffect(() => {
    let alive = true;
    void defaultStore.list().then((raw) => {
      if (!alive) return;
      const norm = canonicalize(raw, canon);
      setIdsList((prev) => (sameOrder(prev, norm) ? prev : norm));
    });
    return () => {
      alive = false;
    };
  }, [canon]);

  const ids = useMemo(() => new Set(idsList), [idsList]);

  const toggle = (id: string) => {
    const cid = canon(id);
    // Optimistisk state-opdatering (funktionel updater → seneste-vinder ved hurtige toggles);
    // persistér async. Sidste skrivning vinder.
    setIdsList((prev) => {
      const next = prev.includes(cid) ? prev.filter((x) => x !== cid) : [cid, ...prev];
      void safeWrite(next);
      return next;
    });
  };

  return { ids, has: (id) => ids.has(canon(id)), toggle, count: idsList.length };
}
