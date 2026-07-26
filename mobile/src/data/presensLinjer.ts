// Mobilens enkle linje-metadata: titel/slægtsnavn + én signeret våben-URL samt præsens-intro.
import { getAll } from '@daa/core';
import { isMediaAuthEpochCurrent, signPaths } from '../lib/media';
import { supabase } from '../lib/supabase';

export type PresensLinjeInfo = {
  titel: string;
  slaegtsnavn: string | null;
  vaabenUrl: string | null;
};

type RawLineage = {
  id: number;
  kode: string;
  navn: string;
  slaegtsnavn: string | null;
  presens_kode: string | null;
};
type RawRelation = { subjekt_id: number; objekt_id: number };
type RawMedia = { id: number; storage_path: string | null };

// Nøgles på presens_kode, ikke kode: præsenslisten omnummererer kun nulevende linjer.
// Første signerbare afbildning pr. våben vælges i relationsrækkefølgen.
export function mapPresensLinjer(
  lineageRows: RawLineage[],
  vaabenRel: RawRelation[],
  mediaRel: RawRelation[],
  mediaRows: RawMedia[],
  signed: Map<string, string>,
): Record<string, PresensLinjeInfo> {
  const armIdByLineageId = new Map(vaabenRel.map((r) => [r.subjekt_id, r.objekt_id]));
  const mediaIdsByArmId = new Map<number, number[]>();
  for (const rel of mediaRel) {
    const ids = mediaIdsByArmId.get(rel.objekt_id) ?? [];
    ids.push(rel.subjekt_id);
    mediaIdsByArmId.set(rel.objekt_id, ids);
  }
  const mediaById = new Map(mediaRows.map((m) => [m.id, m]));
  const out: Record<string, PresensLinjeInfo> = {};
  for (const lineage of lineageRows) {
    if (lineage.presens_kode == null) continue;
    const armId = armIdByLineageId.get(lineage.id);
    const vaabenUrl = armId == null
      ? null
      : (mediaIdsByArmId.get(armId) ?? [])
          .map((id) => mediaById.get(id)?.storage_path)
          .filter((path): path is string => !!path)
          .map((path) => signed.get(path) ?? null)
          .find((url): url is string => url != null) ?? null;
    out[lineage.presens_kode] = {
      titel: lineage.navn,
      slaegtsnavn: lineage.slaegtsnavn,
      vaabenUrl,
    };
  }
  return out;
}

export async function fetchPresensLinjer(epoch: number): Promise<Record<string, PresensLinjeInfo>> {
  if (!supabase) return {};
  const sb = supabase;
  const lineageRows = await getAll<RawLineage>(() =>
    sb.from('lineage').select('id,kode,navn,slaegtsnavn,presens_kode'));
  const lineageIds = lineageRows.map((lineage) => lineage.id);
  const vaabenRel = lineageIds.length
    ? await getAll<RawRelation>(() =>
        sb.from('relation').select('subjekt_id,objekt_id')
          .eq('subjekt_type', 'lineage')
          .eq('objekt_type', 'coat_of_arms')
          .eq('rolle', 'vaaben')
          .in('subjekt_id', lineageIds)
          .order('id'))
    : [];
  const armIds = [...new Set(vaabenRel.map((rel) => rel.objekt_id))];
  const mediaRel = armIds.length
    ? await getAll<RawRelation>(() =>
        sb.from('relation').select('subjekt_id,objekt_id')
          .eq('subjekt_type', 'media')
          .eq('objekt_type', 'coat_of_arms')
          .eq('rolle', 'afbildet')
          .in('objekt_id', armIds)
          .order('id'))
    : [];
  const mediaIds = [...new Set(mediaRel.map((rel) => rel.subjekt_id))];
  const mediaRows = mediaIds.length
    ? await getAll<RawMedia>(() =>
        sb.from('media').select('id,storage_path').in('id', mediaIds).order('id'))
    : [];
  const signed = await signPaths(
    mediaRows.map((media) => media.storage_path ?? '').filter(Boolean),
    epoch,
  );
  if (!isMediaAuthEpochCurrent(epoch)) return {};
  return mapPresensLinjer(lineageRows, vaabenRel, mediaRel, mediaRows, signed);
}

type RawIntroNarr = {
  id: number;
  tekst: string | null;
  source: { slags: string | null } | null;
};

export function pickPresensIntro(rows: RawIntroNarr[]): string | null {
  const candidates = rows.filter(
    (row) => row.source?.slags === 'præsens-intro' && (row.tekst ?? '').trim() !== '',
  );
  if (!candidates.length) return null;
  return [...candidates].sort((a, b) => b.id - a.id)[0].tekst;
}

export async function fetchPresensIntro(): Promise<string | null> {
  if (!supabase) return null;
  const res = await supabase.from('narrative').select('id,tekst,source:source_id(slags)')
    .eq('subjekt_type', 'slaegt').eq('subjekt_id', 1).eq('privat', false);
  if (res.error) throw res.error;
  const rows = (res.data ?? []) as unknown as RawIntroNarr[];
  return pickPresensIntro(rows);
}
