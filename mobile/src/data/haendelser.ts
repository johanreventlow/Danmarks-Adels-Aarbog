// Hændelses-load (fase2-design.md §5.2): tolerant treleddet hentning af den
// regenererbare hændelsesprojektion + narrativ/source-metadata til feed-kildefødder.
// Narrativ-teksten hentes bevidst ikke. Enhver fejl — også en endnu umigreret base —
// degraderer til et tomt map, så fase 1-feedet fortsat virker.
import { getAll } from '@daa/core';
import { buildHaendelserBy } from '@daa/feed';
import type {
  HaendelseNarrativRow,
  HaendelseRow,
  HaendelseSourceRow,
  HaendelserBy,
} from '@daa/feed';
import type { supabase } from '../lib/supabase';

const IN_CHUNK = 200;

function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function fetchInChunks<T, TId>(
  ids: TId[],
  run: (idsChunk: TId[]) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const out: T[] = [];
  for (const idsChunk of chunkArray(ids, IN_CHUNK)) {
    const { data, error } = await run(idsChunk);
    if (error) throw error;
    out.push(...(data ?? []));
  }
  return out;
}

export type HaendelseRowsResult = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
};

export async function fetchHaendelseRows(
  sb: NonNullable<typeof supabase>,
): Promise<HaendelseRowsResult> {
  const empty: HaendelseRowsResult = { rows: [], narrativer: [], sources: [] };
  try {
    const rows = await getAll<HaendelseRow>(() =>
      sb.from('haendelse')
        .select('id,subjekt_id,narrative_id,klausul,kategori,date_min,date_max,date_qualifier,date_raw,feed_status,fact_id,relation_id')
        .eq('subjekt_type', 'person')
        .order('id'),
    );
    if (!rows.length) return empty;

    const narrativeIds = [...new Set(rows.map((row) => row.narrative_id))];
    const narrativer = await fetchInChunks<HaendelseNarrativRow, string | number>(
      narrativeIds,
      (idsChunk) => sb.from('narrative').select('id,source_id,side')
        .in('id', idsChunk).order('id'),
    );
    const sourceIds = [...new Set(
      narrativer.map((n) => n.source_id).filter((id): id is string | number => id != null),
    )];
    const sources = sourceIds.length > 0
      ? await fetchInChunks<HaendelseSourceRow, string | number>(
          sourceIds,
          (idsChunk) => sb.from('source').select('id,udgave').in('id', idsChunk).order('id'),
        )
      : [];
    return { rows, narrativer, sources };
  } catch (e) {
    console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades:', e);
    return empty;
  }
}

export async function loadHaendelserBy(
  sb: NonNullable<typeof supabase>,
  canonicalIdById: Record<string, string>,
): Promise<HaendelserBy> {
  const result = await fetchHaendelseRows(sb);
  return buildHaendelserBy(
    result.rows, result.narrativer, result.sources, canonicalIdById,
  );
}
