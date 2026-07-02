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

describe('buildBrowse — H1: ugyldigt activeLetter falder tilbage til Alle (ingen dead-end)', () => {
  test('activeLetter der ikke findes i pool → alle grupper vises (ikke blank)', () => {
    // 'X' er intet efternavns-initial → må ikke give tom liste.
    const r = buildBrowse(people, '', 'navn', 'X', null);
    expect(r.grouped).toBe(true);
    expect(r.groups.length).toBeGreaterThan(0);
    expect(r.flat).toHaveLength(people.length);
  });

  test('activeLetter fjernet af gren-filter → falder tilbage til Alle', () => {
    const byLinje: Record<string, string[]> = { '1': ['I'], '2': ['I'] }; // linje I = kun Reventlow (R)
    // Bruger havde valgt 'Æ' i hele slægten; skifter så til linje I (uden Æ-efternavne).
    const r = buildBrowse(people, '', 'navn', 'Æ', { linjeByPerson: byLinje, activeLinje: 'I' });
    expect(r.groups.map((g) => g.letter)).toEqual(['R']); // ikke [] → ingen dead-end
    expect(r.flat.map((p) => p.id).sort()).toEqual(['1', '2']);
  });

  test('gyldigt activeLetter respekteres stadig', () => {
    const r = buildBrowse(people, '', 'navn', 'R', null);
    expect(r.groups.map((g) => g.letter)).toEqual(['R']);
  });
});

describe('buildBrowse — gren-filter (§9.2, activeLinje)', () => {
  // Reventlow(1,2) → linje I; Ærø(3),Øster(4) → II; resten uden linje.
  const byLinje: Record<string, string[]> = { '1': ['I'], '2': ['I'], '3': ['II'], '4': ['II'] };

  test('activeLinje begrænser til grenens medlemmer (stadig grupperet)', () => {
    const r = buildBrowse(people, '', 'navn', null, { linjeByPerson: byLinje, activeLinje: 'I' });
    expect(r.grouped).toBe(true);
    expect(r.flat.map((p) => p.id).sort()).toEqual(['1', '2']); // kun linje I
    expect(r.letters).toEqual(['R']); // begge Reventlow
  });

  test('linje-filter komponeres MED query', () => {
    const r = buildBrowse(people, 'anna', 'navn', null, { linjeByPerson: byLinje, activeLinje: 'I' });
    expect(r.flat.map((p) => p.id)).toEqual(['2']); // Anna Reventlow er i linje I
  });

  test('linje-filter komponeres MED alfabet-filter', () => {
    const r = buildBrowse(people, '', 'navn', 'Æ', { linjeByPerson: byLinje, activeLinje: 'II' });
    expect(r.groups).toHaveLength(1);
    expect(r.groups[0].people.map((p) => p.id)).toEqual(['3']); // kun Ærø i II under Æ
  });

  test('ingen activeLinje → uændret (alle personer)', () => {
    const r = buildBrowse(people, '', 'navn', null, { linjeByPerson: byLinje, activeLinje: null });
    expect(r.flat).toHaveLength(people.length);
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
