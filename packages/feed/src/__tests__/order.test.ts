import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { chooseNext, weightedDrawIndex, buildFeedOrder } from '../order';
import { stableHash } from '../prng';
import { createFeedStream } from '../stream';
import { pickDagensPerson } from '../temporal';
import type {
  FeedAux, FeedCard, FeedInputs, HaendelseItem, HaendelserBy, Model, StorieBy, StoryItem,
} from '../types';

// died defaulter til sikkert-død (levende.ts's GDPR-gate udelukker ellers alle test-personer
// fra buildFeedOrder). Tests af selve gaten sætter died/born eksplicit til null/nylig.
function person(id: string, over: Partial<{
  name: string; born: number | null; died: number | null; years: string;
  title: string; bio: string; privat: boolean;
}> = {}) {
  return {
    id, name: 'Person ' + id, born: null, died: 1700, years: '', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(persons: ReturnType<typeof person>[]): Model {
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}

const EMPTY_AUX: FeedAux = { godsListe: [], vaabenListe: [], officesBy: {} };
const LONG_BIO = 'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, '
  + 'virke og eftermæle, skrevet med tilstrækkeligt mange detaljer og sammenhæng.';

function baseInputs(over: Partial<FeedInputs> = {}): FeedInputs {
  return { seed: 1, todayISO: '2026-07-18', meId: null, focusId: null, ...over };
}

function haendelse(id: string, over: Partial<HaendelseItem> = {}): HaendelseItem {
  return {
    id, klausul: 'En tilstrækkelig lang klausul om personens historiske liv og virke.',
    kategori: null, dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    interessant: false, rygrad: false, kilde: null, ...over,
  };
}

function storie(id: string, over: Partial<StoryItem> = {}): StoryItem {
  return {
    id, titel: null, tekst: 'En kort redaktionel minihistorie om personens liv og virke.',
    dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    haendelseId: null, publiceretDato: null, kilde: null, ...over,
  };
}

// --- weightedDrawIndex -------------------------------------------------------
describe('weightedDrawIndex', () => {
  it('vælger indeks proportionalt med vægt (deterministisk rng-sekvens)', () => {
    const pool = [{ score: 1 }, { score: 1 }, { score: 8 }];
    // total=10; rng()=0.05 → r=0.5 → i0 (0.5-1<=0) → index 0
    expect(weightedDrawIndex(pool, () => 0.05)).toBe(0);
    // rng()=0.95 → r=9.5 → efter i0(8.5),i1(7.5),i2(-0.5<=0) → index 2
    expect(weightedDrawIndex(pool, () => 0.95)).toBe(2);
  });
  it('tom pool → -1', () => {
    expect(weightedDrawIndex([], () => 0.5)).toBe(-1);
  });
  it('total score 0 → -1', () => {
    expect(weightedDrawIndex([{ score: 0 }, { score: 0 }], () => 0.5)).toBe(-1);
  });
});

// --- chooseNext (R1/R2 + relaksering) ----------------------------------------
describe('chooseNext', () => {
  const cardA: FeedCard = { kind: 'portrait', id: 'portrait:a', personId: 'a', name: 'A', years: '', initials: 'A', title: null, bio: 'x', kicker: '' };
  const cardB: FeedCard = { kind: 'gods', id: 'gods:1', estateId: '1', navn: 'B', meta: '', ownerDots: 0, kicker: '' };

  it('R1: springer kandidat med samme kind som forrige over, vælger næste', () => {
    // rng-sekvens: første kald vælger idx0 (portrait, samme som prevKind) → afvises;
    // andet kald vælger idx1 (gods) → accepteres.
    const pool = [{ card: cardA, score: 1 }, { card: cardB, score: 1 }];
    const seq = [0.1, 0.9];
    let i = 0;
    const rng = () => seq[i++];
    const idx = chooseNext(pool, rng, 'portrait', []);
    expect(pool[idx].card.kind).toBe('gods');
  });

  it('R2: springer kandidat med personId i recentPersonIds over', () => {
    const cardA2: FeedCard = { ...cardA, id: 'embede:a', kind: 'embede', label: 'X', name: 'A', period: '', init: 'A' } as FeedCard;
    const pool = [{ card: cardA2, score: 1 }, { card: cardB, score: 1 }];
    const seq = [0.1, 0.9];
    let i = 0;
    const rng = () => seq[i++];
    const idx = chooseNext(pool, rng, null, ['a']);
    expect(pool[idx].card.kind).toBe('gods');
  });

  it('relaxR1/relaxR2: accepterer selv en normalt afvist kandidat', () => {
    const pool = [{ card: cardA, score: 1 }];
    const idx = chooseNext(pool, () => 0.5, 'portrait', ['a'], { relaxR1: true, relaxR2: true });
    expect(idx).toBe(0);
  });

  it('ingen kandidat består inden for MAX_ATTEMPTS uden relaksering → -1', () => {
    // Kun én kandidat, der altid overtræder R1 (samme kind som prevKind); uden relaksering
    // kan intet forsøg lykkes.
    const pool = [{ card: cardA, score: 1 }];
    const idx = chooseNext(pool, () => 0.1, 'portrait', []);
    expect(idx).toBe(-1);
  });
});

// --- buildFeedOrder — determinisme & seed ------------------------------------
describe('buildFeedOrder — determinisme', () => {
  it('samme input → identisk ordning', () => {
    const persons = Array.from({ length: 30 }, (_, i) => person('p' + i, { bio: LONG_BIO, born: 1900 + i }));
    const m = mkModel(persons);
    const inputs = baseInputs();
    expect(buildFeedOrder(m, EMPTY_AUX, inputs)).toEqual(buildFeedOrder(m, EMPTY_AUX, inputs));
  });

  it('forskellige seeds → forskellig rækkefølge, samme kort-mængde', () => {
    const persons = Array.from({ length: 30 }, (_, i) => person('p' + i, { bio: LONG_BIO, born: 1900 + i }));
    const m = mkModel(persons);
    const a = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 1 }));
    const b = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 2 }));
    expect(a.map((c) => c.id).sort()).toEqual(b.map((c) => c.id).sort());
    expect(a.map((c) => c.id)).not.toEqual(b.map((c) => c.id));
  });

  it('tom model → []', () => {
    expect(buildFeedOrder(mkModel([]), EMPTY_AUX, baseInputs())).toEqual([]);
  });

  it('tomme FeedAux-felter → ingen crash, ingen kort af den type', () => {
    const persons = [person('a', { bio: LONG_BIO })];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    expect(cards.some((c) => c.kind === 'gods' || c.kind === 'vaaben' || c.kind === 'embede')).toBe(false);
  });

  it('udeladt og eksplicit tomt haendelserBy er dybt identisk med fase 1', () => {
    const m = mkModel(Array.from({ length: 20 }, (_, i) => person('p' + i, { bio: LONG_BIO })));
    expect(buildFeedOrder(m, EMPTY_AUX, baseInputs())).toEqual(
      buildFeedOrder(m, EMPTY_AUX, baseInputs({ haendelserBy: {} })),
    );
  });

  it('hændelses-input er deterministisk; seeds ændrer rækkefølge men ikke kortmængde', () => {
    const persons = Array.from({ length: 20 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const hs: HaendelserBy = Object.fromEntries(
      persons.map((p, i) => [p.id, [haendelse('h' + i, { dateRaw: String(1700 + i) })]]),
    );
    const a = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 1, haendelserBy: hs }));
    const a2 = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 1, haendelserBy: hs }));
    const b = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 2, haendelserBy: hs }));
    expect(a).toEqual(a2);
    expect(a.map((c) => c.id).sort()).toEqual(b.map((c) => c.id).sort());
    expect(a.map((c) => c.id)).not.toEqual(b.map((c) => c.id));
  });

  it('valgt citat-klausul optræder aldrig også som arkiv-kort', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const dagens = pickDagensPerson(m, '2026-07-18');
    const citatPerson = persons.find((p) => stableHash(p.id) % 4 === 0 && p.id !== dagens);
    expect(citatPerson).toBeDefined();
    const hs: HaendelserBy = {
      [citatPerson!.id]: [haendelse('valgt-citat')],
    };
    for (const seed of [1, 2, 3, 4, 5]) {
      const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed, haendelserBy: hs }));
      expect(cards.some((c) => c.id === 'citat:' + citatPerson!.id)).toBe(true);
      expect(cards.some((c) => c.id === 'arkiv:valgt-citat')).toBe(false);
    }
  });
});

