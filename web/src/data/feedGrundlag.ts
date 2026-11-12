// Grundlaget for feedets »Nævnt i Aarbogen«-kort: hvilke personer har MERE end et navn
// (embede, gods, hændelse, historie)? Et kort om en person må aldrig vises, fordi en hentning
// fejlede og så tom ud — derfor kaster denne funktion ved enhver fejl i stedet for at falde
// tilbage til en tom mængde (ingen safe()), og kalderen sender så intet naevntGrundlag.
// Kun person-id'er hentes; teksterne hentes af feedets egne loadere.
import { getAll } from '@daa/core';
import type { NaevntGrundlag } from '@daa/feed';
import { supabase } from '../supabase';

type SubjektRow = { subjekt_id: number | string };

export function buildNaevntGrundlag(
  rowGroups: SubjektRow[][],
  canonicalIdById: Record<string, string>,
): NaevntGrundlag {
  const personer = new Set<string>();
  for (const rows of rowGroups) {
    for (const row of rows) {
      const id = String(row.subjekt_id);
      personer.add(canonicalIdById[id] ?? id);
    }
  }
  return { personerMedMereEndNavn: personer };
}

export async function fetchNaevntGrundlag(
  canonicalIdById: Record<string, string>,
): Promise<NaevntGrundlag> {
  const rowGroups = await Promise.all([
    // Embeder (organisation) og godser (estate) — samme kilde som personsidens sektioner.
    getAll<SubjektRow>(() => supabase.from('relation').select('subjekt_id')
      .eq('subjekt_type', 'person').in('objekt_type', ['organisation', 'estate']).order('id')),
    // Alle hændelser, også dem feedet ikke viser (feed_status): de er stadig mere end et navn.
    getAll<SubjektRow>(() => supabase.from('haendelse').select('subjekt_id')
      .eq('subjekt_type', 'person').order('id')),
    getAll<SubjektRow>(() => supabase.from('story').select('subjekt_id')
      .eq('subjekt_type', 'person').eq('status', 'publiceret').order('id')),
  ]);
  return buildNaevntGrundlag(rowGroups, canonicalIdById);
}
