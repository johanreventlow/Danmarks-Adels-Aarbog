// 6e på mobilen (batch 4): linjerne samles på den kanoniske linje på tværs af udgaver. Eksemplet er person 446
// (DAA 2018-20, linje V nr. 148), foldet (samme_som) med person 1337 (DAA 1939, linje IV nr. 3): samme mand, samme
// kanoniske linje, nummereret forskelligt i de to udgaver.
import { b6Noter, erTekniskLinje, kanoniskeLinjer, kanoniskeLinjerPrPerson, linjerForUdgave, synligeLinjer } from '@daa/core';
import type { RawLineageContext } from '@daa/core';
import { byggUdgaveLag, TOMT_SKEMA } from '../udgaveLag';
import type { RawExtId, RawSource } from '../types';

const sources: RawSource[] = [
  { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', udgave: 'DAA 1939', aar: 1939, ekstern: null },
  { id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null },
];
const lineageRows: RawLineageContext[] = [
  { id: 50, source_id: 2, kode: 'V', navn: 'Den grevelige Linje af 1673', slaegt_id: 1, slaegtsnavn: 'Reventlow' },
  { id: 40, source_id: 2, kode: 'I', navn: 'Den holstenske Linje', slaegt_id: 1, slaegtsnavn: 'Reventlow' },
];
const schemeRows = {
  schemes: [
    { id: 10, slaegt_id: 1, source_id: 1, kind: 'stamtavle' },
    { id: 20, slaegt_id: 1, source_id: 2, kind: 'stamtavle' },
  ],
  entries: [
    { id: 101, scheme_id: 10, code: 'IV', label: 'IV. Den grevelige Linje af 1673' },
    { id: 201, scheme_id: 20, code: 'V', label: 'V. Den grevelige Linje af 1673' },
    { id: 202, scheme_id: 20, code: 'I', label: 'I. Den holstenske Linje' },
  ],
  mappings: [
    { entry_id: 101, lineage_id: 50, relation_kind: 'canonical' },
    { entry_id: 201, lineage_id: 50, relation_kind: 'canonical' },
    { entry_id: 202, lineage_id: 40, relation_kind: 'canonical' },
  ],
};
const extIds: RawExtId[] = [
  { person_id: 446, source_id: 2, linje: 'V', nr: 148, slaegtled_lokal: 9, provenance: 'placement', trykt_side: '512' },
  { person_id: 1337, source_id: 1, linje: 'IV', nr: 3, slaegtled_lokal: 2, provenance: 'placement', trykt_side: '410' },
  // Linjernes hoveder: 2018-20 (nyeste udgave) giver stamfaderen, også når 1939 har sit eget nr. 1.
  { person_id: 400, source_id: 2, linje: 'V', nr: 1, slaegtled_lokal: 1, provenance: 'placement' },
  { person_id: 1300, source_id: 1, linje: 'IV', nr: 1, slaegtled_lokal: 1, provenance: 'placement' },
  { person_id: 10, source_id: 2, linje: 'I', nr: 1, slaegtled_lokal: 1, provenance: 'placement' },
  // En legacy-kode uden for 1939-skemaet: bliver en teknisk nøgle, som aldrig må nå læseren.
  { person_id: 1337, source_id: 1, linje: '1939', nr: null, provenance: 'legacy_external_id', trykt_side: '410' },
];
const canonicalIdById = { '1337': '446' };
const KANONISK_V = 'slaegt:1:lineage:50:scheme:canonical';

// buildLineage advarer om den tekniske legacy-koordinat; det er forventet her.
beforeEach(() => { jest.spyOn(console, 'warn').mockImplementation(() => {}); });
afterEach(() => jest.restoreAllMocks());
const stille = <T,>(f: () => T): T => {
  const spy = jest.spyOn(console, 'warn').mockImplementation(() => {});
  try { return f(); } finally { spy.mockRestore(); }
};

describe('byggUdgaveLag — person foldet på tværs af 1939 »IV« og 2018-20 »V«', () => {
  const lag = stille(() => byggUdgaveLag({ extIds, sources, lineageRows, schemeRows }, canonicalIdById));

  test('personen har ÉN kanonisk linje (ikke »IV« og »V«)', () => {
    expect(kanoniskeLinjer(lag.lineage, '446')).toEqual([KANONISK_V]);
    expect(lag.lineage.navn[KANONISK_V]).toBe('Den grevelige Linje af 1673');
  });

  test('linjelisten har én post pr. kanonisk linje med stamfaderen fra den nyeste udgave', () => {
    expect(lag.lineage.list.map((l) => l.linje).sort()).toEqual(['slaegt:1:lineage:40:scheme:canonical', KANONISK_V]);
    const v = lag.lineage.list.find((l) => l.linje === KANONISK_V);
    expect(v?.headId).toBe('400');
    expect(v?.count).toBe(3); // 400, 446 (= 1337) og 1300
  });

  test('ingen tekniske legacy-source-nøgler i listen eller i person → linjer', () => {
    expect(lag.lineage.list.some((l) => erTekniskLinje(l.linje))).toBe(false);
    expect(synligeLinjer(lag.lineage.list)).toHaveLength(2);
    expect(Object.values(kanoniskeLinjerPrPerson(lag.lineage)).flat().some(erTekniskLinje)).toBe(false);
    // byPerson bevarer udgavenøglerne (også den tekniske) — de filtreres først ved visning, som på web.
    expect(lag.lineage.byPerson['446']).toHaveLength(3);
  });

  test('linjerækker pr. udgave + B6-note', () => {
    const r = lag.linjeRaekkerBy['446'];
    expect(linjerForUdgave(r, '2')).toEqual(['V. Den grevelige Linje af 1673']);
    expect(linjerForUdgave(r, '1')).toEqual(['IV. Den grevelige Linje af 1673']);
    expect(b6Noter(r, '2')).toEqual(['✓ også i DAA 1939 (IV. Den grevelige Linje af 1673)']);
  });

  test('bogens kilder: linjens navn + trykt side + nr., samlet på den kanoniske person', () => {
    expect(lag.sourcesBy['446']?.map((s) => s.ref)).toEqual([
      'V. Den grevelige Linje af 1673, s. 512, nr. 148',
      'IV. Den grevelige Linje af 1673, s. 410, nr. 3',
      's. 410',
    ]);
    expect(lag.sourcesBy['1337']).toBeUndefined();
  });

  test('udgaver og bogens numre', () => {
    expect(lag.udgaver.map((u) => u.label)).toEqual(['DAA 1939', 'DAA 2018-20']);
    expect(lag.udgaveForPersonRaekke['1337']).toBe('1');
    expect(lag.bogNrBy['446']?.map((b) => `${b.sourceId}:${b.linje}:${b.nr}`)).toEqual(['2:V:148', '1:IV:3']);
  });
});

describe('byggUdgaveLag — uden skematabeller (hentningen fejlede)', () => {
  test('kilderne falder tilbage til de trykte koder (»Linje V, nr. 148«)', () => {
    const lag = byggUdgaveLag({ extIds, sources, lineageRows, schemeRows: TOMT_SKEMA }, canonicalIdById);
    expect(lag.sourcesBy['446']?.[0]?.ref).toBe('Linje V, nr. 148');
    expect(lag.linjeRaekkerBy).toEqual({});
  });

  test('uden lineage-kontekst er de trykte koder selv nøglerne', () => {
    const lag = byggUdgaveLag({ extIds: extIds.slice(0, 5), sources, lineageRows: [], schemeRows: TOMT_SKEMA }, canonicalIdById);
    expect(lag.lineage.list.map((l) => l.linje)).toEqual(['I', 'IV', 'V']);
    expect(lag.lineage.list.every((l) => l.navn === null)).toBe(true);
  });

  test('linjehovedet er 15a før 15b, og kilden viser etiketten', () => {
    const lag = byggUdgaveLag({
      extIds: [
        { person_id: 31, source_id: 2, linje: 'II', nr: 15, nr_label: '15b', provenance: 'placement' },
        { person_id: 30, source_id: 2, linje: 'II', nr: 15, nr_label: '15a', provenance: 'placement' },
      ],
      sources, lineageRows: [], schemeRows: TOMT_SKEMA,
    });
    expect(lag.lineage.list.find((l) => l.linje === 'II')?.headId).toBe('30');
    expect(lag.sourcesBy['30']?.[0]?.ref).toBe('Linje II, nr. 15a');
  });
});
