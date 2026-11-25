import { describe, expect, it } from 'vitest';
import { erPortraetSlags, MEDIA_SLAGS, MEDIA_SLAGS_STANDARD, mediaCaption, mediaSlagsLabel } from '../mediaVisning';

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
    expect(erPortraetSlags(' Portræt')).toBe(true);
    // gamle teknik-værdier er ikke længere portrætter (databasen oversætter dem til 'portræt', 2026-11-25)
    expect(erPortraetSlags('maleri')).toBe(false);
    expect(erPortraetSlags('portraet')).toBe(false);
    expect(erPortraetSlags('segl')).toBe(false);
    expect(erPortraetSlags('våben')).toBe(false);
    expect(erPortraetSlags(undefined)).toBe(false);
  });
});

describe('MEDIA_SLAGS (billedtype = motiv; spec 2026-11-25-media-slags-ordliste)', () => {
  it('er de seks motiver i fast rækkefølge — samme liste som vocab-rækkerne i db-verify.sql', () => {
    expect(MEDIA_SLAGS.map((s) => s.code)).toEqual(['portræt', 'våben', 'segl', 'medalje', 'gods', 'dokument']);
    expect(MEDIA_SLAGS.map((s) => s.label)).toEqual(['Portræt', 'Våben', 'Segl', 'Medalje', 'Gods', 'Dokument']);
  });
  it('standardvalget ved upload er portræt', () => {
    expect(MEDIA_SLAGS_STANDARD).toBe('portræt');
  });
  it('mediaSlagsLabel viser label for kendte koder og koden selv for ukendte/gamle', () => {
    expect(mediaSlagsLabel('våben')).toBe('Våben');
    expect(mediaSlagsLabel('maleri')).toBe('maleri');
    expect(mediaSlagsLabel(null)).toBe('');
  });
});
