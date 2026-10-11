import { beforeEach, describe, expect, it, vi } from 'vitest';

let rpc = vi.fn();
vi.mock('../../supabase', () => ({ supabase: { rpc: (n: string, a: unknown) => rpc(n, a) } }));
const { fetchFamilySources } = await import('../familySources');
beforeEach(() => { rpc = vi.fn(); });

describe('fetchFamilySources', () => {
  it(`kalder RPC med decimalstrenge og former rækkerne`, async () => {
    rpc.mockResolvedValueOnce({ data: [{ family_id: 10, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: 'r', source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' }], error: null });
    const ud = await fetchFamilySources(['10', 'x', '10', '9999999999999999999']);
    expect(rpc).toHaveBeenCalledWith('public_family_sources', { p_family_ids: ['10'] });
    expect(ud[0].recordLabel).toBe('Post 1');
    expect(ud[0].familyId).toBe('10');
  });
  it('rpc_fejl_giver_tom', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Could not find the function' } });
    expect(await fetchFamilySources(['10'])).toEqual([]);
    rpc.mockRejectedValueOnce(new Error('net'));
    expect(await fetchFamilySources(['10'])).toEqual([]);
  });
  it(`ingen id'er ⇒ intet kald`, async () => {
    expect(await fetchFamilySources([])).toEqual([]);
    expect(await fetchFamilySources(['x'])).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
  });
});
