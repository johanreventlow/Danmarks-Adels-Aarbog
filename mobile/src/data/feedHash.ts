// Rene, deterministiske hjælpere til feed-generatoren (buildFeed). Ingen Math.random/Date.now.

// FNV-1a 32-bit → usigneret. Bruges til stabil partition (portrait/citat) + seed-fri ordning.
export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

// Round-robin-fletning af grupper: element 0 fra hver ikke-tom gruppe, så element 1, osv.
// Bevarer intern gruppe-rækkefølge; springer tomme grupper over.
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
