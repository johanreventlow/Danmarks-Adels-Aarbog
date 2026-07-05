// Afledte selektorer over model + aux. Rene funktioner (testbare) — skærmene kalder dem
// frem for at grave i indekser direkte.
import { compareDanish, initialOf } from '../lib/collation';
import { adjacentGen, type GenCoord } from './generations';
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
  focusId?: string;      // v2: sat KUN på anker-kolonnen — dominant kort blandt fokus+naboer
  overflowPeers?: number; // v2: antal slægtled-naboer skåret væk af buildAnchorPeers' cap
};

const COL_MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
const ANCESTOR_LABELS = ['Forældre', 'Bedsteforældre', 'Oldeforældre', 'Tipoldeforældre'];
const DESCENDANT_LABELS = ['Børn', 'Børnebørn', 'Oldebørn', 'Tipoldebørn'];

// v2-overskrift: kombinerer slægtskabsbetegnelse (ANCESTOR/DESCENDANT_LABELS) med det ABSOLUTTE
// slægtled-tal (genCoord.lokal) + linje-navn, når kendt. Ren formattering — ingen I/O, intet
// TreeColumn-behov; kaldes med de rå felter så den er testbar uafhængigt af
// buildBidirectionalColumns. `activeCoord == null` → `slaegtled`/`linje` er `null` → falder tilbage
// til v1's rene kinship-labels (ingen regression for personer uden slægtled-data). Bevaret
// byte-identisk mellem web/src/data/tree.ts og mobile/src/data/selectors.ts.
export function columnLabel(a: {
  kind: ColumnKind;
  depth: number;
  slaegtled: number | null;
  linje: string | null;
  fallback?: boolean;
}): string {
  if (a.kind === 'anchor') {
    if (a.slaegtled == null) return 'Fokus';
    return `${a.slaegtled}. slægtled · ${a.linje}-linjen`;
  }
  if (a.fallback) {
    return `muligt · ${a.slaegtled}. slægtled · ${a.linje}-linjen`;
  }
  if (a.depth <= 4) {
    const table = a.kind === 'ancestor' ? ANCESTOR_LABELS : DESCENDANT_LABELS;
    const kinship = table[a.depth - 1];
    if (a.slaegtled == null) return kinship;
    return `${kinship} · ${a.slaegtled}. slægtled`;
  }
  if (a.slaegtled == null) {
    return `${a.depth - 3}× ${a.kind === 'ancestor' ? 'Tipoldeforældre' : 'Tipoldebørn'}`;
  }
  return `${a.slaegtled}. slægtled`;
}

