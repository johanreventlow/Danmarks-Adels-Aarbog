// Global app-store (Zustand). Holder data-laget (model + aux) og app-tilstand der IKKE er
// navigation (Expo Router styrer ruter): focus, variant, aktiv linje, "mig", slægtskab,
// søge-/bladre-tilstand. buildModel kaldes eksplicit her efter load (advisor 2026-06-23).
import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { buildModel } from '../data/buildModel';
import { loadFromSupabase } from '../data/load';
import { SEED } from '../data/seed';
import type { Aux, Model } from '../data/types';

const ME_KEY = 'daa_me_id';

export type LoadStatus = 'idle' | 'loading' | 'ready' | 'error';
export type DataSource = 'live' | 'seed' | null;
export type TreeVariant = 'A' | 'B' | 'C';
export type BrowseSort = 'alpha' | 'born';

type State = {
  status: LoadStatus;
  source: DataSource;
  error: string | null;
  model: Model | null;
  aux: Aux | null;

  rootId: string | null;
  focusId: string | null;
  variant: TreeVariant;
  activeLinje: string | null;

  meId: string | null;
  relA: string | null;
  relB: string | null;

  // Søg/bladr (§9.1)
  query: string;
  browseSort: BrowseSort;
  activeLetter: string | null;

  // actions
  load: () => Promise<void>;
  hydrateMe: () => Promise<void>;
  setMe: (id: string | null) => Promise<void>;
  setFocus: (id: string) => void;
  setVariant: (v: TreeVariant) => void;
  pickLinje: (linje: string, headId: string | null) => void;
  clearLinje: () => void;
  setQuery: (q: string) => void;
  setBrowseSort: (s: BrowseSort) => void;
  setActiveLetter: (l: string | null) => void;
};

export const useStore = create<State>((set, get) => ({
  status: 'idle',
  source: null,
  error: null,
  model: null,
  aux: null,
  rootId: null,
  focusId: null,
  variant: 'A',
  activeLinje: null,
  meId: null,
  relA: null,
  relB: null,
  query: '',
  browseSort: 'alpha',
  activeLetter: null,

  load: async () => {
    if (get().status === 'loading') return;
    set({ status: 'loading', error: null });
    try {
      const res = await loadFromSupabase();
      const model = buildModel(res.db);
      set({
        status: 'ready',
        source: 'live',
        model,
        aux: res.aux,
        rootId: res.rootId,
        focusId: res.focusId,
        relA: res.relAId,
        relB: res.relBId,
      });
    } catch (e) {
      // Offline-fallback: indlejret Reventlow-seed, så appen ikke står blank.
      const model = buildModel(SEED.db);
      set({
        status: 'ready',
        source: 'seed',
        error: e instanceof Error ? e.message : String(e),
        model,
        aux: SEED.aux,
        rootId: SEED.rootId,
        focusId: SEED.focusId,
        relA: SEED.relAId,
        relB: SEED.relBId,
      });
    }
  },

  hydrateMe: async () => {
    try {
      const me = await AsyncStorage.getItem(ME_KEY);
      if (me) set({ meId: me });
    } catch {
      // ignore
    }
  },

  setMe: async (id) => {
    set({ meId: id });
    try {
      if (id) await AsyncStorage.setItem(ME_KEY, id);
      else await AsyncStorage.removeItem(ME_KEY);
    } catch {
      // ignore
    }
  },

  setFocus: (id) => set({ focusId: id, variant: get().variant }),
  setVariant: (v) => set({ variant: v }),

  // §9.2 linje-hop: spring fokus til linjens stamfader + filtrér gren.
  pickLinje: (linje, headId) => {
    if (!headId) return;
    set({ activeLinje: linje, focusId: headId });
  },
  clearLinje: () => set({ activeLinje: null, focusId: get().rootId }),

  setQuery: (q) => set({ query: q }),
  setBrowseSort: (s) => set({ browseSort: s }),
  setActiveLetter: (l) => set({ activeLetter: l }),
}));
