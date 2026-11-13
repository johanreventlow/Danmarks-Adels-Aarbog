import { describe, it, expect } from 'vitest';
import { coordinateRowToExtId, compareLineHead, type PublicCoordinateRow } from '../placementCoordinates';

const row = (o: Partial<PublicCoordinateRow> = {}): PublicCoordinateRow => ({
  person_id: 7,
  source_id: 1,
  legacy_line_code: 'I',
  printed_number: 15,
  printed_number_label: '15a',
  generation_local: 3,
  generation_global: 7,
  kuld_label: null,
  provenance_kind: 'placement',
  ...o,
});

describe('coordinateRowToExtId', () => {
  it('mapper RPC-rækken til RawExtId med label og proveniens', () => {
    expect(coordinateRowToExtId(row({ kuld_label: 'II' }))).toEqual({
      person_id: 7,
      source_id: 1,
      linje: 'I',
      nr: 15,
      nr_label: '15a',
      slaegtled_lokal: 3,
      slaegtled_gennem: 7,
      kuld: 'II',
      provenance: 'placement',
      trykt_side: null,
    });
  });

  it('bærer printed_page videre som trykt_side', () => {
    expect(coordinateRowToExtId(row({ printed_page: '49' })).trykt_side).toBe('49');
  });

  it('bevarer null-koordinater (karantæne nedstrøms)', () => {
    const x = coordinateRowToExtId(row({
      legacy_line_code: null, printed_number: null, printed_number_label: null,
      generation_local: null, generation_global: null, kuld_label: null, provenance_kind: 'legacy_external_id',
    }));
    expect(x).toMatchObject({ linje: null, nr: null, nr_label: null, slaegtled_lokal: null, slaegtled_gennem: null, kuld: null, provenance: 'legacy_external_id' });
  });
});

describe('compareLineHead', () => {
  it('sorterer på heltal, derefter label, null sidst', () => {
    const xs = [{ nr: 16, nr_label: '16' }, { nr: null, nr_label: null }, { nr: 15, nr_label: '15b' }, { nr: 15, nr_label: '15a' }];
    expect([...xs].sort(compareLineHead).map((x) => x.nr_label)).toEqual(['15a', '15b', '16', null]);
  });

  it('uden label sorteres et rent heltal før et suffiks med samme tal', () => {
    expect(compareLineHead({ nr: 15 }, { nr: 15, nr_label: '15a' })).toBeLessThan(0);
  });
});
