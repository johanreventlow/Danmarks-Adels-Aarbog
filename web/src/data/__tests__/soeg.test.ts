import { describe, expect, it } from 'vitest';
import { soegFiltre, soegSti, STANDARD_FILTRE } from '../soeg';

describe('filtre i adressen', () => {
  it('tur-retur; kun afvigelser skrives', () => {
    expect(soegSti({ q: 'Conrad' })).toBe('/soeg?q=Conrad');
    expect(soegSti(STANDARD_FILTRE)).toBe('/soeg');
    const f = { ...STANDARD_FILTRE, q: 'a b', type: 'personer' as const, linje: 'k:1', fra: 1600, til: 1900, sort: 'foedt' as const, bm: true };
    expect(soegFiltre(soegSti(f).split('?')[1])).toEqual(f);
  });
  it('type=godser (fra før fase 7a) betyder besiddelser', () => {
    expect(soegFiltre('?type=godser').type).toBe('besiddelser');
  });
  it('ugyldige værdier falder tilbage til standarden', () => {
    expect(soegFiltre('?type=x&sort=y&fra=abc&bm=2')).toEqual(STANDARD_FILTRE);
  });
});
