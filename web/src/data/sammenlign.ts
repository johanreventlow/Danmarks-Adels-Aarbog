// "Sammenlign udgaver" — arbejdsliste-logik (Problem 3 §5.2). Ren funktion: matcher-par →
// arbejdsliste grupperet pr. ny-udgave-person, med tier/status/fremdrift. Afledt tilstand
// (§2): en person er "afklaret" når et af dens par er linket; "ny" når alle dens kandidater
// over tærsklen er afvist.
import {
  assignTiers, buildScored, defaultCfg, finalScore, jaroWinkler, matchKey, overlapEvidence, parseYear,
  type Id, type MatchCfg, type MatchFrame, type RedMatchPerson, type ScoredPair,
} from '@daa/core';

/** Normaliseret retningsløs par-nøgle (samme_som er retningsbestemt, ikke_samme_som normaliseret —
 *  til opslag bruger vi den normaliserede form begge steder). */
export function pairKey(a: Id, b: Id): string {
  const s = [String(a), String(b)].sort();
  return `${s[0]}|${s[1]}`;
}

/** Retning for et nyt samme_som-link. Den ÆLDRE udgaves person foldes ind (alias) i den nyere
 *  (kanonisk), så den nyeste udgaves profil forbliver synlig — uanset hvilken udgave redaktøren
 *  arbejder fra (projektejerens regel 2026-11-15). Kan udgaven ikke afgøres for begge, eller er
 *  den ens, gælder redaktørens side som før: a er alias. `red_samme_som` kan stadig vælge retning
 *  efter data, når serveren har et entydigt grundlag. */
export function sammeSomRetning(
  aId: string, bId: string, udgaveAar: (id: string) => number | null,
): { aliasId: string; objektId: string } {
  const ya = udgaveAar(aId), yb = udgaveAar(bId);
  if (ya != null && yb != null && yb < ya) return { aliasId: bId, objektId: aId };
  return { aliasId: aId, objektId: bId };
}

/** Kandidatpar til arbejdslisten. Afviste par holdes ude af matcherens 1:1-tildeling: ellers
 *  "bruger" en afvist ★ stadig både personen og kandidaten, så de næstbedste forslag for
 *  begge nedgraderes og forsvinder af syne (review 2026-11-15, A3). De afviste par returneres
 *  stadig (scoret, tier efter tærsklen), så buildArbejdsliste kan se, at personen HAVDE en
 *  kandidat over tærsklen, og at den er afvist. */
