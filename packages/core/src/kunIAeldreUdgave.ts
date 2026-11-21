import type { BogNr } from './bogensOrden';

export type KunIAeldre = { kunI: string[]; ikkeI: string };

// Tavshed i forældrenes nyere stamtavle er en oplysning om udgaverne, ikke en konfidensvurdering.
export function kunIAeldreUdgave(
  personId: string,
  foraeldreIds: readonly string[],
  bogNrBy: Record<string, BogNr[]> | undefined,
  udgaver: readonly { sourceId: string; aar: number | null }[] | undefined,
): KunIAeldre | null {
  if (!bogNrBy) return null;
  const aar = new Map<string, number>();
  for (const u of udgaver ?? []) if (u.aar != null) aar.set(u.sourceId, u.aar);

  let nyeste: { sourceId: string; aar: number } | null = null;
  for (const id of foraeldreIds) {
    for (const nr of bogNrBy[id] ?? []) {
      const a = aar.get(nr.sourceId);
      if (nr.stamtavle !== false && a != null && (!nyeste || a > nyeste.aar)) {
        nyeste = { sourceId: nr.sourceId, aar: a };
      }
    }
  }
  if (!nyeste) return null;

  const egne = [...new Set((bogNrBy[personId] ?? []).map((nr) => nr.sourceId))].filter((sid) => aar.has(sid));
  if (!egne.length || egne.some((sid) => aar.get(sid)! >= nyeste.aar)) return null;
  return { kunI: egne.sort((a, b) => aar.get(b)! - aar.get(a)!), ikkeI: nyeste.sourceId };
}
