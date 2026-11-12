import { describe, it, expect } from 'vitest';
import type { PublicPersonFactRow } from '../personFacts';
import { faktaVaerdierEns } from '../factEquality';
import {
  byggUdgaveFakta,
  udgaveForRaekker,
  udgaverMedFakta,
  type Udgave,
  type UdgaveFaktaInput,
  type UdgaveFaktaVisning,
} from '../editionFacts';

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

const D18: Udgave = { sourceId: '1', label: 'DAA 2018-20', aar: 2018 };
const D39: Udgave = { sourceId: '3', label: 'DAA 1939', aar: 1939 };
const UDGAVER = [D39, D18]; // bevidst ikke i årsorden

// Tekst-fakta (navn, titel, begravelse …) bærer værdien i vaerdi_tekst.
const tekst = (o: Partial<PublicPersonFactRow>) => row({ date_raw: null, ...o });
const r18 = (o: Partial<PublicPersonFactRow>) => row({ source_id: 1, source_label: 'DAA 2018-20', ...o });
const r39 = (o: Partial<PublicPersonFactRow>) => row({ source_id: 3, source_label: 'DAA 1939', ...o });

const input = (rows: PublicPersonFactRow[], o: Partial<UdgaveFaktaInput> = {}): UdgaveFaktaInput => ({
  rows,
  udgaver: UDGAVER,
  udgaveForPersonRaekke: {},
  fritekstKilde: {},
  ...o,
});

type Fixture = { navn: string; input: UdgaveFaktaInput; undtaget?: string[] };
const FIXTURES: Fixture[] = [];
const fixture = (navn: string, inp: UdgaveFaktaInput, undtaget?: string[]) => {
  FIXTURES.push({ navn, input: inp, undtaget });
  return inp;
};

// ---- Conrad Reventlow (255 III-58, 392 V-1, 1198 1939) ----
const conradNavnRed = tekst({ person_id: 392, fact_id: 3920, faktatype: 'navn', assertion_id: 39200, chosen: true,
  vaerdi_tekst: 'Conrad', source_id: null, source_label: null });
const conrad = fixture('Conrad', input([
  conradNavnRed,
  tekst({ person_id: 392, fact_id: 3920, faktatype: 'navn', assertion_id: 39201, chosen: false,
    vaerdi_tekst: 'Conrad de Reventlow', source_id: 1, source_label: 'DAA 2018-20', side: '201' }),
  tekst({ person_id: 255, fact_id: 2551, faktatype: 'titel', vaerdi_tekst: 'greve', source_id: 1, source_label: 'DAA 2018-20',
    record_ref: 'rec-iii58', record_label: 'III-58', citation_label: 'DAA 2018-20, s. 137' }),
  tekst({ person_id: 392, fact_id: 3921, faktatype: 'titel', vaerdi_tekst: 'Greve', source_id: 1, source_label: 'DAA 2018-20',
    record_ref: 'rec-v1', record_label: 'V-1', citation_label: 'DAA 2018-20, s. 201-202' }),
  r18({ person_id: 392, fact_id: 3922, faktatype: 'fødsel', date_raw: '21. april 1644', date_min: '1644-04-21' }),
  r18({ person_id: 392, fact_id: 3923, faktatype: 'død', date_raw: '21. juli 1708', date_min: '1708-07-21' }),
  ...(() => {
    const bundet = { source_id: 3, source_label: 'DAA 1939', record_ref: 'rec-1939',
      record_label: 'record-07565168-b903-4444-9189-43d62d5c6ed6', citation_label: 'DAA 1939, s. 541' };
    return [
      tekst({ person_id: 1198, fact_id: 11980, faktatype: 'navn', vaerdi_tekst: 'Conrad Reventlow', ...bundet }),
      tekst({ person_id: 1198, fact_id: 11981, faktatype: 'titel', vaerdi_tekst: 'Greve', ...bundet }),
      row({ person_id: 1198, fact_id: 11982, faktatype: 'fødsel', date_raw: '21 April 1644', ...bundet }),
      row({ person_id: 1198, fact_id: 11983, faktatype: 'død', date_raw: '21 Juli 1708', date_min: '1708-01-01', ...bundet }),
    ];
  })(),
], {
  udgaveForPersonRaekke: { '255': '1', '392': '1', '1198': '3' },
  fritekstKilde: { '39200': ['Dansk Adels Aarbog – DAA 1939'] },
}));

