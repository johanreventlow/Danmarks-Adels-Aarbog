import { describe, it, expect } from 'vitest';
import { pickPreferredBio, NarrativeCand } from '../pickPreferredBio';

const c = (o: Partial<NarrativeCand>): NarrativeCand =>
  ({ narrativeId: 1, tekst: 'x', sourceId: 1, slags: 'DAA-udgave', aar: 2018, udgave: 'DAA 2018-20', ...o });

describe('pickPreferredBio', () => {
  it('vælger nyeste DAA-udgave (aar DESC)', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 1, aar: 1982, udgave: 'DAA 1982-84' }),
      c({ narrativeId: 2, aar: 2018, udgave: 'DAA 2018-20' }),
    ]);
    expect(r?.narrativeId).toBe(2);
  });
  it('NULLS LAST: udgave uden aar taber til backfillet 2018', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 1, aar: null, udgave: 'DAA særudgave' }),
      c({ narrativeId: 2, aar: 2018 }),
    ]);
    expect(r?.narrativeId).toBe(2);
  });
  it('ignorerer tom tekst', () => {
    const r = pickPreferredBio([c({ narrativeId: 1, tekst: '' }), c({ narrativeId: 2, tekst: 'bio' })]);
    expect(r?.narrativeId).toBe(2);
  });
  it('non-DAA giver ingen bio (fallback = null, ikke vilkårlig stub)', () => {
    const r = pickPreferredBio([c({ narrativeId: 1, slags: 'genealogi-database', aar: null, udgave: null })]);
    expect(r).toBeNull();
  });
  it('deterministisk tie-break ved ens aar: sourceId DESC, så narrativeId DESC', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 5, sourceId: 1, aar: 2018 }),
      c({ narrativeId: 6, sourceId: 3, aar: 2018 }),
    ]);
    expect(r?.narrativeId).toBe(6);
  });
  it('tom liste → null', () => {
    expect(pickPreferredBio([])).toBeNull();
  });
});
