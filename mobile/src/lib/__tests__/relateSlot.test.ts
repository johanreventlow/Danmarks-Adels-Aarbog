import { chooseMeSlot } from '../relateSlot';

describe('chooseMeSlot', () => {
  test('begge felter tomme → A', () => {
    expect(chooseMeSlot(null, null, 'me')).toBe('A');
  });

  test('A sat, B tom → B (buggens eksakte scenarie: profil-navigation fylder A)', () => {
    expect(chooseMeSlot('x', null, 'me')).toBe('B');
  });

  test('A tom, B sat → A', () => {
    expect(chooseMeSlot(null, 'y', 'me')).toBe('A');
  });

  test('begge sat af andre (ingen er mig) → B', () => {
    expect(chooseMeSlot('x', 'y', 'me')).toBe('B');
  });

  test('mig allerede i A → null', () => {
    expect(chooseMeSlot('me', 'y', 'me')).toBeNull();
  });

  test('mig allerede i B → null', () => {
    expect(chooseMeSlot('x', 'me', 'me')).toBeNull();
  });
});
