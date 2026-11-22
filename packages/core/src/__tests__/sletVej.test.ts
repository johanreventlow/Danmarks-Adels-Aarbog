import { describe, expect, it } from 'vitest';
import { sletAarsagTekst, sletKraeverSletHelt, sletKraeverSletHeltTekst, sletVejFraPreview, type SletAarsag } from '../sletVej';

describe('sletVejFraPreview (review 37 P11)', () => {
  it('kun kan_fortrydes === true giver den fortrydelige vej', () => {
    expect(sletVejFraPreview({ kan_fortrydes: true, aarsag: null })).toEqual({ kanFortrydes: true, aarsag: null });
    expect(sletVejFraPreview({ kan_fortrydes: false, aarsag: 'levende' })).toEqual({ kanFortrydes: false, aarsag: 'levende' });
    expect(sletVejFraPreview({ kan_fortrydes: false, aarsag: 'samme_som_skjult' }))
      .toEqual({ kanFortrydes: false, aarsag: 'samme_som_skjult' });
  });
  it.each([
    ['database fra før P11 (intet felt)', { antal_facts: 3 }],
    ['tomt svar', null],
    ['kan_fortrydes som tekst', { kan_fortrydes: 'true' }],
    ['ukendt årsag', { kan_fortrydes: false, aarsag: 'noget_nyt' }],
  ])('fail-closed ved %s', (_navn, raw) => {
    expect(sletVejFraPreview(raw)).toEqual({ kanFortrydes: false, aarsag: 'ukendt' });
  });
});

describe('sletKraeverSletHelt', () => {
  it('læser årsagen fra databasens fejl', () => {
    expect(sletKraeverSletHelt('SLET_KRAEVER_SLET_HELT: privat — personen er ikke offentlig, så den skal slettes helt')).toBe('privat');
    expect(sletKraeverSletHelt('P0001: SLET_KRAEVER_SLET_HELT: staged — …')).toBe('staged');
    expect(sletKraeverSletHelt('SLET_KRAEVER_SLET_HELT')).toBe('ukendt');
    expect(sletKraeverSletHelt('Kun redaktion')).toBeNull();
  });
  it('teksten siger, at intet er slettet, og peger på »Slet helt«', () => {
    const t = sletKraeverSletHeltTekst('levende');
    expect(t).toMatch(/Intet er slettet/);
    expect(t).toMatch(/»Slet helt«/);
    expect(t).toMatch(/nulevende/);
  });
});

it('hver årsag har en forklaring og en vej videre', () => {
  for (const a of ['levende', 'privat', 'staged', 'samme_som_skjult', 'findes_ikke', 'ukendt'] as SletAarsag[]) {
    const t = sletAarsagTekst(a);
    expect(t.hvorfor.length).toBeGreaterThan(10);
    expect(t.hvordan.length).toBeGreaterThan(5);
  }
});