// --- rytme-regler på rig fixture ----------------------------------------------
function rigModel(n: number): Model {
  const persons = Array.from({ length: n }, (_, i) => person('p' + i, { bio: LONG_BIO }));
  return mkModel(persons);
}
function rigRelatedModel(n: number): Model {
  const persons = Array.from({ length: n }, (_, i) => person('p' + i, { bio: LONG_BIO }));
  return buildModel({
    persons,
    unions: [{ id: 'u1', p1: 'p2', p2: null, p2_name: null, year: null }],
    parentChild: [
      { child: 'p0', parent: 'p2', union: 'u1', konfidens: 'sikker' },
      { child: 'p1', parent: 'p2', union: 'u1', konfidens: 'sikker' },
    ],
  }) as unknown as Model;
}
function rigAux(n: number): FeedAux {
  return {
    godsListe: Array.from({ length: n }, (_, i) => ({ id: 'e' + i, navn: 'Gods ' + i, slags: 'Gods', ownerCount: 1 })),
    vaabenListe: Array.from({ length: n }, (_, i) => ({ id: 'v' + i, blasonering: 'Blasonering ' + i, note: '' })),
    officesBy: {},
  };
}

describe('buildFeedOrder — rytme R1/R3 på rig, kind-varieret fixture', () => {
  // Med endeligt mangfoldige, men UENSARTET vægtede kandidat-puljer (BASE-vægtene i
  // score.ts adskiller sig pr. kind) VIL den tungest vægtede overlevende kind uundgåeligt
  // ende alene i halen, når alle andre kinds er opbrugt — R1/R3 KAN ikke holde der (kun
  // ét kind tilbage = intet alternativ at vælge). Det er lempelsen der virker efter hensigten
  // (spec §3.5), ikke en fejl. Testen beviser derfor en STRUKTUREL invariant i stedet for
  // "nul afvigelser": enhver afvigelse er en del af den afsluttende ensartede hale.
  it('R1: enhver afvigelse indgår i den afsluttende samme-kind-hale (ingen spredte glitches)', () => {
    const cards = buildFeedOrder(rigModel(40), rigAux(12), baseInputs({ seed: 3 }));
    const lastKind = cards[cards.length - 1].kind;
    for (let i = 1; i < cards.length; i++) {
      if (cards[i].kind === cards[i - 1].kind) {
        expect(cards[i].kind).toBe(lastKind);
      }
    }
  });

  it('R3: et portrætløst 6-vindue kan kun opstå EFTER portræt-poolens sidste kort', () => {
    const cards = buildFeedOrder(rigModel(40), rigAux(12), baseInputs({ seed: 3 }));
    let lastPortraitPos = -1;
    cards.forEach((c, i) => { if (c.kind === 'portrait' || c.kind === 'dagensperson') lastPortraitPos = i; });
    for (let i = 0; i + 6 <= cards.length; i++) {
      const window = cards.slice(i, i + 6);
      if (!window.some((c) => c.kind === 'portrait' || c.kind === 'dagensperson')) {
        expect(i).toBeGreaterThan(lastPortraitPos);
      }
    }
  });

  it('R3 overlever positionslåsen på tværs af mange seeds', () => {
    const model = rigModel(80);
    const aux = rigAux(40);
    for (let seed = 0; seed < 250; seed++) {
      const cards = buildFeedOrder(model, aux, baseInputs({ seed }));
      let lastPortraitPos = -1;
      cards.forEach((c, i) => {
        if (c.kind === 'portrait' || c.kind === 'dagensperson') lastPortraitPos = i;
      });
      for (let i = 0; i + 6 <= cards.length && i <= lastPortraitPos; i++) {
        expect(
          cards.slice(i, i + 6).some((c) => c.kind === 'portrait' || c.kind === 'dagensperson'),
          `seed=${seed}, window=${i}`,
        ).toBe(true);
      }
    }
  });

  it('R3 overlever også et låst slægtskort på tværs af mange seeds', () => {
    const model = rigRelatedModel(80);
    const aux = rigAux(40);
    for (let seed = 0; seed < 250; seed++) {
      const cards = buildFeedOrder(model, aux, baseInputs({ seed, meId: 'p0', focusId: 'p1' }));
      expect(cards.findIndex((c) => c.kind === 'slaegt'), `seed=${seed}`).toBeGreaterThanOrEqual(3);
      expect(cards.findIndex((c) => c.kind === 'slaegt'), `seed=${seed}`).toBeLessThanOrEqual(9);
      let lastPortraitPos = -1;
      cards.forEach((c, i) => {
        if (c.kind === 'portrait' || c.kind === 'dagensperson') lastPortraitPos = i;
      });
      for (let i = 0; i + 6 <= cards.length && i <= lastPortraitPos; i++) {
        expect(
          cards.slice(i, i + 6).some((c) => c.kind === 'portrait' || c.kind === 'dagensperson'),
          `seed=${seed}, window=${i}`,
        ).toBe(true);
      }
    }
  });
});

