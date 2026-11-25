import { describe, it, expect } from 'vitest';
import { buildPersonFacts, datoErDobbelt, datoVisesIForvejen, factSource, factValue, FAKTA_UDELADT, type PublicPersonFactRow } from '../personFacts';

let next = 1;
const row = (o: Partial<PublicPersonFactRow> = {}): PublicPersonFactRow => {
  const id = next++;
  return {
    person_id: 1,
    fact_id: id,
    faktatype: 'død',
    conclusion_status: 'afklaret',
    assertion_id: id,
    chosen: true,
    vaerdi_tekst: null,
    date_raw: '1850',
    date_min: null,
    date_max: null,
    date_qualifier: null,
    date_certainty: null,
    source_id: 1,
    source_label: 'DAA 2018-20',
    side: null,
    record_ref: null,
    record_label: null,
    citation_label: null,
    ...o,
  };
};

describe('buildPersonFacts', () => {
  it('udelader forældrefamilie og forældre_ukendt', () => {
    expect(FAKTA_UDELADT).toEqual(['forældrefamilie', 'forældre_ukendt']);
    const v = buildPersonFacts([row({ faktatype: 'forældrefamilie' }), row({ faktatype: 'forældre_ukendt' }), row({ faktatype: 'død' })]);
    expect(v.map((f) => f.faktatype)).toEqual(['død']);
  });

  it('rækkefølge: typeorden, så date_min (null sidst), så fact_id; ukendte typer sidst', () => {
    const v = buildPersonFacts([
      row({ fact_id: 50, assertion_id: 50, faktatype: 'begravelse' }),
      row({ fact_id: 40, assertion_id: 40, faktatype: 'ukendt_type' }),
      row({ fact_id: 30, assertion_id: 30, faktatype: 'titel', date_min: null }),
      row({ fact_id: 31, assertion_id: 31, faktatype: 'titel', date_min: '1700-01-01' }),
      row({ fact_id: 20, assertion_id: 20, faktatype: 'fødsel' }),
      row({ fact_id: 10, assertion_id: 10, faktatype: 'navn', vaerdi_tekst: 'Anna', date_raw: null }),
    ]);
    expect(v.map((f) => f.factId)).toEqual(['10', '20', '31', '30', '50', '40']);
    const order = ['navn', 'tilnavn', 'fødsel', 'dåb', 'titel', 'dekoration', 'adling', 'floruit', 'klosterindgang',
      'overhoved', 'død', 'dødsårsag', 'begravelse'];
    const all = buildPersonFacts([...order].reverse().map((t) => row({ faktatype: t })));
    expect(all.map((f) => f.faktatype)).toEqual(order);
  });

  it('værdi: tekst og dato sammen, ellers den ene, ellers —', () => {
    const v = buildPersonFacts([
      row({ fact_id: 1, assertion_id: 1, faktatype: 'død', vaerdi_tekst: 'Kbh.', date_raw: '1850' }),
      row({ fact_id: 2, assertion_id: 2, faktatype: 'titel', vaerdi_tekst: 'Kammerherre', date_raw: null }),
      row({ fact_id: 3, assertion_id: 3, faktatype: 'dåb', vaerdi_tekst: null, date_raw: null }),
    ]);
    const byType = Object.fromEntries(v.map((f) => [f.faktatype, f.chosen?.value]));
    expect(byType).toEqual({ død: 'Kbh., 1850', titel: 'Kammerherre', dåb: '—' });
  });

  it('tre kildevisninger: bundet, import (med og uden side), ingen', () => {
    const v = buildPersonFacts([
      row({ fact_id: 1, assertion_id: 1, faktatype: 'navn', record_ref: 'r1', record_label: 'I-32', citation_label: 'DAA 2018-20, s. 45', source_label: 'DAA 2018-20' }),
      row({ fact_id: 2, assertion_id: 2, faktatype: 'fødsel', source_label: 'DAA 1939', side: '123' }),
      row({ fact_id: 3, assertion_id: 3, faktatype: 'død', source_label: 'DAA 2018-20' }),
      row({ fact_id: 4, assertion_id: 4, faktatype: 'begravelse', source_id: null, source_label: null }),
    ]);
    expect(v.map((f) => f.chosen?.source)).toEqual([
      { kind: 'bundet', label: 'DAA 2018-20, s. 45 · I-32', recordRef: 'r1' },
      { kind: 'import', label: 'DAA 1939, s. 123', recordRef: null },
      { kind: 'import', label: 'DAA 2018-20', recordRef: null },
      { kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null },
    ]);
  });

  it('bundet med teknisk record_label viser ikke nøglen', () => {
    const [f] = buildPersonFacts([row({ record_ref: 'r', record_label: 'record-07565168-b903-4444-9189-43d62d5c6ed6', citation_label: 'DAA 1939, s. 541' })]);
    expect(f.chosen?.source.label).toBe('DAA 1939, s. 541');
  });
  it('bundet uden citation_label bruger udgaven foran posten', () => {
    const [f] = buildPersonFacts([row({ record_ref: 'r', record_label: 'III-37', citation_label: '' })]);
    expect(f.chosen?.source.label).toBe('DAA 2018-20 · III-37');
  });

  it('flere påstande: den valgte som chosen, resten i others med egen kilde', () => {
    const v = buildPersonFacts([
      row({ fact_id: 9, assertion_id: 91, chosen: true, date_raw: '1850', source_label: 'DAA 2018-20' }),
      row({ fact_id: 9, assertion_id: 92, chosen: false, date_raw: '1851', source_label: 'DAA 1939', side: '7' }),
    ]);
    expect(v).toHaveLength(1);
    expect(v[0].chosen?.value).toBe('1850');
    expect(v[0].others.map((o) => [o.value, o.source.label])).toEqual([['1851', 'DAA 1939, s. 7']]);
    expect(v[0].omstridt).toBe(false);
  });

  it('omstridt uden valgt påstand: chosen null, alle i others', () => {
    const v = buildPersonFacts([
      row({ fact_id: 9, assertion_id: 91, chosen: false, conclusion_status: 'omstridt' }),
      row({ fact_id: 9, assertion_id: 92, chosen: false, conclusion_status: 'omstridt' }),
    ]);
    expect(v[0]).toMatchObject({ omstridt: true, chosen: null });
    expect(v[0].others).toHaveLength(2);
  });

  it('dedup: samme fact_id fra to medlems-id\'er giver ét faktum; to citationer giver to udsagn', () => {
    const a = row({ fact_id: 5, assertion_id: 55, source_label: 'DAA 1939', side: '1' });
    const dup = { ...a };
    const v = buildPersonFacts([a, dup, { ...a, side: '2' }]);
    expect(v).toHaveLength(1);
    expect([v[0].chosen, ...v[0].others].map((s) => s?.source.label)).toEqual(['DAA 1939, s. 1', 'DAA 1939, s. 2']);
  });

  it('viser vaerdi_tekst og date_raw én gang, når de er ens', () => {
    const [v] = buildPersonFacts([row({ vaerdi_tekst: '15. febr. 1878.', date_raw: '15. febr. 1878.' })]);
    expect(v.chosen?.value).toBe('15. febr. 1878.');
    const [w] = buildPersonFacts([row({ vaerdi_tekst: 'a', date_raw: 'b' })]);
    expect(w.chosen?.value).toBe('a, b');
  });

  it('ledende *, † eller ⚭ fjernes i visningen; tegn inde i værdien bevares (spec §5.8)', () => {
    expect(factValue(row({ vaerdi_tekst: null, date_raw: '* 1749' }))).toBe('1749');
    expect(factValue(row({ vaerdi_tekst: '† ung', date_raw: null }))).toBe('ung');
    expect(factValue(row({ vaerdi_tekst: '⚭ 1700', date_raw: null }))).toBe('1700');
    expect(factValue(row({ vaerdi_tekst: '*1749', date_raw: null }))).toBe('1749');
    expect(factValue(row({ vaerdi_tekst: 'ca. *1700', date_raw: null }))).toBe('ca. *1700');
    // tegnet fjernes før sammenligningen, så samme tekst ikke vises to gange
    expect(factValue(row({ vaerdi_tekst: '* 1749', date_raw: '1749' }))).toBe('1749');
    expect(factValue(row({ vaerdi_tekst: '†', date_raw: null }))).toBe('—');
  });

  it('date_raw vises ikke igen, når vaerdi_tekst slutter med den og den er mere end et årstal (afgørelse 13)', () => {
    expect(factValue(row({ vaerdi_tekst: 'hjemmedøbt 10. febr. 1922', date_raw: '10. febr. 1922' }))).toBe('hjemmedøbt 10. febr. 1922');
    expect(factValue(row({ vaerdi_tekst: 'hjemmedøbt 10. febr. 1922.', date_raw: '10. febr. 1922' }))).toBe('hjemmedøbt 10. febr. 1922.');
    // et rent årstal kan være et tilfælde → begge vises
    expect(factValue(row({ vaerdi_tekst: 'døbt i kirken opført 1845', date_raw: '1845' }))).toBe('døbt i kirken opført 1845, 1845');
    expect(factValue(row({ vaerdi_tekst: 'døbt 5. sept. 1845 eller 1846', date_raw: '1846' }))).toBe('døbt 5. sept. 1845 eller 1846, 1846');
    // afgørelse 13 revideret 2026-11-24 (projektejeren): står datoen ordret inde i teksten, vises den også kun én gang
    expect(factValue(row({ vaerdi_tekst: 'døbt 5. sept. 1845 i Vesterborg Kirke', date_raw: '5. sept. 1845' })))
      .toBe('døbt 5. sept. 1845 i Vesterborg Kirke');
    expect(factValue(row({ vaerdi_tekst: '25. april 1861 på Pederstrup', date_raw: '25. april 1861' }))).toBe('25. april 1861 på Pederstrup');
    expect(factValue(row({ vaerdi_tekst: 'bisat 27. s.m. fra Garnisons Kirke s.st. og begravet 29. s.m.', date_raw: '27. s.m.' })))
      .toBe('bisat 27. s.m. fra Garnisons Kirke s.st. og begravet 29. s.m.');
    // et rent årstal inde i teksten tæller stadig ikke
    expect(factValue(row({ vaerdi_tekst: 'døbt i kirken fra 1845 af præsten', date_raw: '1845' }))).toBe('døbt i kirken fra 1845 af præsten, 1845');
    // kun ved ordgrænse på begge sider: »5. sept. 1845« står ikke i »15. sept. 1845« eller »5. sept. 18450«
    expect(factValue(row({ vaerdi_tekst: 'døbt 15. sept. 1845', date_raw: '5. sept. 1845' }))).toBe('døbt 15. sept. 1845, 5. sept. 1845');
    expect(factValue(row({ vaerdi_tekst: 'døbt 15. sept. 1845 i kirken', date_raw: '5. sept. 1845' }))).toBe('døbt 15. sept. 1845 i kirken, 5. sept. 1845');
    expect(factValue(row({ vaerdi_tekst: 'nr. 5. sept. 18450 i kirken', date_raw: '5. sept. 1845' }))).toBe('nr. 5. sept. 18450 i kirken, 5. sept. 1845');
    // tjekket sker efter en omformning af hver del (opløsning af relative datoer)
    const opl = (v: string) => v.replace('s.å.', '1922');
    expect(factValue(row({ vaerdi_tekst: 'hjemmedøbt 10. febr. 1922', date_raw: '10. febr. s.å.' }), opl)).toBe('hjemmedøbt 10. febr. 1922');
  });

  it('opløsningen bruger visningens regel (#478): et datofelt inde i teksten er også en gentagelse', () => {
    expect(datoVisesIForvejen('hjemmedøbt 10. febr. s.å.', '10. febr. s.å.')).toBe(true);
    expect(datoVisesIForvejen('døbt 18. aug. s.å. i Vesterborg Kirke', '18. aug. s.å.')).toBe(true);
    // »slutter med« alene (afgørelse 13's oprindelige regel) dækker ikke midten
    expect(datoErDobbelt('døbt 18. aug. s.å. i Vesterborg Kirke', '18. aug. s.å.')).toBe(false);
    // værnene: rent årstal, ordgrænse, »?« efter datoen
    expect(datoVisesIForvejen('kirken opført 1845 i Vester', '1845')).toBe(false);
    expect(datoVisesIForvejen('døbt 118. aug. s.å.', '18. aug. s.å.')).toBe(false);
    expect(datoVisesIForvejen('døbt 18. aug. 1858? i kirken', '18. aug. 1858')).toBe(false);
    // efter et afsluttende punktum er »?« tekstens eget tegn: det bliver stående i teksten, så intet tabes
    expect(datoVisesIForvejen('døbt 18. aug. s.å.? i kirken', '18. aug. s.å.')).toBe(true);
  });

  it('C1: et betydningsbærende tegn i date_raw (»?«, parentes) fjernes aldrig ved dobbelttjekket', () => {
    expect(factValue(row({ vaerdi_tekst: 'døbt 21. april 1644', date_raw: '21. april 1644?' }))).toBe('døbt 21. april 1644, 21. april 1644?');
    expect(factValue(row({ vaerdi_tekst: 'døbt 21. april 1644', date_raw: '21. april 1644)' }))).toBe('døbt 21. april 1644, 21. april 1644)');
    expect(factValue(row({ vaerdi_tekst: 'døbt 21. april 1644?', date_raw: '21. april 1644' }))).toBe('døbt 21. april 1644?, 21. april 1644');
    // ender teksten med netop »…?«, er datofeltet dobbelt
    expect(factValue(row({ vaerdi_tekst: 'døbt 21. april 1644?', date_raw: '21. april 1644?' }))).toBe('døbt 21. april 1644?');
    // afsluttende punktum, komma og mellemrum er stadig kun skrivemåde
    expect(factValue(row({ vaerdi_tekst: 'døbt 21. april 1644.', date_raw: '21. april 1644, ' }))).toBe('døbt 21. april 1644.');
  });

  it('kildeetiketten viser »<udgave>, s. N« (også intervaller) (spec §5.8)', () => {
    const bundet = (citation_label: string) =>
      factSource(row({ record_ref: 'r', record_label: 'record-07565168-b903-4444-9189-43d62d5c6ed6', citation_label })).label;
    expect(bundet('DAA 1939 side 532')).toBe('DAA 1939, s. 532');
    expect(bundet('DAA 1939 side 125-126')).toBe('DAA 1939, s. 125-126');
    expect(bundet('DAA 2018-20, s. 201-202')).toBe('DAA 2018-20, s. 201-202');
    expect(factSource(row({ record_ref: 'r', record_label: 'I-32', citation_label: 'DAA 1939 side 7' })).label).toBe('DAA 1939, s. 7 · I-32');
    expect(factSource(row({ source_label: 'DAA 1939 side 532' })).label).toBe('DAA 1939, s. 532');
    // kun den første » side« efter udgaven får komma
    expect(factSource(row({ source_label: 'DAA 1939 side 12 og side 14' })).label).toBe('DAA 1939, s. 12 og s. 14');
    expect(factSource(row({ source_label: 'Optegnelser om Inderside 12' })).label).toBe('Optegnelser om Inderside 12');
    // kun formen » side <tal>«
    expect(factSource(row({ source_label: 'Kirkebog, side B' })).label).toBe('Kirkebog, side B');
  });
});
