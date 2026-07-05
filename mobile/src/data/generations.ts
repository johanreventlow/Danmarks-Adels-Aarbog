// Rene generations-helpers til hul-reparation. Coalescer ALDRIG generation pr. person:
// en founder bærer flere linje-koordinater med hver sit tal (design-spec §6-7).
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

// Retnings-generaliseret nabo-generation: dir=-1 er v1's founder-hoppende ane-logik (nu
// (sourceId, lineageId)-scoped i stedet for kun `linje`), dir=+1 er den enkle efterkommer-
// retning — samme (sourceId, lineageId), lokal+1, ALDRIG hop (design-spec §T1).
export function adjacentGen(
  coords: GenCoord[],
  sourceId: string,
  lineageId: string | null,
  lokal: number,
  dir: -1 | 1,
): { sourceId: string; lineageId: string | null; linje: string; lokal: number } | null {
  const cur = coords.find((c) => c.sourceId === sourceId && c.lineageId === lineageId && c.lokal === lokal);
  if (dir === 1) {
    if (!cur) return null;
    return { sourceId, lineageId, linje: cur.linje, lokal: lokal + 1 };
  }
  // dir === -1
  if (lokal > 1) {
    if (!cur) return null;
    return { sourceId, lineageId, linje: cur.linje, lokal: lokal - 1 };
  }
  // Founder (lokal 1): hop til moderlinjen. Find den aktuelle koordinats parentLineageId.
  const parentId = cur?.parentLineageId ?? null;
  const candidates = coords.filter(
    (c) => c.sourceId === sourceId && c.lineageId != null && c.lineageId === parentId && (c.lokal ?? 0) > 1,
  );
  if (candidates.length !== 1) return null; // fail-closed: kun præcis ét mål
  const t = candidates[0];
  return { sourceId, lineageId: t.lineageId, linje: t.linje, lokal: (t.lokal as number) - 1 };
}
