// Tværudgave-matcher — deterministisk scoring + rangering af kandidatpar mellem to
// kilders personmængder. Port 1:1 af R/tng-qa/04-match.R (score-model + injektive tiers)
// oven på foldnings-kernen (navnevarianter.ts). Ren funktion, klient-side, RÅDGIVENDE:
// intet tier udløser en skrivning — hvert samme_som-link kræver et redaktør-klik (spec §3.4).
import { matchKey } from './navnevarianter';
import { parseYear } from './fields';
import type { Union } from './types';

export type Sex = 'mand' | 'kvinde' | 'ukendt';
export type Id = string | number;

export interface MatchFrame {
  id: Id;
  nameKey: string; // foldet match-nøgle; tom = umatchbar (NN/tom → udelukkes)
  birthMin: number | null;
  birthMax: number | null;
  deathMin: number | null;
  deathMax: number | null;
  sex: Sex;
}

export interface MatchCfg {
  yearWindow: number;
  wName: number; wBirth: number; wDeath: number; wSex: number;
  autoCutoff: number; reviewCutoff: number; ambiguityMargin: number;
  topK: number;
}

export function defaultCfg(): MatchCfg {
  // arvet fra TNG-QA's bootstrap-kalibrering (docs/tng-qa-koersel.md) — START-værdier,
  // ikke løfter; kalibreres mod håndlabelt facit efter første rigtige udgave-load (spec §3.5).
  return {
    yearWindow: 5,
    wName: 0.6, wBirth: 0.2, wDeath: 0.1, wSex: 0.1,
    autoCutoff: 0.9, reviewCutoff: 0.7, ambiguityMargin: 0.05,
    topK: 10,
  };
}

export type Tier = 'auto' | 'review' | 'none';

export interface ScoredPair {
  aId: Id; bId: Id;
  nameSim: number;
  birthOverlap: boolean;
  deathOverlap: boolean;
  sexEq: boolean;
  uniqueBlock: boolean;
  score?: number;
  tier?: Tier;
}

// ---- Jaro-Winkler (svarer til stringdist method="jw", p=0.1) ----
function jaro(s1: string, s2: string): number {
  if (s1 === s2) return s1.length === 0 ? 0 : 1;
  const len1 = s1.length, len2 = s2.length;
  if (len1 === 0 || len2 === 0) return 0;
  const window = Math.max(0, Math.floor(Math.max(len1, len2) / 2) - 1);
  const m1 = new Array<boolean>(len1).fill(false);
  const m2 = new Array<boolean>(len2).fill(false);
  let matches = 0;
  for (let i = 0; i < len1; i++) {
    const lo = Math.max(0, i - window);
    const hi = Math.min(i + window + 1, len2);
    for (let j = lo; j < hi; j++) {
      if (!m2[j] && s1[i] === s2[j]) { m1[i] = true; m2[j] = true; matches++; break; }
    }
  }
  if (matches === 0) return 0;
  let t = 0, k = 0;
  for (let i = 0; i < len1; i++) {
    if (m1[i]) { while (!m2[k]) k++; if (s1[i] !== s2[k]) t++; k++; }
  }
  t /= 2;
  return (matches / len1 + matches / len2 + (matches - t) / matches) / 3;
}

/** Jaro-Winkler-similaritet (1 − jw-afstand). name_similarity i R-porten. */
export function jaroWinkler(a: string, b: string, p = 0.1): number {
  const sa = a ?? '', sb = b ?? '';
  const j = jaro(sa, sb);
  if (j === 0) return 0;
  let prefix = 0;
  const maxPrefix = Math.min(4, sa.length, sb.length);
  while (prefix < maxPrefix && sa[prefix] === sb[prefix]) prefix++;
  return j + prefix * p * (1 - j);
}

// ---- Interval-overlap ----
function overlapVec(
  amin: number | null, amax: number | null, bmin: number | null, bmax: number | null,
): boolean {
  const aLo = amin ?? -Infinity, aHi = amax ?? Infinity;
  const bLo = bmin ?? -Infinity, bHi = bmax ?? Infinity;
  return aLo <= bHi && bLo <= aHi;
}

