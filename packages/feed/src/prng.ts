// Rene, deterministiske hjælpere til feed-motoren. Ingen Math.random/Date.now.

// mulberry32: lille, hurtig, veldokumenteret 32-bit PRNG. Deterministisk pr. seed —
// al variation i feed'en kommer herfra (spec §3.5, §4.3), aldrig fra Math.random.
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// FNV-1a 32-bit → usigneret. Bruges til stabil partition (portrait/citat, dagensperson)
// + til at aflede seeds. Flyttet fra mobile/src/data/feedHash.ts (uændret).
export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

// Round-robin-fletning af grupper: element 0 fra hver ikke-tom gruppe, så element 1, osv.
// Bevarer intern gruppe-rækkefølge; springer tomme grupper over. Flyttet uændret.
export function interleave<T>(groups: T[][]): T[] {
  const out: T[] = [];
  const max = groups.reduce((m, g) => Math.max(m, g.length), 0);
  for (let i = 0; i < max; i++) {
    for (const g of groups) {
      if (i < g.length) out.push(g[i]);
    }
  }
  return out;
}
