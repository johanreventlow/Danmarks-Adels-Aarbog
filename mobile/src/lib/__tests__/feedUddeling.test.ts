import { buildModel } from '@daa/core';
import { createFeedStream, type FeedAux, type FeedCard, type FeedStream, type Model } from '@daa/feed';
import { foersteUddeling, genoptag, naesteSide } from '../feedUddeling';

// Kunstig strøm over en fast kortliste (samme kontrakt som createFeedStream).
function fake(cards: FeedCard[]): FeedStream {
  let cursor = 0;
  return {
    next(n) { const s = cards.slice(cursor, cursor + n); cursor += s.length; return s; },
    done: () => cursor >= cards.length,
    total: () => cards.length,
  };
}
const portrait = (pid: string): FeedCard => ({ kind: 'portrait', id: 'portrait:' + pid, personId: pid, name: 'P ' + pid } as FeedCard);
const dagens = (pid: string): FeedCard => ({ kind: 'dagensperson', id: 'dagensperson:' + pid, personId: pid, name: 'P ' + pid } as FeedCard);
const samle: FeedCard = { kind: 'samle', id: 'samle:personer', count: 3, tail: '', kicker: '' };
const ids = (cards: readonly FeedCard[]) => cards.map((c) => c.id);

describe('naesteSide', () => {
  it('holder samlekortet tilbage, før kilderne er afgjort', () => {
    expect(ids(naesteSide(fake([portrait('1'), samle]), 5, false))).toEqual(['portrait:1']);
  });
  it('deler samlekortet ud, når kilderne er afgjort', () => {
    expect(ids(naesteSide(fake([portrait('1'), samle]), 5, true))).toEqual(['portrait:1', 'samle:personer']);
  });
});

describe('foersteUddeling', () => {
  it('ved fristen med kun samlekortet: venter (null) i stedet for at låse en tom forside', () => {
    expect(foersteUddeling(fake([samle]), 12, false)).toBeNull();
    expect(foersteUddeling(fake([]), 12, false)).toBeNull();
  });
  it('når alt er afgjort, deles der ud — også en tom eller ren samle-strøm', () => {
    expect(foersteUddeling(fake([samle]), 12, true)).toEqual([samle]);
    expect(foersteUddeling(fake([]), 12, true)).toEqual([]);
  });
  it('ved fristen med egentlige blade: deler dem ud uden samlekortet', () => {
    expect(ids(foersteUddeling(fake([portrait('1'), portrait('2'), samle]), 12, false)!)).toEqual(['portrait:1', 'portrait:2']);
  });
});

describe('genoptag', () => {
  it('beholder de viste kort og fylder op til en side uden gentagelser af kort eller personer', () => {
    const vist = [portrait('1'), portrait('2')];
    const built = fake([portrait('2'), { kind: 'citat', id: 'citat:1', personId: '1' } as FeedCard, portrait('3'), portrait('4'), samle]);
    const r = genoptag(built, vist, 3, true, false);
    expect(ids(r.shown)).toEqual(['portrait:1', 'portrait:2', 'portrait:3']);
    expect(ids(r.stream.next(5))).toEqual(['portrait:4', 'samle:personer']);
  });

  it('fjerner et vist samlekort; den nye strøm leverer sit eget til sidst', () => {
    const r = genoptag(fake([portrait('1'), portrait('2'), samle]), [portrait('1'), samle], 2, true, true);
    expect(ids(r.shown)).toEqual(['portrait:1', 'portrait:2']);
    expect(ids(r.stream.next(5))).toEqual(['samle:personer']);
  });

  it('en hel side vist og gammel strøm ikke udtømt: intet ændres (samme reference)', () => {
    const vist = [portrait('1'), portrait('2')];
    const r = genoptag(fake([portrait('1'), portrait('3')]), vist, 2, true, false);
    expect(r.shown).toBe(vist);
    expect(ids(r.stream.next(5))).toEqual(['portrait:3']);
  });

  it('var den gamle strøm udtømt, fyldes en ny side på straks (FlatList kalder ikke onEndReached igen)', () => {
    const vist = [portrait('1'), portrait('2')];
    const r = genoptag(fake([portrait('3'), portrait('4'), portrait('5')]), vist, 2, true, true);
    expect(ids(r.shown)).toEqual(['portrait:1', 'portrait:2', 'portrait:3', 'portrait:4']);
  });

  it('viser ikke en ny »dagens person«, når en anden allerede er vist', () => {
    const r = genoptag(fake([dagens('9'), portrait('2'), portrait('3')]), [dagens('1')], 3, true, false);
    expect(ids(r.shown)).toEqual(['dagensperson:1', 'portrait:2', 'portrait:3']);
  });

  it('før kilderne er afgjort, fyldes der ikke med samlekortet', () => {
    const r = genoptag(fake([portrait('1'), samle]), [], 3, false, false);
    expect(ids(r.shown)).toEqual(['portrait:1']);
  });
});

// Hele forløbet med den rigtige motor: før biografierne giver kun personer med titel og embede kort på forsiden; når
// biografierne kommer, beholdes de viste kort, og de nye personer kommer bagefter.
describe('forløb med createFeedStream og forsidens minimumskrav', () => {
  const BIO = 'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, virke og eftermæle, '
    + 'skrevet med tilstrækkeligt mange detaljer og sammenhæng, så den klart når forsidens minimum for en biografi.';
  const T_IDS = ['t1', 't2', 't3', 't4'];
  const AUX: FeedAux = {
    godsListe: [], vaabenListe: [],
    officesBy: Object.fromEntries(T_IDS.map((id, i) => [id, [{ label: 'Amtmand', period: '1650-1660', _y: 1650 + i }]])),
  };
  const person = (id: string, over: Partial<{ title: string; bio: string }> = {}) => ({
    id, name: 'Christian Reventlow ' + id, born: 1600, died: 1680, years: '1600-1680', title: '', bio: '', privat: false, ...over,
  });
  const mk = (bio: boolean): Model => buildModel({
    persons: [
      ...T_IDS.map((id) => person(id, { title: 'Greve' })),
      ...Array.from({ length: 20 }, (_, i) => person('b' + i, bio ? { bio: BIO } : {})),
    ],
    unions: [], parentChild: [],
  }) as unknown as Model;
  const inputs = { seed: 7, todayISO: '2026-11-25', meId: null, focusId: null, forsideKrav: true };

  it('kort fra fristen bliver stående; senere kort kommer fra den biografi-berigede strøm', () => {
    const foer = foersteUddeling(createFeedStream(mk(false), AUX, inputs), 12, false)!;
    expect(foer.length).toBeGreaterThan(0);
    expect(foer.length).toBeLessThan(12);
    const efter = genoptag(createFeedStream(mk(true), AUX, inputs), foer, 12, true, true);
    expect(efter.shown.slice(0, foer.length)).toEqual(foer);
    expect(efter.shown.length).toBe(12);
    const alle = [...efter.shown, ...efter.stream.next(100)];
    expect(new Set(ids(alle)).size).toBe(alle.length);
    expect(alle.filter((c) => c.kind === 'dagensperson').length).toBeLessThanOrEqual(1);
  });
});