/** Overlap som SCORING-EVIDENS: TRUE kun når BEGGE sider har en dato OG de overlapper.
 *  Ukendt dato = manglende evidens, ikke enighed (spec §3.1 / .overlap_evidence). */
export function overlapEvidence(
  amin: number | null, amax: number | null, bmin: number | null, bmax: number | null,
): boolean {
  const aKnown = amin != null || amax != null;
  const bKnown = bmin != null || bmax != null;
  return aKnown && bKnown && overlapVec(amin, amax, bmin, bmax);
}

export function scorePair(
  nameSim: number, birthOverlap: boolean, deathOverlap: boolean, sexEq: boolean, cfg: MatchCfg,
): number {
  return cfg.wName * nameSim
    + cfg.wBirth * (birthOverlap ? 1 : 0)
    + cfg.wDeath * (deathOverlap ? 1 : 0)
    + cfg.wSex * (sexEq ? 1 : 0);
}

/** Byg kandidat-par: blocking (fornavns-initial af foldet nøgle) + fødselsårs-vindue +
 *  name_floor-prune + top-K. Disjunkte kilder forudsættes af kalderen (a ⟂ b). */
export function buildScored(a: MatchFrame[], b: MatchFrame[], cfg: MatchCfg = defaultCfg()): ScoredPair[] {
  const byBlock = new Map<string, MatchFrame[]>();
  for (const bf of b) {
    if (!bf.nameKey) continue; // NN/tom udelukkes som KANDIDAT
    const blk = bf.nameKey[0];
    const arr = byBlock.get(blk);
    if (arr) arr.push(bf); else byBlock.set(blk, [bf]);
  }
  // tabsfri navne-floor: et par kan kun nå review_cutoff hvis name_sim ≥ dette.
  const nameFloor = Math.max(0, (cfg.reviewCutoff - (cfg.wBirth + cfg.wDeath + cfg.wSex)) / cfg.wName);
  const out: ScoredPair[] = [];

  for (const af of a) {
    if (!af.nameKey) continue; // NN/tom udelukkes som FORESPØRGSEL
    let cand = byBlock.get(af.nameKey[0]) ?? [];
    if (!cand.length) continue;

    // fødselsår-vindue: kun når VORES år kendes; dato-løse kandidater beholdes.
    if (af.birthMin != null || af.birthMax != null) {
      const lo = af.birthMin != null ? af.birthMin - cfg.yearWindow : null;
      const hi = af.birthMax != null ? af.birthMax + cfg.yearWindow : null;
      cand = cand.filter((c) => overlapVec(lo, hi, c.birthMin, c.birthMax));
    }
    if (!cand.length) continue;

    // Beregn name_sim + overlap-evidens + køn-lighed ÉN gang pr. kandidat (genbruges i
    // både top-K-sorteringen og den endelige push — undgår dobbelt-beregning).
    let scored = cand
      .map((c) => ({
        c,
        sim: jaroWinkler(af.nameKey, c.nameKey),
        birthOverlap: overlapEvidence(af.birthMin, af.birthMax, c.birthMin, c.birthMax),
        deathOverlap: overlapEvidence(af.deathMin, af.deathMax, c.deathMin, c.deathMax),
        sexEq: af.sex === c.sex && af.sex !== 'ukendt',
      }))
      .filter((x) => x.sim >= nameFloor);
    if (!scored.length) continue;
    const nPlausible = scored.length; // ægte unikhed FØR top-K-cap

    // top-K på FAKTISK score (ligenavngivne skelnes af dato-overlap, ikke name_sim alene).
    if (nPlausible > cfg.topK) {
      scored = scored
        .map((x) => ({ x, sc: scorePair(x.sim, x.birthOverlap, x.deathOverlap, x.sexEq, cfg) }))
        .sort((p, q) => q.sc - p.sc)
        .slice(0, cfg.topK)
        .map((w) => w.x);
    }

    for (const { c, sim, birthOverlap, deathOverlap, sexEq } of scored) {
      out.push({ aId: af.id, bId: c.id, nameSim: sim, birthOverlap, deathOverlap, sexEq, uniqueBlock: nPlausible === 1 });
    }
  }
  return out;
}

