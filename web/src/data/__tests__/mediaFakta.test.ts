import { describe, it, expect } from 'vitest';
import { joinMediaFakta, mediaCaption, mediaFaktaFelter } from '../media';

describe('joinMediaFakta', () => {
  it('samler valgt assertion pr. faktatype pr. medie', () => {
    const out = joinMediaFakta(
      [{ id: 10, subjekt_id: 5, faktatype: 'kreditlinje' }],
      [{ id: 100, target_id: 10, vaerdi_tekst: 'Luise … | Lizenz: CC BY-SA 4.0', date_min: null, date_max: null, date_qualifier: null, date_raw: null }],
      [{ target_id: 10, valgt_assertion_id: 100 }],
    );
    expect(out.get('5')?.kreditlinje?.vaerdi).toContain('Lizenz');
    expect(out.get('5')?.kreditlinje?.factId).toBe('10');
  });
  it('udelader fact uden valgt assertion', () => {
    const out = joinMediaFakta([{ id: 10, subjekt_id: 5, faktatype: 'teknik' }], [], []);
    expect(out.get('5')?.teknik).toBeUndefined();
  });
  it('udelader tilbagetrukket fakt (status-filter, MM-02)', () => {
    // fetchMediaFakta filtrerer .eq('status','afklaret') i selecten; join-funktionen skal
    // ALLIGEVEL forsvare sig: en conclusion-række med status !== 'afklaret' ignoreres.
    const out = joinMediaFakta(
      [{ id: 10, subjekt_id: 5, faktatype: 'fotograf' }],
      [{ id: 100, target_id: 10, vaerdi_tekst: 'X', date_min: null, date_max: null, date_qualifier: null, date_raw: null }],
      [{ target_id: 10, valgt_assertion_id: 100, status: 'tilbagetrukket' }],
    );
    expect(out.get('5')?.fotograf).toBeUndefined();
  });
  it('bevarer date-felter på datering', () => {
    const out = joinMediaFakta(
      [{ id: 11, subjekt_id: 5, faktatype: 'datering' }],
      [{ id: 101, target_id: 11, vaerdi_tekst: 'ca. 1840', date_min: '1835-01-01', date_max: '1845-12-31', date_qualifier: 'ca', date_raw: 'ca. 1840' }],
      [{ target_id: 11, valgt_assertion_id: 101 }],
    );
    expect(out.get('5')?.datering?.dateMin).toBe('1835-01-01');
  });
});

describe('mediaCaption', () => {
  it('bruger dateringFakt før datering (Global Constraint: fakt vinder)', () => {
    expect(mediaCaption({ titel: 'T', kunstner: null, datering: '1900', dateringFakt: 'ca. 1840' })).toContain('ca. 1840');
    expect(mediaCaption({ titel: 'T', kunstner: null, datering: '1900', dateringFakt: 'ca. 1840' })).not.toContain('1900');
  });
  it('falder tilbage til datering når ingen dateringFakt', () => {
    expect(mediaCaption({ titel: 'T', kunstner: null, datering: '1900', dateringFakt: null })).toContain('1900');
  });
});

describe('mediaFaktaFelter', () => {
  it('mapper fakta-felter til MediaItem-berigelsen, dateringFakt bruger dateRaw før vaerdi', () => {
    const fakta = {
      alt_tekst: { factId: '1', vaerdi: 'En dame i sort', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      kreditlinje: { factId: '2', vaerdi: 'Luise … | Lizenz: CC BY-SA 4.0', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      kilde_url: { factId: '3', vaerdi: 'https://example.org/x', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      kilde_institution: { factId: '4', vaerdi: 'Deutsche Digitale Bibliothek', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      beskrivelse: { factId: '5', vaerdi: 'Et portræt fra 1840.', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      teknik: { factId: '6', vaerdi: 'Olie på lærred', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      fysiske_maal: { factId: '7', vaerdi: '80x60 cm', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null },
      datering: { factId: '8', vaerdi: '1840', dateMin: '1835-01-01', dateMax: '1845-12-31', dateQualifier: 'about', dateRaw: 'ca. 1840' },
    };
    expect(mediaFaktaFelter(fakta)).toEqual({
      altTekst: 'En dame i sort',
      kreditlinje: 'Luise … | Lizenz: CC BY-SA 4.0',
      kildeUrl: 'https://example.org/x',
      kildeInstitution: 'Deutsche Digitale Bibliothek',
      beskrivelse: 'Et portræt fra 1840.',
      teknik: 'Olie på lærred',
      fysiskeMaal: '80x60 cm',
      dateringFakt: 'ca. 1840',
    });
  });
  it('dateringFakt falder tilbage til vaerdi når dateRaw mangler', () => {
    const fakta = { datering: { factId: '8', vaerdi: '1840', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null } };
    expect(mediaFaktaFelter(fakta).dateringFakt).toBe('1840');
  });
  it('ingen fakta giver alle felter null', () => {
    expect(mediaFaktaFelter(undefined)).toEqual({
      altTekst: null, kreditlinje: null, kildeUrl: null, kildeInstitution: null,
      beskrivelse: null, teknik: null, fysiskeMaal: null, dateringFakt: null,
    });
  });
});
