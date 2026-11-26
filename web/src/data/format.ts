// Delte visnings-hjælpere (brugt af både Folgesvend og Redaktion).

// Initialer til avatar-badges: op til to forbogstaver, versaler.
// Monogram: første bogstav i de to første ord, der rummer et bogstav. Parenteser, tal og
// tankestreger tæller ikke (»Adelheid (Lilli)« → »AL«, ikke »A(«); \p{L} bevarer æ, ø og å.
export const initials = (navn: string): string =>
  navn.split(/\s+/).map((ord) => ord.match(/\p{L}/u)?.[0]).filter(Boolean).slice(0, 2).join('').toUpperCase() || '?';

// konfTekst er flyttet til @daa/core (mobil-paritet, batch 6); re-eksport så web-imports er uændrede.
export { konfTekst } from '@daa/core';

// Fast dansk tidsstempel (DD.MM.YYYY HH:MM) til historik-visninger — bevidst IKKE
// toLocaleString, så OCR-historik og ændringshistorik viser samme format uanset runtime-locale.
export function formatTidspunkt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