/** Score + injektiv (1:1) grådig tildeling i tre bins. Intet tier udløser en skrivning
 *  (rangering/fremhævning). auto = score≥cutoff + margin≥margin + personens top-kandidat. */
export function assignTiers(scored: ScoredPair[], cfg: MatchCfg = defaultCfg()): ScoredPair[] {
  interface Row extends ScoredPair { score: number; _margin: number; _isTop: boolean }
  const rows: Row[] = scored.map((s) => ({
    ...s,
    score: scorePair(s.nameSim, s.birthOverlap, s.deathOverlap, s.sexEq, cfg),
    _margin: Infinity, _isTop: false,
  }));

  // per-A: margin (bedste − næstbedste) + flag for A's top-kandidat.
  const byA = new Map<Id, Row[]>();
  for (const r of rows) { const arr = byA.get(r.aId); if (arr) arr.push(r); else byA.set(r.aId, [r]); }
  for (const arr of byA.values()) {
    const ordered = [...arr].sort((p, q) => q.score - p.score);
    const m = ordered.length < 2 ? Infinity : ordered[0].score - ordered[1].score;
    for (const r of arr) r._margin = m;
    ordered[0]._isTop = true;
  }

  // sortér ALLE efter score desc; injektiv grådig tildeling.
  const ordered = [...rows].sort((p, q) => q.score - p.score);
  const usedA = new Set<Id>(), usedB = new Set<Id>();
  for (const r of ordered) {
    if (usedA.has(r.aId) || usedB.has(r.bId)) { r.tier = 'none'; continue; }
    if (r.score >= cfg.autoCutoff && r._margin >= cfg.ambiguityMargin && r._isTop) {
      r.tier = 'auto'; usedA.add(r.aId); usedB.add(r.bId);
    } else if (r.score >= cfg.reviewCutoff) {
      r.tier = 'review';
    } else {
      r.tier = 'none';
    }
  }

  return rows.map(({ _margin, _isTop, ...r }) => r);
}

/** Fuld pipeline: byg kandidatpar → score + tiers. */
export function matchUdgaver(a: MatchFrame[], b: MatchFrame[], cfg: MatchCfg = defaultCfg()): ScoredPair[] {
  return assignTiers(buildScored(a, b, cfg), cfg);
}

// ---- Adapter: udtræks-/redaktions-person → MatchFrame ----
export interface FramePerson {
  id: Id;
  navn: string;
  koen?: string | null;
  foedsel?: { date_min?: string | null; date_max?: string | null } | null;
  doed?: { date_min?: string | null; date_max?: string | null } | null;
}

const UNMATCHABLE_RE = /^(n\.?\s*n\.?|nn|ukendt|ubekendt|\?+)$/i;

function normSex(x?: string | null): Sex {
  const s = (x ?? '').toLowerCase().trim();
  if (s === 'm' || s === 'mand' || s === 'male') return 'mand';
  if (s === 'f' || s === 'k' || s === 'kvinde' || s === 'female') return 'kvinde';
  return 'ukendt';
}

// ---- Kalibrerings-harness (§3.5) ----
export interface CrosswalkPair { aId: Id; bId: Id }

/** Precision/recall af et crosswalk mod et håndlabelt facit (port af eval_precision_recall).
 *  precision = korrekte/|crosswalk|; recall = korrekte/|facit|. */
export function evalPrecisionRecall(
  crosswalk: CrosswalkPair[], truth: CrosswalkPair[],
): { correct: number; precision: number; recall: number } {
  const truthMap = new Map<Id, Id>();
  for (const t of truth) truthMap.set(t.aId, t.bId);
  let correct = 0;
  for (const c of crosswalk) if (truthMap.get(c.aId) === c.bId) correct++;
  return {
    correct,
    precision: crosswalk.length ? correct / crosswalk.length : 0,
    recall: truth.length ? correct / truth.length : 0,
  };
}

/** Eksportér alle scorede par som CSV til offline cutoff-sweeps (spec §3.5). */
export function pairsToCsv(pairs: ScoredPair[]): string {
  const header = 'aId,bId,nameSim,birthOverlap,deathOverlap,sexEq,uniqueBlock,score,tier';
  const rows = pairs.map((p) =>
    [p.aId, p.bId, p.nameSim, p.birthOverlap, p.deathOverlap, p.sexEq, p.uniqueBlock, p.score ?? '', p.tier ?? ''].join(','),
  );
  return [header, ...rows].join('\n') + '\n';
}

