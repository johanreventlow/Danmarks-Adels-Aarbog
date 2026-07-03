// Delt selector (spejlet i mobile/src/data/pickPreferredBio.ts — hold i sync).
// Vælger den foretrukne offentlige biografi for ÉT subjekt blandt dets narrativer.
// Kalderen har allerede filtreret private rækker fra (RLS + query).

export type NarrativeCand = {
  narrativeId: number;
  tekst: string | null;
  sourceId: number | null;
  slags: string | null;   // source.slags
  aar: number | null;     // source.aar
  udgave: string | null;  // source.udgave (til byline)
};

// Godkendte source-slags der må levere en offentlig standardbio. Kun DAA-udgaver nu;
// udvid bevidst (ikke vilkårlig fallback — en TNG-stub må ikke blive autoritativ bio).
const BIO_SLAGS = new Set(['DAA-udgave']);

// Fuld deterministisk orden: aar DESC NULLS LAST, sourceId DESC, narrativeId DESC.
// Sidste tie-break på narrativeId er nødvendig fordi DB-unikhed pr. (subjekt,source) er udskudt.
export function pickPreferredBio(cands: NarrativeCand[]): NarrativeCand | null {
  const eligible = cands.filter(
    (c) => (c.tekst ?? '').trim() !== '' && c.slags != null && BIO_SLAGS.has(c.slags),
  );
  if (eligible.length === 0) return null;
  eligible.sort((a, b) => {
    const aa = a.aar ?? -Infinity, ba = b.aar ?? -Infinity;   // NULLS LAST ved DESC
    if (aa !== ba) return ba - aa;
    const as = a.sourceId ?? -Infinity, bs = b.sourceId ?? -Infinity;
    if (as !== bs) return bs - as;
    return b.narrativeId - a.narrativeId;
  });
  return eligible[0];
}
