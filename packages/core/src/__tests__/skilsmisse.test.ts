import { describe, expect, it } from 'vitest';
import { buildModel } from '../buildModel';
import { byggSkilsmisser, fmtSkilt, parSkilsmisse } from '../skilsmisse';
import type { AppPerson } from '../types';

const persons: AppPerson[] = ['a', 'b', 'c'].map((id) => ({
  id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false,
}));
const basis = buildModel({ persons, unions: [
  { id: 'f350', p1: 'a', p2: 'b', p2_name: null, year: null },
  { id: 'f351', p1: 'b', p2: 'a', p2_name: null, year: null },
  { id: 'f360', p1: 'a', p2: 'c', p2_name: null, year: null },
], parentChild: [] });

describe('skilsmisse', () => {
  it('byggSkilsmisser nøgler på familie-id og bærer datoerne', () => {
    expect(byggSkilsmisser([{ id: 9, subjekt_id: 350 }], [{ target_id: 9, valgt_assertion_id: 4 }],
      [{ id: 4, date_min: '1901-10-12', date_max: '1901-10-12' }])).toEqual({ '350': { dateMin: '1901-10-12', dateMax: '1901-10-12' } });
  });
  it('byggSkilsmisser ignorerer ukendt fact og manglende påstand', () => {
    expect(byggSkilsmisser([{ id: 9, subjekt_id: 350 }],
      [{ target_id: 8, valgt_assertion_id: 4 }, { target_id: 9, valgt_assertion_id: 5 }, { target_id: 9, valgt_assertion_id: null }],
      [{ id: 4, date_min: null, date_max: null }])).toEqual({});
  });
  it('fmtSkilt: dag, år og ord', () => {
    const s = { dateMin: '1901-10-12', dateMax: '1901-10-12' };
    expect(fmtSkilt(s, 'dag')).toBe('skilt 12. okt. 1901');
    expect(fmtSkilt(s, 'aar')).toBe('skilt 1901');
    expect(fmtSkilt(s, 'ord')).toBe('skilt');
    expect(fmtSkilt({ dateMin: '1901-01-01', dateMax: '1901-12-31' }, 'dag')).toBe('skilt 1901');
    expect(fmtSkilt({ dateMin: '1900-01-01', dateMax: '1901-12-31' }, 'aar')).toBe('skilt');
    expect(fmtSkilt({ dateMin: 'xx', dateMax: 'xx' }, 'dag')).toBe('skilt');
    expect(fmtSkilt({ dateMin: null, dateMax: null }, 'dag')).toBe('skilt');
  });
  it('parSkilsmisse: skilt hvis bare én af parrets familier har skilsmissen (samme_som-kopi)', () => {
    const model = { ...basis, skilsmisser: { '350': { dateMin: null, dateMax: null } } };
    expect(parSkilsmisse(model, 'a', 'b')).toEqual({ dateMin: null, dateMax: null });
    expect(parSkilsmisse(model, 'b', 'a')).toEqual({ dateMin: null, dateMax: null });
  });
  it('parSkilsmisse: foldet alias-partner i unionen findes via kanoniske id er', () => {
    const model = {
      ...basis, canonicalIdById: { a1939: 'a' },
      indexes: { ...basis.indexes, unionById: { ...basis.indexes.unionById,
        f351: { id: 'f351', p1: 'b', p2: 'a1939', p2_name: null, year: null } } },
      skilsmisser: { '351': { dateMin: '2001-05-01', dateMax: '2001-05-01' } },
    };
    expect(parSkilsmisse(model, 'a', 'b')).toEqual({ dateMin: '2001-05-01', dateMax: '2001-05-01' });
    expect(parSkilsmisse(model, 'a1939', 'b')).toEqual({ dateMin: '2001-05-01', dateMax: '2001-05-01' });
  });
  it('parSkilsmisse: null når ingen familie er skilt; undefined når skilsmisser er null eller mangler', () => {
    expect(parSkilsmisse({ ...basis, skilsmisser: { '350': { dateMin: null, dateMax: null } } }, 'a', 'c')).toBeNull();
    expect(parSkilsmisse({ ...basis, skilsmisser: {} }, 'a', 'b')).toBeNull();
    expect(parSkilsmisse({ ...basis, skilsmisser: null }, 'a', 'b')).toBeUndefined();
    expect(parSkilsmisse(basis, 'a', 'b')).toBeUndefined();
  });
});
