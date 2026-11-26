// Paritetsplanens batch 7: slægtskabet til »mig« over navnet, formet som web's SlaegtskabsLinje.
import { buildModel, slaegtskabsKontekst, type AppPerson, type Db } from '@daa/core';
import { linjeTekst, slaegtskabsLinje } from '../slaegtskabsLinje';

const P = (id: string, koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name: id === 'B' ? 'Christian' : id, born: null, died: null, years: '', title: '', bio: '', privat: false, koen });
const db: Db = {
  persons: [P('F', 'mand'), P('B', 'mand'), P('X', 'kvinde'), P('U', 'mand'), P('Z')],
  unions: [{ id: 'f1', p1: 'B', p2: 'X', p2_name: null, year: null }],
  parentChild: [
    { child: 'B', parent: 'F', union: 'f0' },
    { child: 'U', parent: 'F', union: 'f0', konfidens: 'formodet' },
  ],
};
const m = buildModel(db);
const linje = (me: string | null, fokus: string) => slaegtskabsLinje(slaegtskabsKontekst(m, me, fokus), me, fokus);

describe('slaegtskabsLinje', () => {
  test('intet »mig« → ingen linje', () => {
    expect(linje(null, 'F')).toBeNull();
  });
  test('blodslægt: ordet med stort og »Se vejen« til »Er vi i familie?«', () => {
    const v = linje('B', 'F')!;
    expect(linjeTekst(v)).toBe('Din far · Se vejen');
    expect(v.dele.find((d) => d.art === 'vej')).toEqual({ art: 'vej', tekst: 'Se vejen', fra: 'B', til: 'F' });
  });
  test('usikker forbindelse siges med ord i faresignalets farve', () => {
    const v = linje('U', 'F')!;
    expect(v.dele[0]).toEqual({ art: 'tvivl', tekst: 'Sandsynligvis' });
    expect(linjeTekst(v)).toBe('Sandsynligvis din far · Se vejen');
  });
  test('gift med en blodslægtning: ægtefællen som link, vejen til ægtefællen', () => {
    const v = linje('F', 'X')!;
    expect(linjeTekst(v)).toBe('Gift med Christian, din søn · Se vejen');
    expect(v.dele[1]).toEqual({ art: 'person', tekst: 'Christian', personId: 'B' });
    expect(v.dele.find((d) => d.art === 'vej')).toMatchObject({ fra: 'F', til: 'B' });
  });
  test('dig, din ægtefælle og ingen fælles ane (dæmpet)', () => {
    expect(linjeTekst(linje('B', 'B')!)).toBe('Det er dig');
    expect(linjeTekst(linje('B', 'X')!)).toBe('Din ægtefælle');
    const ingen = linje('B', 'Z')!;
    expect(linjeTekst(ingen)).toBe('Aarbogen viser ingen fælles ane med dig');
    expect(ingen.daempet).toBe(true);
  });
});
