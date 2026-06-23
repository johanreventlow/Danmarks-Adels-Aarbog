// Afledte selektorer over model + aux. Rene funktioner (testbare) — skærmene kalder dem
// frem for at grave i indekser direkte.
import { compareDanish, initialOf } from '../lib/collation';
import type { Aux, Model, ModelPerson } from './types';

// Forside-tællere: personer / linjer / godser.
export function counts(model: Model | null, aux: Aux | null) {
  return {
    personer: model?.persons.length ?? 0,
    linjer: aux?.linjeList.length ?? 0,
    godser: aux?.estateList.length ?? 0,
  };
}

// Børn pr. ægteskab for en person (rækkefølge: unions først, så __none).
export function childrenByMarriage(
  model: Model,
  parentId: string,
): { unionId: string; spouseName: string; children: ModelPerson[] }[] {
  const groups = model.indexes.childrenByUnion[parentId];
  if (!groups) return [];
  return Object.keys(groups).map((unionId) => {
    const union = model.indexes.unionById[unionId];
    let spouseName = '';
    if (union) {
      const otherId = union.p1 === parentId ? union.p2 : union.p1;
      spouseName = union.p2_name || (otherId ? model.byId[otherId]?.name ?? '' : '');
    }
    const children = groups[unionId]
      .map((cid) => model.byId[cid])
      .filter((c): c is ModelPerson => Boolean(c));
    return { unionId, spouseName, children };
  });
}

// Forældre for en person (fra primær fødselsfamilie).
export function parentsOf(model: Model, id: string): ModelPerson[] {
  return (model.indexes.parentsByChild[id] || [])
    .map((pid) => model.byId[pid])
    .filter((p): p is ModelPerson => Boolean(p));
}

// Ægtefæller (navn + evt. id hvis personen findes i basen).
export function spousesOf(model: Model, id: string) {
  return model.indexes.spousesBy[id] || [];
}

// Alle børn af en person (fladt, på tværs af ægteskaber) — til "børn & grene" i variant A.
export function childrenOf(model: Model, id: string): ModelPerson[] {
  const groups = model.indexes.childrenByUnion[id];
  if (!groups) return [];
  const ids: string[] = [];
  Object.values(groups).forEach((arr) => arr.forEach((cid) => ids.push(cid)));
  return ids.map((cid) => model.byId[cid]).filter((c): c is ModelPerson => Boolean(c));
}

// Søskende = den primære forælders børn (inkl. personen selv). Hvis ingen forælder: kun personen.
export function siblingsOf(model: Model, id: string): ModelPerson[] {
  const person = model.byId[id];
  if (!person) return [];
  if (!person.parentId) return [person];
  const sibs = childrenOf(model, person.parentId);
  return sibs.length ? sibs : [person];
}

// Variant C · slægtsspor: byg en lodret linje [rod … fokus … første-barn-efterkommere].
// depth = indeks for fokus-personen i path. Port af buildSnapPath fra v2-designet (linje 997).
export function buildSnapPath(
  model: Model,
  fid: string,
  fallbackRootId: string | null,
): { path: string[]; depth: number } {
  const up: string[] = [];
  let c: ModelPerson | undefined = model.byId[fid];
  let g = 0;
  while (c && g < 40) {
    up.unshift(c.id);
    c = c.parentId ? model.byId[c.parentId] : undefined;
    g++;
  }
  if (!up.length && fallbackRootId) up.push(fallbackRootId);
  const path = up.slice();
  let cur = path[path.length - 1];
  let h = 0;
  while (cur && h < 40) {
    const kids = childrenOf(model, cur);
    if (!kids.length) break;
    cur = kids[0].id;
    path.push(cur);
    h++;
  }
  return { path, depth: Math.max(0, up.length - 1) };
}

