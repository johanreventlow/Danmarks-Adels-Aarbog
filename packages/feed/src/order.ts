// Seeded ordning (spec §3.5): vægtet trækning uden tilbagelægning + rytme-regler +
// positionslåse + terminal. Hele ordningen beregnes ÉN GANG pr. seed (eager, bevidst
// implementeringsvalg — spec §3.5) — "uendelig scroll" er dosering af denne færdige
// ordning (strøm-API, task 5), ikke løbende genberegning.
import {
  buildArkivKort,
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

export function buildFeedOrder(model: Model, aux: FeedAux, inputs: FeedInputs): FeedCard[] {
  const rng = mulberry32(inputs.seed);
  const livsdatoBy = inputs.livsdatoBy ?? {};
  const haendelserBy = inputs.haendelserBy ?? {};
  const todayYear = Number(inputs.todayISO.slice(0, 4));

  // dagens person udelades af portræt/citat-poolen (disjunkthed) og vises som sit eget kort.
  const dagensPersonId = pickDagensPerson(model, inputs.todayISO);
  const { portraits, citater, usedCitatHaendelseIds } = buildPortraitAndCitat(
    model, dagensPersonId, haendelserBy,
  );
  const dagensPersonCard = dagensPersonId ? buildDagensPersonCard(model, dagensPersonId) : null;

  const candidateCards: FeedCard[] = [
    ...portraits,
    ...citater,
    ...buildArkivKort(model, haendelserBy, usedCitatHaendelseIds),
    ...buildGods(aux),
    ...buildForbundet(model),
    ...buildEmbeder(model, aux),
    ...buildJubilaeer(model, todayYear, livsdatoBy, inputs.todayISO),
    ...buildVaaben(aux),
    ...buildSlaegt(model, inputs.meId, inputs.focusId),
    ...buildPaaDenneDag(model, livsdatoBy, inputs.todayISO, haendelserBy),
    ...(dagensPersonCard ? [dagensPersonCard] : []),
  ];

  const ctx = toScoreContext(inputs);
  // Score <= 0 (typisk seenWeights=0) udelukker kortet HELT — det trækkes aldrig.
  const pool: ScoredCard[] = candidateCards
    .map((card) => ({ card, score: score(card, ctx) }))
    .filter((c) => c.score > 0);

  const ordered: FeedCard[] = [];
  while (pool.length > 0) {
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
    let effectivePool = pool;
    // Undgå et fuldt pool-scan ved hvert træk. Portræt-delpoolen er kun relevant,
    // når R3 faktisk skal overveje forcing; RNG-forløb og valgsemantik er uændret.
    if (!recentHasPortrait) {
      const portraitCandidates = pool.filter((c) => c.card.kind === 'portrait');
      if (portraitCandidates.length > 0) effectivePool = portraitCandidates;
    }

    // Eskalerende relaksering: normal → R2 relakseret → R1+R2 relakseret (garanteret
    // at finde noget, da effectivePool er ikke-tom og fuld relaksering altid består).
    let idx = chooseNext(effectivePool, rng, prevKind, recentPersonIds);
    if (idx < 0) idx = chooseNext(effectivePool, rng, prevKind, recentPersonIds, { relaxR2: true });
    if (idx < 0) idx = chooseNext(effectivePool, rng, prevKind, recentPersonIds, { relaxR1: true, relaxR2: true });

    const chosen = effectivePool[idx];
    ordered.push(chosen.card);
    pool.splice(pool.indexOf(chosen), 1);
  }

  // Positionslåse (spec §3.5 step 3), seed-drevet: flyt kortet til en låst position.
  // Implementeret som BYT (swap), ikke fjern+genindsæt — en ren fjernelse fra midten ville
  // sammenføje kortets tidligere naboer, som ellers kun var adskilt AF det fjernede kort,
  // og kunne dermed skabe en helt ny (og usynlig for kalderen) R1/R3-krænkelse et andet sted
  // i listen. Et byt er en lokalt afgrænset perturbation ved præcis de to berørte positioner.
  const swapTo = (fromIdx: number, toIdx: number): void => {
    const clamped = Math.min(toIdx, ordered.length - 1);
    if (clamped === fromIdx) return;
    [ordered[fromIdx], ordered[clamped]] = [ordered[clamped], ordered[fromIdx]];
  };
  if (dagensPersonCard) {
    const idx = ordered.findIndex((c) => c.id === dagensPersonCard.id);
    if (idx >= 0) swapTo(idx, Math.floor(rng() * 3));
  }
  const slaegtIdx = ordered.findIndex((c) => c.kind === 'slaegt');
  if (slaegtIdx >= 0) swapTo(slaegtIdx, 3 + Math.floor(rng() * 7));

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
