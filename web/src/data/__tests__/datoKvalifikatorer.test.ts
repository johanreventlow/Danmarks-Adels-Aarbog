import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { STORY_DATO_KVALIFIKATORER } from '../datoKvalifikatorer';

// Review 37 R37B-4: valgfeltets værdier skal være præcis dem, databasens CHECK tillader — ellers kan editoren
// tilbyde en værdi, som gemningen afviser (DATO_KVALIFIKATOR_UGYLDIG), eller mangle en gyldig.
describe('STORY_DATO_KVALIFIKATORER (R37B-4)', () => {
  it('svarer til story_date_qualifier_chk i schema.sql', () => {
    const schema = readFileSync(resolve(__dirname, '../../../../schema.sql'), 'utf8');
    const m = schema.match(/'story_date_qualifier_chk',\s*\$c\$date_qualifier IN \(([^)]*)\)\$c\$/);
    expect(m).not.toBeNull();
    const tilladte = [...m![1].matchAll(/'([^']+)'/g)].map((x) => x[1]).sort();
    const valg = STORY_DATO_KVALIFIKATORER.map(([v]) => v).filter(Boolean).sort();
    expect(valg).toEqual(tilladte);
  });

  it('har et tomt valg (ikke sat) og unikke danske etiketter', () => {
    expect(STORY_DATO_KVALIFIKATORER[0][0]).toBe('');
    const etiketter = STORY_DATO_KVALIFIKATORER.map(([, l]) => l);
    expect(new Set(etiketter).size).toBe(etiketter.length);
  });
});
