// Felt-hjælpere — port fra design-HTML (parseYear linje 872, fmtYears 873-880, stripParen 812).

// Første 3-4-cifrede årstal i en streng, ellers null.
export function parseYear(s: string | null | undefined): number | null {
  if (s == null) return null;
  const m = String(s).match(/\d{3,4}/);
  return m ? parseInt(m[0], 10) : null;
}

// Alle årstal i en dato som spænd: »† 1406/1410« → [1406, 1410], »17. aug. 1840« → [1840, 1840]. Dage og
// måneder (1–2 cifre) tæller ikke. Null uden årstal (fx en uopløst »s.å.«).
export function aarSpaend(s: string | null | undefined): [number, number] | null {
  if (s == null) return null;
  const aar = [...String(s).matchAll(/\d{3,4}/g)].map((m) => parseInt(m[0], 10));
  return aar.length ? [Math.min(...aar), Math.max(...aar)] : null;
}

// Ordret leveår-visning: "* 1640 † 1708", "* 1640", "† 1708" eller tom (Aarbogens tegn, ikke bindestreg:
// »1688–lille« læses forkert, »* 1688 † lille« gør ikke).
export function fmtYears(f: string | null | undefined, d: string | null | undefined): string {
  const clean = (s: string | null | undefined) =>
    s == null ? '' : String(s).replace(/^[*†\s]+/, '').trim();
  const F = clean(f);
  const D = clean(d);
  if (F && D) return '* ' + F + ' † ' + D;
  if (F) return '* ' + F;
  if (D) return '† ' + D;
  return '';
}

// Visningsår: livsdatoer vinder; ellers »Nævnes <floruit>« (DB-kolonnen visning_floruit); ellers tom.
export function fmtVisningsAar(
  foedt: string | null | undefined,
  doed: string | null | undefined,
  floruit: string | null | undefined,
): string {
  const liv = fmtYears(foedt, doed);
  if (liv) return liv;
  return floruit ? 'Nævnes ' + floruit : '';
}

// Forening af floruit-værdier (»1671« eller »1349–1391«, en-dash): mindste lo til største hi.
// Værdier der ikke matcher formen ignoreres; ingen gyldige → null.
export function fletFloruit(vaerdier: (string | null | undefined)[]): string | null {
  const aar: number[] = [];
  for (const v of vaerdier) {
    const m = v == null ? null : /^(\d{3,4})(?:–(\d{3,4}))?$/.exec(v);
    if (m) aar.push(parseInt(m[1], 10), parseInt(m[2] ?? m[1], 10));
  }
  if (!aar.length) return null;
  const lo = Math.min(...aar);
  const hi = Math.max(...aar);
  return lo === hi ? String(lo) : `${lo}–${hi}`;
}

// Fjern omkransende parenteser/whitespace fra periode-tekst.
export function stripParen(s: string | null | undefined): string {
  return s == null ? '' : String(s).replace(/^[\s(]+|[\s)]+$/g, '').trim();
}
