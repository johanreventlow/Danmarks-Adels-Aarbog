// Redaktionel pin/skjul-kurering. Fejl giver et almindeligt ukurateret feed.
import { getAll } from '@daa/core';
import { buildFeedPins } from '@daa/feed';
import type { FeedPinInput, FeedPinRow } from '@daa/feed';
import { supabase } from '../supabase';

export async function fetchFeedPinRows(): Promise<FeedPinRow[]> {
  return getAll<FeedPinRow>(() =>
    supabase.from('feed_pin').select('kort_noegle,handling,oprettet_naar')
      .order('oprettet_naar').order('kort_noegle'),
  );
}

export async function fetchFeedPins(): Promise<FeedPinInput[]> {
  try {
    const rows = await fetchFeedPinRows();
    return buildFeedPins(rows);
  } catch (error) {
    console.warn('[feedPins] utilgængelig — feed vises ukurateret:', error);
    return [];
  }
}
