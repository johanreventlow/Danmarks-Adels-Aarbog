// Rå feed_pin-rækker normaliseres og sorteres i klientlaget; motoren bevarer inputordenen.
import type { FeedPinInput } from './types';

export interface FeedPinRow {
  kort_noegle: string;
  handling: string;
  oprettet_naar: string | null;
}

export function buildFeedPins(rows: FeedPinRow[]): FeedPinInput[] {
  return rows
    .filter((row): row is FeedPinRow & { handling: 'pin' | 'skjul' } =>
      row.handling === 'pin' || row.handling === 'skjul')
    .sort((a, b) => {
      if (a.oprettet_naar == null && b.oprettet_naar != null) return 1;
      if (a.oprettet_naar != null && b.oprettet_naar == null) return -1;
      if (a.oprettet_naar != null && b.oprettet_naar != null && a.oprettet_naar !== b.oprettet_naar) {
        return a.oprettet_naar.localeCompare(b.oprettet_naar);
      }
      return a.kort_noegle.localeCompare(b.kort_noegle);
    })
    .map((row) => ({ kortNoegle: row.kort_noegle, handling: row.handling }));
}
