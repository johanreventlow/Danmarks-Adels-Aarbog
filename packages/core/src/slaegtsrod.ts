// Slægts-rod og arvet slægtsnavn — klient-siden af `lineage_effective_slaegtsnavn()`.
//
// Slægtsnavnet bor på slægts-roden (den lineage-række uden parent_lineage_id) og arves ned ad
// parent_lineage_id til grenene, så det står ÉT sted pr. slægt i stedet for gentaget på hver gren.
// En undergren der har skiftet navn (adling, len) bærer sit eget og vinder over rodens — samme
// regel som i DB'en: første ikke-NULL på vejen op.
//
// Klienten SKAL folde det samme; læser man `lineage.slaegtsnavn` råt, viser en gren tomt.

export type LineageArv = {
  id: number | string;
  slaegtsnavn: string | null;
  parent_lineage_id: number | string | null;
};

const MAX_DYBDE = 50; // samme grænse som lineage_ancestors()

/** Første ikke-NULL slaegtsnavn på vejen fra linjen op mod roden. Null hvis ingen findes. */
export function effektivtSlaegtsnavn(rows: LineageArv[], id: number | string): string | null {
  const byId = new Map(rows.map((r) => [String(r.id), r]));
  const set = new Set<string>();
  let cur = byId.get(String(id));
  for (let i = 0; cur && i < MAX_DYBDE; i++) {
    const key = String(cur.id);
    if (set.has(key)) return null; // cyklus: terminer frem for at hænge
    set.add(key);
    if (cur.slaegtsnavn) return cur.slaegtsnavn;
    if (cur.parent_lineage_id == null) return null;
    cur = byId.get(String(cur.parent_lineage_id));
  }
  return null;
}

/**
 * Slægts-rodens id: rækken uden ophav der selv bærer et slægtsnavn. Før B2-migrationen har hver
 * gren sit eget navn og intet ophav — da vælges den laveste, så opslag der før pegede hårdt på
 * lineage 1 fortsat virker.
 */
export function findSlaegtsrod(rows: LineageArv[]): number | string | null {
  const kandidater = rows.filter((r) => r.parent_lineage_id == null && r.slaegtsnavn);
  if (!kandidater.length) return null;
  return kandidater.sort((a, b) => (Number(a.id) || 0) - (Number(b.id) || 0))[0].id;
}
