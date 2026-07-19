// Tolerant treleddet story-load. En umigreret eller utilgængelig base degraderer til
// fase 2-feed uden at påvirke resten af mobilens dataload.
import { getAll } from '@daa/core';
import { buildStorieBy } from '@daa/feed';
import type { StoryKildeRow, StoryRow, StorySourceRow, StorieBy } from '@daa/feed';
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

export type StoryRowsResult = {
  rows: StoryRow[];
  kilder: StoryKildeRow[];
  sources: StorySourceRow[];
};

export async function fetchStoryRows(
  sb: NonNullable<typeof supabase>,
): Promise<StoryRowsResult> {
  const empty: StoryRowsResult = { rows: [], kilder: [], sources: [] };
  try {
    const rows = await getAll<StoryRow>(() =>
      sb.from('story')
        .select('id,subjekt_id,haendelse_id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat')
        .eq('subjekt_type', 'person')
        .eq('status', 'publiceret')
        .order('id'),
    );
    if (!rows.length) return empty;

    const storyIds = [...new Set(rows.map((row) => row.id))];
    const kilder = await fetchInChunks<StoryKildeRow, string | number>(storyIds, (idsChunk) =>
      sb.from('story_kilde').select('id,story_id,source_id,side')
        .in('story_id', idsChunk).order('id'),
    );
    const sourceIds = [...new Set(kilder.map((kilde) => kilde.source_id))];
    const sources = sourceIds.length > 0
      ? await fetchInChunks<StorySourceRow, string | number>(sourceIds, (idsChunk) =>
          sb.from('source').select('id,udgave').in('id', idsChunk).order('id'),
        )
      : [];
    return { rows, kilder, sources };
  } catch (error) {
    console.warn('[story] utilgængelig — historie-kort udelades:', error);
    return empty;
  }
}

export async function loadStorieBy(
  sb: NonNullable<typeof supabase>,
  canonicalIdById: Record<string, string>,
): Promise<StorieBy> {
  const result = await fetchStoryRows(sb);
  return buildStorieBy(result.rows, result.kilder, result.sources, canonicalIdById);
}
