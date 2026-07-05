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

export function previousAncestorGen(
  coords: GenCoord[],
  curLinje: string,
  curLokal: number,
): { linje: string; lokal: number } | null {
  if (curLokal > 1) return { linje: curLinje, lokal: curLokal - 1 };
  // Founder (lokal 1): hop til moderlinjen. Find den aktuelle koordinats parentLineageId.
  const cur = coords.find((c) => c.linje === curLinje && c.lokal === 1);
  const parentId = cur?.parentLineageId ?? null;
  const candidates = coords.filter(
    (c) => c.lineageId != null && c.lineageId === parentId && (c.lokal ?? 0) > 1,
  );
  if (candidates.length !== 1) return null; // fail-closed: kun præcis ét mål
  return { linje: candidates[0].linje, lokal: (candidates[0].lokal as number) - 1 };
}