const linje = (v: UdgaveFaktaVisning, type: string) => v.linjer.filter((l) => l.faktatype === type);

describe('byggUdgaveFakta', () => {
  it('Conrad: 2018-20 viser bøgernes ord med noter', () => {
    const v = byggUdgaveFakta(conrad, '1');
    const [navn, ...flereNavne] = linje(v, 'navn');
    expect(flereNavne).toEqual([]);
    expect(navn.vaerdi).toBe('Conrad de Reventlow');
    expect(navn.noter).toEqual([{ art: 'skriver', udgave: D39, vaerdier: ['Conrad Reventlow'] }]);
    // redaktørens valg forsvinder ikke: det står som andet udsagn
    expect(navn.andre.map((a) => a.value)).toEqual(['Conrad']);

    const titler = linje(v, 'titel');
    expect(titler).toHaveLength(1);
    expect(titler[0].kilder.map((k) => k.label).sort()).toEqual(['DAA 2018-20, s. 137 · III-58', 'DAA 2018-20, s. 201-202 · V-1']);
    expect(titler[0].noter).toEqual([{ art: 'enig', udgave: D39 }]);

    expect(linje(v, 'fødsel').map((l) => l.noter)).toEqual([[{ art: 'enig', udgave: D39 }]]);
    expect(linje(v, 'død').map((l) => l.noter)).toEqual([[{ art: 'enig', udgave: D39 }]]);
    expect(v.kunI).toEqual([]);
    expect(v.linjer.map((l) => l.faktatype)).toEqual(['navn', 'fødsel', 'titel', 'død']);
  });

  it("Conrad: 1939 viser 1939's ord og 2018-20 som note", () => {
    const v = byggUdgaveFakta(conrad, '3');
    const navn = linje(v, 'navn');
    expect(navn).toHaveLength(1);
    expect(navn[0].vaerdi).toBe('Conrad Reventlow');
    expect(navn[0].noter).toEqual([{ art: 'skriver', udgave: D18, vaerdier: ['Conrad de Reventlow'] }]);
    const labels = v.linjer.flatMap((l) => [...l.kilder.map((k) => k.label), ...l.andre.map((a) => a.source.label)]);
    expect(labels.length).toBeGreaterThan(0);
    expect(labels.some((l) => l.includes('record-'))).toBe(false);
    expect(linje(v, 'titel').map((l) => l.noter)).toEqual([[{ art: 'enig', udgave: D18 }]]);
    expect(v.kunI).toEqual([]);
  });

  it('OCR-rettelse med fritekst for samme udgave vises som udgavens egen', () => {
    const inp = fixture('OCR', input([
      tekst({ person_id: 1073, fact_id: 10730, faktatype: 'navn', assertion_id: 107301, chosen: false,
        vaerdi_tekst: 'Ditlev Chriftian', source_id: 3, source_label: 'DAA 1939', record_ref: 'rec-1073',
        record_label: 'record-11111111-2222-3333-4444-555555555555', citation_label: 'DAA 1939, s. 521' }),
      tekst({ person_id: 1073, fact_id: 10730, faktatype: 'navn', assertion_id: 107302, chosen: true,
        vaerdi_tekst: 'Ditlev Christian', source_id: null, source_label: null }),
      tekst({ person_id: 73, fact_id: 730, faktatype: 'navn', vaerdi_tekst: 'Ditlev Christian' }),
    ], {
      udgaveForPersonRaekke: { '1073': '3', '73': '1' },
      fritekstKilde: { '107302': ['Dansk Adels Aarbog – DAA 1939, 521'] },
    }));
    const v = byggUdgaveFakta(inp, '3');
    expect(linje(v, 'navn').map((l) => l.vaerdi)).toEqual(['Ditlev Christian']);
    expect(linje(v, 'navn')[0].noter).toEqual([{ art: 'enig', udgave: D18 }]);
    expect(linje(v, 'navn')[0].andre.map((a) => a.value)).toEqual(['Ditlev Chriftian']);
  });

  it('redaktørfaktum uden udgaveegen påstand vises som i dag og uden noter', () => {
    const inp = fixture('redaktør alene', input([
      r18({ person_id: 5, faktatype: 'overhoved', vaerdi_tekst: 'Slægtens overhoved', date_raw: null, assertion_id: 5001,
        source_id: null, source_label: null }),
      r39({ person_id: 6, faktatype: 'overhoved', vaerdi_tekst: 'Overhoved', date_raw: null,
        record_ref: 'rec-6', citation_label: 'DAA 1939, s. 9' }),
    ], {
      udgaveForPersonRaekke: { '5': '1', '6': '3' },
      fritekstKilde: { '5001': ['(kilde mangler)'] },
    }), ['Slægtens overhoved']);
    const v = byggUdgaveFakta(inp, '1');
    const l = linje(v, 'overhoved');
    expect(l).toHaveLength(1);
    expect(l[0].vaerdi).toBe('Slægtens overhoved');
    expect(l[0].kilder).toEqual([{ kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null }]);
    expect(l[0].noter).toEqual([]);
    // den anden udgaves egen værdi er ikke dækket af en note → kunI
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'overhoved', vaerdier: ['Overhoved'] }]);
  });

  it('enkeltværdi: flere forskellige værdier i den anden udgave giver skriver a; b, aldrig ✓', () => {
    const inp = fixture('enkeltværdi', input([
      r18({ person_id: 10, date_raw: '1850' }),
      r39({ person_id: 11, date_raw: '1850' }),
      r39({ person_id: 12, date_raw: '1851' }),
    ], { udgaveForPersonRaekke: { '10': '1', '11': '3', '12': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'død').map((l) => l.noter)).toEqual([[{ art: 'skriver', udgave: D39, vaerdier: ['1850', '1851'] }]]);
    expect(v.kunI).toEqual([]);
    // omvendt: to linjer i 1939 (uenighed inden for udgaven), hver med sin note
    const w = byggUdgaveFakta(inp, '3');
    expect(linje(w, 'død').map((l) => [l.vaerdi, l.noter])).toEqual([
      ['1850', [{ art: 'enig', udgave: D18 }]],
      ['1851', [{ art: 'skriver', udgave: D18, vaerdier: ['1850'] }]],
    ]);
  });

  it('flerværdi: uparret titel går til kunI', () => {
    const inp = fixture('flerværdi', input([
      tekst({ person_id: 20, faktatype: 'titel', vaerdi_tekst: 'Greve' }),
      tekst({ person_id: 20, faktatype: 'titel', vaerdi_tekst: 'hvid ridder' }),
      tekst({ person_id: 21, faktatype: 'titel', vaerdi_tekst: 'greve', source_id: 3, source_label: 'DAA 1939' }),
      tekst({ person_id: 21, faktatype: 'titel', vaerdi_tekst: 'Kammerherre', source_id: 3, source_label: 'DAA 1939' }),
    ], { udgaveForPersonRaekke: { '20': '1', '21': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'titel').map((l) => [l.vaerdi, l.noter])).toEqual([
      ['Greve', [{ art: 'enig', udgave: D39 }]],
      ['hvid ridder', []],
    ]);
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'titel', vaerdier: ['Kammerherre'] }]);
  });

  it('type kun i den anden udgave går til kunI', () => {
    const inp = fixture('kun i anden', input([
      r18({ person_id: 30, date_raw: '1850' }),
      r39({ person_id: 31, date_raw: '1850' }),
      r39({ person_id: 31, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: 'Slesvig Domkirke' }),
      r39({ person_id: 31, faktatype: 'dekoration', date_raw: null, vaerdi_tekst: 'R.' }),
    ], { udgaveForPersonRaekke: { '30': '1', '31': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(v.linjer.map((l) => l.faktatype)).toEqual(['død']);
    expect(v.kunI).toEqual([
      { udgave: D39, faktatype: 'dekoration', vaerdier: ['R.'] },
      { udgave: D39, faktatype: 'begravelse', vaerdier: ['Slesvig Domkirke'] },
    ]);
  });

  it('slukketEnighed gør enig til skriver for typen', () => {
    const rows = [
      r18({ person_id: 40, date_raw: '1850' }),
      tekst({ person_id: 40, faktatype: 'titel', vaerdi_tekst: 'Greve' }),
      tekst({ person_id: 40, faktatype: 'titel', vaerdi_tekst: 'hvid ridder' }),
      r39({ person_id: 41, date_raw: '1850' }),
      tekst({ person_id: 41, faktatype: 'titel', vaerdi_tekst: 'greve', source_id: 3, source_label: 'DAA 1939' }),
    ];
    const ext = { '40': '1', '41': '3' };
    fixture('slukket', input(rows, { udgaveForPersonRaekke: ext, slukketEnighed: new Set(['død', 'titel']) }));
    const foer = byggUdgaveFakta(input(rows, { udgaveForPersonRaekke: ext }), '1');
    expect(linje(foer, 'død')[0].noter).toEqual([{ art: 'enig', udgave: D39 }]);
    expect(linje(foer, 'titel').map((l) => l.noter)).toEqual([[{ art: 'enig', udgave: D39 }], []]);

    const doed = byggUdgaveFakta(input(rows, { udgaveForPersonRaekke: ext, slukketEnighed: new Set(['død']) }), '1');
    expect(linje(doed, 'død')[0].noter).toEqual([{ art: 'skriver', udgave: D39, vaerdier: ['1850'] }]);
    expect(linje(doed, 'titel')[0].noter).toEqual([{ art: 'enig', udgave: D39 }]);

    const titel = byggUdgaveFakta(input(rows, { udgaveForPersonRaekke: ext, slukketEnighed: new Set(['titel']) }), '1');
    expect(linje(titel, 'død')[0].noter).toEqual([{ art: 'enig', udgave: D39 }]);
    expect(linje(titel, 'titel').map((l) => l.noter)).toEqual([
      [{ art: 'skriver', udgave: D39, vaerdier: ['greve'] }],
      [{ art: 'skriver', udgave: D39, vaerdier: ['greve'] }],
    ]);
    expect(titel.kunI).toEqual([]);
  });

  it('redaktørfaktum i valgt udgave: den anden udgaves egen værdi går til kunI', () => {
    const inp = fixture('redaktør i valgt', input([
      r18({ person_id: 50, date_raw: '1708?', assertion_id: 5050, source_id: null, source_label: null }),
      r39({ person_id: 51, date_raw: '1708', record_ref: 'rec-51', citation_label: 'DAA 1939, s. 541' }),
    ], {
      udgaveForPersonRaekke: { '50': '1', '51': '3' },
      fritekstKilde: { '5050': ['(kilde mangler)'] },
    }), ['1708?']);
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'død').map((l) => [l.vaerdi, l.noter])).toEqual([['1708?', []]]);
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'død', vaerdier: ['1708'] }]);
    // Bevidst valg (spec §5.2 »indgår ikke i noter«): redaktørfaktummet nævnes ikke i 1939-visningen.
    const w = byggUdgaveFakta(inp, '3');
    expect(linje(w, 'død').map((l) => [l.vaerdi, l.noter])).toEqual([['1708', []]]);
    expect(w.kunI).toEqual([]);
  });

  it('fritekst: flere citationer med modstridende udgaver → ikke egen, uanset rækkefølge', () => {
    const lav = (pid: number, tekster: string[]) => {
      const valgt = tekst({ person_id: pid, fact_id: pid * 10, faktatype: 'navn', chosen: true, vaerdi_tekst: 'Rettet',
        source_id: null, source_label: null });
      const bundet = tekst({ person_id: pid, fact_id: pid * 10, faktatype: 'navn', chosen: false, vaerdi_tekst: 'Bogens',
        source_id: 3, source_label: 'DAA 1939', record_ref: `rec-${pid}`, citation_label: 'DAA 1939, s. 1' });
      return { rows: [valgt, bundet], fritekst: { [String(valgt.assertion_id)]: tekster } };
    };
    for (const tekster of [
      ['Dansk Adels Aarbog – DAA 1939', 'Dansk Adels Aarbog – DAA 2018-20'],
      ['Dansk Adels Aarbog – DAA 2018-20', 'Dansk Adels Aarbog – DAA 1939'],
      ['DAA 1939 og DAA 2018-20'],
      [],
    ]) {
      const { rows, fritekst } = lav(60, tekster);
      const inp = fixture(`fritekst ${tekster.join('|')}`, input(rows, { udgaveForPersonRaekke: { '60': '3' }, fritekstKilde: fritekst }));
      expect(linje(byggUdgaveFakta(inp, '3'), 'navn').map((l) => l.vaerdi)).toEqual(['Bogens']);
    }
    // og kontrol: samme udgave i alle tekster → egen
    const { rows, fritekst } = lav(61, ['Dansk Adels Aarbog – DAA 1939', 'DAA 1939, s. 4']);
    const ok = input(rows, { udgaveForPersonRaekke: { '61': '3' }, fritekstKilde: fritekst });
    expect(linje(byggUdgaveFakta(ok, '3'), 'navn').map((l) => l.vaerdi)).toEqual(['Rettet']);
  });

  it('ægtefælle uden ekstern nøgle får udgave fra citationerne', () => {
    const inp = fixture('ægtefælle', input([
      tekst({ person_id: 70, faktatype: 'navn', vaerdi_tekst: 'Anna Holck', source_id: 3, source_label: 'DAA 1939' }),
      r39({ person_id: 70, date_raw: '1801' }),
      // ikke-DAA-kilde gør ikke rækken flertydig
      r39({ person_id: 70, faktatype: 'begravelse', vaerdi_tekst: 'Roskilde', date_raw: null, source_id: 99, source_label: 'Kirkebog' }),
      tekst({ person_id: 71, faktatype: 'navn', vaerdi_tekst: 'Anna Holck' }),
    ], { udgaveForPersonRaekke: { '71': '1' } }), ['Roskilde']);
    expect(udgaveForRaekker(inp)).toEqual({ '70': '3', '71': '1' });
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'navn').map((l) => l.noter)).toEqual([[{ art: 'enig', udgave: D39 }]]);
    // kirkebogens begravelse er ikke 1939's egne ord → hverken note eller kunI (vises i 1939-visningen som i dag)
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'død', vaerdier: ['1801'] }]);
    const w = byggUdgaveFakta(inp, '3');
    expect(w.linjer.map((l) => [l.faktatype, l.vaerdi])).toEqual([['navn', 'Anna Holck'], ['død', '1801'], ['begravelse', 'Roskilde']]);
  });

  it('række med citationer til to udgaver vises i alle og indgår ikke i noter', () => {
    const inp = fixture('to udgaver', input([
      tekst({ person_id: 80, faktatype: 'navn', vaerdi_tekst: 'Sophie' }),
      r39({ person_id: 80, date_raw: '1800' }),
      r18({ person_id: 81, date_raw: '1801' }),
      r39({ person_id: 82, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: 'Vor Frue' }),
      r18({ person_id: 83, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: 'X' }),
    ], { udgaveForPersonRaekke: { '81': '1', '82': '3' } }));
    // 83 citerer kun 2018-20 → udgave 1; 80 citerer begge → null
    expect(udgaveForRaekker(inp)).toEqual({ '80': null, '81': '1', '82': '3', '83': '1' });
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'navn').map((l) => [l.vaerdi, l.noter])).toEqual([['Sophie', []]]);
    // 80's død 1800 (fra 1939-citation) bekræfter/modsiger ikke 81's 1801
    expect(linje(v, 'død').map((l) => [l.vaerdi, l.noter])).toEqual([['1800', []], ['1801', []]]);
    expect(v.kunI).toEqual([]);
    const w = byggUdgaveFakta(inp, '3');
    expect(linje(w, 'navn').map((l) => [l.vaerdi, l.noter])).toEqual([['Sophie', []]]);
    expect(linje(w, 'død').map((l) => [l.vaerdi, l.noter])).toEqual([['1800', []]]);
    expect(w.kunI).toEqual([{ udgave: D18, faktatype: 'død', vaerdier: ['1801'] }]);
    expect(linje(w, 'begravelse').map((l) => l.noter)).toEqual([[{ art: 'skriver', udgave: D18, vaerdier: ['X'] }]]);
  });

  it('omstridt uden valgt påstand: alle udsagn som skriver i den anden udgave', () => {
    const inp = fixture('omstridt', input([
      r18({ person_id: 90, date_raw: '1850' }),
      tekst({ person_id: 90, faktatype: 'titel', vaerdi_tekst: 'Greve' }),
      r39({ person_id: 91, fact_id: 910, conclusion_status: 'omstridt', chosen: false, date_raw: '1850' }),
      r39({ person_id: 91, fact_id: 910, conclusion_status: 'omstridt', chosen: false, date_raw: '1851' }),
      tekst({ person_id: 91, fact_id: 911, faktatype: 'titel', conclusion_status: 'omstridt', chosen: false,
        vaerdi_tekst: 'Greve', source_id: 3, source_label: 'DAA 1939' }),
    ], { udgaveForPersonRaekke: { '90': '1', '91': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(linje(v, 'død')[0].noter).toEqual([{ art: 'skriver', udgave: D39, vaerdier: ['1850', '1851'] }]);
    // flerværdi: et omstridt udsagn parres aldrig som ✓ — det står under »Kun i«
    expect(linje(v, 'titel')[0].noter).toEqual([]);
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'titel', vaerdier: ['Greve'] }]);

    const w = byggUdgaveFakta(inp, '3');
    const d = linje(w, 'død');
    expect(d).toHaveLength(1);
    expect(d[0].omstridt).toBe(true);
    expect(d[0].vaerdi).toBe('');
    expect(d[0].kilder).toEqual([]);
    expect(d[0].andre.map((a) => a.value)).toEqual(['1850', '1851']);
    expect(d[0].noter).toEqual([]);
    expect(w.kunI).toEqual([
      { udgave: D18, faktatype: 'titel', vaerdier: ['Greve'] },
      { udgave: D18, faktatype: 'død', vaerdier: ['1850'] },
    ]);
  });

  it("samme række fra flere medlems-id'er tælles én gang", () => {
    const a = r18({ person_id: 100, date_raw: '1850', side: '12' });
    const b = r39({ person_id: 101, date_raw: '1851' });
    const inp = fixture('dubletter', input([a, { ...a }, b, { ...b }], { udgaveForPersonRaekke: { '100': '1', '101': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(v.linjer).toHaveLength(1);
    expect(v.linjer[0].kilder).toHaveLength(1);
    expect(v.linjer[0].andre).toEqual([]);
    expect(v.linjer[0].noter).toEqual([{ art: 'skriver', udgave: D39, vaerdier: ['1851'] }]);
  });

  it('én udgave: ingen noter, dubletter lagt sammen', () => {
    const inp = fixture('én udgave', input([
      r18({ person_id: 110, date_raw: '21. juli 1708', side: '137' }),
      r18({ person_id: 111, date_raw: '21 Juli 1708', side: '201' }),
      tekst({ person_id: 110, faktatype: 'titel', vaerdi_tekst: 'Greve', side: '137' }),
      tekst({ person_id: 111, faktatype: 'titel', vaerdi_tekst: 'greve', side: '201' }),
      tekst({ person_id: 111, faktatype: 'titel', vaerdi_tekst: 'hvid ridder', side: '201' }),
    ], { udgaveForPersonRaekke: { '110': '1', '111': '1' } }));
    expect(udgaverMedFakta(inp)).toEqual(['1']);
    const v = byggUdgaveFakta(inp, '1');
    expect(v.linjer.map((l) => [l.faktatype, l.vaerdi, l.kilder.map((k) => k.label)])).toEqual([
      ['titel', 'Greve', ['DAA 2018-20, s. 137', 'DAA 2018-20, s. 201']],
      ['titel', 'hvid ridder', ['DAA 2018-20, s. 201']],
      ['død', '21. juli 1708', ['DAA 2018-20, s. 137', 'DAA 2018-20, s. 201']],
    ]);
    expect(v.linjer.every((l) => l.noter.length === 0)).toBe(true);
    expect(v.kunI).toEqual([]);
    // valgt = null: samme billede
    expect(byggUdgaveFakta(inp, null)).toEqual(v);
  });

  it('tomt udgaveegent alternativ sluger ikke redaktørens valg', () => {
    const inp = fixture('tomt alternativ', input([
      r39({ person_id: 130, fact_id: 1300, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: '—', chosen: false,
        record_ref: 'rec-130', citation_label: 'DAA 1939, s. 7' }),
      r39({ person_id: 130, fact_id: 1300, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: 'Vor Frue Kirke',
        chosen: true, assertion_id: 13002, source_id: null, source_label: null }),
      r18({ person_id: 131, faktatype: 'begravelse', date_raw: null, vaerdi_tekst: 'Vor Frue Kirke' }),
    ], {
      udgaveForPersonRaekke: { '130': '3', '131': '1' },
      fritekstKilde: { '13002': ['(kilde mangler)'] },
    }), ['Vor Frue Kirke@3']);
    const v = byggUdgaveFakta(inp, '3');
    expect(linje(v, 'begravelse').map((l) => [l.vaerdi, l.noter])).toEqual([['Vor Frue Kirke', []]]);
    expect(v.kunI).toEqual([{ udgave: D18, faktatype: 'begravelse', vaerdier: ['Vor Frue Kirke'] }]);
  });

  it('tom værdi giver hverken linje, note eller kunI', () => {
    const inp = fixture('tom værdi', input([
      r18({ person_id: 120, faktatype: 'begravelse', vaerdi_tekst: '—', date_raw: null }),
      r18({ person_id: 120, faktatype: 'dødsårsag', vaerdi_tekst: ' .; ', date_raw: null }),
      r18({ person_id: 120, faktatype: 'dåb', vaerdi_tekst: null, date_raw: null }),
      r39({ person_id: 121, faktatype: 'begravelse', vaerdi_tekst: '—', date_raw: null }),
      r39({ person_id: 121, faktatype: 'dødsårsag', vaerdi_tekst: 'Kopper', date_raw: null }),
      r18({ person_id: 120, faktatype: 'forældrefamilie', vaerdi_tekst: 'X', date_raw: null }),
    ], { udgaveForPersonRaekke: { '120': '1', '121': '3' } }));
    const v = byggUdgaveFakta(inp, '1');
    expect(v.linjer).toEqual([]);
    // 2018-20's tomme dødsårsag dækker ikke 1939's »Kopper«
    expect(v.kunI).toEqual([{ udgave: D39, faktatype: 'dødsårsag', vaerdier: ['Kopper'] }]);
    const w = byggUdgaveFakta(inp, '3');
    expect(w.linjer.map((l) => [l.faktatype, l.noter])).toEqual([['dødsårsag', []]]);
    expect(w.kunI).toEqual([]);
    expect(udgaverMedFakta(inp)).toEqual(['3']);
  });

  it('udgaverMedFakta: udgaver med viste fakta, nyeste først', () => {
    expect(udgaverMedFakta(conrad)).toEqual(['1', '3']);
  });

  it('valgt = null: alle rækker som én udgave uden noter', () => {
    const v = byggUdgaveFakta(conrad, null);
    expect(v.kunI).toEqual([]);
    expect(v.linjer.every((l) => l.noter.length === 0)).toBe(true);
    // valgt påstand som i dag; ens værdier på tværs lagt sammen
    expect(linje(v, 'navn').map((l) => l.vaerdi)).toEqual(['Conrad', 'Conrad Reventlow']);
    expect(linje(v, 'titel')).toHaveLength(1);
    expect(linje(v, 'titel')[0].kilder).toHaveLength(3);
  });

  it('invariant: hver anden udgaves viste værdi er i en note eller kunI', () => {
    let tjekket = 0;
    for (const fx of FIXTURES) {
      const raekkeUdgave = udgaveForRaekker(fx.input);
      for (const slukket of [fx.input.slukketEnighed, new Set(['navn', 'titel', 'død', 'fødsel', 'begravelse', 'dekoration', 'dødsårsag', 'overhoved'])]) {
        const inp = { ...fx.input, slukketEnighed: slukket };
        for (const valgt of inp.udgaver) {
          const vis = byggUdgaveFakta(inp, valgt.sourceId);
          for (const anden of inp.udgaver) {
            if (anden.sourceId === valgt.sourceId) continue;
            // den anden udgaves egen visning (kun dens rækker)
            const egne = inp.rows.filter((r) => raekkeUdgave[String(r.person_id)] === anden.sourceId);
            const egenVis = byggUdgaveFakta({ ...inp, rows: egne }, anden.sourceId);
            for (const l of egenVis.linjer) {
              const vaerdier = l.vaerdi === '' ? l.andre.map((a) => a.value) : [l.vaerdi];
              for (const v of vaerdier) {
                // undtaget: redaktørfakta o.l. (ikke udgavens ord); »værdi@sourceId« begrænser til én udgave
                if (fx.undtaget?.includes(v) || fx.undtaget?.includes(`${v}@${anden.sourceId}`)) continue;
                const ens = (x: string) => faktaVaerdierEns(l.faktatype, x, v);
                const iNote = vis.linjer.some((m) => m.faktatype === l.faktatype && m.noter.some((n) =>
                  n.udgave.sourceId === anden.sourceId && (n.art === 'enig' ? ens(m.vaerdi) : n.vaerdier.some(ens))));
                const iKunI = vis.kunI.some((k) => k.udgave.sourceId === anden.sourceId && k.faktatype === l.faktatype && k.vaerdier.some(ens));
                expect(iNote || iKunI, `${fx.navn}: ${anden.label} ${l.faktatype} »${v}« set fra ${valgt.label}`).toBe(true);
                tjekket++;
              }
            }
          }
        }
      }
    }
    expect(FIXTURES.length).toBeGreaterThanOrEqual(15);
    expect(tjekket).toBeGreaterThan(50);
  });
});
