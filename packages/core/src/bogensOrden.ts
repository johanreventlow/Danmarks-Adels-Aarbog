// Aarbogens rækkefølge for en børneflok (projektejeren 2026-11-21, spec 2026-11-21-boern-pr-aegteskab-design).
//
// Kilden er barnets stamtavlenummer (koordinatens nr + nr_label): loaderen hentede børn via forælderens
// nr-interval, så nummeret ER bogens orden. family_member.ordinal er partneres ægteskabsnummer og bruges ikke.
// Højst ét nummer pr. person og udgave (person_external_id's nøgle), men en sammenfoldet person har ét pr. udgave.
import type { RawExtId } from './types';

export type BogNr = { sourceId: string; linje: string; nr: number; nrLabel: string | null };

// Kanonisk person-id → personens stamtavlenumre (ét pr. udgave). Rækker uden linje eller nr springes over.
export function byggBogNr(extIds: RawExtId[], canonicalIdById: Record<string, string>): Record<string, BogNr[]> {
  const ud: Record<string, BogNr[]> = {};
  for (const x of extIds) {
    if (x.linje == null || x.nr == null) continue;
    const canon = canonicalIdById[String(x.person_id)] ?? String(x.person_id);
    (ud[canon] ??= []).push({ sourceId: String(x.source_id), linje: x.linje, nr: x.nr, nrLabel: x.nr_label ?? null });
  }
  return ud;
}

type Barn = { id: string; born: number | null; name: string };
type UdgaveAar = { sourceId: string; aar: number | null };

const etiket = (n: BogNr) => n.nrLabel ?? String(n.nr);

// Børn i bogens rækkefølge:
// 1. Udgaven: den nyeste (ukendt år sidst), hvor mindst ét barn har et nummer; forælderens egne udgaver først ved lige år.
// 2. Linjen: forælderens linje(r) i udgaven, hvis et barn står dér; ellers den linje flest børn står i (1939: forælderen
//    står under en anden linjekode end børnene).
// 3. Børn med nummer i den linje efter linje, nr, label; øvrige bagefter efter fødselsår (ukendt sidst), så navn.
export function sorterBoernEfterBogen<T extends Barn>(
  boern: readonly T[],
  foraelderId: string,
  bogNrBy: Record<string, BogNr[]> | undefined,
  udgaver: readonly UdgaveAar[] | undefined,
): T[] {
  const nøgler = new Map<string, BogNr>();
  if (bogNrBy) {
    const aar = new Map((udgaver ?? []).map((u) => [u.sourceId, u.aar]));
    const egne = new Set((bogNrBy[foraelderId] ?? []).map((n) => n.sourceId));
    const kandidater = [...new Set([...egne, ...boern.flatMap((b) => (bogNrBy[b.id] ?? []).map((n) => n.sourceId))])];
    kandidater.sort((a, b) => {
      const aa = aar.get(a) ?? null;
      const ba = aar.get(b) ?? null;
      if (aa !== ba) return aa == null ? 1 : ba == null ? -1 : ba - aa;
      return Number(egne.has(b)) - Number(egne.has(a));
    });
    const iUdgave = (id: string, sid: string) => (bogNrBy[id] ?? []).find((n) => n.sourceId === sid) ?? null;
    const udgave = kandidater.find((sid) => boern.some((b) => iUdgave(b.id, sid)));
    if (udgave) {
      const nummererede = boern.map((b) => [b.id, iUdgave(b.id, udgave)] as const).filter((x): x is readonly [string, BogNr] => x[1] != null);
      const foraelderLinjer = new Set((bogNrBy[foraelderId] ?? []).filter((n) => n.sourceId === udgave).map((n) => n.linje));
      let linjer = new Set([...foraelderLinjer].filter((l) => nummererede.some(([, n]) => n.linje === l)));
      if (linjer.size === 0) {
        const antal = new Map<string, number>();
        for (const [, n] of nummererede) antal.set(n.linje, (antal.get(n.linje) ?? 0) + 1);
        const flest = [...antal.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))[0][0];
        linjer = new Set([flest]);
      }
      for (const [id, n] of nummererede) if (linjer.has(n.linje)) nøgler.set(id, n);
    }
  }
  return [...boern].sort((a, b) => {
    const na = nøgler.get(a.id);
    const nb = nøgler.get(b.id);
    if (na && nb) {
      if (na.linje !== nb.linje) return na.linje < nb.linje ? -1 : 1;
      if (na.nr !== nb.nr) return na.nr - nb.nr;
      const ea = etiket(na);
      const eb = etiket(nb);
      return ea < eb ? -1 : ea > eb ? 1 : 0;
    }
    if (na || nb) return na ? -1 : 1;
    if (a.born !== b.born) return a.born == null ? 1 : b.born == null ? -1 : a.born - b.born;
    return a.name.localeCompare(b.name, 'da');
  });
}
