import { buildModel } from '../buildModel';
import type { Db } from '../types';

const mk = (id: string, name: string) => ({
  id,
  name,
  born: null,
  died: null,
  years: '',
  title: '',
  bio: '',
});

describe('buildModel — udleder parentId, spouse og indekser', () => {
  const db: Db = {
    persons: [mk('1', 'Far'), mk('2', 'Mor'), mk('3', 'Barn A'), mk('4', 'Barn B')],
    unions: [{ id: 'f1', p1: '1', p2: '2', p2_name: null, year: null }],
    parentChild: [
      { child: '3', parent: '1', union: 'f1' },
      { child: '3', parent: '2', union: 'f1' },
      { child: '4', parent: '1', union: 'f1' },
      { child: '4', parent: '2', union: 'f1' },
    ],
  };
  const model = buildModel(db);

  test('parentId = første forælder fra primær fødselsfamilie', () => {
    expect(model.byId['3'].parentId).toBe('1');
    expect(model.byId['4'].parentId).toBe('1');
  });

  test('spouse afledes begge veje', () => {
    expect(model.byId['1'].spouse).toBe('Mor');
    expect(model.byId['2'].spouse).toBe('Far');
  });

  test('parentsByChild rummer begge forældre', () => {
    expect(model.indexes.parentsByChild['3'].sort()).toEqual(['1', '2']);
  });

  test('childrenByUnion grupperer børn pr. ægteskab', () => {
    expect(model.indexes.childrenByUnion['1']['f1'].sort()).toEqual(['3', '4']);
  });

  test('byId-opslag dækker alle personer', () => {
    expect(Object.keys(model.byId).sort()).toEqual(['1', '2', '3', '4']);
  });
});

describe('buildModel — første-union-reglen (barn i flere familier får ikke flettet forældre)', () => {
  const db: Db = {
    persons: [mk('1', 'Bioforælder'), mk('2', 'Stedforælder'), mk('3', 'Barn')],
    unions: [
      { id: 'f1', p1: '1', p2: null, p2_name: null, year: null },
      { id: 'f2', p1: '2', p2: null, p2_name: null, year: null },
    ],
    parentChild: [
      { child: '3', parent: '1', union: 'f1' },
      { child: '3', parent: '2', union: 'f2' }, // optræder i anden familie
    ],
  };
  const model = buildModel(db);

  test('kun forældre fra første union tælles', () => {
    expect(model.byId['3'].parentId).toBe('1');
    expect(model.indexes.parentsByChild['3']).toEqual(['1']);
  });
});

describe('buildModel — sanity-guard mod umulige forælder→barn-kanter', () => {
  const mkY = (id: string, name: string, born: number | null, died: number | null = null) => ({ id, name, born, died, years: '', title: '', bio: '' });
  const db: Db = {
    persons: [
      mkY('p', 'Forælder', 1850, 1900),
      mkY('c', 'Tidligt barn', 1685), // født før forælder
      mkY('late', 'For sent barn', 1905), // født >1 år efter forælders død (1900)
      mkY('post', 'Posthumt barn', 1901), // født 1 år efter død → tilladt
      mkY('ok', 'Rigtigt barn', 1880),
    ],
    unions: [{ id: 'f1', p1: 'p', p2: null, p2_name: null, year: null }],
    parentChild: [
      { child: 'c', parent: 'p', union: 'f1' },
      { child: 'late', parent: 'p', union: 'f1' },
      { child: 'post', parent: 'p', union: 'f1' },
      { child: 'ok', parent: 'p', union: 'f1' },
    ],
  };
  const model = buildModel(db);

  test('dropper barn født før forælder OG >1 år efter forælders død; beholder posthumt + gyldigt', () => {
    const kids = Object.values(model.indexes.childrenByUnion['p'] ?? {}).flat();
    expect(kids.sort()).toEqual(['ok', 'post']);
    expect(model.byId['c'].parentId).toBeNull();
    expect(model.byId['late'].parentId).toBeNull();
    expect(model.byId['post'].parentId).toBe('p');
    expect(model.byId['ok'].parentId).toBe('p');
  });
});
