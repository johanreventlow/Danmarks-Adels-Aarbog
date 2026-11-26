// Besiddelseslisten (mobil-paritet, bid 9) — samme regler som web's EstatesView/Folgesvend: alle slægtens godser,
// også dem uden registrerede ejere; ejertallet er antal forskellige personer læseren kan se (antalEjere i @daa/core:
// kanoniske id'er, ejere uden for modellen tælles ikke). Flest ejere først, derefter navn.
import { antalEjere, compareDanish, type Model } from '@daa/core';
import type { EstateListEntry } from './types';

export function besiddelserVist(liste: readonly EstateListEntry[], model: Model | null): EstateListEntry[] {
  return liste
    .map((e) => (model ? { ...e, ownerCount: antalEjere(e.ejerIds, model) } : e))
    .sort((a, b) => b.ownerCount - a.ownerCount || compareDanish(a.navn, b.navn));
}

// Kortets undertekst, ordret som web's liste.
export function ejerTekst(n: number): string {
  return n ? `${n} ${n === 1 ? 'ejer' : 'ejere'} i Aarbogen` : 'Ingen ejere registreret';
}
