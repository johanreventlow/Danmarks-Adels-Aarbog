import { buildModel, soeg, stavemaader, STANDARD_FILTRE, type AppPerson } from '@daa/core';
import { aarFraTekst, antalAfgraensninger, fremhaevDele, ingenTitel, soegerAktivt, statusTekst } from '../soegning';

const P = (id: string, name: string, born: number | null = null, died: number | null = null): AppPerson =>
  ({ id, name, born, died, years: '', title: '', bio: '', privat: false, koen: null });
const f = (x: Partial<typeof STANDARD_FILTRE>) => ({ ...STANDARD_FILTRE, ...x });

const model = buildModel({
  persons: [P('1', 'Detlev Reventlow', 1700, 1760), P('2', 'Ida Reventlou', null, null), P('3', 'Anna Brahe', 1600, 1650)],
  unions: [], parentChild: [],
});
const godser = [{ id: 'e1', navn: 'Ålholm', slags: 'gods', ownerCount: 1 }, { id: 'e2', navn: 'Brahetrolleborg', slags: 'gods', ownerCount: 0 }];

test('søgefanen bruger core-søgningen: foldet stavemåde og besiddelser i resultatet', () => {
  const r = soeg(model, godser, f({ q: 'detlef' }));
  expect(r.personer.map((p) => p.id)).toEqual(['1']);
  expect(soeg(model, godser, f({ q: 'aalholm' })).godser.map((g) => g.id)).toEqual(['e1']);
  const brahe = soeg(model, godser, f({ q: 'brahe' }));
  expect([brahe.personer.map((p) => p.id), brahe.godser.map((g) => g.id)]).toEqual([['3'], ['e2']]);
  expect(stavemaader(model.persons.map((p) => p.name), 'Reventlow')).toContain('Reventlou');
});

test('søgningen afløser bladringen ved søgeord eller afgrænsning', () => {
  expect(soegerAktivt(STANDARD_FILTRE)).toBe(false);
  expect(soegerAktivt(f({ q: '  ' }))).toBe(false);
  expect(soegerAktivt(f({ q: 'a' }))).toBe(true);
  expect(soegerAktivt(f({ type: 'besiddelser' }))).toBe(true);
  expect(soegerAktivt(f({ fra: 1700 }))).toBe(true);
  expect(antalAfgraensninger(f({ linje: 'K', til: 1800, type: 'personer' }))).toBe(3);
});

test('fremhævning af de bogstavret fundne søgeord', () => {
  expect(fremhaevDele('Greve Conrad', [[6, 12]])).toEqual([{ tekst: 'Greve ', mark: false }, { tekst: 'Conrad', mark: true }]);
  expect(fremhaevDele('Ålholm', [])).toEqual([{ tekst: 'Ålholm', mark: false }]);
});

test('status- og tomtekster som web', () => {
  const r = soeg(model, godser, f({ q: 'brahe' }));
  expect(statusTekst(f({ q: 'brahe' }), r)).toBe('1 person · 1 besiddelse');
  const periode = soeg(model, godser, f({ q: 'reventl', fra: 1700, til: 1710 }));
  expect(statusTekst(f({ q: 'reventl', fra: 1700, til: 1710 }), periode)).toBe('1 person · 1 uden årstal er ikke med');
  expect(statusTekst(f({ q: 'zz' }), soeg(model, godser, f({ q: 'zz' })))).toBe('Ingen resultater');
  expect(ingenTitel(f({ q: 'zz', type: 'besiddelser' }))).toBe('Ingen besiddelse hedder »zz«');
  expect(ingenTitel(f({ linje: 'K' }))).toBe('Ingen passer til afgrænsningen');
});

test('årstalsfelt: kun hele år tæller', () => {
  expect(aarFraTekst('17')).toEqual({ tekst: '17', aar: undefined });
  expect(aarFraTekst('17a00')).toEqual({ tekst: '1700', aar: 1700 });
  expect(aarFraTekst('')).toEqual({ tekst: '', aar: null });
});
