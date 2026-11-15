// "Sammenlign udgaver" — arbejdsliste-logik (Problem 3 §5.2). Ren funktion: matcher-par →
// arbejdsliste grupperet pr. ny-udgave-person, med tier/status/fremdrift. Afledt tilstand
// (§2): en person er "afklaret" når et af dens par er linket, eller alle dens kandidater
// over tærsklen er afvist.
import {
  assignTiers, buildScored, defaultCfg,
  type Id, type MatchCfg, type MatchFrame, type ScoredPair,
} from '@daa/core';

/** Normaliseret retningsløs par-nøgle (samme_som er retningsbestemt, ikke_samme_som normaliseret —
 *  til opslag bruger vi den normaliserede form begge steder). */
export function pairKey(a: Id, b: Id): string {
  const s = [String(a), String(b)].sort();
  return `${s[0]}|${s[1]}`;
}

/** Kandidatpar til arbejdslisten. Afviste par fjernes FØR matcherens 1:1-tildeling: ellers
 *  "bruger" en afvist ★ stadig både personen og kandidaten, så de næstbedste forslag for
 *  begge nedgraderes og forsvinder af syne (review 2026-11-15, A3). */
export function beregnKandidatPar(
  a: MatchFrame[],
  b: MatchFrame[],
  cfg: MatchCfg,
  afvisteKeys: ReadonlySet<string>,
): ScoredPair[] {
  const scored = buildScored(a, b, cfg).filter((p) => !afvisteKeys.has(pairKey(p.aId, p.bId)));
  return assignTiers(scored, cfg);
}

/** Kandidater der allerede er matchet (samme_som) med en ANDEN person på den nye udgaves side:
 *  kandidat-id → den person, den er matchet med. Bruges til at mærke og nedprioritere — ikke
 *  skjule: 1939 har dubletpersoner, så to personer på A-siden kan legitimt pege på samme kandidat. */
export function byggMatchetMed(
  links: ReadonlyArray<{ aId: string; bId: string }>,
  aSide: ReadonlySet<string>,
): Map<string, string> {
  const m = new Map<string, string>();
  for (const { aId, bId } of links) {
    if (aSide.has(aId) && !aSide.has(bId)) m.set(bId, aId);
    else if (aSide.has(bId) && !aSide.has(aId)) m.set(aId, bId);
  }
  return m;
}

export type Kandidat = ScoredPair & {
  afvist: boolean;
  linket: boolean;
  /** Id på den person (i den nye udgave), kandidaten allerede er matchet med — ellers null. */
  matchetMed: string | null;
};
export type PersonStatus = 'aaben' | 'afklaret' | 'formodet_ny';
export type ArbejdslistePerson = {
  aId: string;
  kandidater: Kandidat[];
  /** Kandidater under review-tærsklen. Holdes UDE af status og fremdrift — de er ikke
   *  arbejde matcheren tør pålægge — men bevares, så redaktøren kan tage stilling alligevel.
   *  Personer uden årstal (bogens ægtefæller har sjældent nogen) kan strukturelt ikke nå
   *  tærsklen: overlap tæller kun når BEGGE sider har en dato, så deres loft er
   *  0,6·navn + 0,1·køn = 0,70 = præcis cutoff. Uden denne liste var de en blindgyde. */
  svageKandidater: Kandidat[];
  status: PersonStatus;
};
export type Fremdrift = {
  total: number; afklaret: number; staerke: number; gennemse: number; formodetNye: number;
};
export type Arbejdsliste = { personer: ArbejdslistePerson[]; fremdrift: Fremdrift };

export type ArbejdslisteValg = {
  /** Tærsklen for "kandidat" (default: matcherens reviewCutoff). */
  reviewCutoff?: number;
  /** Fra byggMatchetMed: kandidat-id → person i den nye udgave, den allerede er matchet med. */
  matchetMed?: ReadonlyMap<string, string>;
};

export function buildArbejdsliste(
  pairs: ScoredPair[],
  aIds: string[],            // ALLE personer i den nye udgave (også dem uden kandidater)
  afvisteKeys: ReadonlySet<string>,  // ikke_samme_som normaliserede par-nøgler
  linkedeKeys: ReadonlySet<string>,  // samme_som normaliserede par-nøgler
  valg: ArbejdslisteValg = {},
): Arbejdsliste {
  const cutoff = valg.reviewCutoff ?? defaultCfg().reviewCutoff;
  // En kandidat er et par over tærsklen — uanset tier. Matcherens 1:1-tildeling sætter tier
  // 'none' på par, hvis person eller kandidat allerede er brugt af et stærkere par; de er stadig
  // lige så plausible og må ikke forsvinde fra listen (review 2026-11-15, A3).
  const erKandidat = (p: ScoredPair) => p.tier !== 'none' || (p.score ?? 0) >= cutoff;
  const byA = new Map<string, ScoredPair[]>();
  const svageByA = new Map<string, ScoredPair[]>();
  for (const p of pairs) {
    const maal = erKandidat(p) ? byA : svageByA;
    const arr = maal.get(String(p.aId));
    if (arr) arr.push(p); else maal.set(String(p.aId), [p]);
  }

  const berig = (p: ScoredPair, kandidat: boolean): Kandidat => {
    const aId = String(p.aId), bId = String(p.bId);
    const linket = linkedeKeys.has(pairKey(aId, bId));
    const andenA = valg.matchetMed?.get(bId);
    const matchetMed = !linket && andenA != null && andenA !== aId ? andenA : null;
    // Ingen ★ på en kandidat der er matchet andetsteds, og et nedgraderet par vises som "gennemse".
    const tier = !kandidat ? p.tier
      : p.tier === 'none' || (p.tier === 'auto' && matchetMed) ? 'review' : p.tier;
    return { ...p, tier, afvist: afvisteKeys.has(pairKey(aId, bId)), linket, matchetMed };
  };
  // Matchet-andetsteds sidst, ellers efter score.
  const orden = (x: Kandidat, y: Kandidat) =>
    Number(x.matchetMed != null) - Number(y.matchetMed != null) || (y.score ?? 0) - (x.score ?? 0);

  const personer: ArbejdslistePerson[] = aIds.map((aId) => {
    const kandidater = (byA.get(aId) ?? []).map((p) => berig(p, true)).sort(orden);
    const svageKandidater = (svageByA.get(aId) ?? []).map((p) => berig(p, false)).sort(orden);
    const aktive = kandidater.filter((k) => !k.afvist);
    let status: PersonStatus;
    if (kandidater.length === 0) status = 'formodet_ny';
    else if (kandidater.some((k) => k.linket) || aktive.length === 0) status = 'afklaret';
    else status = 'aaben';
    return { aId, kandidater, svageKandidater, status };
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
