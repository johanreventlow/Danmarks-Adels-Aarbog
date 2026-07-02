// Bygger lineage-projektionen (grene) som REN funktion — mirror af mobile/src/data/buildAux.ts's
// linje-blok, udtrukket så den kan unit-testes DB-uafhængigt. Hver person hører til én linje
// (fra person_external_id.linje); hver linje har en stamfader = medlemmet med laveste nr.
import type { Lineage, RawExtId, RawLineage } from './types';

export function buildLineage(extIds: RawExtId[], lineageRows: RawLineage[]): Lineage {
  const byPerson: Record<string, string> = {};
  const counts: Record<string, number> = {};
  const head: Record<string, { id: string; nr: number }> = {};

  (extIds || []).forEach((x) => {
    if (!x.linje) return;
    byPerson[String(x.person_id)] = x.linje;
    counts[x.linje] = (counts[x.linje] || 0) + 1;
    const nr = x.nr == null ? 9999 : x.nr;
    const cur = head[x.linje];
    if (!cur || nr < cur.nr) head[x.linje] = { id: String(x.person_id), nr };
  });

  // Linje-navne fra lineage-tabellen (kode → navn); fallback til kode hvis tom/mangler.
  const navn: Record<string, string> = {};
  (lineageRows || []).forEach((l) => {
    if (l.kode && l.navn) navn[l.kode] = l.navn;
  });

  const list = Object.keys(counts)
    .sort()
    .map((l) => ({ linje: l, count: counts[l], headId: head[l]?.id ?? null, navn: navn[l] ?? null }));

  return { byPerson, list, navn };
}
