import { describe, expect, it } from 'vitest';
import { buildPersonerMedBillede } from '../personerMedBillede';

describe('buildPersonerMedBillede', () => {
  it('folder alias-id\'er til kanoniske og fjerner dubletter', () => {
    expect([...buildPersonerMedBillede(['17', '3', '5'], { '17': '5' })].sort()).toEqual(['3', '5']);
  });
  it('tom liste giver tom mængde', () => {
    expect(buildPersonerMedBillede([], {}).size).toBe(0);
  });
});