describe('buildFeedOrder — lempelse på degenereret fixture', () => {
  it('kun gods-kandidater (ingen anden kind) → komplet ordning uden crash/uendelig løkke', () => {
    const m = mkModel([]);
    const aux: FeedAux = {
      godsListe: Array.from({ length: 25 }, (_, i) => ({ id: 'e' + i, navn: 'G' + i, slags: '', ownerCount: 0 })),
      vaabenListe: [], officesBy: {},
    };
    const cards = buildFeedOrder(m, aux, baseInputs());
    expect(cards).toHaveLength(25);
    expect(cards.every((c) => c.kind === 'gods')).toBe(true);
  });
});

// --- positionslåse + terminal -------------------------------------------------
describe('buildFeedOrder — positionslåse', () => {
  it('dagensperson-kortet står i position 0-2', () => {
    const persons = Array.from({ length: 15 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 5 }));
    const idx = cards.findIndex((c) => c.kind === 'dagensperson');
    expect(idx).toBeGreaterThanOrEqual(0);
    expect(idx).toBeLessThanOrEqual(2);
  });

  it('slaegt-kortet står i position 3-9 når meId+focusId er sat', () => {
    const persons = Array.from({ length: 15 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 5, meId: 'p0', focusId: 'p1' }));
    const idx = cards.findIndex((c) => c.kind === 'slaegt');
    // computeRelationship kan finde forbindelsen mellem urelaterede p0/p1 som "ingen"
    // (found:false) i denne minimale fixture — så kortet kan mangle. Assert kun position
    // NÅR kortet findes.
    if (idx >= 0) {
      expect(idx).toBeGreaterThanOrEqual(3);
      expect(idx).toBeLessThanOrEqual(9);
    }
  });

  it('samle-kort ligger sidst når nogen personer ikke fik eget kort', () => {
    const persons = [
      ...Array.from({ length: 5 }, (_, i) => person('b' + i, { bio: LONG_BIO })),
      ...Array.from({ length: 10 }, (_, i) => person('n' + i)), // uden bio
    ];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    expect(cards[cards.length - 1].kind).toBe('samle');
  });
});

