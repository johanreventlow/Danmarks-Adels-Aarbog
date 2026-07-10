// Rene generations-helpers. Coalescer ALDRIG generation pr. person: en founder bærer flere
// linje-koordinater med hver sit tal (en person kan være III/12 OG V/1). Koordinaterne driver
// slægtled-labels på det beviste træ (columnGen i tree.ts/selectors.ts) OG den marker-gatede
// kandidat-visning (unknownParentRing) — begge læser den FAKTISKE koordinat, aldrig aritmetik.
import type { RawExtId, RawLineage } from './types';

export type GenCoord = {
  sourceId: string;
  linje: string;
  lineageId: string | null;
  parentLineageId: string | null;
  lokal: number | null;
  gennem: number | null;
  kuld: string | null;
};

export function buildGenCoords(
  extIds: RawExtId[],
  lineageRows: RawLineage[],
  canonicalIdById: Record<string, string>,
): Record<string, GenCoord[]> {
  const linById = new Map<string, RawLineage>();
  for (const l of lineageRows) linById.set(`${l.source_id}:${l.kode}`, l);
  const out: Record<string, GenCoord[]> = {};
  for (const x of extIds) {
    if (x.linje == null) continue; // NULL linje karantænes — ingen koordinat
    const canon = canonicalIdById[String(x.person_id)] ?? String(x.person_id);
    const lin = linById.get(`${x.source_id}:${x.linje}`) ?? null;
    (out[canon] ??= []).push({
      sourceId: String(x.source_id),
      linje: x.linje,
      lineageId: lin && lin.id != null ? String(lin.id) : null,
      parentLineageId: lin && lin.parent_lineage_id != null ? String(lin.parent_lineage_id) : null,
      lokal: x.slaegtled_lokal ?? null,
      gennem: x.slaegtled_gennem ?? null,
      kuld: x.kuld ?? null,
    });
  }
  return out;
}
