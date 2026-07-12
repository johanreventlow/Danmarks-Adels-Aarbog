import { selectMeId, type State } from '../useStore';

// selectMeId læser kun meId + canonicalIdById — et minimalt udsnit af State er nok
// (undgår at skulle stille hele store-formen op i hver test).
type MeSlice = Pick<State, 'meId' | 'canonicalIdById'>;
const s = (o: MeSlice): State => o as State;

describe('selectMeId', () => {
  test('alias-id → kanonisk id via canonicalIdById', () => {
    expect(selectMeId(s({ meId: 'a', canonicalIdById: { a: 'C' } }))).toBe('C');
  });

  test('id ukendt i (evt. tomt) canonicalIdById → rå id uændret', () => {
    expect(selectMeId(s({ meId: 'x', canonicalIdById: {} }))).toBe('x');
    expect(selectMeId(s({ meId: 'x', canonicalIdById: { andet: 'y' } }))).toBe('x');
  });

  test('meId = null → null (uanset canonicalIdById)', () => {
    expect(selectMeId(s({ meId: null, canonicalIdById: { a: 'C' } }))).toBeNull();
  });
});