export function buildMatchFrame(p: FramePerson): MatchFrame {
  const navn = (p.navn ?? '').trim();
  return {
    id: p.id,
    nameKey: UNMATCHABLE_RE.test(navn) ? '' : matchKey(navn),
    birthMin: parseYear(p.foedsel?.date_min),
    birthMax: parseYear(p.foedsel?.date_max),
    deathMin: parseYear(p.doed?.date_min),
    deathMax: parseYear(p.doed?.date_max),
    sex: normSex(p.koen),
  };
}

// ---- DB→MatchFrame-input-mappere (rene; delt web+mobil via @daa/core, §11) ----
// Bygger MatchFrame-input af flade DB-rækker: konkluderede fødsels-/døds-intervaller +
// kilde-medlemskab. App-laget leverer kun de tynde supabase-fetches (redaktionRead).

export type RedMatchPerson = {
  id: string;
  navn: string;
  fuldtNavn: string | null;
  koen: string | null;
  foedsel: { date_min: string | null; date_max: string | null } | null;
  doed: { date_min: string | null; date_max: string | null } | null;
  titel: string | null;
  bogReferencer: MatchBogReference[];
  sourceIds: number[]; // kilde-medlemskab (person_external_id) → disjunkt-kilde-afgrænsning
  staged: boolean; // K2-kuratering: TRUE = usynlig for anon (§7.20 selektiv publicering)
};

export type MatchBogReference = {
  sourceId: number;
  linje: string | null;
  nr: number | null;
  slaegtledLokal: number | null;
  slaegtledGennem: number | null;
  kuld: string | null;
  grenNavn: string | null;
};

export type MatchPersonRow = {
  id: number;
  visning_navn: string | null;
  visning_fuldt_navn?: string | null;
  koen: string | null;
  staged?: boolean | null;
};
export type MatchFactRow = { id: number; subjekt_id: number; faktatype: string };
export type MatchConcRow = { target_id: number; valgt_assertion_id: number | null };
export type MatchAssertRow = {
  id: number;
  date_min: string | null;
  date_max: string | null;
  vaerdi_tekst?: string | null;
};
export type MatchExtIdRow = {
  person_id: number;
  source_id: number;
  linje?: string | null;
  nr?: number | null;
  slaegtled_lokal?: number | null;
  slaegtled_gennem?: number | null;
  kuld?: string | null;
};
export type MatchLineageRow = { source_id: number; kode: string; navn: string | null };

/** Ren samling: personer + konkluderede fødsels-/døds-intervaller + kilde-medlemskab →
 *  MatchFrame-input. Fødsel/død fra den VALGTE assertions date_min/date_max (as-of-korrekt). */
