import { buildBrowse } from '../browse';
import type { ModelPerson } from '../types';

// Minimal person-fabrik — buildBrowse bruger kun name + born, resten er defaults.
const mp = (id: string, name: string, born: number | null = null): ModelPerson => ({
  id, name, born, died: null, years: '', title: '', bio: '', privat: false,
  parentId: null, spouse: '',
});

// Fixture: efternavne der spænder over flere bogstaver + Æ/Ø/Å (grupperes på EFTERNAVN).
const people: ModelPerson[] = [
  mp('1', 'Christian Ditlev Reventlow', 1748),
  mp('2', 'Anna Reventlow', 1693),
  mp('3', 'Niels Ærø', 1801),
  mp('4', 'Ove Øster', 1770),
  mp('5', 'Per Åstrup', 1650),
  mp('6', 'Sophie Joachimsdatter [Bjørn]', 1600),
  mp('7', 'Zacharias Zahle', 1710),
  mp('8', 'Frederik Ahlefeldt', 1662),
];

describe('buildBrowse — grupperet navne-sort (§9.1)', () => {
  const r = buildBrowse(people, '', 'navn', null);

  test('grupperet når navne-sort uden query', () => {
    expect(r.grouped).toBe(true);
  });

  test('bogstaver i dansk orden — Æ/Ø/Å EFTER Z', () => {
    // Efternavne: Ahlefeldt(A), Bjørn(B), Reventlow(R), Zahle(Z), Ærø(Æ), Øster(Ø), Åstrup(Å)
    expect(r.letters).toEqual(['A', 'B', 'R', 'Z', 'Æ', 'Ø', 'Å']);
  });

  test('grupperne følger samme danske orden', () => {
    expect(r.groups.map((g) => g.letter)).toEqual(['A', 'B', 'R', 'Z', 'Æ', 'Ø', 'Å']);
  });

  test('grupperer på efternavn, ikke fornavn', () => {
    const rGroup = r.groups.find((g) => g.letter === 'R');
    expect(rGroup?.people.map((p) => p.id).sort()).toEqual(['1', '2']); // begge Reventlow
  });

  test('rekonstrueret efternavn [Bjørn] → B (springer klamme over)', () => {
    expect(r.groups.find((g) => g.letter === 'B')?.people[0].id).toBe('6');
  });
});

describe('buildBrowse — activeLetter filtrerer', () => {
  test('kun det valgte bogstavs gruppe', () => {
    const r = buildBrowse(people, '', 'navn', 'Æ');
    expect(r.grouped).toBe(true);
    expect(r.groups).toHaveLength(1);
    expect(r.groups[0].letter).toBe('Æ');
    expect(r.groups[0].people[0].id).toBe('3');
  });

  test('letters-rækken viser stadig ALLE bogstaver (så man kan skifte)', () => {
    const r = buildBrowse(people, '', 'navn', 'Æ');
    expect(r.letters).toEqual(['A', 'B', 'R', 'Z', 'Æ', 'Ø', 'Å']);
  });
});

describe('buildBrowse — query giver flad, ufiltreret liste', () => {
  test('query → grouped=false + kun matchende', () => {
    const r = buildBrowse(people, 'reventlow', 'navn', null);
    expect(r.grouped).toBe(false);
    expect(r.flat.map((p) => p.id).sort()).toEqual(['1', '2']);
    expect(r.letters).toEqual([]);
  });

  test('query er case-insensitiv og matcher fornavn', () => {
    const r = buildBrowse(people, 'PER', 'navn', null);
    expect(r.flat.map((p) => p.id)).toEqual(['5']);
  });
});

describe('buildBrowse — fødeår-sort', () => {
  const r = buildBrowse(people, '', 'aar', null);

  test('flad (ikke grupperet) og ingen alfabet', () => {
    expect(r.grouped).toBe(false);
    expect(r.letters).toEqual([]);
  });

  test('sorteret stigende på fødeår', () => {
    expect(r.flat.map((p) => p.born)).toEqual([1600, 1650, 1662, 1693, 1710, 1748, 1770, 1801]);
  });
});
