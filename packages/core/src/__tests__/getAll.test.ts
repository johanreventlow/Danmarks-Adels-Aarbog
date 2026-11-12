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
  it('kaster når loftet nås med en fuld sidste side (intet lydløst afkortet resultat)', async () => {
    const fuld = Array.from({ length: 1000 }, (_, i) => i);
    let call = 0;
    await expect(getAll<number>(() => ({
      range: async () => { call++; return { data: fuld, error: null }; },
    }))).rejects.toThrow(/loftet/);
    expect(call).toBe(400);
  });
  it('præcis på loftet med delvis sidste side → ok', async () => {
    const fuld = Array.from({ length: 1000 }, (_, i) => i);
    let call = 0;
    const rows = await getAll<number>(() => ({
      range: async () => {
        call++;
        return { data: call < 400 ? fuld : [1, 2, 3], error: null };
      },
    }));
    expect(call).toBe(400);
    expect(rows).toHaveLength(399 * 1000 + 3);
  });
  it('tom side efter fulde sider afslutter uden fejl', async () => {
    const pages = [Array.from({ length: 1000 }, (_, i) => i), []];
    let call = 0;
    const rows = await getAll<number>(() => ({
      range: async () => ({ data: pages[call++] ?? [], error: null }),
    }));
    expect(rows).toHaveLength(1000);
  });
});
