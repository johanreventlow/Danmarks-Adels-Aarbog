import { describe, expect, it } from 'vitest';
import { byggErStamtavle } from '../stamtavleKilder';

describe('byggErStamtavle', () => {
  const linjer = [
    { source_id: 20, kode: 'A', slaegt_id: 1 },
    { source_id: '20', kode: 'B', slaegt_id: '2' },
    { source_id: 20, kode: 'C', slaegt_id: 3 },
    { source_id: 10, kode: 'B', slaegt_id: 1 },
  ];
  const skemaer = [
    { source_id: '20', slaegt_id: '1', kind: 'stamtavle' },
    { source_id: 20, slaegt_id: 2, kind: 'presensliste' },
    { source_id: 20, slaegt_id: 1, kind: 'editorial' },
    { source_id: 10, slaegt_id: 1, kind: 'editorial' },
    { source_id: 10, slaegt_id: 2, kind: 'presensliste' },
    { source_id: null, slaegt_id: 4, kind: 'stamtavle' },
  ];

  it('samme kilde: slægt A er stamtavle og slægt B er præsensliste', () => {
    const er = byggErStamtavle(linjer, skemaer);
    expect(er('20', 'A')).toBe(true);
    expect(er('20', 'B')).toBe(false);
  });

  it('skema for slægten uden stamtavle giver false', () => {
    expect(byggErStamtavle(linjer, skemaer)('10', 'B')).toBe(false);
  });

  it('slægt uden eget skema falder tilbage til kildens stamtavle', () => {
    expect(byggErStamtavle(linjer, skemaer)('20', 'C')).toBe(true);
  });

  it('ukendt linje falder tilbage til kildens stamtavle', () => {
    expect(byggErStamtavle(linjer, skemaer)('20', 'ukendt')).toBe(true);
  });

  it('kildeskemaer uden stamtavle giver false', () => {
    expect(byggErStamtavle(linjer, skemaer)('10', 'ukendt')).toBe(false);
  });

  it('ingen skemaer for kilden giver true, også med år-løst skema', () => {
    const er = byggErStamtavle(linjer, skemaer);
    expect(er('30', 'A')).toBe(true);
    expect(byggErStamtavle([], [])('20', 'A')).toBe(true);
  });

  it('linje uden slægt falder tilbage på kildeniveau', () => {
    expect(byggErStamtavle([{ source_id: 10, kode: 'A', slaegt_id: null }], skemaer)('10', 'A')).toBe(false);
  });
});