// Byg fallback-ring: alle personer der deler den NABO-generations (linje, lokal)-koordinat med
// `cur` i retning `dir`, via `genCoords` (ekstern opslagstabel — ikke `model.genCoordsByPerson`).
// Ren projektion; vælger ingen skrivning, opretter intet — kun kandidat-visning når den beviste
// ring (`parentsOf`/`childrenOf`) er tom. `dir=-1` = aner MED founder-krydshop (v1-adfærd,
// uændret); `dir=+1` = efterkommer, ren `lokal+1` i samme `(sourceId,lineageId)`, INGEN hop —
// se design-spec §3. En founder (lokal 1) bærer flere linje-koordinater i samme array.
function fallbackRing(
  model: Model, genCoords: GenCoords | undefined, anchorId: string, cur: string, depth: number, dir: -1 | 1,
): TreeColumn | null {
  const coords = genCoords?.[cur];
  if (!coords || !coords.length) return null;
  const kind: 'ancestor' | 'descendant' = dir === -1 ? 'ancestor' : 'descendant';
  // Deterministisk rækkefølge: laveste lokal først, så et ægte founder-hop (lokal 1) altid
  // forsøges før en højere-lokal-medlemskab — uafhængigt af hentnings-/indsættelsesrækkefølgen
  // fra DB'en (dual-review 2026-07-05).
  const sorted = [...coords].sort((a, b) => (a.lokal ?? Infinity) - (b.lokal ?? Infinity));
  // Vælg den koordinat vi traverserer på: første med et gyldigt spring til nabo-generationen.
  // NB: hvis personen reelt hører til flere linjer (flere GenCoord'er), viser ringen kun
  // nabo-generationen for ÉT af dem — det er aldrig en påstand om en bestemt (mulig forkert)
  // forælder, men et bevidst valg blandt flere gyldige medlemskaber; brugerens aktive
  // traverserings-linje (`c`, i den rækkefølge vi prøver dem) afgør hvilket. Bevidst
  // v2-forfinelse, ikke en bug — se dual-review 2026-07-05.
  for (const c of sorted) {
    if (c.lokal == null) continue;
    const adj = adjacentGen(coords, c.sourceId, c.lineageId, c.lokal, dir);
    if (!adj) continue;
    // Skop ringen til SAMME kilde (udgave) + SAMME (konkrete) linje som traverseringskoordinaten
    // `c` — ellers ville to udgavers/linjers "linje III, slægtled 11" blive slået sammen i én ring.
    // `adj.lineageId` er allerede korrekt scoped af `adjacentGen` (egen linje ved almindeligt
    // ét-skridt-spring, moderlinjen ved et founder-hop).
    const matchesAdj = (k: GenCoord) =>
      k.linje === adj.linje && k.lokal === adj.lokal
      && k.sourceId === adj.sourceId && k.lineageId === adj.lineageId;
    const all = model.persons.filter((p) => {
      if (p.id === anchorId || p.id === cur) return false;
      const pc = genCoords?.[p.id];
      return !!pc?.some(matchesAdj);
    });
    if (!all.length) continue;
    const kuldGroups: Record<string, ModelPerson[]> = {};
    for (const p of all) {
      const k = genCoords?.[p.id]?.find(matchesAdj)?.kuld ?? '—';
      (kuldGroups[k] ??= []).push(p);
    }
    const gennem = all
      .map((p) => genCoords?.[p.id]?.find(matchesAdj)?.gennem)
      .find((g) => g != null);
    const genLabel = `${adj.lokal}. slægtled · ${adj.linje}-linjen`
      + (gennem != null ? ` (${gennem}. gennemgående)` : '');
    return {
      key: `${kind}:${depth}:fb`, kind, depth,
      label: columnLabel({ kind, depth, slaegtled: adj.lokal, linje: adj.linje, fallback: true }),
      people: all, selectedId: null,
      fallback: true, genLabel, kuldGroups,
    };
  }
  return null;
}

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet).
// visited (seedet med ankeret + de valgte) guard'er mod self-forælder/cyklus i defekt data.
// `activeLokal`/`linje` (afledt af `activeCoord` i buildBidirectionalColumns) driver
// kolonne-labels via `columnLabel`; `null` → v1's rene kinship-labels (ingen regression).
// Efterkommer-fallback (dir=+1) er KUN et v2-tilbud og kræver `activeLokal != null` — uden
// `activeCoord` skal opkaldere (endnu) uden UI-wiring til peers/labels ikke pludselig få en
// uventet "muligt"-kolonne til højre (v1 havde slet ingen efterkommer-fallback). Ane-fallback
// (dir=-1) forbliver ubetinget = v1-adfærd (kun styret af genCoords-tilstedeværelse).
function buildDirection(
  model: Model,
  anchorId: string,
  selections: string[],
  traverse: (m: Model, id: string) => ModelPerson[],
  kind: 'ancestor' | 'descendant',
  dir: -1 | 1,
  activeLokal: number | null,
  linje: string | null,
  genCoords?: GenCoords,
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= COL_MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) {
      const fallbackAllowed = dir === -1 || activeLokal != null;
      const fb = fallbackAllowed ? fallbackRing(model, genCoords, anchorId, cur, depth, dir) : null;
      if (fb) cols.push(fb);
      break; // fallback-ringen er en bevidst dødende: vælg re-ankrer i stedet for at drille videre
    }
    const sel = selections[depth - 1] ?? null;
    const slaegtled = activeLokal != null ? activeLokal + (kind === 'ancestor' ? -depth : depth) : null;
    const label = columnLabel({ kind, depth, slaegtled, linje });
    cols.push({ key: `${kind}:${depth}`, kind, depth, label, people, selectedId: sel });
    if (!sel) break;
    visited.add(sel);
    cur = sel;
    depth += 1;
  }
  return cols;
}

