import { personMemberIds } from '../personMembers';

describe('personMemberIds', () => {
  it('bevarer den kanoniske id, selv når mergedFrom kun indeholder aliaser', () => {
    expect(personMemberIds('10', {
      mergedFrom: [
        { personId: '3', linje: 'III', nr: 3 },
        { personId: '2', linje: 'II', nr: 2 },
      ],
    })).toEqual(['10', '2', '3']);
  });

  it('giver kun canonical id for en ikke-foldet person', () => {
    expect(personMemberIds('10', undefined)).toEqual(['10']);
  });
});
