import { describe, it, expect } from 'vitest';
import { erRelativDato, oploesRelativDato, relativReferenceStatus } from '../relativeDates';

describe('erRelativDato', () => {
  it('genkender s.m., s.d., s.å./s.a. og »samme …« uanset versaler og mellemrum', () => {
    for (const v of ['29. s.m.', '29 s. m.', '15 s. M.', 'hjemmedøbt 6. febr. s.å.', '3. maj s. A.', 's.d.', 's. D.',
      '6. febr. s.a.', 'død samme Maaned', 'samme dag', 'samme år', '15\ns. M.']) {
      expect(erRelativDato(v), v).toBe(true);
    }
  });

  it('almindelige datoer, »s.st.« og ord der blot begynder med s er ikke relative', () => {
    for (const v of ['29. maj 1700', '21 April 1644', 'i Kiel s.st.', 's. Andersen', 'Hans. M. Kirke', '1749', '']) {
      expect(erRelativDato(v), v).toBe(false);
    }
  });
});

describe('oploesRelativDato', () => {
  it('opløser ud fra referencen og bevarer resten af teksten', () => {
    expect(oploesRelativDato('15 s. M.', '3. Maj 1700')).toBe('15 maj 1700');
    expect(oploesRelativDato('29. s.m.', '21. april 1644')).toBe('29. april 1644');
    expect(oploesRelativDato('hjemmedøbt 6. febr. s.å.', '21 April 1644')).toBe('hjemmedøbt 6. febr. 1644');
    expect(oploesRelativDato('s.d.', '3. maj 1700')).toBe('3. maj 1700');
    expect(oploesRelativDato('6. febr. s.å. i Slesvig Domkirke', 'april 1644')).toBe('6. febr. 1644 i Slesvig Domkirke');
    expect(oploesRelativDato('29. s.m.', 'april 1644')).toBe('29. april 1644');
    expect(oploesRelativDato('6. febr. s.å.', '1644')).toBe('6. febr. 1644');
    expect(oploesRelativDato('3. maj s. A.', 'Kiel, 3 Jan. 1700')).toBe('3. maj 1700');
    expect(oploesRelativDato('begr. samme måned', '3. maj 1700')).toBe('begr. maj 1700');
    // to relative led i samme værdi (vaerdi_tekst + date_raw) opløses begge
    expect(oploesRelativDato('hjemmedøbt 6. febr. s.å. i X Kirke, 6. febr. s.å.', '21. april 1644'))
      .toBe('hjemmedøbt 6. febr. 1644 i X Kirke, 6. febr. 1644');
  });

  it('referencen må gentage samme dato (vaerdi_tekst + date_raw)', () => {
    expect(oploesRelativDato('29. s.m.', 'Sandbjerg 21. april 1644, 21. april 1644')).toBe('29. april 1644');
  });

  it('kan ikke opløses: mangler, mangler den nødvendige del, er selv relativ, usikker eller flertydig', () => {
    expect(oploesRelativDato('29. s.m.', '1644')).toBeNull();
    expect(oploesRelativDato('29. s.m.', null)).toBeNull();
    expect(oploesRelativDato('29. s.m.', '5. s.m.')).toBeNull();
    expect(oploesRelativDato('s.d.', 'april 1644')).toBeNull();
    expect(oploesRelativDato('s.å.', 'ung')).toBeNull();
    expect(oploesRelativDato('s.å.', '')).toBeNull();
    // usikker reference giver ikke en sikker dato (mit valg)
    expect(oploesRelativDato('6. febr. s.å.', 'ca. 1644')).toBeNull();
    expect(oploesRelativDato('6. febr. s.å.', 'o. 1644')).toBeNull();
    expect(oploesRelativDato('6. febr. s.å.', '1644?')).toBeNull();
    expect(oploesRelativDato('6. febr. s.å.', 'før 1644')).toBeNull();
    expect(oploesRelativDato('29. s.m.', '21.-22. april 1644')).toBeNull();
    expect(oploesRelativDato('6. febr. s.å.', '1643 eller 1644')).toBeNull();
    // to forskellige datoer i referencen
    expect(oploesRelativDato('29. s.m.', '21. april 1644, 21. maj 1644')).toBeNull();
    expect(oploesRelativDato('6. febr. s.å.', '1643, 1644')).toBeNull();
    // en ikke-relativ værdi returneres uændret
    expect(oploesRelativDato('29. maj 1700', null)).toBe('29. maj 1700');
  });
});

