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

export type BioSourceVersion = {
  recordRef: string | null;
  sourceLabel: string;
  recordLabel: string;
  narrativeText: string;
  citationLabel: string;
  provenanceKind: 'source_record' | 'legacy_narrative';
};

export type PublicBioSourceVersionRow = {
  record_ref: string | null;
  source_label: string;
  record_label: string;
  narrative_text: string;
  citation_label: string;
  provenance_kind: 'source_record' | 'legacy_narrative';
};

// Version 2 is deliberately a separate public contract.  It exposes only
// public sort inputs and never carries a private source-record UUID or key.
export type PublicBioSourceVersionRowV2 = {
  person_id: number;
  source_id: number;
  source_year: number | null;
  record_order: number | null;
  source_record_ref: string | null;
  source_label: string;
  record_label: string;
  narrative_text: string;
  citation_label: string;
  provenance_kind: 'source_record' | 'legacy_narrative';
};

export type BioSourceVersionV2 = BioSourceVersion & {
  personId: number;
  sourceId: number;
  sourceYear: number | null;
  recordOrder: number | null;
  sourceRecordRef: string | null;
};

// RPC-rækker er allerede publicerings- og privatlivsgatede i databasen. Denne
// mapper bevarer derfor hver record som sin egen version i stedet for at samle
// tekst pr. bog, som den ældre fallback-builder gør.
export function buildBioSourceVersions(rows: PublicBioSourceVersionRow[]): BioSourceVersion[] {
  return rows
    .filter((row) => row.narrative_text.trim() !== '')
    .map((row) => ({
      recordRef: row.record_ref,
      sourceLabel: row.source_label,
      recordLabel: row.record_label,
      narrativeText: row.narrative_text.trim(),
      citationLabel: row.citation_label,
      provenanceKind: row.provenance_kind,
    }))
    .sort((a, b) => a.sourceLabel.localeCompare(b.sourceLabel, 'da')
      || a.recordLabel.localeCompare(b.recordLabel, 'da')
      || (a.recordRef ?? '').localeCompare(b.recordRef ?? ''));
}

function requireNumber(value: unknown, column: string, nullable = false): number | null {
  if (nullable && value === null) return null;
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    throw new Error(`PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_${column}`);
  }
  return value;
}

function requireString(value: unknown, column: string, nullable = false): string | null {
  if (nullable && value === null) return null;
  if (typeof value !== 'string') throw new Error(`PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_${column}`);
  return value;
}

function mapPublicBioSourceVersionRowV2(row: unknown): BioSourceVersionV2 {
  if (typeof row !== 'object' || row === null || Array.isArray(row)) {
    throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_ROW');
  }
  const value = row as Record<string, unknown>;
  const provenanceKind = value.provenance_kind;
  if (provenanceKind !== 'source_record' && provenanceKind !== 'legacy_narrative') {
    throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_provenance_kind');
  }
  const personId = requireNumber(value.person_id, 'person_id') as number;
  const sourceId = requireNumber(value.source_id, 'source_id') as number;
  const sourceYear = requireNumber(value.source_year, 'source_year', true);
  const recordOrder = requireNumber(value.record_order, 'record_order', true);
  const sourceRecordRef = requireString(value.source_record_ref, 'source_record_ref', true);
  const sourceLabel = requireString(value.source_label, 'source_label') as string;
  const recordLabel = requireString(value.record_label, 'record_label') as string;
  const narrativeText = requireString(value.narrative_text, 'narrative_text') as string;
  const citationLabel = requireString(value.citation_label, 'citation_label') as string;
  return {
    personId,
    sourceId,
    sourceYear,
    recordOrder,
    sourceRecordRef,
    recordRef: sourceRecordRef,
    sourceLabel,
    recordLabel,
    narrativeText,
    citationLabel,
    provenanceKind,
  };
}

// The public v2 RPC returns the canonical chronology.  Keep the ordering in
// core as a defensive client-side contract as well: source labels are not
// chronology and source ids are opaque ascending tie-breakers only.
export function mapPublicBioSourceVersionsV2(rows: readonly unknown[]): BioSourceVersionV2[] {
  return rows.map(mapPublicBioSourceVersionRowV2).sort((a, b) => {
    if (a.sourceYear !== b.sourceYear) {
      if (a.sourceYear === null) return 1;
      if (b.sourceYear === null) return -1;
      return b.sourceYear - a.sourceYear;
    }
    if (a.sourceId !== b.sourceId) return a.sourceId - b.sourceId;
    if (a.provenanceKind !== b.provenanceKind) {
      return a.provenanceKind === 'source_record' ? -1 : 1;
    }
    if (a.recordOrder !== b.recordOrder) {
      if (a.recordOrder === null) return 1;
      if (b.recordOrder === null) return -1;
      return a.recordOrder - b.recordOrder;
    }
    const labelOrder = a.recordLabel.localeCompare(b.recordLabel, 'da');
    if (labelOrder !== 0) return labelOrder;
    return (a.sourceRecordRef ?? '').localeCompare(b.sourceRecordRef ?? '');
  });
}

// A blank event text is not a usable biography, but it remains visible to the
// caller as a malformed/empty public response rather than being concatenated.
export function selectDefaultPublicBioSourceVersionV2(
  versions: readonly BioSourceVersionV2[],
): BioSourceVersionV2 | null {
  const eligible = (version: BioSourceVersionV2) => version.narrativeText.trim() !== '';
  return versions.find((version) => version.provenanceKind === 'source_record' && eligible(version))
    ?? versions.find((version) => version.provenanceKind === 'legacy_narrative' && eligible(version))
    ?? null;
}

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
