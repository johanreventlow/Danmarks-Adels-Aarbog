import {
  buildBioSourceVersions,
  mapPublicBioSourceVersionsV2,
  physicalPersonIds,
  type BioSourceVersion,
  type Provenance,
} from '@daa/core';

type PublicBioRpc = {
  rpc: (name: string, args: unknown) => PromiseLike<{ data: unknown; error: unknown }>;
};

export async function fetchNarrativeRecordContractVersion(sb: PublicBioRpc): Promise<number | null> {
  try {
    const result = await sb.rpc('narrative_record_contract_version', {});
    return result.error || typeof result.data !== 'number' || !Number.isInteger(result.data)
      ? null
      : result.data;
  } catch {
    return null;
  }
}

function mapV1(rows: unknown[]): BioSourceVersion[] {
  return buildBioSourceVersions(rows.flatMap((row) => {
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

export async function fetchPublicBioVersions(
  sb: PublicBioRpc, personIds: string[],
): Promise<BioSourceVersion[] | null> {
  const personIdsNumeric = personIds.map(Number).filter(Number.isFinite);
  const version = await fetchNarrativeRecordContractVersion(sb);
  if (version === null) return null;
  try {
    if (version >= 2) {
      const result = await sb.rpc('public_person_bio_source_versions_v2', { p_person_ids: personIdsNumeric });
      if (result.error || !Array.isArray(result.data)) return null;
      return mapPublicBioSourceVersionsV2(result.data);
    }
    const result = await sb.rpc('public_person_bio_source_versions', { p_person_ids: personIdsNumeric });
    return result.error || !Array.isArray(result.data) ? null : mapV1(result.data);
  } catch {
    // A v2 error must stay an explicit unavailable result.  In particular, do
    // not retry the old RPC or any direct narrative table read after cutover.
    return null;
  }
}

export function fetchPublicBioVersionsForPerson(
  sb: Parameters<typeof fetchPublicBioVersions>[0],
  canonicalId: string,
  mergedFrom?: ReadonlyArray<Provenance>,
): Promise<BioSourceVersion[] | null> {
  return fetchPublicBioVersions(sb, physicalPersonIds(canonicalId, mergedFrom));
}
