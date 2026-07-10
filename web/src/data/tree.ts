// Stamtræ variant B ("Kolonner"): bidirektionel vandret-scrollende kolonne-stribe.
// Fokus-personen er et fast ANKER i midten; aner folder ud til venstre (Forældre →
// Bedsteforældre → …), efterkommere til højre (Børn → Børnebørn → …). Ren funktion, så
// drill-down-logikken er testbar uafhængigt af komponenten (jf. browse.ts/collapseSameAs.ts).
//
// `up`/`down` ER drill-tilstanden: up[i] = valgt forælder i ane-ring i+1, down[i] = valgt barn
// i efterkommer-ring i+1. En retning stopper ved første ring uden et valg, eller når den valgte
// er forældre-/barnløs. Se docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md.
//
// KUN BEVISTE KANTER. Der er BEVIDST ingen "gæt et manglende slægtled"-fallback her: en manglende
// forælder-kant i basen kan lige så godt være et udtræks-hul som en genuin uforbundethed i kilden,
// og de to må ikke behandles ens (docs/reviews/25-generationer-ukendt-forbindelse-analyse.md).
// Den ærlige, marker-gatede kandidat-visning (kun hvor kilden faktisk angiver "ingen forbindelse")
// bygges separat i unknownParentRing (Phase C) — den fyrer på en TILSTEDEVÆRENDE markering, aldrig
// på fravær af en kant. Slægtled-tal/-linje til labels læses fra den faktiske koordinat (columnGen),
// aldrig ved aritmetik fra ankeret (review 20 H1: gav "-7. slægtled" for founder-aner).
import { childrenOf, parentsOf } from './model';
import { type GenCoord } from './generations';
import type { Model, ModelPerson } from './types';

export type ColumnKind = 'ancestor' | 'anchor' | 'descendant';

// Genereret koordinat-opslag pr. person — sendes EKSPLICIT ind (ikke `model.genCoordsByPerson`),
// så bygge-funktionen forbliver platform-agnostisk: web sender model.genCoordsByPerson, mobil
// sender store/LoadResult-værdien (mobils smalle `Model` bærer bevidst ikke feltet selv).
export type GenCoords = Record<string, GenCoord[]>;

export type TreeColumn = {
  key: string;               // STABIL identitet `${kind}:${depth}` — ancestor:1 ≠ descendant:1
  kind: ColumnKind;
  depth: number;             // 0 = anker, 1.. = ring-afstand fra ankeret
  label: string;             // relativt slægts-label (+ slægtled/linje når kendt)
  people: ModelPerson[];     // alle registrerede i ringen (ikke antaget = 2 for forældre)
  selectedId: string | null; // valgt kort → driver næste ring i samme retning
};

type Traverse = (model: Model, id: string) => ModelPerson[];

const MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
const ANCESTOR_LABELS = ['Forældre', 'Bedsteforældre', 'Oldeforældre', 'Tipoldeforældre'];
const DESCENDANT_LABELS = ['Børn', 'Børnebørn', 'Oldebørn', 'Tipoldebørn'];

// Kolonne-overskrift: kombinerer slægtskabsbetegnelse (ANCESTOR/DESCENDANT_LABELS) med det ABSOLUTTE
// slægtled-tal (genCoord.lokal) + linje-navn, når kendt. Ren formattering — ingen I/O, intet
// TreeColumn-behov; kaldes med de rå felter så den er testbar uafhængigt af
// buildBidirectionalColumns. `slaegtled == null` → falder tilbage til rene kinship-labels (ingen
// regression for personer uden slægtled-data). Bevaret byte-identisk mellem
// web/src/data/tree.ts og mobile/src/data/selectors.ts.
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
// lokal ∓ depth (som antog monoton samme-linje-tælling; brister for en founder-anker der reelt
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
// kinship-labels. Ingen fallback: en tom bevist ring er en ærlig dødende (den marker-gatede
// kandidat-visning håndteres separat af kalderen — se unknownParentRing).
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
    if (!people.length) break; // ærlig dødende — ingen ugated gætning på et manglende slægtled
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

// Komposer: [...aner omvendt (dybest yderst til venstre), ankerkolonne, ...efterkommere].
// Slægtled-labels læses fra genCoords (valgfri) via columnGen — ankerets eget tal fra dets egen
// koordinat (null/"Fokus" hvis founderen bærer flere linje-medlemskaber, dvs. tvetydig).
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
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant', genCoords);
  const ag = columnGen(genCoords, [anchor]);
  const anchorCol: TreeColumn = {
    key: 'anchor:0', kind: 'anchor', depth: 0,
    label: columnLabel({ kind: 'anchor', depth: 0, slaegtled: ag?.lokal ?? null, linje: ag?.linje ?? null }),
    people: [anchor], selectedId: anchorId,
  };
  return [...ancestors.reverse(), anchorCol, ...descendants];
}
