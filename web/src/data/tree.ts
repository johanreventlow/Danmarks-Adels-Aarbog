// Stamtræ variant B ("Kolonner"): bidirektionel vandret-scrollende kolonne-stribe.
// Fokus-personen er et fast ANKER i midten; aner folder ud til venstre (Forældre →
// Bedsteforældre → …), efterkommere til højre (Børn → Børnebørn → …). Ren funktion, så
// drill-down-logikken er testbar uafhængigt af komponenten (jf. browse.ts/collapseSameAs.ts).
//
// `up`/`down` ER drill-tilstanden: up[i] = valgt forælder i ane-ring i+1, down[i] = valgt barn
// i efterkommer-ring i+1. En retning stopper ved første ring uden et valg, eller når den valgte
// er forældre-/barnløs. Se docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md.
import { childrenOf, parentsOf } from './model';
import { adjacentGen, type GenCoord } from './generations';
import type { Model, ModelPerson } from './types';
import { compareDanish } from '../lib/collation';

export type ColumnKind = 'ancestor' | 'anchor' | 'descendant';

// Genereret koordinat-opslag pr. person — sendes EKSPLICIT ind (ikke `model.genCoordsByPerson`),
// så bygge-funktionen forbliver platform-agnostisk: web sender model.genCoordsByPerson, mobil
// sender store/LoadResult-værdien (mobils smalle `Model` bærer bevidst ikke feltet selv).
export type GenCoords = Record<string, GenCoord[]>;

export type TreeColumn = {
  key: string;               // STABIL identitet `${kind}:${depth}` — ancestor:1 ≠ descendant:1
  kind: ColumnKind;
  depth: number;             // 0 = anker, 1.. = ring-afstand fra ankeret
  label: string;             // relativt slægts-label
  people: ModelPerson[];     // alle registrerede i ringen (ikke antaget = 2 for forældre)
  selectedId: string | null; // valgt kort → driver næste ring i samme retning
  fallback?: boolean;                         // true = ubeviste generations-naboer (ikke `parentsOf`)
  genLabel?: string;                          // 'N. slægtled · <linje>-linjen (M. gennemgående)'
  kuldGroups?: Record<string, ModelPerson[]>; // gruppering pr. kuld (v1, hvor kendt)
  focusId?: string;      // v2: sat KUN på anker-kolonnen — dominant kort blandt fokus+naboer
  overflowPeers?: number; // v2: antal slægtled-naboer skåret væk af buildAnchorPeers' cap
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
  traverse: Traverse,
  kind: 'ancestor' | 'descendant',
  dir: -1 | 1,
  activeLokal: number | null,
  genCoords?: GenCoords,
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) {
      // Efterkommer-fallback er patrilineal (DAA-linjen føres videre gennem manden): en kvinde
      // fører ALDRIG linjen videre, så vis aldrig "muligt næste slægtled" som hendes efterkommer-
      // kandidater (review 20 fix 3). Ane-fallback (dir=-1) er upåvirket — kvinder har naturligvis
      // ane-linjer. Ukendt/manglende køn behandles som ikke-kvinde (uændret v1/v2-adfærd).
      const curIsKvinde = model.byId[cur]?.koen === 'kvinde';
      const fallbackAllowed = dir === -1 || (activeLokal != null && !curIsKvinde);
      const fb = fallbackAllowed ? fallbackRing(model, genCoords, anchorId, cur, depth, dir) : null;
      if (fb) cols.push(fb);
      break; // fallback-ringen er en bevidst dødende: vælg re-ankrer i stedet for at drille videre
    }
    const sel = selections[depth - 1] ?? null;
    // Konsulter kun genCoords når vi er i v2-aktiv-koordinat-tilstand (`activeLokal != null`) —
    // samme opt-in-gate som resten af filen. Uden den ville en kalder uden UI-wiring til
    // activeCoord (der aldrig satte den fri) pludselig se slægtled-tal dukke op, fordi personerne
    // i ringen TILFÆLDIGVIS har genCoords (v1-regression).
    const g = activeLokal != null ? columnGen(genCoords, people, sel) : null;
    const label = columnLabel({ kind, depth, slaegtled: g?.lokal ?? null, linje: g?.linje ?? null });
    cols.push({ key: `${kind}:${depth}`, kind, depth, label, people, selectedId: sel });
    if (!sel) break; // intet valgt endnu på dette niveau → stop (ingen næste ring)
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
  const ancestors = buildDirection(model, anchorId, up, parentsOf, 'ancestor', -1, activeLokal, genCoords);
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant', 1, activeLokal, genCoords);
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
