// REFERENCE — ordret kopi af buildFeedOrder (packages/feed/src/order.ts) FØR review 36 P11's omskrivning af
// trækningsløkken (filter+splice+indexOf pr. træk, O(n²)). Bruges af order.ekvivalens.test.ts (ny og gammel
// rækkefølge skal være identisk) og af scripts/maal-order.ts (før/efter-måling). Ret ALDRIG i denne fil for at få en
// test grøn: en ændret rækkefølge er en ændret ordning, ikke en optimering.
//
// Ét tillæg i forhold til originalen: `grene` tæller, hvilke regel-grene løkken har ramt, så ekvivalenstesten kan
// bevise, at generatoren faktisk dækker dem. Tællingen påvirker hverken rng-forbrug eller output.
import { kunSikkertDoede } from '../levende';
import {
  buildArkivKort,
  buildEmbeder,
  buildForbundet,
  buildGods,
  buildJubilaeer,
  buildNaevnt,
  buildPortraitAndCitat,
  buildSlaegt,
  buildVaaben,
} from '../pool';
import { mulberry32 } from '../prng';
import { score, toScoreContext } from '../score';
import { buildStorieKort } from '../story';
import { buildDagensPersonCard, buildPaaDenneDag, pickDagensPerson } from '../temporal';
import { bookmarkPersonId } from '../types';
import type { FeedAux, FeedCard, FeedInputs, Model } from '../types';
import { MAX_ATTEMPTS, NAEVNT_VINDUE, R2_WINDOW, R3_LOOKBACK } from '../order';

export const grene: Record<string, number> = {};
const ramt = (gren: string) => { grene[gren] = (grene[gren] ?? 0) + 1; };

interface ScoredCard {
  card: FeedCard;
  score: number;
}

interface RankedCard extends ScoredCard {
  priority: number;
}