// --- vægt-effekt ---------------------------------------------------------------
describe('buildFeedOrder — vægt-effekt', () => {
  it('seenWeights=0 udelukker kortet fuldstændigt', () => {
    const persons = [person('a', { bio: LONG_BIO })];
    const excludedId = 'portrait:a';
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs({ seenWeights: { [excludedId]: 0 } }));
    expect(cards.some((c) => c.id === excludedId)).toBe(false);
  });

  it('bogmærket person rykker i gennemsnit tidligere frem over faste seeds', () => {
    const persons = Array.from({ length: 20 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const seeds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    let bookmarkedTotal = 0;
    let plainTotal = 0;
    for (const seed of seeds) {
      const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed, bookmarkedIds: ['p0'] }));
      const bookmarkedIdx = cards.findIndex((c) => 'personId' in c && c.personId === 'p0');
      const plainIdx = cards.findIndex((c) => 'personId' in c && c.personId === 'p1');
      bookmarkedTotal += bookmarkedIdx;
      plainTotal += plainIdx;
    }
    expect(bookmarkedTotal / seeds.length).toBeLessThan(plainTotal / seeds.length);
  });

  it('interessant arkiv-kort rykker i gennemsnit tidligere frem over faste seeds', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const dagens = pickDagensPerson(m, '2026-07-18');
    const target = persons.find((p) => stableHash(p.id) % 4 !== 0 && p.id !== dagens)!;
    const plain: HaendelserBy = Object.fromEntries(
      persons.map((p, i) => [p.id, [haendelse('h' + i)]]),
    );
    const boosted: HaendelserBy = Object.fromEntries(
      Object.entries(plain).map(([pid, items]) => [
        pid, items.map((item) => item.id === plain[target.id][0].id
          ? { ...item, interessant: true }
          : item),
      ]),
    );
    const targetId = 'arkiv:' + plain[target.id][0].id;
    const seeds = Array.from({ length: 30 }, (_, i) => i + 1);
    const meanIndex = (hs: HaendelserBy): number => seeds.reduce((sum, seed) => {
      const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed, haendelserBy: hs }));
      return sum + cards.findIndex((c) => c.id === targetId);
    }, 0) / seeds.length;
    expect(meanIndex(boosted)).toBeLessThan(meanIndex(plain));
  });
});

