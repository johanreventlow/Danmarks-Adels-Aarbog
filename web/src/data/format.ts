// Delte visnings-hjælpere (brugt af både Folgesvend og Redaktion).
import type { Konfidens } from './types';

// Initialer til avatar-badges: op til to forbogstaver, versaler.
export const initials = (navn: string): string =>
  navn.split(' ').filter(Boolean).map((s) => s[0]).slice(0, 2).join('').toUpperCase();

// Vis kun de led der reelt er usikre (formodet/omstridt); sikre/sandsynlige/uangivne flages ikke.
export const konfTekst = (k?: Konfidens): string =>
  k === 'omstridt' ? 'omstridt' : k === 'formodet' ? 'formodet' : '';
