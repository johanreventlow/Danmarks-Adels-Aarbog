// Stamtræ variant B ("Kolonner"): vandret-scrollende kolonner, én pr. generation.
// Port af design/project/Reventlow-web-v2.dc.html (linje 1165-1183). Ren funktion, så
// drill-down-logikken er testbar uafhængigt af komponenten (jf. browse.ts/collapseSameAs.ts).
//
// `path` ER hele drill-down-tilstanden: path[0] = fokus-personen (kolonne 0, alene),
// path[i] = det valgte barn i kolonne i. Kolonne i+1 viser børn af path[i]. Kæden
// stopper ved første niveau uden et valg, eller når den valgte person er barnløs.
import { childrenOf } from './model';
import type { Model, ModelPerson } from './types';

export type TreeColumn = {
  level: number;            // 0-indekseret generation-dybde
  label: string;            // "Generation N" (level+1)
  people: ModelPerson[];    // kort i kolonnen
  selectedId: string | null; // hvilket kort der er valgt (driver næste kolonne)
};

const MAX_DEPTH = 40; // guard mod utilsigtet cyklus i forældre/barn-data (jf. design)

export function buildTreeColumns(model: Model, path: string[]): TreeColumn[] {
  const cols: TreeColumn[] = [];
  const root = path[0] ? model.byId[path[0]] : undefined;
  if (!root) return cols;

  cols.push({ level: 0, label: 'Generation 1', people: [root], selectedId: path[0] });

  let cur = path[0];
  let i = 1;
  while (i <= MAX_DEPTH) {
    const kids = childrenOf(model, cur);
    if (!kids.length) break;
    const sel = path[i] ?? null;
    cols.push({ level: i, label: `Generation ${i + 1}`, people: kids, selectedId: sel });
    if (!sel) break; // intet valgt endnu på dette niveau → stop (ingen næste kolonne)
    cur = sel;
    i += 1;
  }
  return cols;
}
