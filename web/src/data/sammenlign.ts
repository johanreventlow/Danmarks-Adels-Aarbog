// "Sammenlign udgaver" — arbejdsliste-logik (Problem 3 §5.2). Ren funktion: matcher-par →
// arbejdsliste grupperet pr. ny-udgave-person, med tier/status/fremdrift. Afledt tilstand
// (§2): en person er "afklaret" når alle kandidater ≥review enten er linket eller afvist.
import type { ScoredPair, Id } from '@daa/core';

/** Normaliseret retningsløs par-nøgle (samme_som er retningsbestemt, ikke_samme_som normaliseret —
 *  til opslag bruger vi den normaliserede form begge steder). */
export function pairKey(a: Id, b: Id): string {
  const s = [String(a), String(b)].sort();
  return `${s[0]}|${s[1]}`;
}

export type Kandidat = ScoredPair & { afvist: boolean; linket: boolean };
export type PersonStatus = 'aaben' | 'afklaret' | 'formodet_ny';
export type ArbejdslistePerson = { aId: string; kandidater: Kandidat[]; status: PersonStatus };
export type Fremdrift = { total: number; afklaret: number; staerke: number; gennemse: number; formodetNye: number };
export type Arbejdsliste = { personer: ArbejdslistePerson[]; fremdrift: Fremdrift };

export function buildArbejdsliste(
  pairs: ScoredPair[],
  aIds: string[],            // ALLE personer i den nye udgave (også dem uden kandidater)
  afvisteKeys: Set<string>,  // ikke_samme_som normaliserede par-nøgler
  linkedeKeys: Set<string>,  // samme_som normaliserede par-nøgler
): Arbejdsliste {
  const byA = new Map<string, ScoredPair[]>();
  for (const p of pairs) {
    if (p.tier === 'none') continue;
    const arr = byA.get(String(p.aId));
    if (arr) arr.push(p); else byA.set(String(p.aId), [p]);
  }

  const personer: ArbejdslistePerson[] = aIds.map((aId) => {
    const kandidater: Kandidat[] = (byA.get(aId) ?? [])
      .map((p) => ({ ...p, afvist: afvisteKeys.has(pairKey(p.aId, p.bId)), linket: linkedeKeys.has(pairKey(p.aId, p.bId)) }))
      .sort((x, y) => (y.score ?? 0) - (x.score ?? 0));
    const aktive = kandidater.filter((k) => !k.afvist);
    const harLink = kandidater.some((k) => k.linket);
    let status: PersonStatus;
    if (kandidater.length === 0) status = 'formodet_ny';
    else if (harLink || aktive.length === 0) status = 'afklaret';
    else status = 'aaben';
    return { aId, kandidater, status };
  });

  // sortér: åbne først (topscore faldende), så afklarede, så formodet-nye
  const rank: Record<PersonStatus, number> = { aaben: 0, afklaret: 1, formodet_ny: 2 };
  personer.sort((a, b) =>
    rank[a.status] - rank[b.status] || (b.kandidater[0]?.score ?? 0) - (a.kandidater[0]?.score ?? 0));

  const harAktivAuto = (p: ArbejdslistePerson) => p.kandidater.some((k) => k.tier === 'auto' && !k.afvist);
  const fremdrift: Fremdrift = {
    total: personer.length,
    afklaret: personer.filter((p) => p.status === 'afklaret').length,
    staerke: personer.filter((p) => p.status === 'aaben' && harAktivAuto(p)).length,
    gennemse: personer.filter((p) => p.status === 'aaben' && !harAktivAuto(p)).length,
    formodetNye: personer.filter((p) => p.status === 'formodet_ny').length,
  };
  return { personer, fremdrift };
}
