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

export type WayStep = 'up' | 'down' | 'left' | 'right' | 'arrived';

// Anekæde inkl. personen selv, ældste først (samme klatre-mønster som buildSnapPath).
function ancestorsOf(model: Model, id: string): string[] {
  const out: string[] = [];
  let c: ModelPerson | undefined = model.byId[id];
  let g = 0;
  while (c && g < 40) {
    out.unshift(c.id);
    c = c.parentId ? model.byId[c.parentId] : undefined;
    g++;
  }
  return out;
}

// Næste gestus + antal resterende spring fra fokus til mig i Spor-navigationen.
// Bygger HELE gestus-planen konstruktivt (op til fælles ane → søskendeskift → ned),
// så der ikke opstår op/ned-bounce ved gren-kryds. null = ingen fælles ane (ingen vej).
export function wayToMe(
  model: Model,
  snapPath: string[],
  snapDepth: number,
  meId: string,
): { step: WayStep; remaining: number } | null {
  const focus = snapPath[snapDepth];
  if (!focus) return null;
  if (focus === meId) return { step: 'arrived', remaining: 0 };

  const A = snapPath.slice(0, snapDepth + 1); // fokus' anekæde (snapPath ER anekæden)
  const M = ancestorsOf(model, meId);          // mig's anekæde
  if (!M.length || A[0] !== M[0]) return null;  // ingen fælles ane → ingen vej

  let commonLen = 0;
  while (commonLen < A.length && commonLen < M.length && A[commonLen] === M[commonLen]) commonLen++;

  const plan: WayStep[] = [];

  // Søskende-indeks (førstefødt = 0). -1 hvis ikke fundet (defensivt).
  const childIndex = (parentId: string, childId: string): number =>
    childrenOf(model, parentId).findIndex((p) => p.id === childId);

  // Nedstigning fra node M[d] (i dybde d) ned til mig: per niveau ned (lander på
  // førstefødt) + søskende-trin til det rette barn.
  const descendFrom = (d: number) => {
    for (let i = d; i < M.length - 1; i++) {
      plan.push('down');
      const idx = childIndex(M[i], M[i + 1]);
      for (let s = 0; s < idx; s++) plan.push('right');
    }
  };

  if (commonLen === M.length) {
    // Mig er ane til fokus: mig ligger på A i dybde M.length-1 → klatr op.
    const meDepth = M.length - 1;
    for (let s = 0; s < snapDepth - meDepth; s++) plan.push('up');
  } else if (commonLen === snapDepth + 1) {
    // Fokus ligger på mig's egen kæde (A præfiks af M) → ren nedstigning.
    descendFrom(snapDepth);
  } else {
    // Ægte forgrening: klatr op til søskende-dybden commonLen, skift søskende
    // fra A[commonLen] til M[commonLen] (samme forælder), stig så ned.
    for (let s = 0; s < snapDepth - commonLen; s++) plan.push('up');
    const fromIdx = childIndex(M[commonLen - 1], A[commonLen]);
    const toIdx = childIndex(M[commonLen - 1], M[commonLen]);
    const sib = toIdx - fromIdx;
    for (let s = 0; s < Math.abs(sib); s++) plan.push(sib > 0 ? 'right' : 'left');
    descendFrom(commonLen);
  }

  if (!plan.length) return null;
  return { step: plan[0], remaining: plan.length };
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
