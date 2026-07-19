import { beforeEach, describe, expect, it, vi } from 'vitest';

let rows: Record<string, unknown>[] = [];
let shouldThrow = false;

vi.mock('../../supabase', () => ({
  supabase: {
    from() {
      if (shouldThrow) throw new Error('netværksfejl');
      const builder = {
        select: () => builder,
        order: () => builder,
        range: async (from: number, to: number) => ({ data: rows.slice(from, to + 1), error: null }),
        then(resolve: (value: { data: Record<string, unknown>[]; error: null }) => void) {
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
      };
      return builder;
    },
  },
}));

const { fetchFeedPins } = await import('../feedPins');

beforeEach(() => { rows = []; shouldThrow = false; });

describe('fetchFeedPins', () => {
  it('normaliserer og sorterer via buildFeedPins', async () => {
    rows = [
      { kort_noegle: 'portrait:2', handling: 'pin', oprettet_naar: '2026-07-02T00:00:00Z' },
      { kort_noegle: 'story:1', handling: 'skjul', oprettet_naar: '2026-07-01T00:00:00Z' },
    ];
    expect(await fetchFeedPins()).toEqual([
      { kortNoegle: 'story:1', handling: 'skjul' },
      { kortNoegle: 'portrait:2', handling: 'pin' },
    ]);
  });

  it('fejl giver [] og warn', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    shouldThrow = true;
    await expect(fetchFeedPins()).resolves.toEqual([]);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});
