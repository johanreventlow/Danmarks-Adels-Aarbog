// feed_pin er valgfri kurering: fejl må aldrig blokere det almindelige feed.
import { getAll } from '@daa/core';
import { buildFeedPins } from '@daa/feed';
import type { FeedPinInput, FeedPinRow } from '@daa/feed';
import type { supabase } from '../lib/supabase';

export async function fetchFeedPins(
  sb: NonNullable<typeof supabase>,
): Promise<FeedPinInput[]> {
  try {
    const rows = await getAll<FeedPinRow>(() =>
      sb.from('feed_pin').select('kort_noegle,handling,oprettet_naar')
        .order('oprettet_naar').order('kort_noegle'),
    );
    return buildFeedPins(rows);
  } catch (error) {
    console.warn('[feedPins] utilgængelig — feed vises ukurateret:', error);
    return [];
  }
}
