// Afledte selektorer over model + aux. Rene funktioner (testbare) — skærmene kalder dem
// frem for at grave i indekser direkte.
import { compareDanish, initialOf } from '../lib/collation';
import { previousAncestorGen, type GenCoord } from './generations';
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

// Variant B · Kolonner (bidirektionel): fokus-personen er et fast ANKER i midten; aner folder
// ud til venstre (Forældre → Bedsteforældre → …), efterkommere til højre (Børn → Børnebørn → …).
// up[i] = valgt forælder i ane-ring i+1; down[i] = valgt barn i efterkommer-ring i+1. En retning
// stopper ved første ring uden valg eller når den valgte er forældre-/barnløs. Delt design med
// web (web/src/data/tree.ts) — se docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md.
export type ColumnKind = 'ancestor' | 'anchor' | 'descendant';

// Genereret koordinat-opslag pr. person — sendes EKSPLICIT ind (ikke `model.genCoordsByPerson`),
// så bygge-funktionen forbliver platform-agnostisk: web sender model.genCoordsByPerson, mobil
// sender store/LoadResult-værdien (mobils smalle `Model` bærer bevidst ikke feltet selv).
export type GenCoords = Record<string, GenCoord[]>;

export type TreeColumn = {
  key: string;               // STABIL identitet `${kind}:${depth}` — ancestor:1 ≠ descendant:1
  kind: ColumnKind;
  depth: number;             // 0 = anker, 1.. = ring-afstand
  label: string;
  people: ModelPerson[];
  selectedId: string | null;
  fallback?: boolean;                         // true = ubeviste generations-naboer (ikke parentsOf)
  genLabel?: string;                          // 'N. slægtled · <linje>-linjen (M. gennemgående)'
  kuldGroups?: Record<string, ModelPerson[]>; // gruppering pr. kuld (v1, hvor kendt)
};

const COL_MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
const ANCESTOR_LABELS = ['Forældre', 'Bedsteforældre', 'Oldeforældre', 'Tipoldeforældre'];
const DESCENDANT_LABELS = ['Børn', 'Børnebørn', 'Oldebørn', 'Tipoldebørn'];

// Dybde 1-4 navngives; fra dybde 5 bruges den danske genealogiske kortform "N× tipoldeforældre"
// (= tip-tip-…-oldeforældre): dybde 5 = 2×, 6 = 3× osv. → (dybde − 3)×.
function colLabel(kind: 'ancestor' | 'descendant', depth: number): string {
  const table = kind === 'ancestor' ? ANCESTOR_LABELS : DESCENDANT_LABELS;
  if (depth >= 1 && depth <= table.length) return table[depth - 1];
  return `${depth - 3}× ${kind === 'ancestor' ? 'Tipoldeforældre' : 'Tipoldebørn'}`;
}

// Byg fallback-ring: alle personer der deler den FORRIGE generations (linje, lokal)-koordinat med
// `cur`, via `genCoords` (ekstern opslagstabel — ikke `model.genCoordsByPerson`). Ren projektion;
// vælger ingen skrivning, opretter intet — kun kandidat-visning når `parentsOf` er tom. En founder
// (lokal 1) bærer flere linje-koordinater i samme array (kryds-linje-hop via `previousAncestorGen`).
function fallbackAncestorRing(
  model: Model, genCoords: GenCoords | undefined, anchorId: string, cur: string, depth: number,
): TreeColumn | null {
  const coords = genCoords?.[cur];
  if (!coords || !coords.length) return null;
  // Vælg den koordinat vi traverserer på: første med et gyldigt spring til forrige generation.
  for (const c of coords) {
    if (c.lokal == null) continue;
    const prev = previousAncestorGen(coords, c.linje, c.lokal);
    if (!prev) continue;
    const all = model.persons.filter((p) => {
      if (p.id === anchorId || p.id === cur) return false;
      const pc = genCoords?.[p.id];
      return !!pc?.some((k) => k.linje === prev.linje && k.lokal === prev.lokal);
    });
    if (!all.length) continue;
    const kuldGroups: Record<string, ModelPerson[]> = {};
    for (const p of all) {
      const k = genCoords?.[p.id]?.find(
        (x) => x.linje === prev.linje && x.lokal === prev.lokal,
      )?.kuld ?? '—';
      (kuldGroups[k] ??= []).push(p);
    }
    const gennem = all
      .map((p) => genCoords?.[p.id]?.find((x) => x.linje === prev.linje && x.lokal === prev.lokal)?.gennem)
      .find((g) => g != null);
    const genLabel = `${prev.lokal}. slægtled · ${prev.linje}-linjen`
      + (gennem != null ? ` (${gennem}. gennemgående)` : '');
    return {
      key: `ancestor:${depth}:fb`, kind: 'ancestor', depth,
      label: 'Muligt slægtled', people: all, selectedId: null,
      fallback: true, genLabel, kuldGroups,
    };
  }
  return null;
}

function buildDirection(
  model: Model,
  anchorId: string,
  selections: string[],
  traverse: (m: Model, id: string) => ModelPerson[],
  kind: 'ancestor' | 'descendant',
  genCoords?: GenCoords,
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= COL_MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) {
      if (kind === 'ancestor') {
        const fb = fallbackAncestorRing(model, genCoords, anchorId, cur, depth);
        if (fb) cols.push(fb);
      }
      break; // fallback-ringen er en bevidst dødende: vælg re-ankrer i stedet for at drille videre
    }
    const sel = selections[depth - 1] ?? null;
    cols.push({ key: `${kind}:${depth}`, kind, depth, label: colLabel(kind, depth), people, selectedId: sel });
    if (!sel) break;
    visited.add(sel);
    cur = sel;
    depth += 1;
  }
  return cols;
}

export function buildBidirectionalColumns(
  model: Model,
  anchorId: string,
  up: string[],
  down: string[],
  genCoords?: GenCoords,
): TreeColumn[] {
  const anchor = model.byId[anchorId];
  if (!anchor) return [];
  const ancestors = buildDirection(model, anchorId, up, parentsOf, 'ancestor', genCoords);
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant');
  const anchorCol: TreeColumn = {
    key: 'anchor:0', kind: 'anchor', depth: 0, label: 'Fokus', people: [anchor], selectedId: anchorId,
  };
  return [...ancestors.reverse(), anchorCol, ...descendants];
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
