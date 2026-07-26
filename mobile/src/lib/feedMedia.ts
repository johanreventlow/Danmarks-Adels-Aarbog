import { useMemo } from 'react';
import { selectFeedMedia, type FeedCard, type FeedMediaCandidate } from '@daa/feed';
import type { RawMedia } from '../data/types';
import { useMediaAndThumbUris } from './media';

export type MobileFeedMediaItem = {
  id: string;
  slags: string;
  titel: string | null;
  kunstner: string | null;
  datering: string | null;
  mediumUri: string;
  largeUri: string;
};

type NormalizedFeedMedia = FeedMediaCandidate & { raw: RawMedia };

function normalizeFeedMedia(media: readonly RawMedia[]): NormalizedFeedMedia[] {
  return media.flatMap((m) => {
    if (!m.storage_path) return [];
    return [{
      id: String(m.id),
      slags: String(m.slags ?? ''),
      titel: String(m.titel ?? ''),
      kunstner: String(m.kunstner ?? ''),
      datering: String(m.datering ?? ''),
      largePath: String(m.storage_path),
      mediumPath: m.medium_storage_path ? String(m.medium_storage_path) : null,
      primaer: m.primaer === true,
      raw: m,
    }];
  });
}

export function selectMobileFeedMedia(
  card: Pick<FeedCard, 'id' | 'kind'>,
  personId: string,
  media: readonly RawMedia[],
): RawMedia[] {
  return selectFeedMedia(card.id, card.kind, personId, normalizeFeedMedia(media)).map((item) => item.raw);
}

export function buildMobileFeedMediaItems(
  selected: readonly RawMedia[],
  largeUris: Record<string, string>,
  mediumUris: Record<string, string>,
): MobileFeedMediaItem[] {
  return selected.flatMap((m) => {
    const id = String(m.id);
    const largeUri = largeUris[id];
    if (!largeUri) return [];
    return [{
      id,
      slags: String(m.slags ?? ''),
      titel: m.titel ?? null,
      kunstner: m.kunstner ?? null,
      datering: m.datering ?? null,
      mediumUri: mediumUris[id] ?? largeUri,
      largeUri,
    }];
  });
}

export function useMobileFeedMedia(
  card: Pick<FeedCard, 'id' | 'kind'>,
  personId: string,
  media: readonly RawMedia[],
): MobileFeedMediaItem[] {
  const selected = useMemo(
    () => selectMobileFeedMedia(card, personId, media),
    [card.id, card.kind, personId, media],
  );
  const { uris, thumbUris } = useMediaAndThumbUris(selected, (m) => m.medium_storage_path);
  return buildMobileFeedMediaItems(selected, uris, thumbUris);
}
