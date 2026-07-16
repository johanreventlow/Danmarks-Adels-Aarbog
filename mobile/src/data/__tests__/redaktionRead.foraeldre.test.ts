import { buildForaeldreSlot } from '../redaktionRead';

describe('buildForaeldreSlot — konkurrerende forældre-påstande (Problem 2)', () => {
  const assertions = [
    { id: 1, objekt_id: 100 },
    { id: 2, objekt_id: 200 },
    { id: 3, objekt_id: null },
  ];
  const citations = [
    { assertion_id: 1, side: 's.490', citat_tekst: 'udg1', source: { udgave: 'DAA 1939', titel: null } },
    { assertion_id: 2, side: 's.12', citat_tekst: 'udg2', source: { udgave: null, titel: 'Særudgave' } },
  ];
  const partners = [
    { family_id: 100, person_id: 11, visning_navn: 'Far A' },
    { family_id: 100, person_id: 12, visning_navn: 'Mor A' },
    { family_id: 200, person_id: 21, visning_navn: 'Far B' },
    { family_id: 200, person_id: 22, visning_navn: null },
  ];

  it('samler påstande m. forældre, kilde-badge og valgt-markering', () => {
    const slot = buildForaeldreSlot(50, assertions, citations, { valgt_assertion_id: 1, status: 'omstridt' }, partners);
    expect(slot.status).toBe('omstridt');
    expect(slot.paastande).toHaveLength(2);
    expect(slot.paastande[0]).toMatchObject({ assertionId: 1, familyId: 100, udgave: 'DAA 1939', valgt: true });
    expect(slot.paastande[0].foraeldre.map((f) => f.navn)).toEqual(['Far A', 'Mor A']);
    expect(slot.paastande[1]).toMatchObject({ udgave: 'Særudgave', valgt: false });
    expect(slot.paastande[1].foraeldre.map((f) => f.navn)).toEqual(['Far B', '(ukendt)']);
  });

  it('ingen conclusion → status null, ingen valgt; tom slot → tom liste', () => {
    expect(buildForaeldreSlot(50, assertions.slice(0, 1), citations.slice(0, 1), null, partners).paastande[0].valgt).toBe(false);
    expect(buildForaeldreSlot(50, [], [], null, [])).toEqual({ factId: 50, status: null, paastande: [] });
  });
});
