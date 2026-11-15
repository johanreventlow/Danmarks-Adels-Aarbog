// 5c-2 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.2-4.3): læserens kildekoordinater kommer fra RPC'en
// public_person_source_coordinates (placement ved gældende membership, ellers legacy). Én fælles mapping til RawExtId
// for web og mobil, og én sortering af linjehovedet, der tåler bogstavsuffikser (15a før 15b før 16).
import type { RawExtId } from './types';
import { getAll } from './getAll';

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
  printed_page?: string | null; // 6e-2: findes først efter DDL
};

// Kodereview 36 P2: koordinaterne hentes i ÉT kald fra public_person_source_coordinates_samlet (jsonb-array af de
// samme rækker). Rækkefunktionen må ikke offset-pagineres (den beregnes forfra pr. side, jf. getAll). Findes den nye
// funktion ikke endnu (frontend deployet før DDL'en), falder vi tilbage til den gamle via getAll; alle andre fejl
// kastes videre til kalderens degraderingssti.
export const COORDINATES_RPC_SAMLET = 'public_person_source_coordinates_samlet';
export const COORDINATES_RPC_RAEKKER = 'public_person_source_coordinates';

type RpcSvar = { data: unknown; error: unknown };

// PostgREST: PGRST202 = funktionen findes ikke i schema-cachen; 42883 = Postgres' undefined_function.
export function erUkendtFunktion(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  return code === 'PGRST202' || code === '42883';
}

export async function fetchPublicCoordinates(
  samlet: () => PromiseLike<RpcSvar>,
  raekker: () => { range: (from: number, to: number) => PromiseLike<{ data: PublicCoordinateRow[] | null; error: unknown }> },
): Promise<PublicCoordinateRow[]> {
  const { data, error } = await samlet();
  if (!error) {
    if (!Array.isArray(data)) throw new Error(`${COORDINATES_RPC_SAMLET}: forventede et JSON-array`);
    return data as PublicCoordinateRow[];
  }
  if (erUkendtFunktion(error)) return getAll<PublicCoordinateRow>(raekker);
  throw error;
}

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
    trykt_side: row.printed_page ?? null,
  };
}

export type HeadKey = { nr: number | null; nr_label?: string | null; slaegtled?: number | null };

// Linjens hoved (6e-2): laveste slægtled først (NULL sidst), dernæst unummereret før nummereret, så heltallet og
// ved lige tal labelen (manglende label = det rene tal, før et suffiks).
export function compareLineHead(a: HeadKey, b: HeadKey): number {
  const ag = a.slaegtled ?? Number.POSITIVE_INFINITY;
  const bg = b.slaegtled ?? Number.POSITIVE_INFINITY;
  if (ag !== bg) return ag < bg ? -1 : 1;
  if ((a.nr == null) !== (b.nr == null)) return a.nr == null ? -1 : 1;
  const an = a.nr ?? 0;
  const bn = b.nr ?? 0;
  if (an !== bn) return an < bn ? -1 : 1;
  const al = a.nr_label ?? (a.nr == null ? '' : String(a.nr));
  const bl = b.nr_label ?? (b.nr == null ? '' : String(b.nr));
  return al < bl ? -1 : al > bl ? 1 : 0;
}
