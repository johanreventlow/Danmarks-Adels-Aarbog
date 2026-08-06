import { describe, it, expect } from 'vitest';
import { joinMediaFakta } from '../media';

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
