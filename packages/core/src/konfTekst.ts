// Flyttet fra web/src/data/format.ts (mobil-paritet, batch 6); web re-eksporterer den derfra.
import type { Konfidens } from './types';

// Vis kun de led der reelt er usikre (formodet/omstridt); sikre/sandsynlige/uangivne flages ikke.
export const konfTekst = (k?: Konfidens): string =>
  k === 'omstridt' ? 'omstridt' : k === 'formodet' ? 'formodet' : '';
