import { describe, expect, it } from 'vitest';
import { erPortraetSlags, mediaCaption } from '../mediaVisning';

describe('mediaCaption', () => {
  it('samler titel · kunstner · datering og springer tomme over', () => {
    expect(mediaCaption({ titel: 'T', kunstner: 'K', datering: '1900' })).toBe('T · K · 1900');
    expect(mediaCaption({ titel: null, kunstner: null, datering: '1900' })).toBe('1900');
  });
  it('dateringFakt vinder over datering', () => {
    expect(mediaCaption({ titel: 'T', datering: '1900', dateringFakt: 'ca. 1840' })).toBe('T · ca. 1840');
  });
  it('gentager ikke en datering, titlen allerede rummer (uanset mellemrum og store bogstaver)', () => {
    expect(mediaCaption({ titel: 'Hartwig von Reventlows segl 25. februar 1272 (I, 3)', datering: '25. Februar  1272' }))
      .toBe('Hartwig von Reventlows segl 25. februar 1272 (I, 3)');
  });
});

describe('erPortraetSlags', () => {
  it('portrætter ja, segl/medalje/våben nej', () => {
    expect(erPortraetSlags(' Maleri')).toBe(true);
    expect(erPortraetSlags('portraet')).toBe(true);
    expect(erPortraetSlags('segl')).toBe(false);
    expect(erPortraetSlags('våben')).toBe(false);
    expect(erPortraetSlags(undefined)).toBe(false);
  });
});