// --- fase 3: regressions-invariant + pins/skjul -------------------------------
describe('buildFeedOrder — fase 3', () => {
  it('uden stories og pins er ordningen dybt identisk med fase 2', () => {
    const model = rigModel(40);
    const aux = rigAux(12);
    for (let seed = 0; seed < 50; seed++) {
      const fase2 = buildFeedOrder(model, aux, baseInputs({ seed }));
      expect(buildFeedOrder(model, aux, baseInputs({ seed, storieBy: {}, pins: [] }))).toEqual(fase2);
    }
    const hs: HaendelserBy = Object.fromEntries(
      Array.from({ length: 20 }, (_, i) => ['p' + i, [haendelse('h' + i)]]),
    );
    const fase2 = buildFeedOrder(model, aux, baseInputs({ seed: 7, haendelserBy: hs }));
    expect(buildFeedOrder(model, aux, baseInputs({
      seed: 7, haendelserBy: hs, storieBy: {}, pins: [],
    }))).toEqual(fase2);
  });

  it('pin-blok står først og bevarer input-orden', () => {
    const model = rigModel(20);
    const pins = [
      { kortNoegle: 'portrait:p2', handling: 'pin' as const },
      { kortNoegle: 'portrait:p1', handling: 'pin' as const },
    ];
    for (const seed of [1, 2, 3]) {
      const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed, pins }));
      expect(cards[0].id).toBe('portrait:p2');
      expect(cards[1].id).toBe('portrait:p1');
    }
  });

  it('forskubber dagensperson-låsen med pin-blokkens længde', () => {
    const model = mkModel(Array.from({ length: 15 }, (_, i) => person('p' + i, { bio: LONG_BIO })));
    const pins = [
      { kortNoegle: 'portrait:p1', handling: 'pin' as const },
      { kortNoegle: 'portrait:p2', handling: 'pin' as const },
    ];
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed: 5, pins }));
    const index = cards.findIndex((card) => card.kind === 'dagensperson');
    expect(index).toBeGreaterThanOrEqual(2);
    expect(index).toBeLessThanOrEqual(4);
  });

  it('pin vinder over seenWeights=0, mens skjul fjerner kortet', () => {
    const model = mkModel([person('a', { bio: LONG_BIO }), person('b', { bio: LONG_BIO })]);
    const pinned = buildFeedOrder(model, EMPTY_AUX, baseInputs({
      seenWeights: { 'citat:a': 0 },
      pins: [{ kortNoegle: 'citat:a', handling: 'pin' }],
    }));
    expect(pinned[0]?.id).toBe('citat:a');
    const hidden = buildFeedOrder(model, EMPTY_AUX, baseInputs({
      pins: [{ kortNoegle: 'citat:a', handling: 'skjul' }],
    }));
    expect(hidden.some((card) => card.id === 'citat:a')).toBe(false);
  });

  it('dinglende kurering er ufarlig', () => {
    const model = rigModel(20);
    const without = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed: 3 }));
    const withDangling = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed: 3, pins: [
      { kortNoegle: 'story:404', handling: 'pin' },
      { kortNoegle: 'arkiv:404', handling: 'skjul' },
    ] }));
    expect(withDangling).toEqual(without);
  });

  it('korrupt pin+skjul på samme nøgle degraderer til skjul', () => {
    const model = mkModel([person('a', { bio: LONG_BIO }), person('b', { bio: LONG_BIO })]);
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ pins: [
      { kortNoegle: 'portrait:a', handling: 'skjul' },
      { kortNoegle: 'portrait:a', handling: 'pin' },
    ] }));
    expect(cards.some((card) => card.id === 'portrait:a')).toBe(false);
  });

  it('historie-kort deduplikerer ankeret end-to-end', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const model = mkModel(persons);
    const hs: HaendelserBy = Object.fromEntries(persons.map((p, i) => [p.id, [haendelse('h' + i)]]));
    const target = persons[5];
    const sb: StorieBy = { [target.id]: [storie('s1', { haendelseId: hs[target.id][0].id })] };
    for (let seed = 1; seed <= 10; seed++) {
      const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed, haendelserBy: hs, storieBy: sb }));
      expect(cards.some((card) => card.id === 'story:s1')).toBe(true);
      expect(cards.some((card) => card.id === 'arkiv:' + hs[target.id][0].id)).toBe(false);
      expect(cards.some((card) => card.kind === 'citat' && card.personId === target.id
        && card.quote === hs[target.id][0].klausul)).toBe(false);
    }
  });

  it('er deterministisk og leverer pin-blokken i første stream-side', () => {
    const model = rigModel(20);
    const inputs = baseInputs({ seed: 4,
      storieBy: { p1: [storie('s1')] },
      pins: [{ kortNoegle: 'story:s1', handling: 'pin' }] });
    expect(buildFeedOrder(model, EMPTY_AUX, inputs)).toEqual(buildFeedOrder(model, EMPTY_AUX, inputs));
    expect(createFeedStream(model, EMPTY_AUX, inputs).next(12)[0].id).toBe('story:s1');
  });
});

