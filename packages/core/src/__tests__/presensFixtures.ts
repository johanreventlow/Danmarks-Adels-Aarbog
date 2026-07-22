// Delte fixture-hjælpere til presensListe.test.ts og presensFacit.test.ts. Bevidst IKKE en
// *.test.ts-fil: vitest re-eksekverer top-niveau describe/test-kald i en importeret testfil under
// den importerende fils suite (dobbelt test-registrering) — udtrukket hertil for at undgå det.
import type { Koen } from '../types';

export const mk = (id: string, koen: Koen = 'mand', born: number | null = null, died: number | null = null) =>
  ({ id, name: 'P' + id, born, died, years: '', title: '', bio: '', privat: false, koen });
export const union = (id: string, p1: string, p2: string | null = null) => ({ id, p1, p2, p2_name: null, year: null });
export const pc = (child: string, parent: string, unionId: string, konfidens?: 'sikker' | 'sandsynlig' | 'formodet' | 'omstridt') =>
  ({ child, parent, union: unionId, ...(konfidens ? { konfidens } : {}) });
