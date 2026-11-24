// Felt-hjælpere — port fra design-HTML (parseYear linje 872, fmtYears 873-880, stripParen 812).

// Bogens usikre sidste ciffer (»147(5?)«, person 77) læses som det foreslåede år (1475), ikke som år 147.
const USIKKERT_CIFFER = /(\d{3})\((\d)\?\)/g;
const medUsikreCifre = (s: string): string => s.replace(USIKKERT_CIFFER, '$1$2');

// Første 3-4-cifrede årstal i en streng, ellers null.
export function parseYear(s: string | null | undefined): number | null {
  if (s == null) return null;
  const m = medUsikreCifre(String(s)).match(/\d{3,4}/);
  return m ? parseInt(m[0], 10) : null;
}

// Alle årstal i en dato som spænd: »† 1406/1410« → [1406, 1410], »17. aug. 1840« → [1840, 1840]. Dage og
// måneder (1–2 cifre) tæller ikke. Null uden årstal (fx en uopløst »s.å.«).
export function aarSpaend(s: string | null | undefined): [number, number] | null {
  if (s == null) return null;
  const aar = [...medUsikreCifre(String(s)).matchAll(/\d{3,4}/g)].map((m) => parseInt(m[0], 10));
  return aar.length ? [Math.min(...aar), Math.max(...aar)] : null;
}

// Kort livsdato til en sammenfoldet persons overskrift: årstallet med bogens forbehold, uden dag og måned.
// »† efter 1575« → »efter 1575«, »17. aug. 1840« → »1840«, »† 1. aug. 147(5?)« → »147(5?)«, »1678 (?)« → »1678?«,
// »† mellem 1363 og 1364« → »1363/1364«. Tekst uden årstal (»lille«, »ung«) gives ordret. Et forbehold, der står efter
// årstallet, gælder dagen (»† 1496, før 10. okt.«) og falder bort med den (projektejeren 2026-11-24).
const FORBEHOLD = /(?:^|\s)(o\.|ca\.|omkr\.|efter|før|senest|tidligst)\s+(?:\d{1,2}\.?\s+[a-zæøå]+\.?\s+)?$/i;
export function kortLivsdato(tekst: string): string {
  const t = tekst.replace(/^[*†\s]+/, '').replace(/\s+/g, ' ').trim();
  const mellem = /mellem\s+(\d{3,4})\b.*?\bog\s+(\d{3,4})\b/i.exec(t);
  if (mellem) return `${mellem[1]}/${mellem[2]}`;
  const m = /(\d{3,4})(\(\d\?\))?(\/\d{3,4})?/.exec(t);
  if (!m) return t;
  const forbehold = FORBEHOLD.exec(t.slice(0, m.index));
  const tvivl = /^\s*\(\?\)/.test(t.slice(m.index + m[0].length)) ? '?' : '';
  return (forbehold ? forbehold[1] + ' ' : '') + m[0] + tvivl;
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

// Fjern omkransende parenteser/whitespace fra periode-tekst.
export function stripParen(s: string | null | undefined): string {
  return s == null ? '' : String(s).replace(/^[\s(]+|[\s)]+$/g, '').trim();
}