export function buildMatchPersoner(
  persons: MatchPersonRow[],
  facts: MatchFactRow[],
  concs: MatchConcRow[],
  assertions: MatchAssertRow[],
  extIds: MatchExtIdRow[],
  lineages: MatchLineageRow[] = [],
): RedMatchPerson[] {
  const assertById = new Map(assertions.map((a) => [a.id, a]));
  const chosenByFact = new Map(concs.map((c) => [c.target_id, c.valgt_assertion_id]));
  const birth = new Map<number, { date_min: string | null; date_max: string | null }>();
  const death = new Map<number, { date_min: string | null; date_max: string | null }>();
  const titles = new Map<number, string[]>();
  for (const f of facts) {
    if (f.faktatype !== 'fødsel' && f.faktatype !== 'død' && f.faktatype !== 'titel') continue;
    const aid = chosenByFact.get(f.id);
    if (aid == null) continue;
    const a = assertById.get(aid);
    if (!a) continue;
    if (f.faktatype === 'titel') {
      const title = a.vaerdi_tekst?.trim();
      if (!title) continue;
      const arr = titles.get(f.subjekt_id);
      if (arr) {
        if (!arr.includes(title)) arr.push(title);
      } else titles.set(f.subjekt_id, [title]);
    } else {
      (f.faktatype === 'fødsel' ? birth : death).set(f.subjekt_id, { date_min: a.date_min, date_max: a.date_max });
    }
  }
  const srcByPerson = new Map<number, number[]>();
  const refsByPerson = new Map<number, MatchBogReference[]>();
  const lineageBySourceAndCode = new Map(
    lineages.map((l) => [`${l.source_id}:${l.kode ?? ''}`, l]),
  );
  for (const e of extIds) {
    const arr = srcByPerson.get(e.person_id);
    if (arr) arr.push(e.source_id); else srcByPerson.set(e.person_id, [e.source_id]);
    const lineage = e.linje == null
      ? null
      : lineageBySourceAndCode.get(`${e.source_id}:${e.linje}`) ?? null;
    const ref: MatchBogReference = {
      sourceId: e.source_id,
      linje: e.linje ?? null,
      nr: e.nr ?? null,
      slaegtledLokal: e.slaegtled_lokal ?? null,
      slaegtledGennem: e.slaegtled_gennem ?? null,
      kuld: e.kuld ?? null,
      grenNavn: lineage?.navn ?? null,
    };
    const refs = refsByPerson.get(e.person_id);
    if (refs) refs.push(ref); else refsByPerson.set(e.person_id, [ref]);
  }
  return persons.map((p) => ({
    id: String(p.id),
    navn: p.visning_navn ?? '',
    fuldtNavn: p.visning_fuldt_navn ?? p.visning_navn ?? null,
    koen: p.koen,
    foedsel: birth.get(p.id) ?? null,
    doed: death.get(p.id) ?? null,
    titel: titles.get(p.id)?.join(' · ') ?? null,
    bogReferencer: refsByPerson.get(p.id) ?? [],
    sourceIds: srcByPerson.get(p.id) ?? [],
    staged: Boolean(p.staged),
  }));
}

/** Udled udgave-tilhør for ægtefæller uden eget bog-nummer.
 *
 *  Bogens ægtefæller har sjældent en egen nummereret post — moderen står typisk kun
 *  nævnt inde i faderens opslag. `sourceIds` udledes ellers alene af
 *  `person_external_id`, så sådan en person får `[]`, hører til ingen udgave og
 *  bliver derfor aldrig stillet op som kandidat i tværudgave-matcheren. Uden hende
 *  kan et forældrepar ikke matches færdigt, og `collapseSameAs` holder børnene i
 *  karantæne med grunden "konkurrerende forældre".
 *
 *  Reglen: en person uden bog-nummer arver udgaven fra sine partnere i de familier
 *  hun indgår i — men KUN når de peger entydigt på én udgave. Peger de på flere,
 *  lades hun urørt, så matcherens forudsætning om disjunkte kilder (a ⟂ b) holder.
 *
 *  Ren funktion: muterer ikke input. */
export function udledKilderForAegtefaeller<T extends { id: string; sourceIds: number[] }>(
  personer: T[],
  unions: Union[],
): T[] {
  const kilderAf = new Map(personer.map((p) => [p.id, p.sourceIds]));
  const kandidater = new Map<string, Set<number>>();
  for (const u of unions) {
    const parter = [u.p1, u.p2].filter((x): x is string => x != null);
    const kendte = new Set(parter.flatMap((id) => kilderAf.get(id) ?? []));
    for (const id of parter) {
      if ((kilderAf.get(id) ?? []).length) continue;
      const s = kandidater.get(id) ?? new Set<number>();
      for (const k of kendte) s.add(k);
      kandidater.set(id, s);
    }
  }
  return personer.map((p) => {
    if (p.sourceIds.length) return p;
    const s = kandidater.get(p.id);
    if (!s || s.size !== 1) return p; // ukendt eller flertydig → urørt
    return { ...p, sourceIds: [...s] };
  });
}

/** Ren: relation-rækker (rolle='ikke_samme_som') → persistente afvisnings-par. */
export function parseIkkeSammeSomPar(rows: { subjekt_id: number; objekt_id: number }[]): { aId: string; bId: string }[] {
  return rows.map((r) => ({ aId: String(r.subjekt_id), bId: String(r.objekt_id) }));
}
