import { describe, it, expect } from 'vitest';
import { b6Noter, linjerForUdgave, type LinjeRaekke } from '../b6Note';

const r = (o: Partial<LinjeRaekke> & Pick<LinjeRaekke, 'sourceId' | 'udgave'>): LinjeRaekke => ({
  entry: { code: 'V', label: 'V. Den grevelige linje af 1673' },
  lineageId: null,
  provenance: 'placement',
  ...o,
});

const III = { code: 'III', label: 'III. Den mecklenburgske linje' };
const V = { code: 'V', label: 'V. Den grevelige linje af 1673' };
const IV39 = { code: 'IV', label: 'IV. Den danske grevelige Linje af 1673' };

describe('linjerForUdgave', () => {
  const conrad = [r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: III }), r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V })];

  it('giver den valgte udgaves linjetitler', () => {
    expect(linjerForUdgave(conrad, '-2')).toEqual(['III. Den mecklenburgske linje', 'V. Den grevelige linje af 1673']);
  });

  it('valgt udgave uden rækker giver []', () => {
    expect(linjerForUdgave(conrad, '-3')).toEqual([]);
  });

  it('unikke titler i rækkefølgen af første forekomst', () => {
    expect(linjerForUdgave([...conrad, ...conrad].reverse(), '-2')).toEqual(['V. Den grevelige linje af 1673', 'III. Den mecklenburgske linje']);
  });

  it('legacy-række med kode i skemaet tæller som i dag', () => {
    expect(linjerForUdgave([r({ sourceId: '-1', udgave: 'DAA 1920', provenance: 'legacy_external_id' })], '-1')).toEqual(['V. Den grevelige linje af 1673']);
  });
});

describe('b6Noter', () => {
  it('samme lineageId i en anden udgave giver en bekræftelse', () => {
    const rs = [
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' }),
      r({ sourceId: '-3', udgave: 'DAA 1939', entry: IV39, lineageId: '10' }),
    ];
    expect(b6Noter(rs, '-2')).toEqual(['✓ også i DAA 1939 (IV. Den danske grevelige Linje af 1673)']);
  });

  it('forskelligt lineageId giver »placerer i«', () => {
    const rs = [
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' }),
      r({ sourceId: '-3', udgave: 'DAA 1939', entry: IV39, lineageId: '11' }),
    ];
    expect(b6Noter(rs, '-2')).toEqual(['DAA 1939 placerer i: IV. Den danske grevelige Linje af 1673']);
  });

  it('kun den valgte kildes rækker giver ingen note', () => {
    const rs = [r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: III, lineageId: '9' }), r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' })];
    expect(b6Noter(rs, '-2')).toEqual([]);
  });

  it('legacy giver aldrig en note', () => {
    const rs = [
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' }),
      r({ sourceId: '-3', udgave: 'DAA 1939', entry: IV39, lineageId: '10', provenance: 'legacy_external_id' }),
    ];
    expect(b6Noter(rs, '-2')).toEqual([]);
  });

  it('flere linjer i den valgte kilde: lineageId matcher mod en af dem', () => {
    const rs = [
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: III, lineageId: '9' }),
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' }),
      r({ sourceId: '-3', udgave: 'DAA 1939', entry: IV39, lineageId: '10' }),
    ];
    expect(b6Noter(rs, '-2')).toEqual(['✓ også i DAA 1939 (IV. Den danske grevelige Linje af 1673)']);
  });

  it('uden lineageId i den anden kilde: »placerer i«', () => {
    const rs = [
      r({ sourceId: '-2', udgave: 'DAA 2018-20', entry: V, lineageId: '10' }),
      r({ sourceId: '-3', udgave: 'DAA 1939', entry: IV39, lineageId: null }),
    ];
    expect(b6Noter(rs, '-2')).toEqual(['DAA 1939 placerer i: IV. Den danske grevelige Linje af 1673']);
  });
});
