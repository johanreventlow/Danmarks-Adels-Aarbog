// Seeded ordning (spec §3.5): vægtet trækning uden tilbagelægning + rytme-regler +
// positionslåse + terminal. Hele ordningen beregnes ÉN GANG pr. seed (eager, bevidst
// implementeringsvalg — spec §3.5) — "uendelig scroll" er dosering af denne færdige
// ordning (strøm-API, task 5), ikke løbende genberegning.
import {
  buildEmbeder,
  buildForbundet,
  buildGods,
  buildJubilaeer,
  buildPortraitAndCitat,
  buildSlaegt,
  buildVaaben,
} from './pool';
import { mulberry32 } from './prng';
import { score, toScoreContext } from './score';
import { buildDagensPersonCard, buildPaaDenneDag, pickDagensPerson } from './temporal';
import { bookmarkPersonId } from './types';
import type { FeedAux, FeedCard, FeedInputs, Model } from './types';

export const MAX_ATTEMPTS = 20;
export const R2_WINDOW = 8;
export const R3_LOOKBACK = 5;

interface ScoredCard {
  card: FeedCard;
  score: number;
}

interface RankedCard extends ScoredCard {
  priority: number;
}

// Vægtet trækning UDEN tilbagelægning: kumulativ-sum-scan over den overleverede pool.
// -1 hvis poolen er tom eller al vægt er 0 (kalder skal filtrere score<=0 forinden —
// se buildFeedOrder — men funktionen er defensiv, så den kan unit-testes isoleret).
export function weightedDrawIndex(pool: { score: number }[], rng: () => number): number {
  const total = pool.reduce((s, c) => s + c.score, 0);
  if (pool.length === 0 || total <= 0) return -1;
  let r = rng() * total;
  for (let i = 0; i < pool.length; i++) {
    r -= pool[i].score;
    if (r <= 0) return i;
  }
  return pool.length - 1; // flydende-komma-fallback (afrundingsfejl)
}

export interface ChooseOpts {
  relaxR1?: boolean;
  relaxR2?: boolean;
}

// Op til MAX_ATTEMPTS vægtede træk fra `pool`, hvert forsøg tjekket mod R1 (ikke samme
// kind som prevKind) og R2 (personId ikke i recentPersonIds). Relakserede tjek springes
// over. -1 hvis intet forsøg består (kalder eskalerer relakseringen — se buildFeedOrder).
export function chooseNext(
  pool: ScoredCard[],
  rng: () => number,
  prevKind: FeedCard['kind'] | null,
  recentPersonIds: string[],
  opts: ChooseOpts = {},
): number {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const idx = weightedDrawIndex(pool, rng);
    if (idx < 0) return -1;
    const card = pool[idx].card;
    const passR1 = opts.relaxR1 === true || prevKind == null || card.kind !== prevKind;
    const pid = bookmarkPersonId(card);
    const passR2 = opts.relaxR2 === true || pid == null || !recentPersonIds.includes(pid);
    if (passR1 && passR2) return idx;
  }
  return -1;
}

// En eksponentialnøgle giver en vægtet permutation uden tilbagelægning: den mindste
// -log(1-U)/weight vinder. Hele rækkefølgen kan derfor seedes/sorteres én gang i O(n log n)
// i stedet for at genberegne en O(n)-vægtsum for hvert af n træk. Rytmereglerne vælger den
// første tilladte kandidat blandt de næste MAX_ATTEMPTS i den vægtede permutation.
function chooseRankedIndex(
  pool: RankedCard[],
  prevKind: FeedCard['kind'] | null,
  recentPersonIds: string[],
  opts: ChooseOpts = {},
): number {
  const attempts = Math.min(MAX_ATTEMPTS, pool.length);
  for (let idx = 0; idx < attempts; idx++) {
    const card = pool[idx].card;
    const passR1 = opts.relaxR1 === true || prevKind == null || card.kind !== prevKind;
    const pid = bookmarkPersonId(card);
    const passR2 = opts.relaxR2 === true || pid == null || !recentPersonIds.includes(pid);
    if (passR1 && passR2) return idx;
  }
  return -1;
}

