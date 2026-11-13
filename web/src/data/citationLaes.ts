// Læser citationer til proveniens med det beregnede felt side_trykt (findes først efter 6e-2's DDL).
// Før DDL afviser PostgREST kaldet fordi feltet mangler; kun DEN fejl udløser en gentagelse uden feltet.
// Kriterium: kode 42703 / PGRST204 / PGRST200, eller fejlen nævner side_trykt. Alle andre fejl (fx timeout 57014)
// logges og giver tom liste uden gentagelse.
// Før DDL viser gentagelsen bevidst `side` (PDF-siden), som i dag: det er den planlagte overgang, ikke en garanti for, at
// den rå PDF-side aldrig vises. Efter DDL giver side_trykt = null kun værket.
// Overgang: fjernes, når 6e-2's DDL er i prod.
export type CitationSvar = { data: unknown[] | null; error: unknown };
export type CitationForespoergsel = (medSideTrykt: boolean) => PromiseLike<CitationSvar>;

const MANGLER_FELT_KODER = new Set(['42703', 'PGRST204', 'PGRST200']);

function manglerSideTrykt(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const e = error as Record<string, unknown>;
  if (typeof e.code === 'string' && MANGLER_FELT_KODER.has(e.code)) return true;
  return ['message', 'details', 'hint'].some((k) => typeof e[k] === 'string' && (e[k] as string).includes('side_trykt'));
}

export async function laesCitationer(foresp: CitationForespoergsel): Promise<unknown[]> {
  const foerste = await foresp(true);
  if (!foerste.error) return foerste.data ?? [];
  if (!manglerSideTrykt(foerste.error)) {
    console.error('[public] proveniens: citation-læsning fejlede:', foerste.error);
    return [];
  }
  console.warn('[public] proveniens: side_trykt ikke tilgængelig, gentager uden:', foerste.error);
  const anden = await foresp(false);
  if (anden.error) {
    console.error('[public] proveniens: citation-læsning fejlede (med og uden side_trykt):', foerste.error, anden.error);
    return [];
  }
  return anden.data ?? [];
}
