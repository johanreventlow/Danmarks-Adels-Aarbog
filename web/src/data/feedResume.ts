import type { FeedCard } from '@daa/feed';

// `samle` beskriver den aktuelle rest-pool og er derfor ikke en del af det stabile,
// append-only præfiks ved en pool-udvidelse. Bios/livsdato/aux kan ændre både tallet og
// terminalens korrekte placering; behold alle egentlige kort, men lad den nye strøm levere
// sit eget terminalkort til sidst.
export function preserveShownForResume(shown: readonly FeedCard[]): FeedCard[] {
  return shown.filter((card) => card.kind !== 'samle');
}
