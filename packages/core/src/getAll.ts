// getAll — fælles paginerings-helper for web+mobile (@daa/core, eneste kilde).
// PostgREST capper lydløst ved 1000 rækker — getAll gentager .range indtil en kort/tom side.
// Kaster videre ved Supabase-error (ingen tom-som-clean: en RLS/grant-fejl skal ikke ligne 0 rækker).
//
// KALDERENS ANSVAR:
// - Sæt `.order(...)` på en ENTYDIG nøgle (PK, eller alle kolonner i en sammensat PK) i makeQuery.
//   Offset-paginering uden fast rækkefølge kan springe rækker over eller gentage dem mellem siderne,
//   fordi Postgres ikke lover samme rækkefølge fra kald til kald.
// - Offset-paginér ikke RPC'er: funktionen beregnes forfra for HVER side (dyrt), og uden en garanteret
//   orden i resultatet gælder samme risiko for huller/dubletter. Hent RPC-resultater i ét kald.
//
// Loftet (MAX_PAGES × PAGE rækker) er en nødbremse mod uendelige løkker. Rammes det med en fuld
// sidste side, findes der muligvis flere rækker — så kaster vi i stedet for at returnere et
// lydløst afkortet resultat.
const PAGE = 1000;
const MAX_PAGES = 400;

export async function getAll<T>(
  makeQuery: () => {
    range: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>;
  },
): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  for (let i = 0; i < MAX_PAGES; i++) {
    const { data, error } = await makeQuery().range(from, from + PAGE - 1);
    if (error) throw error;
    const chunk = data ?? [];
    if (!chunk.length) return all;
    all.push(...chunk);
    if (chunk.length < PAGE) return all;
    from += PAGE;
  }
  throw new Error(
    `getAll: loftet på ${MAX_PAGES} sider à ${PAGE} rækker er nået, og sidste side var fuld — ` +
      'resultatet ville være afkortet. Afgræns forespørgslen eller hæv loftet bevidst.',
  );
}
