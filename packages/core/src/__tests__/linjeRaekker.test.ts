import { describe, it, expect } from 'vitest';
import { byggLinjeRaekker } from '../linjeRaekker';
import { linjerForUdgave } from '../index';
import type { RawExtId, RawSource } from '../types';

const sources = [
  { id: -1, udgave: 'DAA 1920', titel: 'x', aar: 1920 },
  { id: -2, udgave: 'DAA 2018-20', titel: 'y', aar: 2018 },
  { id: -3, udgave: 'DAA 1939', titel: 'z', aar: 1939 },
] as unknown as RawSource[];
const schemeRows = {
  schemes: [
    { id: 1, slaegt_id: 1, source_id: -1, kind: 'stamtavle' },
    { id: 2, slaegt_id: 1, source_id: -2, kind: 'stamtavle' },
    { id: 3, slaegt_id: 1, source_id: -3, kind: 'stamtavle' },
  ],
  entries: [
    { id: 11, scheme_id: 1, code: 'V', label: 'V. Den grevelige linje af 1673' },
    { id: 22, scheme_id: 2, code: 'V', label: 'V. Den grevelige linje af 1673' },
    { id: 23, scheme_id: 2, code: 'III', label: 'III. Den mecklenburgske linje' },
    { id: 33, scheme_id: 3, code: 'IV', label: 'IV. Den danske grevelige Linje af 1673' },
  ],
  mappings: [
    { entry_id: 22, lineage_id: 100, relation_kind: 'canonical' },
    { entry_id: 33, lineage_id: 100, relation_kind: 'canonical' },
    { entry_id: 23, lineage_id: 101, relation_kind: 'canonical' },
    { entry_id: 22, lineage_id: 999, relation_kind: 'alias' },
  ],
} as never;
const ext = (o: Partial<RawExtId>): RawExtId => ({ person_id: 7, source_id: -2, linje: 'V', nr: 1, provenance: 'placement', ...o });

describe('byggLinjeRaekker', () => {
  it('bygger rækker pr. person med kanonisk lineageId og udgavenavn', () => {
    const out = byggLinjeRaekker([ext({}), ext({ linje: 'III' }), ext({ source_id: -3, linje: 'IV' })], sources, {}, schemeRows);
    expect(out['7'].map((x) => [x.sourceId, x.udgave, x.entry.code, x.lineageId])).toEqual([
      ['-2', 'DAA 2018-20', 'V', '100'], ['-2', 'DAA 2018-20', 'III', '101'], ['-3', 'DAA 1939', 'IV', '100'],
    ]);
    expect(linjerForUdgave(out['7'], '-2')).toEqual(['V. Den grevelige linje af 1673', 'III. Den mecklenburgske linje']);
    expect(linjerForUdgave(out['7'], '-1')).toEqual([]);
  });

  it('kilde 1-legacy med kode i skemaet giver sin linje; kilde 3-legacy-kode 1939 giver ingen', () => {
    const out = byggLinjeRaekker([
      ext({ source_id: -1, provenance: 'legacy_external_id' }),
      ext({ source_id: -3, linje: '1939', provenance: 'legacy_external_id' }),
    ], sources, {}, schemeRows);
    expect(linjerForUdgave(out['7'], '-1')).toEqual(['V. Den grevelige linje af 1673']);
    expect(linjerForUdgave(out['7'], '-3')).toEqual([]);
  });

  it('kilde uden stamtavleskema og rækker uden linje giver ingen række', () => {
    const out = byggLinjeRaekker([ext({ source_id: -9 }), ext({ linje: null })], sources, {}, schemeRows);
    expect(out['7']).toBeUndefined();
  });

  it('samler under kanonisk person og dedupliker', () => {
    const out = byggLinjeRaekker([ext({ person_id: 8 }), ext({ person_id: 8, nr: 2 })], sources, { '8': '7' }, schemeRows);
    expect(out['7']).toHaveLength(1);
  });
});
