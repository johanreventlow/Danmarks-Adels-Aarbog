// Afledte selektorer over model + aux. Rene funktioner (testbare) — skærmene kalder dem
// frem for at grave i indekser direkte.
import { compareDanish, initialOf } from '../lib/collation';
import { GRADE_FORAELDER_UKENDT, type GenCoord, type ParentsUnknown } from './generations';
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
export type ParentsUnknownMap = Record<string, ParentsUnknown>;

export type TreeColumn = {
  key: string;               // STABIL identitet `${kind}:${depth}` — ancestor:1 ≠ descendant:1
  kind: ColumnKind;
  depth: number;             // 0 = anker, 1.. = ring-afstand fra ankeret
  label: string;             // relativt slægts-label (+ slægtled/linje når kendt)
  people: ModelPerson[];     // alle registrerede i ringen (ikke antaget = 2 for forældre)
  selectedId: string | null; // valgt kort → driver næste ring i samme retning
  // --- marker-gatet kandidat-kolonne (kun hvor KILDEN angiver "ingen forbindelse opad") ---
  candidate?: boolean;                         // true = ubeviste kandidater i forrige slægtled
  candidateNote?: string;                      // grad-afhængig ærlig ordlyd (mulige forældre vs. blot naboer)
  kilde?: string | null;                       // proveniens for markeringen (citationens citat_tekst)
  kuldGroups?: Record<string, ModelPerson[]>;  // kuld-gruppering af kandidaterne (hvor kendt)
};

type Traverse = (model: Model, id: string) => ModelPerson[];

const MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
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
}): string {
  if (a.kind === 'anchor') {
    if (a.slaegtled == null) return 'Fokus';
    return `${a.slaegtled}. slægtled · ${a.linje}-linjen`;
  }
  if (a.depth <= 4) {
    const table = a.kind === 'ancestor' ? ANCESTOR_LABELS : DESCENDANT_LABELS;
    const kinship = table[a.depth - 1];
    if (a.slaegtled == null) return kinship;
    if (a.linje == null) return `${kinship} · ${a.slaegtled}. slægtled`;
    return `${kinship} · ${a.slaegtled}. slægtled · ${a.linje}-linjen`;
  }
  if (a.slaegtled == null) {
    return `${a.depth - 3}× ${a.kind === 'ancestor' ? 'Tipoldeforældre' : 'Tipoldebørn'}`;
  }
  if (a.linje == null) return `${a.slaegtled}. slægtled`;
  return `${a.slaegtled}. slægtled · ${a.linje}-linjen`;
}

// Læs kolonnens FAKTISKE (lokal, linje)-koordinat fra genCoords — ALDRIG aritmetik fra ankerets
// activeLokal (som antog monoton ∓depth i samme linje; brister for en founder-anker der reelt
// hopper linje — review 20 H1: person 290 fik "-7. slægtled" i stedet for bogens faktiske "III,
// 4. slægtled"). Samler koordinaterne for alle `people` der har én; hvis de deler PRÆCIS ét
// (lokal, linje)-par (konsensus), returneres det — ellers `null` (blandet/ukendt → ren kinship-
// label, ingen gætning, jf. Codex-recalibrering i review 20). `selectedId`s koordinat bruges som
// tiebreak hvis ringen ellers er tvetydig (fx en founder i ringen der selv bærer flere linje-
// medlemskaber). Bevaret byte-identisk mellem web/src/data/tree.ts og mobile/src/data/selectors.ts.
export function columnGen(
  genCoords: GenCoords | undefined,
  people: ModelPerson[],
  selectedId?: string | null,
): { lokal: number; linje: string } | null {
  if (!genCoords) return null;
  const pairs = new Map<string, { lokal: number; linje: string }>();
  for (const p of people) {
    for (const c of genCoords[p.id] ?? []) {
      if (c.lokal == null) continue;
      pairs.set(`${c.lokal}:${c.linje}`, { lokal: c.lokal, linje: c.linje });
    }
  }
  if (pairs.size === 1) return [...pairs.values()][0];
  if (pairs.size > 1 && selectedId != null) {
    for (const c of genCoords[selectedId] ?? []) {
      if (c.lokal == null) continue;
      const key = `${c.lokal}:${c.linje}`;
      if (pairs.has(key)) return pairs.get(key)!;
    }
  }
  return null;
}

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet).
// visited (seedet med ankeret + de valgte) guard'er mod self-forælder/cyklus i defekt data.
// Slægtled/linje til labels læses fra den faktiske koordinat (columnGen); `null` → rene
// kinship-labels. En tom bevist ane-ring dødender ærligt — MEN hvis den aktuelle person bærer en
// afklaret "forældre ukendt"-markering (parentsUnknown), vises i stedet en marker-gatet
// kandidat-kolonne (unknownParentRing) med kildens forrige slægtled. Fyrer ALDRIG på fravær af en
// kant alene (det var v1/v2-fejlen) — kun på en TILSTEDEVÆRENDE markering. Aner-retning kun.
function buildDirection(
  model: Model,
  anchorId: string,
  selections: string[],
  traverse: Traverse,
  kind: 'ancestor' | 'descendant',
  genCoords?: GenCoords,
  parentsUnknown?: ParentsUnknownMap,
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) {
      if (kind === 'ancestor' && parentsUnknown) {
        const ring = unknownParentRing(model, genCoords, cur, parentsUnknown[cur], depth);
        if (ring) cols.push(ring);
      }
      break; // ærlig dødende (evt. med kandidat-kolonne) — vælg re-ankrer i stedet for at drille videre
    }
    const sel = selections[depth - 1] ?? null;
    const g = columnGen(genCoords, people, sel);
    const label = columnLabel({ kind, depth, slaegtled: g?.lokal ?? null, linje: g?.linje ?? null });
    cols.push({ key: `${kind}:${depth}`, kind, depth, label, people, selectedId: sel });
    if (!sel) break; // intet valgt endnu på dette niveau → stop (ingen næste ring)
    visited.add(sel);
    cur = sel;
    depth += 1;
  }
  return cols;
}

