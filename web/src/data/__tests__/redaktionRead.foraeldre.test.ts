import { describe, it, expect } from 'vitest';
import { buildForaeldreSlot } from '../redaktionRead';

describe('buildForaeldreSlot — konkurrerende forældre-påstande (Problem 2)', () => {
  const assertions = [
    { id: 1, objekt_id: 100 }, // udgave 1: familie 100
    { id: 2, objekt_id: 200 }, // udgave 2: familie 200
    { id: 3, objekt_id: null }, // ikke-familie-assertion (skal ignoreres)
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
    expect(slot.factId).toBe(50);
    expect(slot.status).toBe('omstridt');
    expect(slot.paastande).toHaveLength(2); // objekt_id=null ignoreret
    const p1 = slot.paastande[0];
    expect(p1).toMatchObject({ assertionId: 1, familyId: 100, udgave: 'DAA 1939', side: 's.490', valgt: true });
    expect(p1.foraeldre.map((f) => f.navn)).toEqual(['Far A', 'Mor A']);
    const p2 = slot.paastande[1];
    expect(p2).toMatchObject({ assertionId: 2, familyId: 200, udgave: 'Særudgave', valgt: false }); // udgave falder tilbage til titel
    expect(p2.foraeldre.map((f) => f.navn)).toEqual(['Far B', '(ukendt)']); // NULL-navn → (ukendt)
  });

  it('ingen conclusion → status null, ingen valgt', () => {
    const slot = buildForaeldreSlot(50, assertions.slice(0, 1), citations.slice(0, 1), null, partners);
    expect(slot.status).toBeNull();
    expect(slot.paastande[0].valgt).toBe(false);
  });

  it('tom slot (ingen assertions) → tom påstands-liste', () => {
    expect(buildForaeldreSlot(50, [], [], null, [])).toEqual({ factId: 50, status: null, paastande: [] });
  });
});
