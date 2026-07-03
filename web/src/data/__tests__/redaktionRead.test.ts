import { describe, it, expect } from 'vitest';
import { mapFamilieRows } from '../redaktionRead';
import type { Model } from '../types';

// Minimal model-stub: kun byId.{name,years} bruges af mapFamilieRows (navnAf/aarAf).
const model = {
  byId: {
    '2': { name: 'Anna von Brockdorff', years: '1650–1700' },
    '3': { name: 'Conrad', years: '* 1675' },
    '4': { name: 'Detlef', years: '† 1712' },
  },
} as unknown as Model;

describe('mapFamilieRows — år på partnere og børn', () => {
  const families = [{ id: 10, type: 'vielse' }];
  const members = [
    { family_id: 10, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 3, rolle: 'barn', ordinal: 1, konfidens: 'sikker' },
    { family_id: 10, person_id: 4, rolle: 'barn', ordinal: 2, konfidens: null },
  ];

  it('partner får navn + aar fra model.byId[pid].years', () => {
    const fam = mapFamilieRows('1', families, members, model);
    expect(fam.somPartner).toHaveLength(1);
    expect(fam.somPartner[0].partnere).toEqual([
      { personId: '2', navn: 'Anna von Brockdorff', aar: '1650–1700', konfidens: null, ordinal: null },
    ]);
  });

  it('børn får aar (fødsels/dødsår) fra model, i visningsrækkefølge', () => {
    const fam = mapFamilieRows('1', families, members, model);
    expect(fam.somPartner[0].boern).toEqual([
      { personId: '3', navn: 'Conrad', aar: '* 1675', rolle: 'barn', konfidens: 'sikker', ordinal: 1 },
      { personId: '4', navn: 'Detlef', aar: '† 1712', rolle: 'barn', konfidens: null, ordinal: 2 },
    ]);
  });

  it('aar er tom streng når personen mangler i model (graceful)', () => {
    const fam = mapFamilieRows('1', families,
      [{ family_id: 10, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
       { family_id: 10, person_id: 99, rolle: 'barn', ordinal: 1, konfidens: null }],
      model);
    expect(fam.somPartner[0].boern[0]).toMatchObject({ personId: '99', navn: '#99', aar: '' });
  });
});
