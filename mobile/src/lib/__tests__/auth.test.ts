import { mapProfileRow } from '../auth';

describe('mapProfileRow', () => {
  it('defaulter til medlem når row mangler', () => {
    expect(mapProfileRow(null)).toEqual({ rolle: 'medlem', reventlowPersonId: null });
  });
  it('mapper redaktion-row', () => {
    expect(mapProfileRow({ rolle: 'redaktion', reventlow_person_id: 42 }))
      .toEqual({ rolle: 'redaktion', reventlowPersonId: '42' });
  });
  it('ukendt rolle falder til medlem', () => {
    expect(mapProfileRow({ rolle: 'noget', reventlow_person_id: null }).rolle).toBe('medlem');
  });
});
