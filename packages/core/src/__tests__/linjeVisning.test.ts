import { describe, expect, test } from 'vitest';
import { linjeKodeOgNavn, linjeTitel } from '../linjeVisning';

describe('linjeTitel', () => {
  test('uden præfiks i etiketten (2018-20)', () => {
    expect(linjeTitel({ code: 'V', label: 'Den grevelige linje af 1673' })).toBe('V. Den grevelige linje af 1673');
  });
  test('romertal-præfiks og afsluttende punktum fjernes', () => {
    expect(linjeTitel({ code: 'IV', label: 'IV. Den danske grevelige Linje af 1673.' })).toBe('IV. Den danske grevelige Linje af 1673');
  });
  test('bogstav-præfiks (stammeafsnit) giver bogstavet som kode', () => {
    expect(linjeTitel({ code: 'Stamme-holstenske', label: 'A. Den holstenske Linje.' })).toBe('A. Den holstenske Linje');
    expect(linjeKodeOgNavn({ code: 'Stamme-holstenske', label: 'A. Den holstenske Linje.' }).kode).toBe('A');
  });
  test('før ceremonien: ingen præfiks → koden bruges', () => {
    expect(linjeTitel({ code: 'Stamme-holstenske', label: 'Den holstenske Linje.' })).toBe('Stamme-holstenske. Den holstenske Linje');
  });
  test('tom etiket → navn = kode', () => {
    expect(linjeKodeOgNavn({ code: 'VI', label: null })).toEqual({ kode: 'VI', navn: 'VI' });
    expect(linjeKodeOgNavn({ code: 'VI', label: '' })).toEqual({ kode: 'VI', navn: 'VI' });
  });
});
