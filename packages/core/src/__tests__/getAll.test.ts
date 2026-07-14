import { describe, it, expect } from 'vitest';
import { getAll } from '../getAll';

describe('getAll', () => {
  it('paginerer indtil kort side', async () => {
    const pages = [Array.from({ length: 1000 }, (_, i) => i), [1000, 1001]];
    let call = 0;
    const rows = await getAll<number>(() => ({
      range: async () => ({ data: pages[call++] ?? [], error: null }),
    }));
    expect(rows).toHaveLength(1002);
  });
  it('kaster ved supabase-error', async () => {
    await expect(getAll<number>(() => ({
      range: async () => ({ data: null, error: { message: 'RLS' } }),
    }))).rejects.toBeTruthy();
  });
});
