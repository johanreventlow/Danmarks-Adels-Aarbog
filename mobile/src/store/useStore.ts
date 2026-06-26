// Global app-store (Zustand). Holder data-laget (model + aux) og app-tilstand der IKKE er
// navigation (Expo Router styrer ruter): focus, variant, aktiv linje, "mig", slægtskab,
// søge-/bladre-tilstand. buildModel kaldes eksplicit her efter load (advisor 2026-06-23).
import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { buildModel } from '../data/buildModel';
import { loadFromSupabase } from '../data/load';
import { buildSnapPath } from '../data/selectors';
import { SEED } from '../data/seed';
import { childrenOf } from '../data/selectors';
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

  // Variant B (drill-down kolonner) + C (slægtsspor-snap)
  path: string[];
  snapPath: string[];
  snapDepth: number;

  meId: string | null;
  relA: string | null;
  relB: string | null;

  // Auth-slice
  session: import('@supabase/supabase-js').Session | null;
  rolle: import('./../lib/auth').Rolle;
  reventlowPersonId: string | null;
  dryRun: boolean;
  showAnnotations: boolean;

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
  selectAt: (level: number, id: string) => void;
  moveSnapGen: (delta: number) => void;
  moveSnapSib: (delta: number) => void;
  snapOpenId: () => string | null;
  pickLinje: (linje: string, headId: string | null) => void;
  clearLinje: () => void;
  setQuery: (q: string) => void;
  setBrowseSort: (s: BrowseSort) => void;
  setActiveLetter: (l: string | null) => void;
  setRelA: (id: string) => void;
  setRelB: (id: string) => void;

  // Auth actions
  doSignIn: (email: string, password: string) => Promise<void>;
  doSignOut: () => Promise<void>;
  hydrateAuth: () => Promise<void>;
  setDryRun: (v: boolean) => void;
  setShowAnnotations: (v: boolean) => void;
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
  path: [],
  snapPath: [],
  snapDepth: 0,
  meId: null,
  relA: null,
  relB: null,
  session: null,
  rolle: 'medlem',
  reventlowPersonId: null,
  dryRun: true,
  showAnnotations: false,
  query: '',
  browseSort: 'alpha',
  activeLetter: null,

  load: async () => {
    if (get().status === 'loading') return;
    set({ status: 'loading', error: null });
    try {
      const res = await loadFromSupabase();
      const model = buildModel(res.db);
      const snap = buildSnapPath(model, res.focusId, res.rootId);
      set({
        status: 'ready',
        source: 'live',
        model,
        aux: res.aux,
        rootId: res.rootId,
        focusId: res.focusId,
        path: [res.rootId],
        snapPath: snap.path,
        snapDepth: snap.depth,
        relA: res.relAId,
        relB: res.relBId,
      });
    } catch (e) {
      // Offline-fallback: indlejret Reventlow-seed, så appen ikke står blank.
      const model = buildModel(SEED.db);
      const snap = buildSnapPath(model, SEED.focusId, SEED.rootId);
      set({
        status: 'ready',
        source: 'seed',
        error: e instanceof Error ? e.message : String(e),
        model,
        aux: SEED.aux,
        rootId: SEED.rootId,
        focusId: SEED.focusId,
        path: [SEED.rootId],
        snapPath: snap.path,
        snapDepth: snap.depth,
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

  setFocus: (id) => {
    const m = get().model;
    const snap = m ? buildSnapPath(m, id, get().rootId) : { path: [id], depth: 0 };
    set({ focusId: id, path: [id], snapPath: snap.path, snapDepth: snap.depth });
  },

  // Skift træ-variant. Ved C seedes snapPath fra fokus; ved B nulstilles drill-down til fokus.
  setVariant: (v) => {
    const { model, focusId, rootId } = get();
    if (v === 'C' && model && focusId) {
      const snap = buildSnapPath(model, focusId, rootId);
      set({ variant: 'C', snapPath: snap.path, snapDepth: snap.depth });
    } else if (v === 'B') {
      set({ variant: 'B', path: [focusId ?? rootId ?? ''] });
    } else {
      set({ variant: v });
    }
  },

  // Variant B drill-down: vælg person på niveau `level` → trunkér sti og sæt fokus.
  selectAt: (level, id) => {
    const path = get().path.slice(0, level);
    path[level] = id;
    set({ path, focusId: id });
  },

  // Variant C: skift generation (op=aner / ned=efterkommere) inden for snapPath.
  moveSnapGen: (delta) => {
    const { snapPath, snapDepth } = get();
    const nd = Math.max(0, Math.min(snapDepth + delta, snapPath.length - 1));
    if (nd !== snapDepth) set({ snapDepth: nd, focusId: snapPath[nd] });
  },

  // Variant C: skift mellem søskende på nuværende dybde, genopbyg efterkommer-halen.
  moveSnapSib: (delta) => {
    const { model, snapPath, snapDepth } = get();
    if (!model || snapDepth === 0) return;
    const sibs = childrenOf(model, snapPath[snapDepth - 1]).map((p) => p.id);
    if (sibs.length < 2) return;
    const idx = sibs.indexOf(snapPath[snapDepth]);
    if (idx === -1) return; // fokus ikke blandt de beregnede søskende → undgå spring til sibs[0]
    const i = Math.max(0, Math.min(idx + delta, sibs.length - 1));
    if (sibs[i] === snapPath[snapDepth]) return;
    const np = snapPath.slice(0, snapDepth);
    np[snapDepth] = sibs[i];
    let cur = sibs[i];
    let g = snapDepth;
    while (g < 40) {
      const kids = childrenOf(model, cur);
      if (!kids.length) break;
      cur = kids[0].id;
      np[g + 1] = cur;
      g++;
    }
    set({ snapPath: np, focusId: sibs[i] });
  },

  snapOpenId: () => {
    const { snapPath, snapDepth } = get();
    return snapPath[snapDepth] ?? null;
  },

  // §9.2 linje-hop: spring fokus til linjens stamfader + filtrér gren (+ seed B/C).
  pickLinje: (linje, headId) => {
    if (!headId) return;
    const m = get().model;
    const snap = m ? buildSnapPath(m, headId, headId) : { path: [headId], depth: 0 };
    set({ activeLinje: linje, focusId: headId, path: [headId], snapPath: snap.path, snapDepth: snap.depth });
  },
  clearLinje: () => {
    const { model, rootId } = get();
    const target = rootId ?? '';
    const snap = model && rootId ? buildSnapPath(model, rootId, rootId) : { path: [target], depth: 0 };
    set({ activeLinje: null, focusId: rootId, path: [target], snapPath: snap.path, snapDepth: snap.depth });
  },

  setQuery: (q) => set({ query: q }),
  // Fødeår-sort skjuler alfabet-baren; ryd activeLetter så et skjult bogstav-filter ikke
  // genanvendes lydløst når man skifter tilbage til alfabetisk.
  setBrowseSort: (s) => set(s === 'born' ? { browseSort: s, activeLetter: null } : { browseSort: s }),
  setActiveLetter: (l) => set({ activeLetter: l }),
  setRelA: (id) => set({ relA: id }),
  setRelB: (id) => set({ relB: id }),

  doSignIn: async (email, password) => {
    const { signIn } = await import('../lib/auth');
    const res = await signIn(email, password);
    set({ rolle: res.rolle, reventlowPersonId: res.reventlowPersonId });
    const { supabase } = await import('../lib/supabase');
    const { data } = supabase ? await supabase.auth.getSession() : { data: { session: null } };
    set({ session: data.session });
  },
  doSignOut: async () => {
    const { signOut } = await import('../lib/auth');
    await signOut();
    set({ session: null, rolle: 'medlem', reventlowPersonId: null });
  },
  hydrateAuth: async () => {
    const { supabase } = await import('../lib/supabase');
    if (!supabase) return;
    const { data } = await supabase.auth.getSession();
    if (data.session) {
      const { fetchProfile } = await import('../lib/auth');
      const prof = await fetchProfile(data.session.user.id);
      set({ session: data.session, rolle: prof.rolle, reventlowPersonId: prof.reventlowPersonId });
    }
  },
  setDryRun: (v) => set({ dryRun: v }),
  setShowAnnotations: (v) => set({ showAnnotations: v }),
}));
