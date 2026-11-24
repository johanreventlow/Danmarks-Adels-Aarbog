// Valget af den foretrukne offentlige biografi pr. kanonisk person — kun i browseren (den direkte hentning og
// udpakningen af forsidens fil). Ligger uden for kilder.ts, så Edge-funktionen ikke skal bruge @daa/core.
import {
  buildBioSourceVersions,
  mapPublicBioSourceVersionsV2,
  selectDefaultPublicBioSourceVersionV2,
} from '@daa/core';
import type { BioRaekker } from './kilder';

function mapV1Text(row: unknown): string | null {
  if (typeof row !== 'object' || row === null) return null;
  const value = row as Record<string, unknown>;
  if ((value.provenance_kind !== 'source_record' && value.provenance_kind !== 'legacy_narrative')
    || (value.record_ref !== null && typeof value.record_ref !== 'string')
    || typeof value.source_label !== 'string' || typeof value.record_label !== 'string'
    || typeof value.narrative_text !== 'string' || typeof value.citation_label !== 'string') return null;
  return buildBioSourceVersions([{
    record_ref: value.record_ref,
    source_label: value.source_label,
    record_label: value.record_label,
    narrative_text: value.narrative_text,
    citation_label: value.citation_label,
    provenance_kind: value.provenance_kind,
  }])[0]?.narrativeText ?? null;
}

// Den foretrukne offentlige tekst pr. kanonisk person. Rækkerne samles FØR valget, så aliaser i forskellige bidder giver
// ét valg pr. kanonisk person. En sammenfoldet person, hvis alias lå i en fejlet bid, får ingen tekst frem for en forkert.
export function vaelgFeedBios(r: BioRaekker, canonicalIdById: Record<string, string>): Record<string, string> {
  const kanon = (id: number | string) => canonicalIdById[String(id)] ?? String(id);
  const udelad = new Set(r.fejlede.map(kanon));
  const bioBy: Record<string, string> = {};
  if (r.kontrakt >= 2) {
    const versionsByCanonicalPerson = new Map<string, unknown[]>();
    for (const row of r.rows) {
      if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') {
        throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_person_id');
      }
      const canonicalId = kanon((row as Record<string, number>).person_id);
      const rows = versionsByCanonicalPerson.get(canonicalId);
      if (rows) rows.push(row); else versionsByCanonicalPerson.set(canonicalId, [row]);
    }
    for (const [canonicalId, rows] of versionsByCanonicalPerson) {
      if (udelad.has(canonicalId)) continue;
      const selected = selectDefaultPublicBioSourceVersionV2(mapPublicBioSourceVersionsV2(rows));
      if (selected) bioBy[canonicalId] = selected.narrativeText;
    }
  } else {
    for (const row of r.rows) {
      if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') continue;
      const text = mapV1Text(row);
      if (text) {
        const canonicalId = kanon((row as Record<string, number>).person_id);
        if (!udelad.has(canonicalId)) bioBy[canonicalId] ??= text;
      }
    }
  }
  return bioBy;
}
