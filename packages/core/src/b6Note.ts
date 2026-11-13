// 6e-2 (spec §12.4): hovedet viser linjetitler pr. valgt udgave, og B6-noten sammenligner med de andre udgaver.
import { linjeTitel } from './linjeVisning';

export type LinjeRaekke = {
  sourceId: string;
  udgave: string;
  entry: { code: string; label: string | null };
  lineageId: string | null;
  provenance: 'placement' | 'legacy_external_id';
};

// Den valgte udgaves linjetitler, unikke, i rækkefølgen af første forekomst. Rækker bygges kun, når koden findes
// i kildens stamtavleskema (web/src/data/linjeRaekker.ts), så placement og legacy tæller ens her.
export function linjerForUdgave(raekker: LinjeRaekke[], sourceId: string): string[] {
  const ud: string[] = [];
  for (const r of raekker) {
    if (r.sourceId !== sourceId) continue;
    const t = linjeTitel(r.entry);
    if (!ud.includes(t)) ud.push(t);
  }
  return ud;
}

// En note pr. anden kilde med placement (legacy giver aldrig en note): samme kanoniske linje → bekræftelse,
// ellers hvor den anden udgave placerer personen.
export function b6Noter(raekker: LinjeRaekke[], valgtSourceId: string): string[] {
  const valgte = new Set(raekker.filter((r) => r.sourceId === valgtSourceId && r.lineageId != null).map((r) => r.lineageId));
  const udgaver: string[] = [];
  for (const r of raekker) if (r.sourceId !== valgtSourceId && r.provenance === 'placement' && !udgaver.includes(r.sourceId)) udgaver.push(r.sourceId);
  return udgaver.map((sid) => {
    const rs = raekker.filter((r) => r.sourceId === sid && r.provenance === 'placement');
    const udgave = rs[0].udgave;
    const samme = rs.find((r) => r.lineageId != null && valgte.has(r.lineageId));
    return samme
      ? `✓ også i ${udgave} (${linjeTitel(samme.entry)})`
      : `${udgave} placerer i: ${[...new Set(rs.map((r) => linjeTitel(r.entry)))].join(', ')}`;
  });
}