// --- GDPR-gate: person-kort kræver dødsevidens (levende.ts) --------------------
describe('buildFeedOrder — udelukker personer uden dødsevidens (levende.ts)', () => {
  it('person uden dødsår og født inden for aldersgrænsen optræder i intet person-kort', () => {
    const persons = [
      person('doed', { bio: LONG_BIO, died: 1950 }),
      person('maaske-i-live', { bio: LONG_BIO, born: 1980, died: null }),
    ];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    const ids = cards.flatMap((c) => ('personId' in c ? [c.personId] : []));
    expect(ids).not.toContain('maaske-i-live');
  });

  it('født for over 120 år siden uden dødsår tælles alligevel som sikkert død', () => {
    const persons = [person('gammel', { bio: LONG_BIO, born: 1900, died: null })];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    const ids = cards.flatMap((c) => ('personId' in c ? [c.personId] : []));
    expect(ids).toContain('gammel');
  });

  it('person helt uden fødsels-/dødsår udelades (fail-closed)', () => {
    const persons = [person('ukendt', { bio: LONG_BIO, born: null, died: null })];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    expect(cards.some((c) => 'personId' in c && c.personId === 'ukendt')).toBe(false);
  });

  it('samle-kortets optælling af resterende personer er upåvirket af gaten', () => {
    const persons = [
      person('doed', { bio: LONG_BIO, died: 1950 }),
      person('maaske-i-live', { bio: LONG_BIO, born: 1980, died: null }),
    ];
    const cards = buildFeedOrder(mkModel(persons), EMPTY_AUX, baseInputs());
    const samle = cards.find((c) => c.kind === 'samle');
    expect(samle).toMatchObject({ count: 1 });
  });
});

// --- performance-budget --------------------------------------------------------
describe('buildFeedOrder — ydelse', () => {
  it('ordner ~3000 kandidater under 250ms (rummeligt CI-loft)', () => {
    const persons = Array.from({ length: 1000 }, (_, i) => person('p' + i, { bio: LONG_BIO, born: 1700 + (i % 300) }));
    const m = mkModel(persons);
    const aux = rigAux(1000);
    const start = performance.now();
    const cards = buildFeedOrder(m, aux, baseInputs());
    const elapsed = performance.now() - start;
    expect(cards.length).toBeGreaterThan(1000);
    expect(elapsed).toBeLessThan(250);
  });
});
