import { describe, expect, it } from 'vitest';
import { buildHaendelserBy } from '../haendelser';
import type { HaendelseRow } from '../haendelser';

function row(id: number, over: Partial<HaendelseRow> = {}): HaendelseRow {
  return {
    id, subjekt_id: 'p1', narrative_id: 10, klausul: `Klausul ${id}`,
    kategori: null, date_min: null, date_max: null, date_qualifier: null,
    date_raw: null, feed_status: 'kandidat', fact_id: null, relation_id: null,
    ...over,
  };
}

describe('buildHaendelserBy', () => {
  it('joiner narrativ/source, kanoniserer og afleder status- og rygradsfelter', () => {
    const out = buildHaendelserBy(
      [row(1, { subjekt_id: 'alias', feed_status: 'interessant', fact_id: 99 })],
      [{ id: 10, source_id: 20, side: '209-211' }],
      [{ id: 20, udgave: '2018-20' }],
      { alias: 'kanonisk' },
    );
    expect(out.kanonisk).toEqual([expect.objectContaining({
      id: '1', interessant: true, rygrad: true, kilde: 'DAA 2018-20, s. 209-211',
    })]);
    const viaRelation = buildHaendelserBy(
      [row(2, { relation_id: 77 })], [], [],
    );
    expect(viaRelation.p1[0].rygrad).toBe(true);
  });

  it('sorterer dato stigende, NULL sidst og id som tiebreak', () => {
    const out = buildHaendelserBy([
      row(12),
      row(2, { date_min: '1700-01-01' }),
      row(10, { date_min: '1700-01-01' }),
      row(3, { date_min: '1600-01-01' }),
    ], [], []);
    expect(out.p1.map((x) => x.id)).toEqual(['3', '10', '2', '12']);
  });

  it('filtrerer skjult defensivt og giver null-kilde uden source', () => {
    const out = buildHaendelserBy([
      row(1, { feed_status: 'skjult' }), row(2),
    ], [{ id: 10, source_id: null, side: '5' }], []);
    expect(out.p1).toEqual([expect.objectContaining({ id: '2', kilde: null })]);
  });

  it('sammensætter kilde uden side og håndterer tomme input', () => {
    const out = buildHaendelserBy(
      [row(1)], [{ id: 10, source_id: 20, side: null }], [{ id: 20, udgave: 1939 }],
    );
    expect(out.p1[0].kilde).toBe('DAA 1939');
    expect(buildHaendelserBy([], [], [])).toEqual({});
  });
});
