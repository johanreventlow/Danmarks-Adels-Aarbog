import { fetchFeedPins } from '../feedPins';

function fakeSupabase(rows: Record<string, unknown>[]) {
  const sb = {
    from() {
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
  };
  return sb;
}

describe('fetchFeedPins', () => {
  it('normaliserer og sorterer deterministisk', async () => {
    const out = await fetchFeedPins(fakeSupabase([
      { kort_noegle: 'portrait:2', handling: 'pin', oprettet_naar: '2026-07-02T00:00:00Z' },
      { kort_noegle: 'story:1', handling: 'skjul', oprettet_naar: '2026-07-01T00:00:00Z' },
    ]) as never);
    expect(out).toEqual([
      { kortNoegle: 'story:1', handling: 'skjul' },
      { kortNoegle: 'portrait:2', handling: 'pin' },
    ]);
  });

  it('fejl giver [] og warn', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const broken = { from: () => { throw new Error('netværksfejl'); } };
    await expect(fetchFeedPins(broken as never)).resolves.toEqual([]);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});