// Slår linje-navnet ('III', 'V', …) op for en (sourceId, lineageId)-kontekst ved at scanne
// `genCoords` bredt (ikke kun ankerets egne koordinater) — linje-navnet er en egenskab af selve
// linjen, ikke af personen, så ethvert match holder. Bevaret byte-identisk mellem
// web/src/data/tree.ts og mobile/src/data/selectors.ts.
function linjeNameFor(genCoords: GenCoords | undefined, sourceId: string, lineageId: string | null): string | null {
  if (!genCoords) return null;
  for (const arr of Object.values(genCoords)) {
    const hit = arr.find((c) => c.sourceId === sourceId && c.lineageId === lineageId);
    if (hit) return hit.linje;
  }
  return null;
}

export type ActiveCoord = { sourceId: string; lineageId: string | null; lokal: number };

// Komposer: [...aner omvendt (dybest yderst til venstre), ankerkolonne, ...efterkommere].
// `activeCoord` (v2, valgfri): den aktive linje-koordinat der driver naboer (ankerkolonnens
// `people`/`focusId`/`overflowPeers` via `buildAnchorPeers`), fallback-retning (begge veje nu,
// ikke kun aner) OG labels (`columnLabel`). `activeCoord == null` → uændret v1-adfærd: ingen
// peers, ingen efterkommer-fallback, rene kinship-labels (se design-spec §2-§5).
export function buildBidirectionalColumns(
  model: Model,
  anchorId: string,
  up: string[],
  down: string[],
  genCoords?: GenCoords,
  activeCoord?: ActiveCoord | null,
): TreeColumn[] {
  const anchor = model.byId[anchorId];
  if (!anchor) return [];
  const ac = activeCoord ?? null;
  const linje = ac ? linjeNameFor(genCoords, ac.sourceId, ac.lineageId) : null;
  const activeLokal = ac ? ac.lokal : null;
  const ancestors = buildDirection(model, anchorId, up, parentsOf, 'ancestor', -1, activeLokal, linje, genCoords);
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant', 1, activeLokal, linje, genCoords);
  const peers = buildAnchorPeers(model, genCoords, anchorId, ac);
  const anchorCol: TreeColumn = {
    key: 'anchor:0', kind: 'anchor', depth: 0,
    label: columnLabel({ kind: 'anchor', depth: 0, slaegtled: activeLokal, linje }),
    people: peers.people, selectedId: anchorId, focusId: anchorId, overflowPeers: peers.overflow,
  };
  return [...ancestors.reverse(), anchorCol, ...descendants];
}

// v2: naboer i samme slægtled som fokus-personen (dæmpet visning ved siden af ankeret). `people`
// er ALTID [fokus, ...naboer] (fokus bevares uanset cap); naboerne sorteres alfabetisk og klippes
// til `cap` — `overflow` fortæller hvor mange der blev skåret væk. `activeCoord == null` (ingen
// aktiv slægtled-kontekst) giver bevidst kun fokus, ingen naboer — v1-adfærd uændret. Bevaret
// byte-identisk mellem web/src/data/tree.ts og mobile/src/data/selectors.ts.
export function buildAnchorPeers(
  model: Model,
  genCoords: GenCoords | undefined,
  anchorId: string,
  activeCoord: { sourceId: string; lineageId: string | null; lokal: number } | null,
  cap = 7,
): { people: ModelPerson[]; overflow: number } {
  const focus = model.byId[anchorId];
  if (!focus) return { people: [], overflow: 0 };
  if (!activeCoord) return { people: [focus], overflow: 0 };
  const peers = model.persons
    .filter((p) => {
      if (p.id === anchorId) return false;
      const pc = genCoords?.[p.id];
      return !!pc?.some((c) =>
        c.sourceId === activeCoord.sourceId
        && c.lineageId === activeCoord.lineageId
        && c.lokal === activeCoord.lokal);
    })
    .sort((a, b) => compareDanish(a.name, b.name));
  const overflow = Math.max(0, peers.length - cap);
  return { people: [focus, ...peers.slice(0, cap)], overflow };
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
