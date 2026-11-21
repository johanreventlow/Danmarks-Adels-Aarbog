// Aarbogens rækkefølge for en børneflok (projektejeren 2026-11-21, spec 2026-11-21-boern-pr-aegteskab-design).
//
// Kilden er barnets stamtavlenummer (koordinatens nr + nr_label): loaderen hentede børn via forælderens
// nr-interval, så nummeret ER bogens orden. family_member.ordinal er partneres ægteskabsnummer og bruges ikke.
// Højst ét nummer pr. person-række og udgave (person_external_id's nøgle); en sammenfoldet person kan have flere.
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
const cmpNr = (a: BogNr, b: BogNr) => {
  if (a.linje !== b.linje) return a.linje < b.linje ? -1 : 1;
  if (a.nr !== b.nr) return a.nr - b.nr;
  const ea = etiket(a);
  const eb = etiket(b);
  return ea < eb ? -1 : ea > eb ? 1 : 0;
};
const cmpFallback = (a: Barn, b: Barn) => {
  if (a.born !== b.born) return a.born == null ? 1 : b.born == null ? -1 : a.born - b.born;
  return a.name.localeCompare(b.name, 'da');
};

// Børnenes numre i én udgave, kun i én gyldig linje: den linje flest børn står i (lige: forælderens linje, så
// alfabetisk). Flertallet og ikke forælderens linje afgør, fordi koordinat-RPC'en kan blande proveniens i én udgave
// (1939: Conrad og enkelte børn under legacy-koden »1939«, søskende under skemakoden IV; review I1). Et sammenfoldet
// barn kan have flere numre i samme udgave (to aliasrækker); nummeret i den gyldige linje bruges (review I2).
function noeglerIUdgave(boern: readonly Barn[], foraelderId: string, bogNrBy: Record<string, BogNr[]>, sid: string): Map<string, BogNr> {
  const pr = new Map<string, BogNr[]>();
  for (const b of boern) {
    const ns = (bogNrBy[b.id] ?? []).filter((x) => x.sourceId === sid);
    if (ns.length) pr.set(b.id, ns);
  }
  const ud = new Map<string, BogNr>();
  if (!pr.size) return ud;
  const antal = new Map<string, number>();
  for (const ns of pr.values()) for (const l of new Set(ns.map((n) => n.linje))) antal.set(l, (antal.get(l) ?? 0) + 1);
  const foraelderLinjer = new Set((bogNrBy[foraelderId] ?? []).filter((n) => n.sourceId === sid).map((n) => n.linje));
  const linje = [...antal.entries()].sort((a, b) =>
    b[1] - a[1] || Number(foraelderLinjer.has(b[0])) - Number(foraelderLinjer.has(a[0])) || (a[0] < b[0] ? -1 : 1))[0][0];
  for (const [id, ns] of pr) {
    const i = ns.filter((n) => n.linje === linje).sort(cmpNr)[0];
    if (i) ud.set(id, i);
  }
  return ud;
}

// Børn i bogens rækkefølge:
// 1. Hovedudgaven: den nyeste (ukendt år sidst), hvor mindst ét barn har et nummer; forælderens egne udgaver først
//    ved lige år. Børn med nummer dér står efter linje, nr, label.
// 2. Et barn uden nummer i hovedudgaven, men med nummer i en ældre udgave (fx 1939's nr. 1-2 hos Conrad, som
//    2018-20 ikke har), flettes ind lige før det første barn, der står efter det i den ældre udgave; står intet
//    barn efter det dér, kommer det efter de nummererede.
// 3. Resten efter fødselsår (ukendt sidst), så navn.
export function sorterBoernEfterBogen<T extends Barn>(
  boern: readonly T[],
  foraelderId: string,
  bogNrBy: Record<string, BogNr[]> | undefined,
  udgaver: readonly UdgaveAar[] | undefined,
): T[] {
  if (!bogNrBy) return [...boern].sort(cmpFallback);
  const aar = new Map((udgaver ?? []).map((u) => [u.sourceId, u.aar]));
  const egne = new Set((bogNrBy[foraelderId] ?? []).map((n) => n.sourceId));
  const kandidater = [...new Set([...egne, ...boern.flatMap((b) => (bogNrBy[b.id] ?? []).map((n) => n.sourceId))])];
  kandidater.sort((a, b) => {
    const aa = aar.get(a) ?? null;
    const ba = aar.get(b) ?? null;
    if (aa !== ba) return aa == null ? 1 : ba == null ? -1 : ba - aa;
    return Number(egne.has(b)) - Number(egne.has(a));
  });
  const pr = kandidater.map((sid) => noeglerIUdgave(boern, foraelderId, bogNrBy, sid)).filter((m) => m.size > 0);
  if (!pr.length) return [...boern].sort(cmpFallback);
  const [hoved, ...aeldre] = pr;
  const byId = new Map(boern.map((b) => [b.id, b]));
  const raekke: T[] = [...hoved.entries()].sort((a, b) => cmpNr(a[1], b[1])).map(([id]) => byId.get(id)!);
  const placeret = new Set(raekke.map((b) => b.id));
  let haleStart = raekke.length; // indsæt »efter de nummererede« her, så hale-børn bevarer deres indbyrdes orden
  for (const udg of aeldre) {
    const orden = [...udg.entries()].sort((a, b) => cmpNr(a[1], b[1])).map(([id]) => id);
    orden.forEach((id, i) => {
      if (placeret.has(id)) return;
      const efterfoelger = orden.slice(i + 1).find((x) => placeret.has(x));
      const pos = efterfoelger ? raekke.findIndex((b) => b.id === efterfoelger) : haleStart;
      raekke.splice(pos, 0, byId.get(id)!);
      if (pos <= haleStart) haleStart += 1;
      placeret.add(id);
    });
  }
  return [...raekke, ...boern.filter((b) => !placeret.has(b.id)).sort(cmpFallback)];
}
