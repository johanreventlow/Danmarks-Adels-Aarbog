import { previewSammeSom } from '../sammeSomPreflight';
import type { Db, AppPerson } from '../types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson =>
  ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o });

describe('previewSammeSom (rådgivende)', () => {
  it('rent link folder → folder=true, ingen grund', () => {
    const db: Db = { persons: [P('a'), P('b')], unions: [], parentChild: [] };
    expect(previewSammeSom(db, [], { alias: 'a', canonical: 'b' })).toEqual({ folder: true, grund: null });
  });
  it('køn-konflikt → folder=false med grund', () => {
    const db: Db = { persons: [P('a', { koen: 'mand' }), P('b', { koen: 'kvinde' })], unions: [], parentChild: [] };
    const r = previewSammeSom(db, [], { alias: 'a', canonical: 'b' });
    expect(r.folder).toBe(false);
    expect(r.grund).toMatch(/køn/i);
  });
  it('konkurrerende forældre → folder=false', () => {
    const db: Db = {
      persons: [P('a'), P('b'), P('p1'), P('p2')],
      unions: [],
      parentChild: [
        { child: 'a', parent: 'p1', union: 'f1' },
        { child: 'b', parent: 'p2', union: 'f2' },
      ],
    };
    const r = previewSammeSom(db, [], { alias: 'a', canonical: 'b' });
    expect(r.folder).toBe(false);
    expect(r.grund).toMatch(/forældre/i);
  });
});
