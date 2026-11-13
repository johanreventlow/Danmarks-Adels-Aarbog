// Læser citationer til proveniens med det beregnede felt side_trykt (findes først efter 6e-2's DDL).
// Før DDL afviser PostgREST kaldet; vi gentager så uden feltet. Den brede fangst er BEVIDST: den præcise
// fejlkode for et ukendt beregnet felt kendes ikke, og gentagelsen er en idempotent læsning. Det er en overgang,
// der fjernes, når 6e-2's DDL er i prod. Fejler også gentagelsen, logges begge fejl og resultatet er tomt.
export type CitationSvar = { data: unknown[] | null; error: unknown };
export type CitationForespoergsel = (medSideTrykt: boolean) => PromiseLike<CitationSvar>;

export async function laesCitationer(foresp: CitationForespoergsel): Promise<unknown[]> {
  const foerste = await foresp(true);
  if (!foerste.error) return foerste.data ?? [];
  console.warn('[public] proveniens: side_trykt ikke tilgængelig, gentager uden:', foerste.error);
  const anden = await foresp(false);
  if (anden.error) {
    console.error('[public] proveniens: citation-læsning fejlede (med og uden side_trykt):', foerste.error, anden.error);
    return [];
  }
  return anden.data ?? [];
}
