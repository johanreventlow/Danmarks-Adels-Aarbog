// Scoring (spec §3.4): rene, forklarlige faktorer. score(card) = BASE[kind] × timeliness
// × personal × seen. Ingen anden logik i fase 1 (pin/hide/story-boost kommer fase 3).
import type { FeedCard, FeedInputs } from './types';

export const BASE: Record<FeedCard['kind'], number> = {
  portrait: 1.0,
  paadennedag: 1.0,
  dagensperson: 1.0,
  jubilaeum: 0.9,
  slaegt: 0.8,
  gods: 0.6,
  embede: 0.6,
  forbundet: 0.5,
  citat: 0.4,
  vaaben: 0.3,
  samle: 0, // terminal — bygges separat, går aldrig gennem score()
};

export interface ScoreContext {
  bookmarkedIds: ReadonlySet<string>;
  seenWeights: Record<string, number>;
}

// Forbereder en billig kontekst af FeedInputs én gang pr. ordning, så score() ikke
// laver O(n) opslag i et array for hvert kort.
export function toScoreContext(inputs: FeedInputs): ScoreContext {
  return {
    bookmarkedIds: new Set(inputs.bookmarkedIds ?? []),
    seenWeights: inputs.seenWeights ?? {},
  };
}

export function score(card: FeedCard, ctx: ScoreContext): number {
  let s = BASE[card.kind];

  // timeliness ×4: dag-præcise 'på denne dag'-kort og jubilæer der rammer på dagen.
  if (card.kind === 'paadennedag' && card.praecision === 'dag') s *= 4;
  if (card.kind === 'jubilaeum' && card.paaDagen) s *= 4;

  // personal ×1.5: kortets person er bogmærket.
  const personId = 'personId' in card ? card.personId : null;
  if (personId != null && ctx.bookmarkedIds.has(personId)) s *= 1.5;

  // seen: nyligt sete kort trækkes ned (0 = fuldt udelukket — se buildFeedOrder).
  const seenWeight = ctx.seenWeights[card.id] ?? 1;
  s *= seenWeight;

  return s;
}
