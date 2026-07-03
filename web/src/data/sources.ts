// Bygger "Kilde i Aarbogen"-referencer pr. person (§ + trykt værk + "Linje X, nr. N") som REN
// funktion — mirror af mobile/src/data/buildAux.ts's sourcesBy-blok. Bruger person_external_id
// (linje/nr + source_id) koblet mod source-tabellen (titel/udgave).
import type { RawExtId, RawSource, SourceRef } from './types';

export function buildSources(
  extIds: RawExtId[],
  sources: RawSource[],
  // samme_som-collapse: nøgle kanoniseres → kilder for en foldet person samles under kanonisk id.
  canonicalIdById: Record<string, string> = {},
): Record<string, SourceRef[]> {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const srcById: Record<string, RawSource> = {};
  (sources || []).forEach((s) => { srcById[String(s.id)] = s; });

  const out: Record<string, SourceRef[]> = {};
  (extIds || []).forEach((x) => {
    const src = srcById[String(x.source_id)] ?? ({} as RawSource);
    const work = src.titel || src.udgave || 'Kilde';
    const ref = [x.linje ? 'Linje ' + x.linje : '', x.nr != null ? 'nr. ' + x.nr : '']
      .filter(Boolean)
      .join(', ');
    (out[cid(String(x.person_id))] ??= []).push({ ref, work });
  });
  return out;
}
