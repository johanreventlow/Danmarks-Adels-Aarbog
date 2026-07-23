// Linje-metadata (titel/navn/våben) + dedikeret præsens-intro til Præsenslisten-visningen.
// Sideordnet presens.ts (som holder levende-flag + overhoved-ankre) — eget ansvar, egen fil.
import { supabase } from '../supabase';
import { getAll } from '@daa/core';
import { fetchObjectMedia, firstSignable, type MediaItem } from './media';

export type PresensLinjeInfo = { titel: string; slaegtsnavn: string | null; vaaben: MediaItem | null };

type RawLineage = { id: number; kode: string; navn: string; slaegtsnavn: string | null };
type RawRelation = { subjekt_id: number; objekt_id: number };

// Ren mapper — testes uden Supabase. mediaByArm er keyet på coat_of_arms.id som streng
// (samme konvention som fetchObjectMedia's returtype).
export function mapPresensLinjer(
  lineageRows: RawLineage[],
  vaabenRel: RawRelation[],
  mediaByArm: Map<string, MediaItem[]>,
): Record<string, PresensLinjeInfo> {
  const armIdByLineageId = new Map(vaabenRel.map((r) => [r.subjekt_id, r.objekt_id]));
  const out: Record<string, PresensLinjeInfo> = {};
  for (const l of lineageRows) {
    const armId = armIdByLineageId.get(l.id);
    const media = armId != null ? mediaByArm.get(String(armId)) ?? [] : [];
    out[l.kode] = { titel: l.navn, slaegtsnavn: l.slaegtsnavn, vaaben: firstSignable(media) };
  }
  return out;
}

export async function fetchPresensLinjer(): Promise<Record<string, PresensLinjeInfo>> {
  const lineageRows = await getAll<RawLineage>(() =>
    supabase.from('lineage').select('id,kode,navn,slaegtsnavn'));
  const lineageIds = lineageRows.map((l) => l.id);
  const vaabenRel = lineageIds.length
    ? await getAll<RawRelation>(() =>
        supabase.from('relation').select('subjekt_id,objekt_id')
          .eq('subjekt_type', 'lineage').eq('objekt_type', 'coat_of_arms').eq('rolle', 'vaaben')
          .in('subjekt_id', lineageIds))
    : [];
  const armIds = vaabenRel.map((r) => r.objekt_id);
  const mediaByArm = await fetchObjectMedia('coat_of_arms', armIds);
  return mapPresensLinjer(lineageRows, vaabenRel, mediaByArm);
}

type RawIntroNarr = { id: number; tekst: string | null; source: { slags: string | null } | null };

// IKKE pickPreferredBio (packages/core) — den gater på BIO_SLAGS=Set(['DAA-udgave']) og ville
// stille afvise en 'præsens-intro'-kilde. Kun én kilde forventes i praksis; seneste id vinder
// defensivt hvis der alligevel skulle opstå flere.
export function pickPresensIntro(rows: RawIntroNarr[]): string | null {
  const cands = rows.filter((r) => r.source?.slags === 'præsens-intro' && (r.tekst ?? '').trim() !== '');
  if (!cands.length) return null;
  return [...cands].sort((a, b) => b.id - a.id)[0].tekst;
}

export async function fetchPresensIntro(): Promise<string | null> {
  // Håndfuld rækker (typisk kun 1 præsens-intro-kilde) — ingen getAll-paginering nødvendig.
  // Rå cast (samme mønster som fetchAbout/RawAboutRow i public.ts): Supabases genererede typer
  // for et embedded source_id(...)-join matcher ikke automatisk to-en-kardinalitet.
  const res = await supabase.from('narrative').select('id,tekst,source:source_id(slags)')
    .eq('subjekt_type', 'slaegt').eq('subjekt_id', 1).eq('privat', false);
  if (res.error) throw res.error;
  const rows = (res.data ?? []) as unknown as RawIntroNarr[];
  return pickPresensIntro(rows);
}
