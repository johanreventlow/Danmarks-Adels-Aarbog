// getAll — fælles paginerings-helper for web+mobile (@daa/core, eneste kilde).
// PostgREST capper lydløst ved 1000 rækker — getAll gentager .range indtil en kort/tom side.
// Kaster videre ved Supabase-error (ingen tom-som-clean: en RLS/grant-fejl skal ikke ligne 0 rækker).
const PAGE = 1000;

export async function getAll<T>(
  makeQuery: () => {
    range: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>;
  },
): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  for (let i = 0; i < 400; i++) {
    const { data, error } = await makeQuery().range(from, from + PAGE - 1);
    if (error) throw error;
    const chunk = data ?? [];
    if (!chunk.length) break;
    all.push(...chunk);
    if (chunk.length < PAGE) break;
    from += PAGE;
  }
  return all;
}
