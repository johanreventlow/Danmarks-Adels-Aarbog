// Delte visnings-hjælpere (brugt af både Folgesvend og Redaktion).
import type { Konfidens } from './types';

// Initialer til avatar-badges: op til to forbogstaver, versaler.
// Monogram: første bogstav i de to første ord, der rummer et bogstav. Parenteser, tal og
// tankestreger tæller ikke (»Adelheid (Lilli)« → »AL«, ikke »A(«); \p{L} bevarer æ, ø og å.
export const initials = (navn: string): string =>
  navn.split(/\s+/).map((ord) => ord.match(/\p{L}/u)?.[0]).filter(Boolean).slice(0, 2).join('').toUpperCase() || '?';

// Vis kun de led der reelt er usikre (formodet/omstridt); sikre/sandsynlige/uangivne flages ikke.
export const konfTekst = (k?: Konfidens): string =>
  k === 'omstridt' ? 'omstridt' : k === 'formodet' ? 'formodet' : '';

// Fast dansk tidsstempel (DD.MM.YYYY HH:MM) til historik-visninger — bevidst IKKE
// toLocaleString, så OCR-historik og ændringshistorik viser samme format uanset runtime-locale.
export function formatTidspunkt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
