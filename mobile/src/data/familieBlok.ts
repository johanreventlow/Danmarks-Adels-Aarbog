// Familieblokken på personskærmen (paritetsplanens batch 6). Rækkerne (ægteskaber, børn pr. ægteskab i bogens
// rækkefølge, sætningen for børn uden kendt ægteskab) bygges af @daa/core's byggFokusRaekker — samme funktion som
// web's personside og fokus-stamtræ, så de to aldrig er uenige. Her bor kun det, web har inline i PersonSide.tsx.
import type { KunIAeldreTekst, UdgaveChip } from '@daa/core';

// Et barn, der kun står i en anden udgave, er et link, når den udgave er valgt i udgavevælgeren (projektejeren
// 2026-11-23, valg A); ellers grå tekst med mærket. Kan siden slet ikke vælge barnets udgave (ingen vælger, eller
// vælgeren har ikke den udgave), forbliver det et link, så barnet aldrig bliver uden adgang. Port af web's
// barnErAktivt (web/src/components/PersonSide.tsx).
export function barnErAktivt(k: KunIAeldreTekst | null, aktivChip: UdgaveChip | null, chips: readonly UdgaveChip[]): boolean {
  if (!k || !aktivChip) return true;
  if (k.kunISourceIds.includes(aktivChip.sourceId)) return true;
  return !chips.some((c) => k.kunISourceIds.includes(c.sourceId));
}
