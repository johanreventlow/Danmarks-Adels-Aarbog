// Frontend identitets-projektion: folder flere person-rækker der er samme fysiske person
// (linket via afklarede samme_som-relationer) til ÉN kanonisk post FØR buildModel, så
// slægtskabs-motoren forbliver urørt. Reversibel (returnerer alias-map + proveniens) og
// valideret (konflikter karantæneres, foldes ikke). Se spec 2026-07-02-samme-som-collapse-design.md.
import type { SameAsEdge, QuarantineNote } from './types';

// Union-find over samme_som-kanter → grupper. Kanonisk = unik sink (alias-outdegree 0).
// Karantæne hvis: ingen unik sink, retnings-cyklus, eller endpoint ukendt (ufuldstændig
// komponent — RLS kan have skjult en tvilling). Reversibel: kalder får medlems-lister.
export function groupSameAs(
  edges: SameAsEdge[],
  knownIds: Set<string>,
): { groups: Map<string, string[]>; quarantined: QuarantineNote[] } {
  // Normalisér: fjern dubletter + self-loops.
  const norm = new Map<string, SameAsEdge>();
  for (const e of edges) {
    if (e.alias === e.canonical) continue;
    norm.set(`${e.alias}->${e.canonical}`, e);
  }
  const edgeList = [...norm.values()];

  // Union-find (uden retning) → komponenter.
  const parent = new Map<string, string>();
  const find = (x: string): string => {
    parent.set(x, parent.get(x) ?? x);
    let r = x;
    while (parent.get(r) !== r) r = parent.get(r)!;
    while (parent.get(x) !== r) {
      const n = parent.get(x)!;
      parent.set(x, r);
      x = n;
    }
    return r;
  };
  const union = (a: string, b: string) => {
    parent.set(find(a), find(b));
  };
  for (const e of edgeList) {
    find(e.alias);
    find(e.canonical);
    union(e.alias, e.canonical);
  }

  // Komponent-medlemmer + alias-flag (om noden nogensinde optræder som alias).
  const members = new Map<string, Set<string>>();
  const isAlias = new Map<string, boolean>();
  for (const id of parent.keys()) {
    const r = find(id);
    (members.get(r) ?? members.set(r, new Set()).get(r)!).add(id);
    if (!isAlias.has(id)) isAlias.set(id, false);
  }
  for (const e of edgeList) isAlias.set(e.alias, true);

  const groups = new Map<string, string[]>();
  const quarantined: QuarantineNote[] = [];
  for (const [, mem] of members) {
    const ids = [...mem];
    const missing = ids.filter((id) => !knownIds.has(id));
    if (missing.length) {
      quarantined.push({ members: ids, reason: `ufuldstændig komponent (mangler ${missing.join(',')})` });
      continue;
    }
    const sinks = ids.filter((id) => !isAlias.get(id)); // aldrig alias = sink-kandidat
    if (sinks.length !== 1) {
      quarantined.push({ members: ids, reason: `ingen unik sink (kandidater: ${sinks.join(',') || 'ingen'})` });
      continue;
    }
    groups.set(sinks[0], ids);
  }
  return { groups, quarantined };
}
