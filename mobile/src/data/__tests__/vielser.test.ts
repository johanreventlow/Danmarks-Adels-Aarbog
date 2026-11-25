// Paritetsplanens batch 6: ⚭-datoer på mobilen. Hentningen deler id-listerne i bidder à højst 200 (gæsteloftet),
// og enhver fejl i kæden giver ingen ⚭ frem for en fejlet skærm.
import { buildModel, type Db } from '@daa/core';
import { hentVielsesDatoer, vielseForAegtefaeller, vielsesFamilier, VIELSE_BID } from '../vielser';

type Rows = Record<string, unknown[] | 'fejl' | 'kast'>;
// Filtrerer på .in()-listen (som PostgREST), så hver bid kun får sine egne rækker.
function fakeSb(byTable: Rows) {
  const inStoerrelser: Record<string, number[]> = {};
  const sb = {
    from: (table: string) => {
      let filter: { kol: string; vals: Set<string> } | null = null;
      const b: Record<string, unknown> = {
        select: () => b,
        eq: () => b,
        in: (kol: string, vals: unknown[]) => {
          if (kol !== 'status') {
            (inStoerrelser[table] ??= []).push(vals.length);
            filter = { kol, vals: new Set(vals.map(String)) };
          }
          return b;
        },
        order: () => b,
        range: async (from: number) => {
          const r = byTable[table];
          if (r === 'kast') throw new Error('netfejl');
          if (r === 'fejl') return { data: null, error: { code: '57014', message: 'statement timeout' } };
          const f = filter;
          const rows = (r ?? []).filter((x) => !f || f.vals.has(String((x as Record<string, unknown>)[f.kol])));
          return { data: from === 0 ? rows : [], error: null };
        },
      };
      return b;
    },
  };
  return { sb: sb as never, inStoerrelser };
}

const fam = (n: number) => Array.from({ length: n }, (_, i) => String(1000 + i));

describe('hentVielsesDatoer', () => {
  test('kæden giver færdig tekst pr. familie, den mest præcise vinder', async () => {
    const { sb } = fakeSb({
      fact: [{ id: 1, subjekt_id: 100 }, { id: 2, subjekt_id: 100 }],
      conclusion: [{ target_id: 1, valgt_assertion_id: 11 }, { target_id: 2, valgt_assertion_id: 12 }],
      assertion: [
        { id: 11, date_min: '1667-01-01', date_max: '1667-12-31', date_qualifier: null, date_raw: '1667' },
        { id: 12, date_min: '1667-07-21', date_max: '1667-07-21', date_qualifier: null, date_raw: '21.7.1667' },
      ],
    });
    expect(await hentVielsesDatoer(sb, ['100'])).toEqual({ '100': '⚭ 21. juli 1667' });
  });

  test('hver id-liste deles i bidder à højst 200', async () => {
    expect(VIELSE_BID).toBeLessThanOrEqual(200);
    const facts = Array.from({ length: 450 }, (_, i) => ({ id: i + 1, subjekt_id: 1000 + i }));
    const { sb, inStoerrelser } = fakeSb({
      fact: facts,
      conclusion: facts.map((f) => ({ target_id: f.id, valgt_assertion_id: 5000 + f.id })),
      assertion: facts.map((f) => ({ id: 5000 + f.id, date_min: '1700-01-01', date_max: '1700-12-31' })),
    });
    const ud = await hentVielsesDatoer(sb, fam(450));
    expect(Object.keys(ud)).toHaveLength(450);
    for (const t of ['fact', 'conclusion', 'assertion']) {
      expect(inStoerrelser[t].length).toBeGreaterThan(1);
      expect(Math.max(...inStoerrelser[t])).toBeLessThanOrEqual(200);
      expect(inStoerrelser[t].reduce((a, b) => a + b, 0)).toBe(450);
    }
  });

  test.each(['fejl', 'kast'] as const)('kæden brister (%s) → ingen ⚭', async (art) => {
    for (const t of ['fact', 'conclusion', 'assertion']) {
      const { sb } = fakeSb({
        fact: [{ id: 1, subjekt_id: 100 }], conclusion: [{ target_id: 1, valgt_assertion_id: 11 }],
        assertion: [{ id: 11, date_min: '1667-07-21', date_max: '1667-07-21' }], [t]: art,
      });
      expect(await hentVielsesDatoer(sb, ['100'])).toEqual({});
    }
  });

  test('ingen klient (offline) eller ingen familier → ingen kald, ingen ⚭', async () => {
    expect(await hentVielsesDatoer(null, ['100'])).toEqual({});
    const { sb, inStoerrelser } = fakeSb({});
    expect(await hentVielsesDatoer(sb, [])).toEqual({});
    expect(inStoerrelser).toEqual({});
  });
});

describe('vielse pr. ægtefælle', () => {
  const P = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, koen: null });
  const db: Db = {
    persons: [P('A'), P('B'), P('C')],
    unions: [
      { id: 'f1', p1: 'A', p2: 'B', p2_name: null, year: null },
      { id: 'f2', p1: 'A', p2: 'B', p2_name: null, year: null }, // samme par i en anden udgave
      { id: 'f3', p1: 'A', p2: 'C', p2_name: null, year: null },
    ],
    parentChild: [],
  };
  const m = buildModel(db);

  test('personens familier og den mest præcise dato pr. ægtefælle', () => {
    expect(vielsesFamilier(m.indexes, 'A')).toEqual(['1', '2', '3']);
    expect(vielseForAegtefaeller(m.indexes, 'A', { '1': '⚭ 1667', '2': '⚭ 21. juli 1667', '3': '⚭ ca. 1690' }))
      .toEqual({ B: '⚭ 21. juli 1667', C: '⚭ ca. 1690' });
  });
});
