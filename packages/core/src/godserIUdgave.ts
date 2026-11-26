// Personsidens godser i den valgte udgave (spec §5.8): kun godser, hvis personrække hører til den valgte udgave, eller
// hvis rækkens udgave ikke kendes. Rækkens udgave som for fakta (§5.1): fakta-rækkernes udgave (udgaveForRaekker),
// ellers personrækkens eksterne nøgle, når den er en kendt udgave. Uden valgt udgave eller uden fakta-input vises alle.
// Flyttet fra web/src/components/personVisning.tsx (mobil-paritet, rest fra batch 6), så mobilens personskærm filtrerer
// efter samme regel. Dubletter (samme gods i flere rækker) samler kalderen selv: web viser ét navn, mobilen samler
// perioderne.
import { udgaveForRaekker, type UdgaveFaktaInput } from './editionFacts';

export function godserIUdgave<T extends { personId: string }>(
  godser: readonly T[],
  faktaInput: UdgaveFaktaInput | null,
  udgaver: readonly { sourceId: string }[],
  valgtUdgave: string | null,
): T[] {
  if (!faktaInput || valgtUdgave == null) return [...godser];
  const raekkeUdgave = udgaveForRaekker(faktaInput);
  const udgaveAf = (personId: string): string | null => {
    const r = raekkeUdgave[personId];
    if (r !== undefined) return r;
    const ext = faktaInput.udgaveForPersonRaekke[personId];
    return ext != null && udgaver.some((u) => u.sourceId === ext) ? ext : null;
  };
  return godser.filter((e) => { const u = udgaveAf(e.personId); return u == null || u === valgtUdgave; });
}
