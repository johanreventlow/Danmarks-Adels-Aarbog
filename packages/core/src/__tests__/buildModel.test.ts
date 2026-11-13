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
  privat: false,
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

describe('buildModel — nameOf-opslag (O(1)-map, review 12)', () => {
  test('union med p2_name (ingen p2-person) bruger p2_name direkte', () => {
    const db: Db = {
      persons: [mk('1', 'Enke')],
      unions: [{ id: 'f1', p1: '1', p2: null, p2_name: 'Afdød Ægtefælle', year: null }],
      parentChild: [],
    };
    const model = buildModel(db);
    expect(model.byId['1'].spouse).toBe('Afdød Ægtefælle');
  });

  test('union der refererer et ikke-eksisterende person-id degraderer til tom streng, ikke crash', () => {
    const db: Db = {
      persons: [mk('1', 'Person')],
      unions: [{ id: 'f1', p1: '1', p2: 'ukendt-id', p2_name: null, year: null }],
      parentChild: [],
    };
    expect(() => buildModel(db)).not.toThrow();
    const model = buildModel(db);
    expect(model.byId['1'].spouse).toBe('');
  });
});

describe('buildModel — sanity-guard mod umulige forælder→barn-kanter', () => {
  const mkY = (id: string, name: string, born: number | null, died: number | null = null) => ({ id, name, born, died, years: '', title: '', bio: '', privat: false });
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

  test('registrerer de droppede kanter med årsag (ikke lydløst)', () => {
    expect(model.droppedParentEdges).toEqual([
      { parent: 'p', child: 'c', reason: 'barn_aeldre' },
      { parent: 'p', child: 'late', reason: 'foedt_efter_doed' },
    ]);
  });

  test('ingen droppede kanter → tom liste', () => {
    const ren = buildModel({ ...db, parentChild: db.parentChild.filter((pc) => pc.child === 'ok' || pc.child === 'post') });
    expect(ren.droppedParentEdges).toEqual([]);
  });

  test('flere påstande for samme link giver én registrering', () => {
    const dub = buildModel({ ...db, parentChild: [...db.parentChild, { child: 'late', parent: 'p', union: 'f1' }] });
    expect(dub.droppedParentEdges?.filter((e) => e.child === 'late')).toHaveLength(1);
  });

  test('uændret adfærd: kvalificeret rå datotekst droppes stadig ud fra parseYear-tallet', () => {
    // Forælder "† ca. 1672" giver died=1672; barn født 1678 → droppes som i dag (bevidst, se buildModel).
    const kv = buildModel({
      persons: [
        { ...mkY('p2', 'Forælder', 1640, 1672), years: '1640–ca. 1672' },
        { ...mkY('b2', 'Barn', 1678), years: '* 1678' },
      ],
      unions: [{ id: 'f2', p1: 'p2', p2: null, p2_name: null, year: null }],
      parentChild: [{ child: 'b2', parent: 'p2', union: 'f2' }],
    });
    expect(kv.byId['b2'].parentId).toBeNull();
    expect(kv.droppedParentEdges).toEqual([{ parent: 'p2', child: 'b2', reason: 'foedt_efter_doed' }]);
  });
});
