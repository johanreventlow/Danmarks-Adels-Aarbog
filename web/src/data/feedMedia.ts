import { getAll } from '@daa/core';
import { selectFeedMedia } from '@daa/feed';
import type { FeedCard, FeedMediaCandidate } from '@daa/feed';
import { supabase } from '../supabase';
import { signPaths } from './media';

export type FeedMediaRequest = {
  cardId: string;
  kind: FeedCard['kind'];
  personId: string;
};

export type WebFeedMediaItem = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  mediumUrl: string;
  largeUrl: string;
  primaer?: boolean;
};

export type FeedMediaCandidatesByPerson = Record<string, FeedMediaCandidate[]>;
export type WebFeedMediaByCard = Record<string, WebFeedMediaItem[]>;

type RawRelation = {
  subjekt_id: number;
  objekt_id: number;
  kvalifikator: { primaer?: boolean } | null;
};

type RawMedia = {
  id: number;
  slags: string | null;
  titel: string | null;
  kunstner: string | null;
  datering: string | null;
  storage_path: string | null;
};

type RawVariant = {
  media_id: number;
  storage_path: string;
};

function emptyCandidates(canonicalPersonIds: string[]): FeedMediaCandidatesByPerson {
  return Object.fromEntries(canonicalPersonIds.map((id) => [id, []]));
}

export async function fetchFeedMediaCandidates(
  canonicalPersonIds: string[],
  canonicalIdById: Record<string, string>,
): Promise<FeedMediaCandidatesByPerson> {
  const out = emptyCandidates(canonicalPersonIds);
  if (!canonicalPersonIds.length) return out;

  try {
    const canonicalSet = new Set(canonicalPersonIds);
    const memberIds = Object.entries(canonicalIdById)
      .filter(([, canonical]) => canonicalSet.has(canonical))
      .map(([member]) => Number(member))
      .filter(Number.isFinite);
    for (const id of canonicalPersonIds.map(Number).filter(Number.isFinite)) memberIds.push(id);

    if (!memberIds.length) return out;

    const relations = await getAll<RawRelation>(() =>
      supabase.from('relation').select('subjekt_id,objekt_id,kvalifikator')
        .eq('subjekt_type', 'person').in('subjekt_id', memberIds)
        .eq('objekt_type', 'media').eq('rolle', 'afbildet'),
    );
    const mediaIds = [...new Set(relations.map((relation) => relation.objekt_id))];
    if (!mediaIds.length) return out;

    const [mediaRows, variants] = await Promise.all([
      getAll<RawMedia>(() =>
        supabase.from('media').select('id,slags,titel,kunstner,datering,storage_path').in('id', mediaIds),
      ),
      getAll<RawVariant>(() =>
        supabase.from('media_variant').select('media_id,storage_path').eq('tier', 'medium').in('media_id', mediaIds),
      ),
    ]);
    const mediaById = new Map(mediaRows
      .filter((row): row is RawMedia & { storage_path: string } => !!row.storage_path)
      .map((row) => [row.id, row]));
    const mediumPathByMediaId = new Map(variants.map((variant) => [variant.media_id, variant.storage_path]));
    const candidatesByCanonical = new Map<string, Map<string, FeedMediaCandidate>>();

    for (const relation of relations) {
      const canonicalId = canonicalIdById[String(relation.subjekt_id)] ?? String(relation.subjekt_id);
      if (!canonicalSet.has(canonicalId)) continue;
      const media = mediaById.get(relation.objekt_id);
      if (!media) continue;
      const candidates = candidatesByCanonical.get(canonicalId) ?? new Map<string, FeedMediaCandidate>();
      const candidate: FeedMediaCandidate = {
        id: String(media.id),
        slags: media.slags ?? '',
        titel: media.titel ?? '',
        kunstner: media.kunstner ?? '',
        datering: media.datering ?? '',
        largePath: media.storage_path,
        mediumPath: mediumPathByMediaId.get(media.id) ?? null,
        ...(relation.kvalifikator?.primaer === true ? { primaer: true } : {}),
      };
      const existing = candidates.get(candidate.id);
      if (!existing || (candidate.primaer === true && existing.primaer !== true)) candidates.set(candidate.id, candidate);
      candidatesByCanonical.set(canonicalId, candidates);
    }

    for (const canonicalId of canonicalPersonIds) {
      out[canonicalId] = [...(candidatesByCanonical.get(canonicalId)?.values() ?? [])];
    }
    return out;
  } catch (error) {
    console.warn('[feedMedia] hentning af feedmedier fejlede:', error);
    return emptyCandidates(canonicalPersonIds);
  }
}

export async function resolveFeedMediaForCards(
  requests: FeedMediaRequest[],
  candidatesByPerson: FeedMediaCandidatesByPerson,
): Promise<WebFeedMediaByCard> {
  if (!requests.length) return {};

  const selectedByCard = new Map<string, FeedMediaCandidate[]>();
  const paths = new Set<string>();
  for (const request of requests) {
    const selected = selectFeedMedia(
      request.cardId,
      request.kind,
      request.personId,
      candidatesByPerson[request.personId] ?? [],
    );
    selectedByCard.set(request.cardId, selected);
    for (const candidate of selected) {
      if (candidate.mediumPath) paths.add(candidate.mediumPath);
      paths.add(candidate.largePath);
    }
  }

  const signed = await signPaths([...paths]);
  const out: WebFeedMediaByCard = {};
  for (const request of requests) {
    const items: WebFeedMediaItem[] = [];
    for (const candidate of selectedByCard.get(request.cardId) ?? []) {
      const largeUrl = signed.get(candidate.largePath);
      if (!largeUrl) continue;
      items.push({
        id: candidate.id,
        slags: candidate.slags,
        titel: candidate.titel,
        kunstner: candidate.kunstner,
        datering: candidate.datering,
        mediumUrl: (candidate.mediumPath ? signed.get(candidate.mediumPath) : undefined) ?? largeUrl,
        largeUrl,
        ...(candidate.primaer === true ? { primaer: true } : {}),
      });
    }
    out[request.cardId] = items;
  }
  return out;
}
