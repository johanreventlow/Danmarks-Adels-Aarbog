// Trin 6b (plan Task 10/15): rene hjælpere til kalibreringen af publiceringskontrollen. Kun tal forlader modulet
// gennem kalibrerings-CLI'en; navne læses aldrig.
import type { Candidate, Tier } from './rank';
import type { MatchFrame } from '@daa/core';

export type Pair = [number, number];

// Fordeler syntetiske samme_som-par på inputkopier, så hver EKSISTERENDE klynge (enkeltpersoner er egne klynger) højst
// berøres af ét par pr. kopi. Et par samler så præcis to eksisterende klynger, og klyngerne vokser ikke transitivt
// (én kopi med alle par gav klynger på over 100 personer). Grådig i parrenes rækkefølge; deterministisk.
export function partitionPairs(sameAs: Pair[], pairs: Pair[]): Pair[][] {
  const parent = new Map<number, number>();
  const find = (x: number): number => {
    let r = x;
    while ((parent.get(r) ?? r) !== r) r = parent.get(r)!;
    let y = x;
    while (y !== r) { const n = parent.get(y) ?? y; parent.set(y, r); y = n; }
    return r;
  };
  for (const [a, b] of sameAs) {
    const ra = find(a), rb = find(b);
    if (ra !== rb) parent.set(Math.max(ra, rb), Math.min(ra, rb));
  }
  const batches: Array<{ used: Set<number>; pairs: Pair[] }> = [];
  for (const [a, b] of pairs) {
    const ca = find(a), cb = find(b);
    if (ca === cb) throw new Error('CALIBRATION_PAIR_ALREADY_SAME_CLUSTER');
    let batch = batches.find((x) => !x.used.has(ca) && !x.used.has(cb));
    if (!batch) { batch = { used: new Set(), pairs: [] }; batches.push(batch); }
    batch.used.add(ca); batch.used.add(cb); batch.pairs.push([a, b]);
  }
  return batches.map((x) => x.pairs);
}

// Inputkopiens same_as: de eksisterende par plus de syntetiske, uden dubletter, sorteret som serverens (subjekt, objekt).
export function mutateSameAs(sameAs: Pair[], extra: Pair[]): Pair[] {
  const key = (p: Pair) => `${p[0]},${p[1]}`;
  const seen = new Map<string, Pair>();
  for (const p of [...sameAs, ...extra]) seen.set(key(p), [p[0], p[1]]);
  return [...seen.values()].sort((x, y) => x[0] - y[0] || x[1] - y[1]);
}

type Facit = Array<{ source_persona_id: string; canonical_person_id: number }>;
export type ClusterTal = {
  med_facit: number; med_kandidat: number; top1: number; top3: number;
  tier: Record<Tier, { n: number; rigtige: number }>;
};

// Klyngebevidst 5a-optælling: facit er et træf, når den står i rækkens member_scores (rækkens samme_som-klynge),
// også når rækken bærer en anden repræsentants id (generator ≥ 1.1). calibrate.ts tæller id-strikt.
export function clusterCalibrate(candidates: Candidate[], truth: Facit): ClusterTal {
  const byPersona = new Map<string, Candidate[]>();
  for (const k of candidates) byPersona.set(k.source_persona_id, [...(byPersona.get(k.source_persona_id) ?? []), k]);
  const out: ClusterTal = { med_facit: truth.length, med_kandidat: 0, top1: 0, top3: 0,
    tier: { auto: { n: 0, rigtige: 0 }, review: { n: 0, rigtige: 0 }, none: { n: 0, rigtige: 0 } } };
  for (const t of truth) {
    const list = [...(byPersona.get(t.source_persona_id) ?? [])].sort((a, b) => a.rank - b.rank);
    if (!list.length) continue;
    out.med_kandidat++;
    const hit = (k: Candidate) => k.basis.member_scores.some((m) => m.person_id === t.canonical_person_id);
    if (hit(list[0])) out.top1++;
    if (list.slice(0, 3).some(hit)) out.top3++;
    out.tier[list[0].tier].n++;
    if (hit(list[0])) out.tier[list[0].tier].rigtige++;
  }
  return out;
}

// Årstalsdækning i matcherens frames for en given personmængde.
export function yearCoverage(frames: MatchFrame[], ids: ReadonlySet<number>) {
  const sel = frames.filter((f) => ids.has(Number(f.id)));
  const birth = (f: MatchFrame) => f.birthMin != null || f.birthMax != null;
  const death = (f: MatchFrame) => f.deathMin != null || f.deathMax != null;
  return { personer: sel.length, mindst_et_aar: sel.filter((f) => birth(f) || death(f)).length,
           foedselsaar: sel.filter(birth).length, doedsaar: sel.filter(death).length,
           alle_personer: frames.length, alle_mindst_et_aar: frames.filter((f) => birth(f) || death(f)).length };
}
