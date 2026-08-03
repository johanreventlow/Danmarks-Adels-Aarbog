import { buildBioSourceVersions, type BioSourceVersion } from '@daa/core';

export async function fetchPublicBioVersions(
  sb: { rpc: (name: string, args: unknown) => PromiseLike<{ data: unknown[] | null; error: unknown }> }, personIds: string[],
): Promise<BioSourceVersion[] | null> {
  const result = await sb.rpc('public_person_bio_source_versions', { p_person_ids: personIds.map(Number).filter(Number.isFinite) });
  if (result.error) return null;
  return buildBioSourceVersions((result.data ?? []).flatMap((row) => {
    if (typeof row !== 'object' || row === null) return [];
    const v = row as Record<string, unknown>;
    if ((v.provenance_kind !== 'source_record' && v.provenance_kind !== 'legacy_narrative')
      || (v.record_ref !== null && typeof v.record_ref !== 'string')
      || typeof v.source_label !== 'string' || typeof v.record_label !== 'string'
      || typeof v.narrative_text !== 'string' || typeof v.citation_label !== 'string') return [];
    return [{ record_ref: v.record_ref, source_label: v.source_label, record_label: v.record_label,
      narrative_text: v.narrative_text, citation_label: v.citation_label, provenance_kind: v.provenance_kind }];
  }));
}
