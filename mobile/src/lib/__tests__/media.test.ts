import { pickPortrait } from '../media';
import type { RawMedia } from '../../data/types';

const m = (id: number, slags: string): RawMedia => ({ id, slags });

describe('pickPortrait', () => {
  test('vælger portræt-egnet slags frem for øvrige', () => {
    expect(pickPortrait([m(1, 'segl'), m(2, 'maleri'), m(3, 'dokument')])?.id).toBe(2);
  });

  test('normaliserer slags (case + trim), så "Maleri"/" Portræt " genkendes', () => {
    expect(pickPortrait([m(1, 'segl'), m(2, 'Maleri')])?.id).toBe(2);
    expect(pickPortrait([m(1, 'dokument'), m(2, ' Portræt ')])?.id).toBe(2);
  });

  test('falder tilbage til første medie når intet er portræt-egnet', () => {
    expect(pickPortrait([m(7, 'segl'), m(8, 'dokument')])?.id).toBe(7);
  });

  test('tomt input → null', () => {
    expect(pickPortrait([])).toBeNull();
  });
});
