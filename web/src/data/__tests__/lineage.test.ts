import { buildLineage, lineageContextKey } from '../lineage';
import type { RawExtId, RawLineage } from '../types';

const x = (person_id: string, linje: string | null, nr: number | null): RawExtId => ({
  person_id, source_id: '1', linje, nr,
});

const extIds: RawExtId[] = [
  x('10', 'I', 3),
  x('11', 'I', 1), // stamfader for I (laveste nr)
  x('12', 'I', 2),
  x('20', 'II', 5),
  x('21', 'II', 1), // stamfader for II
  x('30', 'III', null), // nr mangler → 9999
  x('99', null, 1), // ingen linje → ignoreres
];

const lineageRows: RawLineage[] = [
  { source_id: '1', kode: 'I', navn: 'Den holstenske linje' },
  { source_id: '1', kode: 'II', navn: 'Den danske linje' },
  // III mangler navn → fallback null
];

describe('buildLineage', () => {
  const r = buildLineage(extIds, lineageRows);

  test('byPerson mapper person → linje-kode; personer uden linje udelades', () => {
    expect(r.byPerson['10']).toEqual(['I']);
    expect(r.byPerson['21']).toEqual(['II']);
    expect(r.byPerson['99']).toBeUndefined();
  });

  test('samme_som-kanonisering: foldet grundlægger hører til flere linjer + head kanoniseres', () => {
    // III58 (linje III, nr 58) + V1 (linje V, nr 1) folder til V1.
    const ext: RawExtId[] = [x('III58', 'III', 58), x('V1', 'V', 1)];
    const rc = buildLineage(ext, [], { III58: 'V1' });
    expect(rc.byPerson['V1']?.sort()).toEqual(['III', 'V']);
    expect(rc.byPerson['III58']).toBeUndefined(); // alias-nøgle findes ikke
    expect(rc.list.find((l) => l.linje === 'III')?.headId).toBe('V1'); // head var alias → kanonisk
    expect(rc.list.find((l) => l.linje === 'III')?.count).toBe(1); // distinkt person, ikke ext-række
  });

  test('list er sorteret på kode med korrekt antal', () => {
    expect(r.list.map((l) => l.linje)).toEqual(['I', 'II', 'III']);
    expect(r.list.find((l) => l.linje === 'I')?.count).toBe(3);
    expect(r.list.find((l) => l.linje === 'II')?.count).toBe(2);
  });

  test('headId = medlemmet med laveste nr (stamfader)', () => {
    expect(r.list.find((l) => l.linje === 'I')?.headId).toBe('11');
    expect(r.list.find((l) => l.linje === 'II')?.headId).toBe('21');
  });

  test('manglende nr behandles som 9999 (bliver stamfader hvis eneste)', () => {
    expect(r.list.find((l) => l.linje === 'III')?.headId).toBe('30');
  });

  test('navn fra lineage-tabellen, fallback null når kode mangler navn', () => {
    expect(r.list.find((l) => l.linje === 'I')?.navn).toBe('Den holstenske linje');
    expect(r.list.find((l) => l.linje === 'III')?.navn).toBeNull();
  });

  test('tomme input → tom projektion (graceful)', () => {
    const empty = buildLineage([], []);
    expect(empty.list).toEqual([]);
    expect(empty.byPerson).toEqual({});
  });

  test('holder samme trykte kode adskilt mellem slægter med stabile lineage-kontekster', () => {
    const rows = [
      { id: '101', source_id: '1', kode: 'II', navn: 'Grevelig linje', slaegt_id: '10', slaegtsnavn: 'Reventlow' },
      { id: '202', source_id: '2', kode: 'II', navn: 'Hovedlinje', slaegt_id: '20', slaegtsnavn: 'Brahe' },
    ] as Array<RawLineage & { slaegt_id: string; slaegtsnavn: string }>;
    const result = buildLineage([
      x('reventlow-person', 'II', 1),
      { ...x('brahe-person', 'II', 1), source_id: '2' },
    ], rows);
    const reventlowKey = lineageContextKey({ slaegtId: '10', lineageId: '101' });
    const braheKey = lineageContextKey({ slaegtId: '20', lineageId: '202' });

    expect(reventlowKey).not.toBe(braheKey);
    expect(result.byPerson['reventlow-person']).toEqual([reventlowKey]);
    expect(result.byPerson['brahe-person']).toEqual([braheKey]);
    expect(result.navn[reventlowKey]).toBe('Reventlow · Grevelig linje');
    expect(result.navn[braheKey]).toBe('Brahe · Hovedlinje');
  });

  test('bevarer forskellige source-scheme-koder for samme kanoniske lineage', () => {
    const rows: Array<RawLineage & { slaegt_id: string }> = [
      { id: '101', source_id: '1', kode: 'II', navn: 'Grevelig linje', slaegt_id: '10' },
    ];
    const schemes = {
      schemes: [
        { id: 'stamtavle-1939', slaegt_id: '10', source_id: '1', kind: 'stamtavle' },
        { id: 'stamtavle-2018', slaegt_id: '10', source_id: '2', kind: 'stamtavle' },
      ],
      entries: [
        { id: 'entry-1939-ii', scheme_id: 'stamtavle-1939', code: 'II', label: 'II. linje' },
        { id: 'entry-2018-v', scheme_id: 'stamtavle-2018', code: 'V', label: 'V. linje' },
      ],
      mappings: [
        { entry_id: 'entry-1939-ii', lineage_id: '101', relation_kind: 'canonical' },
        { entry_id: 'entry-2018-v', lineage_id: '101', relation_kind: 'canonical' },
      ],
    };
    const result = buildLineage([
      x('from-1939', 'II', 1),
      { ...x('from-2018', 'V', 1), source_id: '2' },
    ], rows, {}, schemes);

    expect(result.byPerson['from-1939']).toEqual([
      lineageContextKey({ slaegtId: '10', lineageId: '101', schemeId: 'stamtavle-1939', schemeEntryId: 'entry-1939-ii' }),
    ]);
    expect(result.byPerson['from-2018']).toEqual([
      lineageContextKey({ slaegtId: '10', lineageId: '101', schemeId: 'stamtavle-2018', schemeEntryId: 'entry-2018-v' }),
    ]);
    expect(result.list.find((entry) => entry.linje === result.byPerson['from-2018'][0])?.navn)
      .toBe('Grevelig linje');
  });

  test('tolker legacy linje-kode som stamtavle, ikke som lige-kodet præsens-entry', () => {
    const rows: Array<RawLineage & { slaegt_id: string }> = [
      { id: '101', source_id: '1', kode: 'II', navn: 'Grevelig linje', slaegt_id: '10' },
    ];
    const result = buildLineage([x('person', 'II', 1)], rows, {}, {
      schemes: [
        { id: 'stamtavle', slaegt_id: '10', source_id: '1', kind: 'stamtavle' },
        { id: 'presens', slaegt_id: '10', source_id: '1', kind: 'presensliste' },
      ],
      entries: [
        { id: 'stamtavle-ii', scheme_id: 'stamtavle', code: 'II', label: 'II. linje' },
        { id: 'presens-ii', scheme_id: 'presens', code: 'II', label: 'II. linje' },
      ],
      mappings: [
        { entry_id: 'stamtavle-ii', lineage_id: '101', relation_kind: 'canonical' },
        { entry_id: 'presens-ii', lineage_id: '999', relation_kind: 'canonical' },
      ],
    });

    expect(result.byPerson.person).toEqual([
      lineageContextKey({ slaegtId: '10', lineageId: '101', schemeId: 'stamtavle', schemeEntryId: 'stamtavle-ii' }),
    ]);
  });

  test('bruger ikke en vilkårlig canonical mapping, når en scheme-entry er tvetydig', () => {
    const rows: Array<RawLineage & { slaegt_id: string }> = [
      { id: '101', source_id: '1', kode: 'II', navn: 'Grevelig linje', slaegt_id: '10' },
    ];
    const result = buildLineage([x('person', 'II', 1)], rows, {}, {
      schemes: [{ id: 'stamtavle', slaegt_id: '10', source_id: '1', kind: 'stamtavle' }],
      entries: [{ id: 'stamtavle-ii', scheme_id: 'stamtavle', code: 'II', label: 'II. linje' }],
      mappings: [
        { entry_id: 'stamtavle-ii', lineage_id: '101', relation_kind: 'canonical' },
        { entry_id: 'stamtavle-ii', lineage_id: '999', relation_kind: 'canonical' },
      ],
    });

    expect(result.byPerson.person).toEqual([
      lineageContextKey({ slaegtId: '10', lineageId: '101' }),
    ]);
  });
});