export function beregnKandidatPar(
  a: MatchFrame[],
  b: MatchFrame[],
  cfg: MatchCfg,
  afvisteKeys: ReadonlySet<string>,
): ScoredPair[] {
  const aktive: ScoredPair[] = [], afviste: ScoredPair[] = [];
  for (const p of buildScored(a, b, cfg)) (afvisteKeys.has(pairKey(p.aId, p.bId)) ? afviste : aktive).push(p);
  return [
    ...assignTiers(aktive, cfg),
    ...afviste.map((p) => {
      const score = finalScore(p, cfg);
      return { ...p, score, tier: score >= cfg.reviewCutoff ? 'review' as const : 'none' as const };
    }),
  ];
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

/** Personer i den nye udgave, der allerede er matchet (samme_som) med en person uden for den:
 *  person → modpart. Uanset hvor linket er lavet (arbejdslisten, »Find modpart«, persondetaljen,
 *  importkæden) — det er linket, ikke matcherens forslag, der afklarer personen.
 *
 *  Kæder tæller: en 1939-oversigtspost kan være foldet ind i 1939-stamtavlens post, der selv er
 *  foldet ind i 2018-20 (1939-91 → 1939-125 → I-97). Personen er da afklaret via sin samme_som-
 *  gruppe. Et direkte link til den anden side foretrækkes som modpart; ellers gruppens første. */
export function byggLinketTil(
  links: ReadonlyArray<{ aId: string; bId: string }>,
  aSide: ReadonlySet<string>,
): Map<string, string> {
  const direkte = new Map<string, string>();
  const forael = new Map<string, string>();
  const rod = (x: string): string => {
    let r = x;
    while (forael.has(r) && forael.get(r) !== r) r = forael.get(r)!;
    forael.set(x, r);
    return r;
  };
  for (const { aId, bId } of links) {
    if (aSide.has(aId) && !aSide.has(bId)) direkte.set(aId, bId);
    else if (aSide.has(bId) && !aSide.has(aId)) direkte.set(bId, aId);
    const ra = rod(aId), rb = rod(bId);
    if (ra !== rb) forael.set(ra, rb);
  }
  // Første person uden for den nye udgave i hver gruppe (i links-rækkefølge, deterministisk).
  const udenforPrGruppe = new Map<string, string>();
  for (const { aId, bId } of links) {
    for (const id of [aId, bId]) {
      if (aSide.has(id)) continue;
      const r = rod(id);
      if (!udenforPrGruppe.has(r)) udenforPrGruppe.set(r, id);
    }
  }
  const m = new Map<string, string>();
  for (const { aId, bId } of links) {
    for (const id of [aId, bId]) {
      if (!aSide.has(id) || m.has(id)) continue;
      const modpart = direkte.get(id) ?? udenforPrGruppe.get(rod(id));
      if (modpart != null) m.set(id, modpart);
    }
  }
  return m;
}

export type Kandidat = ScoredPair & {
  afvist: boolean;
  linket: boolean;
  /** Id på den person (i den nye udgave), kandidaten allerede er matchet med — ellers null. */
  matchetMed: string | null;
};
export type PersonStatus = 'aaben' | 'afklaret' | 'ny' | 'formodet_ny';
export type ArbejdslistePerson = {
  aId: string;
  kandidater: Kandidat[];
  /** Kandidater under review-tærsklen. Holdes UDE af status og fremdrift — de er ikke
   *  arbejde matcheren tør pålægge — men bevares, så redaktøren kan tage stilling alligevel.
   *  Personer uden årstal (bogens ægtefæller har sjældent nogen) kan strukturelt ikke nå
   *  tærsklen: overlap tæller kun når BEGGE sider har en dato, så deres loft er
   *  0,6·navn + 0,1·køn = 0,70 = præcis cutoff. Uden denne liste var de en blindgyde. */
  svageKandidater: Kandidat[];
  /** Modparten, personen er matchet med (fra byggLinketTil eller et linket kandidatpar). */
  linketTil: string | null;
  status: PersonStatus;
};
export type Fremdrift = {
  total: number; afklaret: number; staerke: number; gennemse: number; nye: number; formodetNye: number;
};
export type Arbejdsliste = { personer: ArbejdslistePerson[]; fremdrift: Fremdrift };

export type ArbejdslisteValg = {
  /** Tærsklen for "kandidat" (default: matcherens reviewCutoff). */
  reviewCutoff?: number;
  /** Fra byggMatchetMed: kandidat-id → person i den nye udgave, den allerede er matchet med. */
  matchetMed?: ReadonlyMap<string, string>;
  /** Fra byggLinketTil: person i den nye udgave → modpart, den er matchet med. */
  linketTil?: ReadonlyMap<string, string>;
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
    const linketTil = valg.linketTil?.get(aId)
      ?? [...kandidater, ...svageKandidater].find((k) => k.linket)?.bId?.toString() ?? null;
    // »ny« = havde mindst én kandidat over tærsklen, og alle er afvist. En afvist svag kandidat
    // eller en afvisning andetsteds i basen gør ikke personen ny.
    let status: PersonStatus;
    if (linketTil != null) status = 'afklaret';
    else if (aktive.length) status = 'aaben';
    else if (kandidater.length) status = 'ny';
    else status = 'formodet_ny';
    return { aId, kandidater, svageKandidater, linketTil, status };
  });

  // sortér: åbne først (topscore faldende), så afklarede, nye, formodet-nye
  const rank: Record<PersonStatus, number> = { aaben: 0, afklaret: 1, ny: 2, formodet_ny: 3 };
  personer.sort((a, b) =>
    rank[a.status] - rank[b.status] || (b.kandidater[0]?.score ?? 0) - (a.kandidater[0]?.score ?? 0));

  const harAktivAuto = (p: ArbejdslistePerson) => p.kandidater.some((k) => k.tier === 'auto' && !k.afvist);
  const fremdrift: Fremdrift = {
    total: personer.length,
    afklaret: personer.filter((p) => p.status === 'afklaret').length,
    staerke: personer.filter((p) => p.status === 'aaben' && harAktivAuto(p)).length,
    gennemse: personer.filter((p) => p.status === 'aaben' && !harAktivAuto(p)).length,
    nye: personer.filter((p) => p.status === 'ny').length,
    formodetNye: personer.filter((p) => p.status === 'formodet_ny').length,
  };
  return { personer, fremdrift };
}

