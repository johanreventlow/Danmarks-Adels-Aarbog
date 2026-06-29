const DOEDS_MARGIN = 1; // år efter forælders død et barn stadig kan fødes (graviditet)

export function parseAar(s: string | null): number | null {
  if (!s) return null;
  const m = s.match(/\d{4}/);
  return m ? Number(m[0]) : null;
}

export function eraAdvarsel(
  barnFoedselAar: number | null,
  foraeldre: { foedsel: number | null; doed: number | null }[],
): string | null {
  if (barnFoedselAar == null) return null;
  for (const f of foraeldre) {
    if (f.foedsel != null && barnFoedselAar < f.foedsel)
      return 'Barn født før forælder — tjek kilder.';
    if (f.doed != null && barnFoedselAar > f.doed + DOEDS_MARGIN)
      return 'Barn født efter forælders død — tjek kilder.';
  }
  return null;
}
