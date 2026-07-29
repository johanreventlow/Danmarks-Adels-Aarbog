import { describe, expect, test } from 'vitest';
import { effektivtSlaegtsnavn, findSlaegtsrod } from '../slaegtsrod';

// Mirror af DB'ens lineage_effective_slaegtsnavn(): slægtsnavnet bor på slægts-roden og arves
// ned ad parent_lineage_id. Klienten skal folde det samme, ellers viser præsenslisten tomt
// efter at slaegtsnavn er ryddet på grenene.

const REVENTLOW = [
  { id: 6, slaegtsnavn: 'Reventlow', parent_lineage_id: null },
  { id: 1, slaegtsnavn: null, parent_lineage_id: 6 },
  { id: 2, slaegtsnavn: null, parent_lineage_id: 6 },
];

describe('effektivtSlaegtsnavn', () => {
  test('gren arver roden', () => {
    expect(effektivtSlaegtsnavn(REVENTLOW, 1)).toBe('Reventlow');
  });

  test('roden bærer sit eget', () => {
    expect(effektivtSlaegtsnavn(REVENTLOW, 6)).toBe('Reventlow');
  });

  test('gren med EGET navn vinder over rodens (undergren der har skiftet navn)', () => {
    const rows = [...REVENTLOW, { id: 7, slaegtsnavn: 'Haugwitz-Hardenberg-Reventlow', parent_lineage_id: 1 }];
    expect(effektivtSlaegtsnavn(rows, 7)).toBe('Haugwitz-Hardenberg-Reventlow');
  });

  test('før migrationen — gren bærer selv navnet, ingen rod', () => {
    expect(effektivtSlaegtsnavn([{ id: 1, slaegtsnavn: 'Reventlow', parent_lineage_id: null }], 1))
      .toBe('Reventlow');
  });

  test('ukendt id og navnløs kæde giver null, ikke kast', () => {
    expect(effektivtSlaegtsnavn(REVENTLOW, 99)).toBeNull();
    expect(effektivtSlaegtsnavn([{ id: 3, slaegtsnavn: null, parent_lineage_id: null }], 3)).toBeNull();
  });

  test('cyklus terminerer i stedet for at hænge', () => {
    const cyklus = [
      { id: 1, slaegtsnavn: null, parent_lineage_id: 2 },
      { id: 2, slaegtsnavn: null, parent_lineage_id: 1 },
    ];
    expect(effektivtSlaegtsnavn(cyklus, 1)).toBeNull();
  });
});

describe('findSlaegtsrod', () => {
  test('finder roden efter migrationen', () => {
    expect(findSlaegtsrod(REVENTLOW)).toBe(6);
  });

  test('falder tilbage til den laveste navnbærende rod før migrationen', () => {
    // Fem sideordnede grene med hvert sit slaegtsnavn = tilstanden før B2.
    const foer = [1, 2, 3].map((id) => ({ id, slaegtsnavn: 'Reventlow', parent_lineage_id: null }));
    expect(findSlaegtsrod(foer)).toBe(1);
  });

  test('ingen navnbærende rod → null', () => {
    expect(findSlaegtsrod([{ id: 1, slaegtsnavn: null, parent_lineage_id: null }])).toBeNull();
  });

  test('grene uden eget navn er aldrig roden', () => {
    expect(findSlaegtsrod([{ id: 1, slaegtsnavn: null, parent_lineage_id: 6 }])).toBeNull();
  });
});
