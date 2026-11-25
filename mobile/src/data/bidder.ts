// Bid-hjælpere til gæsteloftet (3 s pr. kald i prod): del id-lister i bidder og kør dem med begrænset parallelitet.
// Spejl af web/src/data/forside/kilder.ts (chunks, mapLimited) og web/src/data/orThrow.ts.

export function chunks<T>(values: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

export async function mapLimited<T, R>(items: readonly T[], limit: number, fn: (item: T) => PromiseLike<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

// supabase-js kaster ikke selv: en RLS-/grant-/netfejl kommer som `{ data: null, error }`, og et blot `data ?? []`
// gør den til "ingen data". orThrow kaster fejlen frem, så kalderen kan skelne fejl fra tomt.
export function orThrow<T>(res: { data: T; error?: unknown }, label: string): T {
  if (res.error) {
    throw Object.assign(
      new Error(`${label}: ${(res.error as { message?: string })?.message ?? 'ukendt fejl'}`),
      { cause: res.error },
    );
  }
  return res.data;
}
