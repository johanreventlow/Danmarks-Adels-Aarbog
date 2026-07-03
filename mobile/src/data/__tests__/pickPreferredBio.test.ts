import { pickPreferredBio, NarrativeCand } from '../pickPreferredBio';

const c = (o: Partial<NarrativeCand>): NarrativeCand =>
  ({ narrativeId: 1, tekst: 'x', sourceId: 1, slags: 'DAA-udgave', aar: 2018, udgave: 'DAA 2018-20', ...o });

test('vælger nyeste DAA-udgave (aar DESC)', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, aar: 1982 }), c({ narrativeId: 2, aar: 2018 })])?.narrativeId).toBe(2);
});
test('NULLS LAST: udgave uden aar taber til backfillet 2018', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, aar: null }), c({ narrativeId: 2, aar: 2018 })])?.narrativeId).toBe(2);
});
test('ignorerer tom tekst', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, tekst: '' }), c({ narrativeId: 2, tekst: 'bio' })])?.narrativeId).toBe(2);
});
test('non-DAA giver null (ingen vilkårlig stub)', () => {
  expect(pickPreferredBio([c({ slags: 'genealogi-database', aar: null, udgave: null })])).toBeNull();
});
test('tie-break sourceId DESC så narrativeId DESC', () => {
  expect(pickPreferredBio([c({ narrativeId: 5, sourceId: 1 }), c({ narrativeId: 6, sourceId: 3 })])?.narrativeId).toBe(6);
});
test('tom liste → null', () => {
  expect(pickPreferredBio([])).toBeNull();
});