interface ChooseOpts {
  relaxR1?: boolean;
  relaxR2?: boolean;
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

export function orderReference(model: Model, aux: FeedAux, inputs: FeedInputs): FeedCard[] {
  const rng = mulberry32(inputs.seed);
  const todayYear = Number(inputs.todayISO.slice(0, 4));
  // GDPR-nødbremse (levende.ts): kun personer med positiv dødsevidens (dødsår, eller fødsel
  // for >120 år siden) må optræde i feedets person-identificerende kort. Ét choke-point her,
  // FØR alle kort-builders, i stedet for spredt pr. builder — se levende.ts for begrundelsen.
  const safeModel = kunSikkertDoede(model, todayYear);
  const livsdatoBy = inputs.livsdatoBy ?? {};
  const haendelserBy = inputs.haendelserBy ?? {};
  const storieBy = inputs.storieBy ?? {};
  const pins = inputs.pins ?? [];
  // Hændelsens feed_status er en indholds-dom pr. hændelse; feed_pin er derimod
  // kurering pr. konkret kort-id. De to skjul-stier er bevidst ortogonale.
  const hideSet = new Set(
    pins.filter((pin) => pin.handling === 'skjul').map((pin) => pin.kortNoegle),
  );
  const pinKeys = pins.filter((pin) => pin.handling === 'pin').map((pin) => pin.kortNoegle);
  const disabledKinds = inputs.disabledKinds ?? new Set();

  // dagens person udelades af portræt/citat-poolen (disjunkthed) og vises som sit eget kort —
  // men kun når kort-typen er slået til. Ellers ville personen forsvinde helt fra feedet
  // (udelukket fra portræt-poolen uden at få et dagensperson-kort i stedet).
  const dagensPersonId = disabledKinds.has('dagensperson')
    ? null
    : pickDagensPerson(safeModel, inputs.todayISO);
  const { cards: storieKort, usedHaendelseIds } = buildStorieKort(
    safeModel, storieBy, haendelserBy, inputs.todayISO,
  );
  const { portraits, citater, usedCitatHaendelseIds } = buildPortraitAndCitat(
    safeModel, dagensPersonId, haendelserBy, usedHaendelseIds, !disabledKinds.has('citat'),
  );
  const arkivEksklusion = new Set([...usedHaendelseIds, ...usedCitatHaendelseIds]);
  const dagensPersonCard = dagensPersonId ? buildDagensPersonCard(safeModel, dagensPersonId) : null;

  const candidateCards: FeedCard[] = [
    ...portraits,
    ...citater,
    ...storieKort,
    ...buildArkivKort(safeModel, haendelserBy, arkivEksklusion),
    ...buildGods(aux),
    ...buildForbundet(safeModel),
    ...buildEmbeder(safeModel, aux),
    ...buildJubilaeer(safeModel, todayYear, livsdatoBy, inputs.todayISO),
    ...buildVaaben(aux),
    ...buildSlaegt(safeModel, inputs.meId, inputs.focusId),
    ...buildPaaDenneDag(safeModel, livsdatoBy, inputs.todayISO, haendelserBy),
    ...(dagensPersonCard ? [dagensPersonCard] : []),
    ...(inputs.naevntGrundlag && !disabledKinds.has('naevnt')
      ? buildNaevnt(safeModel, inputs.naevntGrundlag, aux, haendelserBy, storieBy)
      : []),
  ];

  const visibleCards = hideSet.size > 0
    ? candidateCards.filter((card) => !hideSet.has(card.id))
    : candidateCards;
  // Pin-blokken udtrækkes før score>0-filteret: redaktørens eksplicitte pin vinder
  // over seenWeights=0. Inputordenen bevares, og der forbruges ingen ekstra rng-kald.
  const cardById = new Map(visibleCards.map((card) => [card.id, card]));
  const pinnedBlock: FeedCard[] = [];
  const pinnedIds = new Set<string>();
  for (const key of pinKeys) {
    const card = cardById.get(key);
    if (card && !pinnedIds.has(card.id)) {
      pinnedBlock.push(card);
      pinnedIds.add(card.id);
    }
  }

  const ctx = toScoreContext(inputs);
  // Score <= 0 (typisk seenWeights=0) udelukker kortet HELT — det trækkes aldrig.
  const scoredPool: ScoredCard[] = visibleCards
    .filter((card) => !pinnedIds.has(card.id))
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
  const P = pinnedBlock.length;
  const totalBeforeTerminal = P + scoredPool.length
    + (lockedDagensPerson ? 1 : 0)
    + (lockedSlaegt ? 1 : 0);
  const dagensPosition = lockedDagensPerson
    ? Math.min(P + Math.floor(rng() * 3), Math.max(P, totalBeforeTerminal - 1))
    : -1;
  let slaegtPosition = lockedSlaegt
    ? Math.min(P + 3 + Math.floor(rng() * 7), Math.max(P, totalBeforeTerminal - 1))
    : -1;
  // Kun relevant for syntetiske ultrakorte feeds, hvor [0..2] og [3..9] ikke begge kan
  // opfyldes. Bevar dagens person først og brug den sidste ledige plads til slægtskortet.
  if (slaegtPosition === dagensPosition) {
    slaegtPosition = Math.max(P, totalBeforeTerminal - 1);
  }

  const pool: RankedCard[] = scoredPool
    .map((candidate) => ({
      ...candidate,
      priority: -Math.log(1 - rng()) / candidate.score,
    }))
    .sort((a, b) => a.priority - b.priority || a.card.id.localeCompare(b.card.id));

  const ordered: FeedCard[] = [...pinnedBlock];
  let dagensPending = lockedDagensPerson;
  let slaegtPending = lockedSlaegt;
  while (pool.length > 0 || dagensPending || slaegtPending) {
    if (dagensPending && ordered.length === dagensPosition) {
      ramt('dagens-laas');
      ordered.push(dagensPending.card);
      dagensPending = null;
      continue;
    }
    if (slaegtPending && ordered.length === slaegtPosition) {
      ramt('slaegt-laas');
      ordered.push(slaegtPending.card);
      slaegtPending = null;
      continue;
    }
    if (pool.length === 0) {
      if (dagensPending) { ordered.push(dagensPending.card); dagensPending = null; }
      else if (slaegtPending) { ordered.push(slaegtPending.card); slaegtPending = null; }
      continue;
    }
    // Loft over 'naevnt' (højst ét pr. NAEVNT_VINDUE kort): er der et blandt de seneste
    // NAEVNT_VINDUE-1, må dette træk ikke være et. Er kun 'naevnt' tilbage i puljen, droppes
    // resten — de kan aldrig placeres lovligt — men de låste kort placeres stadig af løkken.
    // Redaktørens fastgjorte kort ligger før løkken og kan bryde loftet: pin vinder.
    const recentHasNaevnt = ordered
      .slice(-(NAEVNT_VINDUE - 1))
      .some((c) => c.kind === 'naevnt');
    let rulePool = pool;
    if (recentHasNaevnt) {
      rulePool = pool.filter((c) => c.card.kind !== 'naevnt');
      ramt('naevnt-loft');
      if (rulePool.length === 0) {
        ramt('naevnt-rest-droppet');
        pool.length = 0;
        continue;
      }
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
    let effectivePool = rulePool;
    // Se ét slot frem når det næste kort er det låste (ikke-portræt) slægtskort. Ellers
    // kan fem portrætløse kort + låsen danne et ugyldigt 6-vindue, før den normale R3-
    // forcing når at reagere på det efterfølgende slot.
    if (!recentHasPortrait || (nextSlotIsLockedSlaegt && !recentFourHavePortrait)) {
      const portraitCandidates = rulePool.filter((c) => c.card.kind === 'portrait');
      if (portraitCandidates.length > 0) effectivePool = portraitCandidates;
      ramt(portraitCandidates.length > 0 ? 'r3-tvang' : 'r3-uden-portraet');
      if (recentHasPortrait) ramt('r3-slaegt-lookahead');
    }

    // Hvis dagens person endnu ikke er placeret (kun position 0-2), må samme persons
    // øvrige kort ikke snige sig ind umiddelbart før låsen og bryde R2.
    if (dagensPending && dagensPersonId) {
      const withoutDagensPerson = effectivePool.filter(
        (c) => bookmarkPersonId(c.card) !== dagensPersonId,
      );
      const foer = effectivePool.length;
      if (withoutDagensPerson.length > 0) effectivePool = withoutDagensPerson;
      ramt(withoutDagensPerson.length === 0 ? 'dagens-filter-tomt'
        : withoutDagensPerson.length < foer ? 'dagens-filter-virkede' : 'dagens-filter-uden-virkning');
    }

    // Eskalerende relaksering: normal → R2 relakseret → R1+R2 relakseret (garanteret
    // at finde noget, da effectivePool er ikke-tom og fuld relaksering altid består).
    let idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds);
    if (idx < 0) { ramt('relax-r2'); idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds, { relaxR2: true }); }
    if (idx < 0) { ramt('relax-r1r2'); idx = chooseRankedIndex(effectivePool, prevKind, recentPersonIds, { relaxR1: true, relaxR2: true }); }
    if (idx >= MAX_ATTEMPTS - 1) ramt('valg-ved-loftet');

    const chosen = effectivePool[idx];
    ordered.push(chosen.card);
    pool.splice(effectivePool === pool ? idx : pool.indexOf(chosen), 1);
  }

  // Terminal 'samle'-kort (uændret semantik fra v3): kun når nogen personer slet ikke
  // fik et eget person-kort (portræt/citat/dagensperson). Lægges altid sidst.
  // Placerede 'naevnt'-kort er også et eget person-kort; droppede (loftet) tælles ikke.
  const placedNaevnt = ordered.filter((c) => c.kind === 'naevnt').length;
  const shownPersonCount = portraits.length + citater.length + (dagensPersonCard ? 1 : 0)
    + placedNaevnt;
  const remaining = model.persons.length - shownPersonCount;
  if (remaining > 0) {
    ordered.push({
      kind: 'samle', id: 'samle:personer', count: remaining,
      tail: 'personer i registeret', kicker: 'Registeret',
    });
  }

  return ordered;
}
