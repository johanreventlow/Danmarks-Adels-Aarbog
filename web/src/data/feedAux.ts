// Web-adapter til feed-motoren (fase1-design.md §7.2-§7.3). buildWebFeedAux mapper
// webbens allerede-hentede estates/arms til FeedAux. Web indlæser IKKE bio pr. person ved
// cold-start (model.ts sætter bio:'') — fetchFeedBios/withFeedBios henter og stempler bio
// ind i en KOPI af modellen ved feed-mount, uden at røre den originale model.
import {
  buildBioSourceVersions,
  mapPublicBioSourceVersionsV2,
  selectDefaultPublicBioSourceVersionV2,
} from '@daa/core';
import { supabase } from '../supabase';
import type { ArmsItem, EstateItem } from './public';
import type { FeedAux } from '@daa/feed';
import type { Model, ModelPerson } from './types';

export function buildWebFeedAux(estates: EstateItem[] | null, arms: ArmsItem[] | null): FeedAux {
  return {
    godsListe: (estates ?? []).map((e) => ({ id: e.id, navn: e.navn, slags: e.slags, ownerCount: e.ownerCount })),
    vaabenListe: (arms ?? []).map((a) => ({ id: a.id, blasonering: a.blasonering, note: a.note })),
    // Web-publikum indlæser ikke embeder pr. person (kun mobilens Aux gør) — bevidst
    // udeladelse i fase 1-MVP'en; embede-kort kommer gratis når fase 2 alligevel rører
    // webbens load. Ingen crash: tomt map ⇒ buildEmbeder giver blot ingen kort.
    officesBy: {},
  };
}

export const FEED_BIO_IN_CHUNK = 200;

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

// Modellen indeholder kun kanoniske personer, mens narrativer også kan ligge på alias-rækker.
// Medtag derfor både model-id'erne og de alias-id'er der foldes ind i dem.
export function buildFeedBioSubjectIds(
  canonicalIdById: Record<string, string>,
  modelPersonIds: readonly string[],
): string[] {
  const canonicalPersons = new Set(modelPersonIds);
  return [...new Set([
    ...modelPersonIds,
    ...Object.entries(canonicalIdById)
      .filter(([, canonical]) => canonicalPersons.has(canonical))
      .map(([alias]) => alias),
  ])].sort();
}

// Hent den foretrukne offentlige eventtekst pr. (kanonisk) person.  Contract
// v2 is the only post-cutover reader; it never falls back to public.narrative.
export async function fetchFeedBios(
  canonicalIdById: Record<string, string>,
  modelPersonIds?: readonly string[],
): Promise<Record<string, string>> {
  let contractVersion: number | null = null;
  try {
    const subjectIds = buildFeedBioSubjectIds(canonicalIdById, modelPersonIds ?? []);
    if (!subjectIds.length) return {};
    const personIds = subjectIds.map(Number).filter(Number.isFinite);
    const version = await supabase.rpc('narrative_record_contract_version', {});
    if (version.error || typeof version.data !== 'number' || !Number.isInteger(version.data)) {
      throw new Error('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
    }
    contractVersion = version.data;
    const rpcName = contractVersion >= 2
      ? 'public_person_bio_source_versions_v2'
      : 'public_person_bio_source_versions';
    const result = await supabase.rpc(rpcName, { p_person_ids: personIds });
    if (result.error || !Array.isArray(result.data)) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    const bioBy: Record<string, string> = {};
    if (contractVersion >= 2) {
      const versionsByCanonicalPerson = new Map<string, unknown[]>();
      for (const row of result.data) {
        if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') {
          throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_person_id');
        }
        const personId = (row as Record<string, number>).person_id;
        const canonicalId = canonicalIdById[String(personId)] ?? String(personId);
        const rows = versionsByCanonicalPerson.get(canonicalId);
        if (rows) rows.push(row); else versionsByCanonicalPerson.set(canonicalId, [row]);
      }
      for (const [canonicalId, rows] of versionsByCanonicalPerson) {
        const selected = selectDefaultPublicBioSourceVersionV2(mapPublicBioSourceVersionsV2(rows));
        if (selected) bioBy[canonicalId] = selected.narrativeText;
      }
    } else {
      for (const row of result.data) {
        if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') continue;
        const text = mapV1Text(row);
        if (text) {
          const personId = (row as Record<string, number>).person_id;
          const canonicalId = canonicalIdById[String(personId)] ?? String(personId);
          bioBy[canonicalId] ??= text;
        }
      }
    }
    return bioBy;
  } catch (e) {
    console.warn('[feedAux] bio-hentning fejlede:', e);
    if (contractVersion !== null && contractVersion < 2) return {};
    throw e;
  }
}

// Ren kopi: stempler bio ind i en NY persons-liste/byId — den originale model (og dens
// øvrige lag: indexes, lineage, geo osv.) røres ikke. Personer uden en post i bioBy
// beholder deres eksisterende (typisk tomme) bio.
export function withFeedBios(model: Model, bioBy: Record<string, string>): Model {
  const persons: ModelPerson[] = model.persons.map((p) =>
    bioBy[p.id] ? { ...p, bio: bioBy[p.id] } : p,
  );
  const byId: Record<string, ModelPerson> = {};
  for (const p of persons) byId[p.id] = p;
  return { ...model, persons, byId };
}
