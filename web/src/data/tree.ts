// Stamtræ variant B ("Kolonner"): bidirektionel vandret-scrollende kolonne-stribe.
// Fokus-personen er et fast ANKER i midten; aner folder ud til venstre (Forældre →
// Bedsteforældre → …), efterkommere til højre (Børn → Børnebørn → …). Ren funktion, så
// drill-down-logikken er testbar uafhængigt af komponenten (jf. browse.ts/collapseSameAs.ts).
//
// `up`/`down` ER drill-tilstanden: up[i] = valgt forælder i ane-ring i+1, down[i] = valgt barn
// i efterkommer-ring i+1. En retning stopper ved første ring uden et valg, eller når den valgte
// er forældre-/barnløs. Se docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md.
import { childrenOf, parentsOf } from './model';
import type { Model, ModelPerson } from './types';

export type ColumnKind = 'ancestor' | 'anchor' | 'descendant';

export type TreeColumn = {
  key: string;               // STABIL identitet `${kind}:${depth}` — ancestor:1 ≠ descendant:1
  kind: ColumnKind;
  depth: number;             // 0 = anker, 1.. = ring-afstand fra ankeret
  label: string;             // relativt slægts-label
  people: ModelPerson[];     // alle registrerede i ringen (ikke antaget = 2 for forældre)
  selectedId: string | null; // valgt kort → driver næste ring i samme retning
};

type Traverse = (model: Model, id: string) => ModelPerson[];

const MAX_DEPTH = 40; // øvre loft (visited-Set nedenfor er den egentlige cyklus-guard)
const ANCESTOR_LABELS = ['Forældre', 'Bedsteforældre', 'Oldeforældre', 'Tipoldeforældre'];
const DESCENDANT_LABELS = ['Børn', 'Børnebørn', 'Oldebørn', 'Tipoldebørn'];

function labelFor(kind: 'ancestor' | 'descendant', depth: number): string {
  const table = kind === 'ancestor' ? ANCESTOR_LABELS : DESCENDANT_LABELS;
  if (depth >= 1 && depth <= table.length) return table[depth - 1];
  return `${depth}. slægtled ${kind === 'ancestor' ? 'tilbage' : 'frem'}`;
}

// Bygger kolonner der udvider fra ankeret i ÉN retning (ankeret IKKE inkluderet).
// visited (seedet med ankeret + de valgte) guard'er mod self-forælder/cyklus i defekt data.
function buildDirection(
  model: Model,
  anchorId: string,
  selections: string[],
  traverse: Traverse,
  kind: 'ancestor' | 'descendant',
): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const visited = new Set<string>([anchorId]);
  let cur = anchorId;
  let depth = 1;
  while (depth <= MAX_DEPTH) {
    const people = traverse(model, cur).filter((p) => !visited.has(p.id));
    if (!people.length) break;
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
): TreeColumn[] {
  const anchor = model.byId[anchorId];
  if (!anchor) return [];
  const ancestors = buildDirection(model, anchorId, up, parentsOf, 'ancestor');
  const descendants = buildDirection(model, anchorId, down, childrenOf, 'descendant');
  const anchorCol: TreeColumn = {
    key: 'anchor:0', kind: 'anchor', depth: 0, label: 'Fokus', people: [anchor], selectedId: anchorId,
  };
  return [...ancestors.reverse(), anchorCol, ...descendants];
}