describe('oploesRelativDato: flertydighed og umulige datoer', () => {
  it('et led, der kan henvise til en tidligere dato i samme tekst med andet resultat, opløses ikke', () => {
    // »s.d.« efter bisættelsen = bisættelsens dag, ikke dødsdagen
    expect(oploesRelativDato('bisat 5. april s.å. og begravet s.d.', '31. marts 1928')).toBeNull();
    // »27. s.m.« efter en eksplicit dato i en anden måned
    expect(oploesRelativDato('bisat 27. s.m., begravet 19. sept. 1924, 27. s.m.', '22. nov. 1922')).toBeNull();
    // »s.m.« efter »5. april s.å.« når referencen er marts
    expect(oploesRelativDato('bisat 5. april s.å., begravet 9. s.m.', '31. marts 1928')).toBeNull();
    // et eksplicit år uden måned foran »s.m.«
    expect(oploesRelativDato('1644, døbt 29. s.m.', '21. april 1644')).toBeNull();
  });

  it('kæden giver samme resultat som referencen → opløses', () => {
    expect(oploesRelativDato('bisat 27. s.m. og begravet 29. s.m.', '22. jan. 1923'))
      .toBe('bisat 27. januar 1923 og begravet 29. januar 1923');
    expect(oploesRelativDato('hjemmedøbt 10. febr. 1922, 10. febr. s.å.', '12. jan. 1922'))
      .toBe('hjemmedøbt 10. febr. 1922, 10. febr. 1922');
    expect(oploesRelativDato('bisat 5. marts s.å., derefter bisat 1746', '7. jan. 1743'))
      .toBe('bisat 5. marts 1743, derefter bisat 1746');
  });

  it('ikkeFoerReference: en opløst dato før referencen (dåb før fødsel) opløses ikke', () => {
    expect(oploesRelativDato('fremstillet, 25. juli s.å.', '28. nov. 1883')).toBe('fremstillet, 25. juli 1883');
    expect(oploesRelativDato('fremstillet, 25. juli s.å.', '28. nov. 1883', { ikkeFoerReference: true })).toBeNull();
    expect(oploesRelativDato('15. s.m.', '21. april 1644', { ikkeFoerReference: true })).toBeNull();
    expect(oploesRelativDato('21. s.m.', '21. april 1644', { ikkeFoerReference: true })).toBe('21. april 1644');
    expect(oploesRelativDato('6. maj s.å.', '21. april 1644', { ikkeFoerReference: true })).toBe('6. maj 1644');
    expect(oploesRelativDato('s.d.', '21. april 1644', { ikkeFoerReference: true })).toBe('21. april 1644');
  });
});

describe('relativReferenceStatus', () => {
  it('skelner manglende, relativ, usikker og flertydig reference', () => {
    expect(relativReferenceStatus('21. april 1644')).toBe('ok');
    expect(relativReferenceStatus('1644')).toBe('ok');
    expect(relativReferenceStatus(null)).toBe('mangler');
    expect(relativReferenceStatus('ung')).toBe('mangler');
    expect(relativReferenceStatus('5. s.m.')).toBe('relativ');
    expect(relativReferenceStatus('ca. 1644')).toBe('usikker');
    expect(relativReferenceStatus('1643, 1644')).toBe('flertydig');
  });
});
