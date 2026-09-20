import { stableHash } from './prng';
import type { FeedCard } from './types';

export type FeedMediaCandidate = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  largePath: string;
  mediumPath: string | null;
  primaer?: boolean;
  // Medie-metadata (Task 6), valgfrit: alt-tekst-fakt for feedets billeder. Optional så eksisterende
  // kaldere/tests der bygger kandidater uden fakta-berigelse ikke skal opdateres.
  altTekst?: string | null;
};

const PORTRAIT_KINDS = new Set<FeedCard['kind']>(['portrait', 'dagensperson']);
const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);
const normSlags = (value: string) => value.trim().toLowerCase();
const rotate = <T,>(items: T[], offset: number) =>
  items.length === 0 ? [] : [...items.slice(offset), ...items.slice(0, offset)];

export function selectFeedMedia<T extends FeedMediaCandidate>(
  cardId: string,
  kind: FeedCard['kind'],
  personId: string,
  media: readonly T[],
  limit = 4,
): T[] {
  if (limit <= 0) return [];

  const byId = new Map<string, T>();
  for (const item of media) {
    const existing = byId.get(item.id);
    if (!existing || (!existing.primaer && item.primaer)) byId.set(item.id, item);
  }

  const candidates = [...byId.values()]
    .sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }));
  if (candidates.length === 0) return [];

  const hash = stableHash(`${cardId}|${personId}`);
  if (!PORTRAIT_KINDS.has(kind)) {
    return rotate(candidates, hash % candidates.length).slice(0, limit);
  }

  const primary = candidates.find((item) => item.primaer)
    ?? candidates.find((item) => PORTRAIT_SLAGS.has(normSlags(item.slags)))
    ?? candidates[0];
  const remainder = candidates.filter((item) => item.id !== primary.id);
  return [primary, ...rotate(remainder, hash % remainder.length)].slice(0, limit);
}