// Variant B · drill-down kolonner: hver kolonne = en generation; kolonne N viser børn af den
// valgte person i kolonne N-1. Port af b_cols-logikken (v2 linje 1335).
export function buildColumns(
  model: Model,
  path: string[],
): { level: number; people: ModelPerson[]; selected: string | null }[] {
  const cols: { level: number; people: ModelPerson[]; selected: string | null }[] = [];
  const rootP = path[0] ? model.byId[path[0]] : null;
  if (!rootP) return cols;
  cols.push({ level: 0, people: [rootP], selected: path[0] });
  let cur = path[0];
  let i = 1;
  let guard = 0;
  while (guard < 40) {
    const kids = childrenOf(model, cur);
    if (!kids.length) break;
    const sel = path[i] ?? null;
    cols.push({ level: i, people: kids, selected: sel });
    if (!sel) break;
    cur = sel;
    i++;
    guard++;
  }
  return cols;
}

// Variant A "kort-fokus": bedsteforælder, forælder, denne generations søskende, børn & grene.
export function treeFocusA(model: Model, focusId: string) {
  const focus = model.byId[focusId] ?? null;
  const parent = focus?.parentId ? model.byId[focus.parentId] ?? null : null;
  const grandparent = parent?.parentId ? model.byId[parent.parentId] ?? null : null;
  const siblings = focus ? siblingsOf(model, focusId) : [];
  const children = focus ? childrenOf(model, focusId) : [];
  const spouseName = focus?.spouse ?? '';
  return { focus, parent, grandparent, siblings, children, spouseName };
}

export type SearchItem = { id: string; name: string; years: string; born: number | null };

const sortName = (a: SearchItem, b: SearchItem) => compareDanish(a.name, b.name);
const sortBorn = (a: SearchItem, b: SearchItem) =>
  (a.born ?? 99999) - (b.born ?? 99999) || compareDanish(a.name, b.name);

// Bygger søge-/bladre-resultatet med §9.1-semantik:
//  - query filtrerer på navn (case-insensitiv, substring)
//  - uden query + alfabetisk sort: activeLetter filtrerer på initial (efternavn)
//  - sortering: alfabetisk (dansk) eller fødeår
export function buildSearch(
  model: Model | null,
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
): {
  matches: SearchItem[];
  letters: { label: string; key: string | null }[];
  showLetters: boolean;
  groups: { letter: string; people: SearchItem[] }[];
} {
  const pool: SearchItem[] = (model?.persons ?? []).map((p) => ({
    id: p.id,
    name: p.name,
    years: p.years,
    born: p.born,
  }));
  const q = opts.query.trim().toLowerCase();

  // Forekommende bogstaver (kun alfabetisk, ingen query, >1 bogstav).
  const present: Record<string, boolean> = {};
  pool.forEach((p) => {
    present[initialOf(p.name)] = true;
  });
  const letterKeys = Object.keys(present).sort(compareDanish);
  const showLetters = opts.sort !== 'born' && !q && letterKeys.length > 1;
  const letters = [{ label: 'Alle', key: null as string | null }].concat(
    letterKeys.map((k) => ({ label: k, key: k })),
  );

  let matches = pool.filter((p) => !q || p.name.toLowerCase().includes(q));
  if (!q && opts.sort !== 'born' && opts.activeLetter) {
    matches = matches.filter((p) => initialOf(p.name) === opts.activeLetter);
  }
  matches.sort(opts.sort === 'born' ? sortBorn : sortName);

  // Sticky-grupper: kun alfabetisk uden query.
  let groups: { letter: string; people: SearchItem[] }[] = [];
  if (opts.sort !== 'born' && !q) {
    const byL: Record<string, SearchItem[]> = {};
    matches.forEach((p) => {
      (byL[initialOf(p.name)] ||= []).push(p);
    });
    groups = Object.keys(byL)
      .sort(compareDanish)
      .map((k) => ({ letter: k, people: byL[k] }));
  }

  return { matches, letters, showLetters, groups };
}
