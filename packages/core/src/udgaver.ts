// 6e-1: udgaveoplysninger til faktalæseren (Model.udgaver / udgaveForPersonRaekke) + slukket enighed.
import type { Udgave } from './editionFacts';
import type { RawExtId, RawSource } from './types';

// Faktatyper uden »✓ også« (spec §5.4). Tom indtil projektejerens dom over stikprøven i Task 5 er faldet
// (docs/evidensbaseret-genimport/laeserflade-6e1-maaling.md); sættes derefter her.
export const SLUKKET_ENIGHED: ReadonlySet<string> = new Set<string>();

export function byggUdgaveModel(sources: RawSource[], extIds: RawExtId[]): { udgaver: Udgave[]; udgaveForPersonRaekke: Record<string, string> } {
  const udgaver: Udgave[] = sources
    .filter((s) => s.slags === 'DAA-udgave')
    .map((s) => ({ sourceId: String(s.id), label: s.udgave ?? s.titel ?? String(s.id), aar: s.aar ?? null }));
  const kendt = new Set(udgaver.map((u) => u.sourceId));
  const udgaveForPersonRaekke: Record<string, string> = {};
  for (const x of extIds) {
    const pid = String(x.person_id);
    const sid = String(x.source_id);
    if (kendt.has(sid) && !(pid in udgaveForPersonRaekke)) udgaveForPersonRaekke[pid] = sid;
  }
  return { udgaver, udgaveForPersonRaekke };
}
