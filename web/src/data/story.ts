// Web-spejl af mobilens tolerante story-loader. Netværksfejl og umigreret base
// betyder blot, at historie-kortene udelades.
import { buildStorieBy } from '@daa/feed';
import type { StorieBy } from '@daa/feed';
import { supabase } from '../supabase';
import { hentHistorieRaekker, type StoryRowsResult } from './forside/kilder';

export type { StoryRowsResult } from './forside/kilder';

export async function fetchStoryRows(): Promise<StoryRowsResult> {
  try {
    return await hentHistorieRaekker(supabase);
  } catch (error) {
    console.warn('[story] utilgængelig — historie-kort udelades:', error);
    return { rows: [], kilder: [], sources: [] };
  }
}

export async function loadStorieBy(
  canonicalIdById: Record<string, string>,
): Promise<StorieBy> {
  const result = await fetchStoryRows();
  return buildStorieBy(result.rows, result.kilder, result.sources, canonicalIdById);
}
