import { describe, expect, it } from 'vitest';
import { byggBogNr, sorterBoernEfterBogen, type BogNr } from '../bogensOrden';

const B = (id: string, born: number | null = null, name = id) => ({ id, born, name });
const N = (sourceId: string, linje: string, nr: number, nrLabel: string | null = null): BogNr => ({ sourceId, linje, nr, nrLabel });
const U2018 = { sourceId: '20', aar: 2018 };
const U1939 = { sourceId: '10', aar: 1939 };
const ider = (xs: { id: string }[]) => xs.map((x) => x.id);

describe('byggBogNr', () => {
  it('folder alias til kanonisk og springer rækker uden linje/nr over', () => {
    const r = byggBogNr([
      { person_id: 1, source_id: 10, linje: 'V', nr: 14, nr_label: '14' },
      { person_id: 2, source_id: 9, linje: 'V', nr: 12, nr_label: null },
      { person_id: 3, source_id: 10, linje: null, nr: 3 },
      { person_id: 4, source_id: 10, linje: 'V', nr: null },
    ], { '2': '1' });
    expect(r['1']).toEqual([N('10', 'V', 14, '14'), N('9', 'V', 12, null)]);
    expect(r['3']).toBeUndefined();
    expect(r['4']).toBeUndefined();
  });
});

describe('sorterBoernEfterBogen', () => {
  it('sorterer efter nummer i forælderens linje, ikke efter indgangsrækkefølge', () => {
    const idx = { F: [N('20', 'V', 1)], c: [N('20', 'V', 4)], a: [N('20', 'V', 2)], b: [N('20', 'V', 3)] };
    expect(ider(sorterBoernEfterBogen([B('c'), B('a'), B('b')], 'F', idx, [U2018]))).toEqual(['a', 'b', 'c']);
  });

  it('15a før 15b', () => {
    const idx = { F: [N('20', 'V', 1)], x: [N('20', 'V', 15, '15b')], y: [N('20', 'V', 15, '15a')] };
    expect(ider(sorterBoernEfterBogen([B('x'), B('y')], 'F', idx, [U2018]))).toEqual(['y', 'x']);
  });

  it('børn uden nummer sidst efter fødselsår, så navn', () => {
    const idx = { F: [N('20', 'V', 1)], x: [N('20', 'V', 2)] };
    const boern = [B('y', 1700), B('z', null), B('x', 1750), B('w', 1690), B('v', 1690, 'Anna')];
    expect(ider(sorterBoernEfterBogen(boern, 'F', idx, [U2018]))).toEqual(['x', 'v', 'w', 'y', 'z']);
  });

  it('nyeste udgave vinder; udgave uden år taber', () => {
    const idx = {
      F: [N('10', 'IV', 1), N('20', 'V', 1), N('30', 'V', 1)],
      p: [N('10', 'IV', 9), N('20', 'V', 2), N('30', 'V', 9)],
      q: [N('10', 'IV', 1), N('20', 'V', 3), N('30', 'V', 1)],
    };
    const udgaver = [U1939, U2018, { sourceId: '30', aar: null }];
    expect(ider(sorterBoernEfterBogen([B('q'), B('p')], 'F', idx, udgaver))).toEqual(['p', 'q']);
  });

  it('forælder uden nummer (indgiftet ægtefælle)', () => {
    const idx = { k: [N('20', 'V', 7)], l: [N('20', 'V', 5)] };
    expect(ider(sorterBoernEfterBogen([B('k'), B('l')], 'M', idx, [U2018]))).toEqual(['l', 'k']);
  });

  it('ingen fælles linje med forælderen (1939: Conrad under »1939«, børnene i IV)', () => {
    const idx = { F: [N('10', '1939', 275)], k: [N('10', 'IV', 3)], l: [N('10', 'IV', 2)] };
    expect(ider(sorterBoernEfterBogen([B('k', 1600), B('l', 1700)], 'F', idx, [U1939]))).toEqual(['l', 'k']);
  });

  it('børn i flere linjer: forælderens linje før fremmede, fremmede uden nøgle', () => {
    const idx = { F: [N('20', 'V', 1)], a: [N('20', 'V', 3)], b: [N('20', 'V', 2)], c: [N('20', 'VI', 1)] };
    expect(ider(sorterBoernEfterBogen([B('c', 1600), B('a'), B('b')], 'F', idx, [U2018]))).toEqual(['b', 'a', 'c']);
  });

  it('uden bogNrBy: fødselsår-fallback', () => {
    expect(ider(sorterBoernEfterBogen([B('b', 1702), B('a', 1701)], 'F', undefined, undefined))).toEqual(['a', 'b']);
  });

  it('muterer ikke input', () => {
    const boern = [B('b', 2), B('a', 1)];
    sorterBoernEfterBogen(boern, 'F', undefined, undefined);
    expect(ider(boern)).toEqual(['b', 'a']);
  });
});
