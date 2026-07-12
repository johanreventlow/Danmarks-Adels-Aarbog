// Forsidens rene data-helpers (brief §6). Holdt uden for HomeView så udvælgelsen kan
// unit-testes og genbruges. Ingen DOM, ingen fetch.
import type { Model, ModelPerson } from './types';
import type { EstateItem } from './public';

// Kuraterede startpersoner til forsiden — "redaktionen udpeger kandidaterne" (brief §6).
// Der findes endnu ingen redaktionel highlights-tabel; PoC-udvælgelsen bruger slægtens
// linje-stamfædre (naturlige, stabile ankre — én pr. gren via lineage.list[].headId) og
// udfylder op til n med de mest "centrale" personer (flest børn, spejler startFokus) hvis
// der er for få stamfædre. Deterministisk: samme model → samme udvalg.
export function curatedFounders(model: Model, n: number): ModelPerson[] {
  const out: ModelPerson[] = [];
  const seen = new Set<string>();
  const push = (id: string | null | undefined) => {
    if (!id || seen.has(id)) return;
    const p = model.byId[id];
    if (!p) return;
    seen.add(id);
    out.push(p);
  };
  for (const l of model.lineage?.list ?? []) push(l.headId);
  if (out.length < n) {
    const byCentrality = model.persons
      .map((p) => ({ id: p.id, c: model.indexes.childIdx[p.id]?.size ?? 0 }))
      .filter((x) => x.c > 0 && !seen.has(x.id))
      .sort((a, b) => b.c - a.c || a.id.localeCompare(b.id));
    for (const x of byCentrality) {
      if (out.length >= n) break;
      push(x.id);
    }
  }
  return out.slice(0, n);
}

// Deterministisk "månedens gods" til "Nyt i arkivet" (brief §6): godset med flest
// registrerede ejere (den rigeste ejerrække), tie-break på id. Der findes ingen dato-
// metadata i modellen, så intet "nyt siden"-tidsstempel fabrikeres (brief §8.4 ærlighed).
export function pickMaanedensGods(estates: EstateItem[] | null): EstateItem | null {
  if (!estates || estates.length === 0) return null;
  return [...estates].sort((a, b) => b.ownerCount - a.ownerCount || a.id.localeCompare(b.id))[0];
}
