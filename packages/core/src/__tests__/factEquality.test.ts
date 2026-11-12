import { describe, it, expect } from 'vitest';
import { faktaVaerdierEns, erTomFaktaVaerdi, DATO_TYPER, ENKELTVAERDI_TYPER } from '../factEquality';

const ens = (t: string, a: string, b: string) => faktaVaerdierEns(t, a, b);

describe('faktaVaerdierEns', () => {
  it('ligner datoer på tværs af udgavers skrivemåde', () => {
    expect(ens('fødsel', '21. april 1644', '21 April 1644')).toBe(true);
    expect(ens('død', '21. juli 1708', '21 Juli 1708')).toBe(true);
    expect(ens('død', '† 21. juli 1708', '21 Juli 1708')).toBe(true);
    expect(ens('fødsel', 'ca. 1690', 'o. 1690')).toBe(true);
  });
  it('er konservativ: tvivl er ikke lighed', () => {
    expect(ens('fødsel', '1.12.1700', '11.2.1700')).toBe(false);
    expect(ens('fødsel', '1644?', '1644')).toBe(false);
    expect(ens('fødsel', 'ca. 1690', '1690')).toBe(false);
    expect(ens('død', '15. febr. 1878 på Pronstorf', '15. febr. 1878')).toBe(false);
    expect(ens('navn', 'Ditlev', 'Detlef')).toBe(false);
    expect(ens('adling', '1767?', '1767')).toBe(false);
    expect(ens('navn', 'Ditlev?', 'Ditlev')).toBe(false);
    expect(ens('dekoration', 'Kmhr.', 'Kammerherre')).toBe(false);
  });
  it('ligner tekst uden hensyn til store/små bogstaver', () => {
    expect(ens('titel', 'Greve', 'greve')).toBe(true);
  });
  it('tomme værdier er aldrig ens', () => {
    expect(erTomFaktaVaerdi('—')).toBe(true);
    expect(erTomFaktaVaerdi(' .; ')).toBe(true);
    expect(erTomFaktaVaerdi('Greve')).toBe(false);
    expect(ens('begravelse', '—', '—')).toBe(false);
  });
  it('eksporterer typesæt', () => {
    expect(DATO_TYPER.size).toBe(4);
    for (const t of ['fødsel', 'dåb', 'død', 'begravelse']) expect(DATO_TYPER.has(t)).toBe(true);
    expect(ENKELTVAERDI_TYPER.has('adling')).toBe(true);
    expect(ENKELTVAERDI_TYPER.has('titel')).toBe(false);
  });
});
