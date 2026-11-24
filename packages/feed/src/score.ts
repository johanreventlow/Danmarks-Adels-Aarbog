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
  // Vægten styrer IKKE hyppigheden: puljen af nævnte er langt større end portrætpuljen, og R1
  // (ikke to portrætter i træk) vælger første ikke-portræt, så snart loftet (NAEVNT_VINDUE i
  // order.ts) slipper. Målt 12/11: med web-feedets tændte typer har næsten hver blok på seks
  // præcis ét naevnt-kort for BASE 0.3, 0.1 og 0.03. Håndtaget er vinduet, ikke denne vægt.
  naevnt: 0.3,
  samle: 0,
};

// Midlertidig drosling (kaldersiden, ikke biblioteket selv): web og mobile sender dette sæt
// videre som FeedInputs.disabledKinds, indtil databasen har mere indhold i kategorierne.
// BASE ovenfor er urørt og afspejler den tilsigtede prioritering — for at genaktivere en
// korttype, fjern den blot herfra (ingen andre ændringer nødvendige).
export const TEMP_DISABLED_KINDS: ReadonlySet<FeedCard['kind']> = new Set([
  'historie', 'dagensperson', 'jubilaeum', 'slaegt',
  'gods', 'embede', 'forbundet', 'arkiv', 'citat', 'vaaben',
  // Projektejeren 24/11: »Nævnt i Aarbogen« handler om personer uden indhold og strider mod forsidens krav om indhold
  // (spec 2026-11-24-forside-minimumskrav-design.md). Tænd igen ved at fjerne den herfra.
  'naevnt',
]);

export interface ScoreContext {
  bookmarkedIds: ReadonlySet<string>;
  seenWeights: Record<string, number>;
  disabledKinds?: ReadonlySet<FeedCard['kind']>;
}

export function toScoreContext(inputs: FeedInputs): ScoreContext {
  return {
    bookmarkedIds: new Set(inputs.bookmarkedIds ?? []),
    seenWeights: inputs.seenWeights ?? {},
    disabledKinds: inputs.disabledKinds ?? new Set(),
  };
}

export function score(card: FeedCard, ctx: ScoreContext): number {
  if (ctx.disabledKinds?.has(card.kind)) return 0;
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