/** Score for et vilkårligt par — også et, matcheren aldrig stillede op (andet forbogstav, årstal
 *  uden for vinduet). Samme signaler og samme scorefunktion som arbejdslisten (finalScore). */
export function scorePersonPar(a: MatchFrame, b: MatchFrame, cfg: MatchCfg): ScoredPair {
  const kendt = (min: number | null, max: number | null) => min != null || max != null;
  const p: ScoredPair = {
    aId: a.id, bId: b.id,
    nameSim: a.nameKey && b.nameKey ? jaroWinkler(a.nameKey, b.nameKey) : 0,
    birthOverlap: overlapEvidence(a.birthMin, a.birthMax, b.birthMin, b.birthMax),
    deathOverlap: overlapEvidence(a.deathMin, a.deathMax, b.deathMin, b.deathMax),
    sexEq: a.sex === b.sex && a.sex !== 'ukendt',
    birthKendt: kendt(a.birthMin, a.birthMax) && kendt(b.birthMin, b.birthMax),
    deathKendt: kendt(a.deathMin, a.deathMax) && kendt(b.deathMin, b.deathMax),
    koenKendt: a.sex !== 'ukendt' && b.sex !== 'ukendt',
    uniqueBlock: false,
  };
  return { ...p, score: finalScore(p, cfg) };
}

const AARSTAL_RE = /^\d{4}$/;
const AARSTAL_TOLERANCE = 2;

/** »Find modpart«: matcher en person søgeteksten? Hvert ord skal passe. Et firecifret tal passer
 *  på fødsels- eller dødsår (±2 år); andre ord på navn, bognummer (fx »III-58«) eller gren —
 *  direkte eller efter matcherens stavefoldning, så »Friedrich« finder »Frederik«. */
export function matcherSoegning(
  query: string,
  p: Pick<RedMatchPerson, 'navn' | 'fuldtNavn' | 'foedsel' | 'doed' | 'bogReferencer'>,
): boolean {
  const ord = query.toLocaleLowerCase('da-DK').split(/\s+/).filter(Boolean);
  if (!ord.length) return false;
  const navn = `${p.fuldtNavn ?? ''} ${p.navn ?? ''}`.toLocaleLowerCase('da-DK');
  const bog = p.bogReferencer
    .map((r) => [r.linje && r.nr != null ? `${r.linje}-${r.nr}` : r.linje, r.grenNavn].filter(Boolean).join(' '))
    .join(' ')
    .toLocaleLowerCase('da-DK');
  const tekst = `${navn} ${bog}`;
  const foldet = matchKey(navn);
  const aar = [
    parseYear(p.foedsel?.date_min ?? p.foedsel?.date_max),
    parseYear(p.doed?.date_min ?? p.doed?.date_max),
  ].filter((y): y is number => y != null);
  return ord.every((o) => {
    if (AARSTAL_RE.test(o)) return aar.some((y) => Math.abs(y - Number(o)) <= AARSTAL_TOLERANCE);
    if (tekst.includes(o)) return true;
    const f = matchKey(o);
    return f !== '' && foldet.includes(f);
  });
}
