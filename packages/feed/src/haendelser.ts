import type { HaendelseItem, HaendelserBy } from './types';

export interface HaendelseRow {
  id: string | number;
  subjekt_id: string | number;
  narrative_id: string | number;
  klausul: string;
  kategori: string | null;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
  date_raw: string | null;
  feed_status: string;
  fact_id: string | number | null;
  relation_id: string | number | null;
}

export interface HaendelseNarrativRow {
  id: string | number;
  source_id: string | number | null;
  side: string | number | null;
}

export interface HaendelseSourceRow {
  id: string | number;
  udgave: string | number | null;
}

const sortKey = (item: HaendelseItem): string => item.dato.min ?? '9999-99-99';

export function buildHaendelserBy(
  rows: HaendelseRow[],
  narrativer: HaendelseNarrativRow[],
  sources: HaendelseSourceRow[],
  canonicalIdById: Record<string, string> = {},
): HaendelserBy {
  const narrativeById = new Map(narrativer.map((n) => [String(n.id), n]));
  const sourceById = new Map(sources.map((s) => [String(s.id), s]));
  const out: HaendelserBy = {};

  for (const row of rows) {
    if (row.feed_status === 'skjult') continue;
    const personId = canonicalIdById[String(row.subjekt_id)] ?? String(row.subjekt_id);
    const narrative = narrativeById.get(String(row.narrative_id));
    const source = narrative?.source_id == null ? undefined : sourceById.get(String(narrative.source_id));
    const udgave = source?.udgave == null ? null : String(source.udgave);
    const side = narrative?.side == null ? null : String(narrative.side);
    const kilde = udgave == null ? null : `DAA ${udgave}${side == null ? '' : `, s. ${side}`}`;

    const item: HaendelseItem = {
      id: String(row.id),
      klausul: row.klausul,
      kategori: row.kategori,
      dato: { min: row.date_min, max: row.date_max, qualifier: row.date_qualifier },
      dateRaw: row.date_raw,
      interessant: row.feed_status === 'interessant',
      rygrad: row.fact_id != null || row.relation_id != null,
      kilde,
    };
    (out[personId] ??= []).push(item);
  }

  for (const items of Object.values(out)) {
    items.sort((a, b) => sortKey(a).localeCompare(sortKey(b)) || a.id.localeCompare(b.id));
  }
  return out;
}
