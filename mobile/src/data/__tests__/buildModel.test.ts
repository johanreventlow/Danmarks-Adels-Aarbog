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
