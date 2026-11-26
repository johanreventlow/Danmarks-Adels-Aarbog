import { describe, expect, it } from 'vitest';
import { faktaTypeNavn, grupperKunI, udgaveNoteTekst } from '../faktaVisning';

const U20 = { sourceId: '20', label: 'DAA 2018-20', aar: 2018 };
const U10 = { sourceId: '10', label: 'DAA 1939', aar: 1939 };

describe('faktaVisning (flyttet fra web PersonFakta, batch 7)', () => {
  it('faktanavne på dansk; ukendte typer med stort begyndelsesbogstav', () => {
    expect(['fødsel', 'dåb', 'død', 'begravelse', 'floruit', 'embede'].map(faktaTypeNavn))
      .toEqual(['Født', 'Døbt', 'Død', 'Begravet', 'Nævnt', 'Embede']);
  });
  it('notetekst for enighed og uenighed', () => {
    expect(udgaveNoteTekst({ art: 'enig', udgave: U10 })).toBe('✓ også i DAA 1939');
    expect(udgaveNoteTekst({ art: 'skriver', udgave: U10, vaerdier: ['1701', 'ca. 1700'] })).toBe('DAA 1939 skriver: 1701; ca. 1700');
  });
  it('»Kun i …« grupperet pr. udgave i indgangsrækkefølgen', () => {
    const g = grupperKunI([
      { udgave: U20, faktatype: 'dåb', vaerdier: ['a'] },
      { udgave: U10, faktatype: 'titel', vaerdier: ['b'] },
      { udgave: U20, faktatype: 'død', vaerdier: ['c'] },
    ]);
    expect(g.map((x) => [x.udgave.sourceId, x.raekker.map((r) => r.faktatype)])).toEqual([['20', ['dåb', 'død']], ['10', ['titel']]]);
  });
});
