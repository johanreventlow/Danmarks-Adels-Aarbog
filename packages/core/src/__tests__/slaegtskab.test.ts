// Batch 7 (mobil-paritet): slægtskabslinjen over navnet bor nu i core. Web's egen test
// (web/src/data/__tests__/slaegtskab.test.ts) dækker reglerne gennem re-eksporten; her prøves den delte sti.
import { describe, expect, it } from 'vitest';
import { buildModel, type AppPerson, type Db } from '../index';
import { slaegtskabsKontekst } from '../slaegtskab';

const P = (id: string, koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, koen });
const db: Db = {
  persons: [P('F', 'mand'), P('B', 'mand'), P('X', 'kvinde')],
  unions: [{ id: 'f1', p1: 'B', p2: 'X', p2_name: null, year: null }],
  parentChild: [{ child: 'B', parent: 'F', union: 'f0' }],
};
const m = buildModel(db);

describe('slaegtskabsKontekst (core)', () => {
  it('skjult uden mig; dig; blod; gift med en blodslægtning; ingen', () => {
    expect(slaegtskabsKontekst(m, null, 'F')).toEqual({ art: 'skjult' });
    expect(slaegtskabsKontekst(m, 'B', 'B')).toEqual({ art: 'dig' });
    expect(slaegtskabsKontekst(m, 'B', 'X')).toEqual({ art: 'min-aegtefaelle' });
    expect(slaegtskabsKontekst(m, 'B', 'F')).toMatchObject({ art: 'blod', ord: 'din far', sikkerhed: 'sikker', veje: 1 });
    expect(slaegtskabsKontekst(m, 'F', 'X')).toMatchObject({ art: 'gift', aegtefaelleId: 'B', ord: 'din søn' });
  });
});
