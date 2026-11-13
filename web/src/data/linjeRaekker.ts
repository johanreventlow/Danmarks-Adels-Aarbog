// 6e-2: personens linjerækker pr. kilde (kun koder, der findes i kildens stamtavleskema) til hovedets linjer pr.
// udgave og B6-noten. Ren funktion; lineageId er entryens kanoniske lineage (relation_kind='canonical').
import type { LinjeRaekke } from '@daa/core';
import { stamtavleEntries, type LineageSchemeRows } from './lineage';
import type { RawExtId, RawSource } from './types';

export function byggLinjeRaekker(
  extIds: RawExtId[],
  sources: RawSource[],
  canonicalIdById: Record<string, string> = {},
  schemeRows?: LineageSchemeRows,
): Record<string, LinjeRaekke[]> {
  const entries = stamtavleEntries(schemeRows);
  const canon = new Map<string, Set<string>>();
  (schemeRows?.mappings ?? []).forEach((m) => {
    if (m.relation_kind !== 'canonical') return;
    const k = String(m.entry_id);
    canon.set(k, (canon.get(k) ?? new Set()).add(String(m.lineage_id)));
  });
  const srcById = new Map((sources ?? []).map((s) => [String(s.id), s]));
  const out: Record<string, LinjeRaekke[]> = {};
  (extIds ?? []).forEach((x) => {
    if (!x.linje) return;
    const sourceId = String(x.source_id);
    const e = entries.get(`${sourceId}:${x.linje}`);
    if (!e) return; // kilde uden skema, eller kode uden for skemaet (fx »1939«): ingen linje
    const ids = canon.get(String(e.id));
    const src = srcById.get(sourceId);
    const rk: LinjeRaekke = {
      sourceId, udgave: src?.udgave ?? src?.titel ?? sourceId, entry: { code: e.code, label: e.label },
      lineageId: ids?.size === 1 ? [...ids][0] : null,
      provenance: x.provenance ?? 'placement',
    };
    const arr = (out[canonicalIdById[String(x.person_id)] ?? String(x.person_id)] ??= []);
    if (!arr.some((a) => a.sourceId === rk.sourceId && a.entry.code === rk.entry.code && a.provenance === rk.provenance)) arr.push(rk);
  });
  return out;
}
