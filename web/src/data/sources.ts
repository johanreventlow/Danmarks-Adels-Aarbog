// Bygger "Kilde i Aarbogen"-referencer pr. person (§ + trykt værk + "Linje X, nr. N") som REN
// funktion — mirror af mobile/src/data/buildAux.ts's sourcesBy-blok. Bruger person_external_id
// (linje/nr + source_id) koblet mod source-tabellen (titel/udgave).
import { linjeKodeOgNavn, linjeTitel, type SkemaOpslag } from '@daa/core';
import type { RawExtId, RawSource, SourceRef } from './types';

export function buildSources(
  extIds: RawExtId[],
  sources: RawSource[],
  // samme_som-collapse: nøgle kanoniseres → kilder for en foldet person samles under kanonisk id.
  canonicalIdById: Record<string, string> = {},
  // 6e-2: opslag i kildens stamtavleskema. Uden: dagens »Linje X, nr. N«.
  skema?: SkemaOpslag,
): Record<string, SourceRef[]> {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const srcById: Record<string, RawSource> = {};
  (sources || []).forEach((s) => { srcById[String(s.id)] = s; });

  const out: Record<string, SourceRef[]> = {};
  (extIds || []).forEach((x) => {
    const src = srcById[String(x.source_id)] ?? ({} as RawSource);
    const work = src.titel || src.udgave || 'Kilde';
    const nrTekst = x.nr_label ?? (x.nr != null ? String(x.nr) : null);
    const side = x.trykt_side?.trim() || null;
    const base = { work, personId: String(x.person_id), sourceId: String(x.source_id), aar: src.aar ?? null, slaegtled: x.slaegtled_lokal ?? null };
    let entry: SourceRef;
    if (!skema) {
      const ref = [x.linje ? 'Linje ' + x.linje : '', nrTekst != null ? 'nr. ' + nrTekst : '']
        .filter(Boolean)
        .join(', ');
      entry = { ...base, ref };
    } else {
      const e = x.linje ? skema(String(x.source_id), x.linje) : null;
      if (e) {
        const hale = [side ? 's. ' + side : '', nrTekst != null ? 'nr. ' + nrTekst : ''].filter(Boolean);
        entry = {
          ...base,
          ref: [linjeTitel(e), ...hale].join(', '),
          kort: [linjeKodeOgNavn(e).kode, ...hale].join(', '),
        };
      } else {
        // Legacy-kode (»1939«, ingen kode): hverken linje eller nr.
        const t = side ? 's. ' + side : '';
        entry = { ...base, ref: t, kort: t };
      }
    }
    (out[cid(String(x.person_id))] ??= []).push(entry);
  });
  return out;
}