// Marker-gatet kandidat-kolonne: personer i FORRIGE slægtled (lokal-1) i hver af den markerede
// persons linjer (en founder henter kandidater fra hver moderlinje). Fyrer KUN når `marking`
// findes (afklaret 'forældre_ukendt') — ikke på en manglende kant. Grad afgør ordlyden: mulige
// forældre vs. blot "andre i forrige slægtled". kuld-grupperet; proveniens fra markeringen. Ren
// projektion — skriver aldrig en kant. Bevaret byte-identisk web ↔ mobil (docs/reviews/25-*).
export function unknownParentRing(
  model: Model,
  genCoords: GenCoords | undefined,
  markedId: string,
  marking: ParentsUnknown | undefined,
  depth: number,
): TreeColumn | null {
  if (!marking || !genCoords) return null;
  const coords = (genCoords[markedId] ?? []).filter((c) => c.lokal != null && (c.lokal as number) > 1);
  if (!coords.length) return null;
  const members = new Map<string, { person: ModelPerson; kuld: string; linje: string; lokal: number }>();
  for (const c of coords) {
    const tLokal = (c.lokal as number) - 1;
    for (const p of model.persons) {
      if (p.id === markedId || members.has(p.id)) continue;
      const pc = (genCoords[p.id] ?? []).find(
        (k) => k.sourceId === c.sourceId && k.lineageId === c.lineageId && k.lokal === tLokal,
      );
      if (pc) members.set(p.id, { person: p, kuld: pc.kuld ?? '—', linje: pc.linje, lokal: tLokal });
    }
  }
  if (!members.size) return null; // intet forrige slægtled at bladre til → ingen ring
  const kuldGroups: Record<string, ModelPerson[]> = {};
  for (const m of members.values()) (kuldGroups[m.kuld] ??= []).push(m.person);
  const people = [...members.values()].map((m) => m.person);
  // Vist generation = target-slægtled (deterministisk laveste lokal/linje ved flere linjer).
  const target = [...members.values()].sort((a, b) => a.lokal - b.lokal || a.linje.localeCompare(b.linje))[0];
  const candidateNote = marking.grade === GRADE_FORAELDER_UKENDT
    ? 'Mulige forældre — kilden navngiver dem ikke'
    : 'Kilden angiver ingen forbindelse — andre i forrige slægtled';
  return {
    key: `ancestor:${depth}:cand`, kind: 'ancestor', depth,
    label: `${target.lokal}. slægtled · ${target.linje}-linjen`,
    people, selectedId: null,
    candidate: true, candidateNote, kilde: marking.kilde ?? null, kuldGroups,
  };
}

// Komposer: [...aner omvendt (dybest yderst til venstre), ankerkolonne, ...efterkommere].
// Slægtled-labels læses fra genCoords (valgfri) via columnGen — ankerets eget tal fra dets egen
// koordinat (null/"Fokus" hvis founderen bærer flere linje-medlemskaber, dvs. tvetydig).
// `parentsUnknown` (valgfri) aktiverer den marker-gatede kandidat-kolonne i ANE-retningen, dér
// hvor en markeret person dødender uden bevist forælder (se buildDirection/unknownParentRing).
export function buildBidirectionalColumns(
  model: Model,
  anchorId: string,
  up: string[],
  down: string[],
  genCoords?: GenCoords,
  parentsUnknown?: ParentsUnknownMap,
): TreeColumn[] {
  const anchor = model.byId[anchorId];
  if (!anchor) return [];
  const ancestors = buildDirection(model, anchorId, up, parentsOf, 'ancestor', genCoords, parentsUnknown);
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant', genCoords);
  const ag = columnGen(genCoords, [anchor]);
  const anchorCol: TreeColumn = {
    key: 'anchor:0', kind: 'anchor', depth: 0,
    label: columnLabel({ kind: 'anchor', depth: 0, slaegtled: ag?.lokal ?? null, linje: ag?.linje ?? null }),
    people: [anchor], selectedId: anchorId,
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
