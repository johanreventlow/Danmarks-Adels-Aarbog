import { describe, expect, it } from 'vitest';
import type { FeedCard, FeedStream } from '@daa/feed';
import { delUd, iBlokke } from '../feedUddeling';

const portraet = (id: string): FeedCard => ({
  kind: 'portrait', id: 'portrait:' + id, personId: id, name: id, years: '', initials: 'X',
  title: null, bio: '', kicker: 'Portræt',
});
const naevnt = (id: string): FeedCard => ({
  kind: 'naevnt', id: 'naevnt:' + id, personId: id, name: id, years: '', relation: null,
  kilde: 'nr. 1', kicker: 'Nævnt i Aarbogen',
});

function strøm(kort: FeedCard[]): FeedStream {
  let i = 0;
  return {
    next: (n) => { const ud = kort.slice(i, i + n); i += ud.length; return ud; },
    done: () => i >= kort.length,
    total: () => kort.length,
  };
}

describe('delUd', () => {
  it('deler seks kort ud ad gangen og stopper ved strømmens ende', () => {
    const s = strøm(Array.from({ length: 8 }, (_, i) => portraet(String(i))));
    expect(delUd(s, [])).toHaveLength(6);
    expect(delUd(s, [])).toHaveLength(2);
    expect(s.done()).toBe(true);
  });

  it('springer et naevnt over, der ville give to inden for seks viste kort (sømmen efter genopbygning)', () => {
    const vist = [portraet('a'), portraet('b'), naevnt('x')];
    const s = strøm([portraet('c'), naevnt('y'), portraet('d'), portraet('e'), portraet('f'), portraet('g'), naevnt('z')]);
    const ud = delUd(s, vist);
    expect(ud.map((c) => c.id)).toEqual([
      'portrait:c', 'portrait:d', 'portrait:e', 'portrait:f', 'portrait:g', 'naevnt:z',
    ]);
  });
});

describe('iBlokke', () => {
  it('deler de viste kort i blokke à seks', () => {
    const kort = Array.from({ length: 13 }, (_, i) => portraet(String(i)));
    expect(iBlokke(kort).map((b) => b.length)).toEqual([6, 6, 1]);
  });
});