export function buildFeedOrder(model: Model, aux: FeedAux, inputs: FeedInputs): FeedCard[] {
  const rng = mulberry32(inputs.seed);
  const livsdatoBy = inputs.livsdatoBy ?? {};
  const todayYear = Number(inputs.todayISO.slice(0, 4));

  // dagens person udelades af portræt/citat-poolen (disjunkthed) og vises som sit eget kort.
  const dagensPersonId = pickDagensPerson(model, inputs.todayISO);
  const { portraits, citater } = buildPortraitAndCitat(model, dagensPersonId);
  const dagensPersonCard = dagensPersonId ? buildDagensPersonCard(model, dagensPersonId) : null;

  const candidateCards: FeedCard[] = [
    ...portraits,
    ...citater,
    ...buildGods(aux),
    ...buildForbundet(model),
    ...buildEmbeder(model, aux),
    ...buildJubilaeer(model, todayYear, livsdatoBy, inputs.todayISO),
    ...buildVaaben(aux),
    ...buildSlaegt(model, inputs.meId, inputs.focusId),
    ...buildPaaDenneDag(model, livsdatoBy, inputs.todayISO),
    ...(dagensPersonCard ? [dagensPersonCard] : []),
  ];

  const ctx = toScoreContext(inputs);
  // Score <= 0 (typisk seenWeights=0) udelukker kortet HELT — det trækkes aldrig.
  const scoredPool: ScoredCard[] = candidateCards
    .map((card) => ({ card, score: score(card, ctx) }))
    .filter((c) => c.score > 0);

  // Positionslåse er en del af selve ordningen. Den tidligere efterfølgende swap kunne
  // flytte et portræt ud af et ellers gyldigt 6-korts-vindue og dermed bryde R3. Tag de
  // låste kort ud af poolen og udled deres positioner før sampling, så alle senere
  // rytmebeslutninger ser den faktiske rækkefølge.
  const takeLocked = (predicate: (card: FeedCard) => boolean): ScoredCard | null => {
    const idx = scoredPool.findIndex((c) => predicate(c.card));
    return idx < 0 ? null : scoredPool.splice(idx, 1)[0];
  };
  const lockedDagensPerson = dagensPersonCard
    ? takeLocked((card) => card.id === dagensPersonCard.id)
    : null;
  const lockedSlaegt = takeLocked((card) => card.kind === 'slaegt');
  const totalBeforeTerminal = scoredPool.length
    + (lockedDagensPerson ? 1 : 0)
    + (lockedSlaegt ? 1 : 0);
  const dagensPosition = lockedDagensPerson
    ? Math.min(Math.floor(rng() * 3), Math.max(0, totalBeforeTerminal - 1))
    : -1;
  let slaegtPosition = lockedSlaegt
    ? Math.min(3 + Math.floor(rng() * 7), Math.max(0, totalBeforeTerminal - 1))
    : -1;
  // Kun relevant for syntetiske ultrakorte feeds, hvor [0..2] og [3..9] ikke begge kan
  // opfyldes. Bevar dagens person først og brug den sidste ledige plads til slægtskortet.
  if (slaegtPosition === dagensPosition) {
    slaegtPosition = Math.max(0, totalBeforeTerminal - 1);
  }

  const pool: RankedCard[] = scoredPool
    .map((candidate) => ({
      ...candidate,
      priority: -Math.log(1 - rng()) / candidate.score,
    }))
    .sort((a, b) => a.priority - b.priority || a.card.id.localeCompare(b.card.id));

  const ordered: FeedCard[] = [];
  let dagensPending = lockedDagensPerson;
  let slaegtPending = lockedSlaegt;
  while (pool.length > 0 || dagensPending || slaegtPending) {
    if (dagensPending && ordered.length === dagensPosition) {
      ordered.push(dagensPending.card);
      dagensPending = null;
      continue;
    }
    if (slaegtPending && ordered.length === slaegtPosition) {
      ordered.push(slaegtPending.card);
      slaegtPending = null;
      continue;
    }
    if (pool.length === 0) {
      if (dagensPending) { ordered.push(dagensPending.card); dagensPending = null; }
      else if (slaegtPending) { ordered.push(slaegtPending.card); slaegtPending = null; }
      continue;
    }
    const prevKind = ordered.length > 0 ? ordered[ordered.length - 1].kind : null;
    const recentPersonIds = ordered
      .slice(-R2_WINDOW)
      .map((c) => bookmarkPersonId(c))
      .filter((id): id is string => id != null);

    // R3 (forcing, ikke afvisning): sidste R3_LOOKBACK kort uden portræt/dagensperson +
    // portræt-kandidater findes stadig → begræns DETTE træk til portræt-kandidater.
    const recentHasPortrait = ordered
      .slice(-R3_LOOKBACK)
      .some((c) => c.kind === 'portrait' || c.kind === 'dagensperson');
    const nextSlotIsLockedSlaegt = Boolean(
      slaegtPending && ordered.length + 1 === slaegtPosition,
    );
    const recentFourHavePortrait = ordered
      .slice(-(R3_LOOKBACK - 1))
      .some((c) => c.kind === 'portrait' || c.kind === 'dagensperson');
    let effectivePool = pool;
    // Se ét slot frem når det næste kort er det låste (ikke-portræt) slægtskort. Ellers
    // kan fem portrætløse kort + låsen danne et ugyldigt 6-vindue, før den normale R3-
    // forcing når at reagere på det efterfølgende slot.
    if (!recentHasPortrait || (nextSlotIsLockedSlaegt && !recentFourHavePortrait)) {
      const portraitCandidates = pool.filter((c) => c.card.kind === 'portrait');
      if (portraitCandidates.length > 0) effectivePool = portraitCandidates;
    }

    // Hvis dagens person endnu ikke er placeret (kun position 0-2), må samme persons
    // øvrige kort ikke snige sig ind umiddelbart før låsen og bryde R2.
    if (dagensPending && dagensPersonId) {
      const withoutDagensPerson = effectivePool.filter(
        (c) => bookmarkPersonId(c.card) !== dagensPersonId,
      );
      if (withoutDagensPerson.length > 0) effectivePool = withoutDagensPerson;
    }

    // Eskalerende relaksering: normal → R2 relakseret → R1+R2 relakseret (garanteret
    // at finde noget, da effectivePool er ikke-tom og fuld relaksering altid består).
    let idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds);
    if (idx < 0) idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds, { relaxR2: true });
    if (idx < 0) idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds, { relaxR1: true, relaxR2: true });

    const chosen = effectivePool[idx];
    ordered.push(chosen.card);
    pool.splice(effectivePool === pool ? idx : pool.indexOf(chosen), 1);
  }

  // Terminal 'samle'-kort (uændret semantik fra v3): kun når nogen personer slet ikke
  // fik et eget person-kort (portræt/citat/dagensperson). Lægges altid sidst.
  const shownPersonCount = portraits.length + citater.length + (dagensPersonCard ? 1 : 0);
  const remaining = model.persons.length - shownPersonCount;
  if (remaining > 0) {
    ordered.push({
      kind: 'samle', id: 'samle:personer', count: remaining,
      tail: 'personer i registeret', kicker: 'Registeret',
    });
  }

  return ordered;
}
