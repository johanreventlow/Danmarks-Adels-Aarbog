// Stamtræ variant B ("Kolonner"): bidirektionel vandret-scrollende kolonne-stribe.
// Fokus-personen er et fast ANKER i midten; aner folder ud til venstre (Forældre →
// Bedsteforældre → …), efterkommere til højre (Børn → Børnebørn → …). Ren funktion, så
// drill-down-logikken er testbar uafhængigt af komponenten (jf. browse.ts/collapseSameAs.ts).
//
// `up`/`down` ER drill-tilstanden: up[i] = valgt forælder i ane-ring i+1, down[i] = valgt barn
// i efterkommer-ring i+1. En retning stopper ved første ring uden et valg, eller når den valgte
// er forældre-/barnløs. Se docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md.
import { childrenOf, parentsOf } from './model';
import { previousAncestorGen, type GenCoord } from './generations';
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
};

type Traverse = (model: Model, id: string) => ModelPerson[];

const MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
const ANCESTOR_LABELS = ['Forældre', 'Bedsteforældre', 'Oldeforældre', 'Tipoldeforældre'];
const DESCENDANT_LABELS = ['Børn', 'Børnebørn', 'Oldebørn', 'Tipoldebørn'];

// Dybde 1-4 navngives; fra dybde 5 bruges den danske genealogiske kortform "N× tipoldeforældre"
// (= tip-tip-…-oldeforældre): dybde 5 = 2×, 6 = 3× osv. → (dybde − 3)×.
function labelFor(kind: 'ancestor' | 'descendant', depth: number): string {
  const table = kind === 'ancestor' ? ANCESTOR_LABELS : DESCENDANT_LABELS;
  if (depth >= 1 && depth <= table.length) return table[depth - 1];
  return `${depth - 3}× ${kind === 'ancestor' ? 'Tipoldeforældre' : 'Tipoldebørn'}`;
}

// v2-overskrift: kombinerer slægtskabsbetegnelse (ANCESTOR/DESCENDANT_LABELS) med det ABSOLUTTE
// slægtled-tal (genCoord.lokal) + linje-navn, når kendt. Ren formattering — ingen I/O, intet
// TreeColumn-behov; kaldes med de rå felter så den er testbar uafhængigt af
// buildBidirectionalColumns (Task 4 kobler den ind som `label`-erstatning). Inlinet (ikke via
// labelFor) så funktionen er selvstændig — `labelFor` fjernes i Task 4, `columnLabel` skal overleve
// det uændret. Bevaret byte-identisk mellem web/src/data/tree.ts og mobile/src/data/selectors.ts.
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

// Byg fallback-ring: alle personer der deler den FORRIGE generations (linje, lokal)-koordinat med
// `cur`, via `genCoords` (ekstern opslagstabel — ikke `model.genCoordsByPerson`). Ren projektion;
// vælger ingen skrivning, opretter intet — kun kandidat-visning når `parentsOf` er tom. En founder
// (lokal 1) bærer flere linje-koordinater i samme array (kryds-linje-hop via `previousAncestorGen`).
function fallbackAncestorRing(
  model: Model, genCoords: GenCoords | undefined, anchorId: string, cur: string, depth: number,
): TreeColumn | null {
  const coords = genCoords?.[cur];
  if (!coords || !coords.length) return null;
  // Deterministisk rækkefølge: laveste lokal først, så et ægte founder-hop (lokal 1) altid
  // forsøges før en højere-lokal-medlemskab — uafhængigt af hentnings-/indsættelsesrækkefølgen
  // fra DB'en (dual-review 2026-07-05).
  const sorted = [...coords].sort((a, b) => (a.lokal ?? Infinity) - (b.lokal ?? Infinity));
  // Vælg den koordinat vi traverserer på: første med et gyldigt spring til forrige generation.
  // NB: hvis personen reelt hører til flere linjer (flere GenCoord'er), viser ringen kun forrige
  // generation for ÉT af dem — det er aldrig en påstand om en bestemt (mulig forkert) forælder,
  // men et bevidst valg blandt flere gyldige medlemskaber; brugerens aktive traverserings-linje
  // (`c`, i den rækkefølge vi prøver dem) afgør hvilket. Bevidst v2-forfinelse, ikke en bug —
  // se dual-review 2026-07-05.
  for (const c of sorted) {
    if (c.lokal == null) continue;
    const prev = previousAncestorGen(coords, c.linje, c.lokal);
    if (!prev) continue;
    // Skop ringen til SAMME kilde (udgave) + SAMME (konkrete) linje som traverseringskoordinaten
    // `c` — ellers ville to udgavers/linjers "linje III, slægtled 11" blive slået sammen i én ring.
    // prevLineageId: samme linje som c ved et almindeligt ét-skridt-op (c.lineageId), men
    // moderlinjen ved et founder-hop (c.parentLineageId) — spejler previousAncestorGen's egen logik.
    const prevLineageId = (c.lokal as number) > 1 ? c.lineageId : c.parentLineageId;
    const matchesPrev = (k: GenCoord) =>
      k.linje === prev.linje && k.lokal === prev.lokal
      && k.sourceId === c.sourceId && k.lineageId === prevLineageId;
    const all = model.persons.filter((p) => {
      if (p.id === anchorId || p.id === cur) return false;
      const pc = genCoords?.[p.id];
      return !!pc?.some(matchesPrev);
    });
    if (!all.length) continue;
    const kuldGroups: Record<string, ModelPerson[]> = {};
    for (const p of all) {
      const k = genCoords?.[p.id]?.find(matchesPrev)?.kuld ?? '—';
      (kuldGroups[k] ??= []).push(p);
    }
    const gennem = all
      .map((p) => genCoords?.[p.id]?.find(matchesPrev)?.gennem)
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

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet).
// visited (seedet med ankeret + de valgte) guard'er mod self-forælder/cyklus i defekt data.
function buildDirection(
  model: Model,
  anchorId: string,
  selections: string[],
  traverse: Traverse,
  kind: 'ancestor' | 'descendant',
  genCoords?: GenCoords,
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) {
      if (kind === 'ancestor') {
        const fb = fallbackAncestorRing(model, genCoords, anchorId, cur, depth);
        if (fb) cols.push(fb);
      }
      break; // fallback-ringen er en bevidst dødende: vælg re-ankrer i stedet for at drille videre
    }
    const sel = selections[depth - 1] ?? null;
    cols.push({ key: `${kind}:${depth}`, kind, depth, label: labelFor(kind, depth), people, selectedId: sel });
    if (!sel) break; // intet valgt endnu på dette niveau → stop (ingen næste ring)
    visited.add(sel);
    cur = sel;
    depth += 1;
  }
  return cols;
}

// Komposer: [...aner omvendt (dybest yderst til venstre), ankerkolonne, ...efterkommere].
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
