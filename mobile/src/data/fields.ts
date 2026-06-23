// Felt-hjælpere — port fra design-HTML (parseYear linje 872, fmtYears 873-880, stripParen 812).

// Første 3-4-cifrede årstal i en streng, ellers null.
export function parseYear(s: string | null | undefined): number | null {
  if (s == null) return null;
  const m = String(s).match(/\d{3,4}/);
  return m ? parseInt(m[0], 10) : null;
}

// Ordret leveår-visning: "1640–1708", "* 1640", "† 1708" eller tom.
export function fmtYears(f: string | null | undefined, d: string | null | undefined): string {
  const clean = (s: string | null | undefined) =>
    s == null ? '' : String(s).replace(/^[*†\s]+/, '').trim();
  const F = clean(f);
  const D = clean(d);
  if (F && D) return F + '–' + D;
  if (F) return '* ' + F;
  if (D) return '† ' + D;
  return '';
}

// Fjern omkransende parenteser/whitespace fra periode-tekst.
export function stripParen(s: string | null | undefined): string {
  return s == null ? '' : String(s).replace(/^[\s(]+|[\s)]+$/g, '').trim();
}
