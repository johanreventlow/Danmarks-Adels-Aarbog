import { describe, it, expect } from 'vitest';
import { mapNarrativer } from '../redaktionRead';

describe('mapNarrativer', () => {
  it('mapper rækker med source-join, ordnet efter source_id så id', () => {
    const rows = [
      { id: 7, source_id: 2, side: null, tekst: 'B', privat: false, source: { titel: 'DAA 1982', udgave: 'DAA 1982-84' } },
      { id: 3, source_id: 1, side: '10', tekst: 'A', privat: true, source: { titel: 'DAA 2018', udgave: 'DAA 2018-20' } },
    ];
    const out = mapNarrativer(rows as any);
    expect(out.map((n) => n.id)).toEqual([3, 7]);
    expect(out[0]).toMatchObject({ sourceId: 1, udgave: 'DAA 2018-20', side: '10', privat: true, tekst: 'A' });
    expect(out[1]).toMatchObject({ sourceId: 2, udgave: 'DAA 1982-84', side: null, privat: false });
  });
  it('håndterer manglende source-join (null)', () => {
    const out = mapNarrativer([{ id: 1, source_id: null, side: null, tekst: 'x', privat: null, source: null }] as any);
    expect(out[0]).toMatchObject({ sourceId: null, sourceTitel: null, udgave: null, privat: false });
  });
});
