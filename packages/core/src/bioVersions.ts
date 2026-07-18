// Udgave-versionsvælger: samme narrativ-kandidater som pickPreferredBio, men i stedet for KUN
// den foretrukne (nyeste) bio returneres ALLE offentlige DAA-udgave-versioner, nyeste først —
// til profilens "tidligere udgaver"-vælger (spec 2026-07-18).
import { BIO_SLAGS, type NarrativeCand } from './pickPreferredBio';

export type BioVersion = {
  sourceId: number | null;
  aar: number | null;
  udgave: string | null;
  tekst: string;
};

// Fuld deterministisk orden: aar DESC NULLS LAST, sourceId DESC — samme som pickPreferredBio,
// så version[0] ALTID er den bio pickPreferredBio ville have valgt.
export function buildBioVersions(cands: NarrativeCand[]): BioVersion[] {
  const eligible = cands.filter(
    (c) => (c.tekst ?? '').trim() !== '' && c.slags != null && BIO_SLAGS.has(c.slags),
  );
  // Gruppér pr. udgave (sourceId): flere medlemmer kan have narrativ i SAMME udgave (foldet
  // person) — sammenføj dedup'et i kandidat-rækkefølgen (kalderen leverer kanonisk medlem først).
  const bySource = new Map<number | null, { aar: number | null; udgave: string | null; texts: string[] }>();
  for (const c of eligible) {
    const key = c.sourceId;
    const entry = bySource.get(key);
    const tekst = (c.tekst ?? '').trim();
    if (entry) {
      if (!entry.texts.includes(tekst)) entry.texts.push(tekst);
    } else {
      bySource.set(key, { aar: c.aar, udgave: c.udgave, texts: [tekst] });
    }
  }
  const versions: BioVersion[] = [...bySource.entries()].map(([sourceId, v]) => ({
    sourceId, aar: v.aar, udgave: v.udgave, tekst: v.texts.join('\n\n'),
  }));
  versions.sort((a, b) => {
    const aa = a.aar ?? -Infinity, ba = b.aar ?? -Infinity; // NULLS LAST ved DESC
    if (aa !== ba) return ba - aa;
    const as = a.sourceId ?? -Infinity, bs = b.sourceId ?? -Infinity;
    return bs - as;
  });
  return versions;
}
