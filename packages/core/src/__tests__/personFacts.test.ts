import { describe, it, expect } from 'vitest';
import { buildPersonFacts, FAKTA_UDELADT, type PublicPersonFactRow } from '../personFacts';

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
});
