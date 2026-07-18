import { buildFamilyGraph, type RawFamilyMember } from '../buildFamilyGraph';

const M = (o: Partial<RawFamilyMember> & Pick<RawFamilyMember, 'family_id' | 'person_id' | 'rolle'>): RawFamilyMember => o;

describe('buildFamilyGraph', () => {
  it('en familie med to forældre + to børn → union + parentChild pr. barn×forælder', () => {
    const { unions, parentChild } = buildFamilyGraph([
      M({ family_id: 1, person_id: 'far', rolle: 'partner' }),
      M({ family_id: 1, person_id: 'mor', rolle: 'partner' }),
      M({ family_id: 1, person_id: 'barn1', rolle: 'barn' }),
      M({ family_id: 1, person_id: 'barn2', rolle: 'barn' }),
    ]);
    expect(unions).toEqual([{ id: 'f1', p1: 'far', p2: 'mor', p2_name: null, year: null }]);
    expect(parentChild).toEqual(
      expect.arrayContaining([
        { child: 'barn1', parent: 'far', union: 'f1' },
        { child: 'barn1', parent: 'mor', union: 'f1' },
        { child: 'barn2', parent: 'far', union: 'f1' },
        { child: 'barn2', parent: 'mor', union: 'f1' },
      ]),
    );
    expect(parentChild).toHaveLength(4);
  });

  it('kun én forælder → union med p2=null, stadig parentChild-kanter', () => {
    const { unions, parentChild } = buildFamilyGraph([
      M({ family_id: 2, person_id: 'mor', rolle: 'partner' }),
      M({ family_id: 2, person_id: 'barn', rolle: 'barn' }),
    ]);
    expect(unions).toEqual([{ id: 'f2', p1: 'mor', p2: null, p2_name: null, year: null }]);
    expect(parentChild).toEqual([{ child: 'barn', parent: 'mor', union: 'f2' }]);
  });

  it('ingen forældre → ingen union, ingen parentChild', () => {
    const { unions, parentChild } = buildFamilyGraph([
      M({ family_id: 3, person_id: 'barn', rolle: 'barn' }),
    ]);
    expect(unions).toEqual([]);
    expect(parentChild).toEqual([]);
  });

  it('andre roller (fx adopteret_barn) ignoreres', () => {
    const { parentChild } = buildFamilyGraph([
      M({ family_id: 4, person_id: 'far', rolle: 'partner' }),
      M({ family_id: 4, person_id: 'stedbarn', rolle: 'stedbarn' }),
    ]);
    expect(parentChild).toEqual([]);
  });

  it('rolle-tekst er case-insensitiv', () => {
    const { unions } = buildFamilyGraph([
      M({ family_id: 5, person_id: 'far', rolle: 'PARTNER' }),
      M({ family_id: 5, person_id: 'barn', rolle: 'Barn' }),
    ]);
    expect(unions).toEqual([{ id: 'f5', p1: 'far', p2: null, p2_name: null, year: null }]);
  });
});
