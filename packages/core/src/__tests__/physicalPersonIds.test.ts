import { physicalPersonIds } from '../physicalPersonIds';

describe('physicalPersonIds', () => {
  it('returnerer den kanoniske person først og aliaser deterministisk sorteret', () => {
    expect(physicalPersonIds('10', [
      { personId: '3' },
      { personId: '10' },
      { personId: '2' },
    ])).toEqual(['10', '2', '3']);
  });

  it('deduplikerer aliaser og ignorerer tomme person-id-er', () => {
    expect(physicalPersonIds('10', [
      { personId: '2' },
      { personId: '2' },
      { personId: '' },
    ])).toEqual(['10', '2']);
  });

  it('returnerer kun den kanoniske person uden proveniens', () => {
    expect(physicalPersonIds('10')).toEqual(['10']);
  });
});
