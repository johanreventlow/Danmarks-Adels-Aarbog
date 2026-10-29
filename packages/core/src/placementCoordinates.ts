// 5c-2 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.2-4.3): læserens kildekoordinater kommer fra RPC'en
// public_person_source_coordinates (placement ved gældende membership, ellers legacy). Én fælles mapping til RawExtId
// for web og mobil, og én sortering af linjehovedet, der tåler bogstavsuffikser (15a før 15b før 16).
import type { RawExtId } from './types';

export type PublicCoordinateRow = {
  person_id: number | string;
  source_id: number | string;
  legacy_line_code: string | null;
  printed_number: number | null;
  printed_number_label: string | null;
  generation_local: number | null;
  generation_global: number | null;
  kuld_label: string | null;
  provenance_kind: 'placement' | 'legacy_external_id';
};

export function coordinateRowToExtId(row: PublicCoordinateRow): RawExtId {
  return {
    person_id: row.person_id,
    source_id: row.source_id,
    linje: row.legacy_line_code,
    nr: row.printed_number,
    nr_label: row.printed_number_label,
    slaegtled_lokal: row.generation_local,
    slaegtled_gennem: row.generation_global,
    kuld: row.kuld_label,
    provenance: row.provenance_kind,
  };
}

type HeadKey = { nr: number | null; nr_label?: string | null };

// Heltallet først (null sidst), ved lige tal labelen (manglende label = det rene tal, før et suffiks).
export function compareLineHead(a: HeadKey, b: HeadKey): number {
  const an = a.nr ?? Number.POSITIVE_INFINITY;
  const bn = b.nr ?? Number.POSITIVE_INFINITY;
  if (an !== bn) return an < bn ? -1 : 1;
  const al = a.nr_label ?? (a.nr == null ? '' : String(a.nr));
  const bl = b.nr_label ?? (b.nr == null ? '' : String(b.nr));
  return al < bl ? -1 : al > bl ? 1 : 0;
}
