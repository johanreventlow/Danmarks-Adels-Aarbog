// Equivalence-lås for previewSammeSoms fast path: hurtig-stien (inert-par afgjort på eget nabolag)
// SKAL give byte-identisk {folder, grund} med den naive fulde beregning — hintet føder reelle
// redaktionelle beslutninger. Seedet generator (deterministisk) over adversarielle små grafer:
// cykler i rådata, degenererede self-rækker/self-unioner, ukendte endpoints, delte endpoints,
// kæder og dubletter i eksisterende kanter, køn/vital-konflikter. Tælleren beviser at både fast
// path og fallback faktisk rammes — ellers ville testen kunne udvandes tavst af en guard-ændring.
import { resolveSameAs } from '../collapseSameAs';
import { previewSammeSom, _previewSammeSomStats } from '../sammeSomPreflight';
import type { AppPerson, Db, Koen, SameAsEdge } from '../types';

// LCG — deterministisk på tværs af kørsler/platforme.
const mkRng = (seed: number) => {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
};

const KOEN: (Koen | undefined)[] = ['mand', 'kvinde', undefined, undefined];

const genDb = (rng: () => number): Db => {
  const n = 24;
  const persons: AppPerson[] = Array.from({ length: n }, (_, i) => {
    const born = rng() < 0.5 ? 1500 + Math.floor(rng() * 400) : null;
    const died = rng() < 0.5 ? 1500 + Math.floor(rng() * 400) : null;
    return {
      id: `p${i}`, name: `p${i}`, born, died, years: '', title: '', bio: '', privat: false,
      koen: KOEN[Math.floor(rng() * KOEN.length)],
    };
  });
  const pick = () => `p${Math.floor(rng() * n)}`;
  const parentChild: Db['parentChild'] = Array.from({ length: 30 }, () => ({
    child: pick(),
    // Lav sandsynlighed for degenereret self-række — den rammer selv-forælder-checket.
    parent: rng() < 0.05 ? 'SELF' : pick(),
    union: `f${Math.floor(rng() * 8)}`,
    ...(rng() < 0.3 ? { konfidens: rng() < 0.5 ? ('sikker' as const) : ('formodet' as const) } : {}),
  })).map((pc) => (pc.parent === 'SELF' ? { ...pc, parent: pc.child } : pc));
  const unions: Db['unions'] = Array.from({ length: 8 }, (_, i) => {
    const p1 = pick();
    return {
      id: `u${i}`,
      p1,
      p2: rng() < 0.1 ? p1 : rng() < 0.85 ? pick() : null,
      p2_name: null,
      year: null,
    };
  });
  return { persons, unions, parentChild };
};

const genEdges = (rng: () => number): SameAsEdge[] => {
  const pool = () => (rng() < 0.08 ? 'ukendtE' : `p${Math.floor(rng() * 16)}`);
  const edges: SameAsEdge[] = Array.from({ length: 7 }, () => ({ alias: pool(), canonical: pool() }));
  if (rng() < 0.3) edges.push({ ...edges[0] }); // dublet
  return edges;
};

// Oraklet: den naive, fulde beregning (præcis hvad previewSammeSom gjorde før fast path'en).
const oracle = (db: Db, edges: SameAsEdge[], hyp: SameAsEdge): { folder: boolean; grund: string | null } => {
  const r = resolveSameAs(db, [...edges, hyp]);
  const q = r.quarantined.find((n) => n.members.includes(hyp.alias) || n.members.includes(hyp.canonical));
  return q ? { folder: false, grund: q.reason } : { folder: true, grund: null };
};

it('fast path ≡ fuld beregning over seedede adversarielle grafer', () => {
  const rng = mkRng(0xdaa2026);
  _previewSammeSomStats.fast = 0;
  _previewSammeSomStats.fallback = 0;
  _previewSammeSomStats.baseline = 0;
  for (let round = 0; round < 60; round++) {
    const db = genDb(rng);
    const edges = genEdges(rng);
    for (let k = 0; k < 60; k++) {
      const id = () => (rng() < 0.05 ? 'ukendtH' : `p${Math.floor(rng() * 24)}`);
      const alias = id();
      const hyp: SameAsEdge = { alias, canonical: rng() < 0.04 ? alias : id() };
      const fast = previewSammeSom(db, edges, hyp);
      const full = oracle(db, edges, hyp);
      if (fast.folder !== full.folder || fast.grund !== full.grund) {
        // Fejl her = fast path afviger fra sandheden — dumpen gør casen reproducérbar.
        throw new Error(
          `divergens round=${round} k=${k} hyp=${JSON.stringify(hyp)} fast=${JSON.stringify(fast)} full=${JSON.stringify(full)}\n` +
            `edges=${JSON.stringify(edges)}\ndb=${JSON.stringify(db)}`,
        );
      }
    }
  }
  // Begge stier skal være reelt afprøvede — floors sat konservativt under de observerede tal.
  expect(_previewSammeSomStats.fast).toBeGreaterThan(300);
  expect(_previewSammeSomStats.fallback).toBeGreaterThan(300);
  expect(_previewSammeSomStats.baseline).toBeGreaterThan(10);
});
