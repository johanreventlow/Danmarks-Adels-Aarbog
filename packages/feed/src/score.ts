// Scoring: rene, forklarlige faktorer. score(card) = BASE[kind] × signaler.
import type { FeedCard, FeedInputs } from './types';

export const BASE: Record<FeedCard['kind'], number> = {
  historie: 1.2,
  portrait: 1.0,
  paadennedag: 1.0,
  dagensperson: 1.0,
  jubilaeum: 0.9,
  slaegt: 0.8,
  gods: 0.6,
  embede: 0.6,
  forbundet: 0.5,
  arkiv: 0.5,
  citat: 0.4,
  vaaben: 0.3,
  samle: 0,
};

export interface ScoreContext {
  bookmarkedIds: ReadonlySet<string>;
  seenWeights: Record<string, number>;
}

export function toScoreContext(inputs: FeedInputs): ScoreContext {
  return {
    bookmarkedIds: new Set(inputs.bookmarkedIds ?? []),
    seenWeights: inputs.seenWeights ?? {},
  };
}

export function score(card: FeedCard, ctx: ScoreContext): number {
  let s = BASE[card.kind];

  if (card.kind === 'paadennedag' && card.praecision === 'dag') s *= 4;
  if (card.kind === 'jubilaeum' && card.paaDagen) s *= 4;
  if (card.kind === 'arkiv' && card.interessant) s *= 2;
  if (card.kind === 'historie' && card.nyPubliceret) s *= 2;

  const personId = 'personId' in card ? card.personId : null;
  if (personId != null && ctx.bookmarkedIds.has(personId)) s *= 1.5;

  s *= ctx.seenWeights[card.id] ?? 1;
  return s;
}
