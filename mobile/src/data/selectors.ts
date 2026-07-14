// Afledte selektorer over model + aux. Rene funktioner (testbare) — skærmene kalder dem
// frem for at grave i indekser direkte. Stamtræ-kernen (columnLabel/columnGen/buildDirection/
// buildBidirectionalColumns/unknownParentRing/unknownChildSection + TreeColumn-typerne) er
// ekstraheret til @daa/core/tree — kun de app-specifikke traverseringer (childrenOf/parentsOf,
// der læser mobilens childrenByUnion/parentsByChild-indekser) og øvrige mobil-selektorer bor her.
import { compareDanish, initialOf } from '@daa/core';
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

// Bygger HELE gestus-planen fra fokus til mig (op til fælles ane → søskendeskift → ned),
// konstruktivt så der ikke opstår op/ned-bounce ved gren-kryds.
// null = ingen fælles ane (ingen vej); [] = fokus ER mig (du er der).
function planToMe(model: Model, snapPath: string[], snapDepth: number, meId: string): WayStep[] | null {
  const focus = snapPath[snapDepth];
  if (!focus) return null;
  if (focus === meId) return [];

  const M = ancestorsOf(model, meId); // mig's anekæde (rod → mig)
  if (!M.length || snapPath[0] !== M[0]) return null; // ingen fælles ane → ingen vej

  // Fælles præfiks af HELE snapPath og M — fanger at mig kan ligge på snapPath UNDER fokus
  // (fx når man scrollede op fra mig), så ruten bliver ren lodret uden falske søskendeskift.
  let commonLen = 0;
  while (commonLen < snapPath.length && commonLen < M.length && snapPath[commonLen] === M[commonLen]) commonLen++;

  const plan: WayStep[] = [];

  // Søskende-indeks (førstefødt = 0). -1 hvis ikke fundet (defensivt).
  const childIndex = (parentId: string, childId: string): number =>
    childrenOf(model, parentId).findIndex((p) => p.id === childId);

  // Lodret fra fokus til toDepth (op eller ned langs snapPath).
  const vertical = (toDepth: number) => {
    const delta = toDepth - snapDepth;
    for (let s = 0; s < Math.abs(delta); s++) plan.push(delta < 0 ? 'up' : 'down');
  };

  // Firstborn-nedstigning fra node M[d] ned til mig: per niveau ned + søskende-trin til rette barn.
  const descendFrom = (d: number) => {
    for (let i = d; i < M.length - 1; i++) {
      plan.push('down');
      const idx = childIndex(M[i], M[i + 1]);
      for (let s = 0; s < idx; s++) plan.push('right');
    }
  };

  if (commonLen === M.length) {
    // Mig ligger PÅ snapPath (ane eller efterkommer på linjen) → ren lodret.
    vertical(M.length - 1);
  } else if (commonLen >= snapPath.length) {
    // snapPath er præfiks af M; mig ligger dybere end snapPath-enden → ned til enden, så firstborn-nedstigning.
    vertical(snapPath.length - 1);
    descendFrom(snapPath.length - 1);
  } else {
    // Sidelæns divergens ved commonLen: naviger til den dybde, skift søskende fra
    // snapPath[commonLen] til M[commonLen] (samme forælder), stig så ned (firstborn).
    vertical(commonLen);
    const fromIdx = childIndex(M[commonLen - 1], snapPath[commonLen]);
    const toIdx = childIndex(M[commonLen - 1], M[commonLen]);
    const sib = toIdx - fromIdx;
    for (let s = 0; s < Math.abs(sib); s++) plan.push(sib > 0 ? 'right' : 'left');
    descendFrom(commonLen);
  }
  return plan;
}

// Næste gestus + antal resterende spring fra fokus til mig i Spor-navigationen.
// null = ingen fælles ane (ingen vej).
export function wayToMe(
  model: Model,
  snapPath: string[],
  snapDepth: number,
  meId: string,
): { step: WayStep; remaining: number } | null {
  const plan = planToMe(model, snapPath, snapDepth, meId);
  if (plan === null) return null;
  if (plan.length === 0) return { step: 'arrived', remaining: 0 };
  return { step: plan[0], remaining: plan.length };
}

// Hele gestus-planen fra fokus til mig — til rute-tegning i Spor.
// null = ingen vej; [] = du er der; ellers sekvensen af gestusser (up/down/left/right).
export function routeToMe(
  model: Model,
  snapPath: string[],
  snapDepth: number,
  meId: string,
): WayStep[] | null {
  return planToMe(model, snapPath, snapDepth, meId);
}

export type SearchItem = { id: string; name: string; years: string; born: number | null };

const sortName = (a: SearchItem, b: SearchItem) => compareDanish(a.name, b.name);
const sortBorn = (a: SearchItem, b: SearchItem) =>
  (a.born ?? 99999) - (b.born ?? 99999) || compareDanish(a.name, b.name);

// Pool-baseret søge-/bladre-funktion med §9.1-semantik:
//  - query filtrerer på navn (case-insensitiv, substring)
//  - uden query + alfabetisk sort: activeLetter filtrerer på initial (efternavn)
//  - sortering: alfabetisk (dansk) eller fødeår
// Genbruges af både publikums-appen og redaktions-listen (DRY).
export function searchPool(
  pool: SearchItem[],
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
): {
  matches: SearchItem[];
  letters: { label: string; key: string | null }[];
  showLetters: boolean;
  groups: { letter: string; people: SearchItem[] }[];
} {
  const q = opts.query.trim().toLowerCase();

  // Forekommende bogstaver (kun alfabetisk, ingen query, >1 bogstav).
  const present: Record<string, boolean> = {};
  pool.forEach((p) => { present[initialOf(p.name)] = true; });
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
    matches.forEach((p) => { (byL[initialOf(p.name)] ||= []).push(p); });
    groups = Object.keys(byL).sort(compareDanish).map((k) => ({ letter: k, people: byL[k] }));
  }

  return { matches, letters, showLetters, groups };
}

// Tynd wrapper: bygger pool fra model og delegerer til searchPool.
// Bevares med uændret signatur + output så eksisterende skærme ikke brydes.
export function buildSearch(
  model: Model | null,
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
) {
  const pool: SearchItem[] = (model?.persons ?? []).map((p) => ({
    id: p.id,
    name: p.name,
    years: p.years,
    born: p.born,
  }));
  return searchPool(pool, opts);
}
