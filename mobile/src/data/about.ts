// Indledende narrativer på slægts-niveau ("Om slægten") — billeder-i-narrativer 2026-07-05,
// Slice C4. Bygget fra bunden (app/about.tsx havde INGEN datahentning før nu, kun en hårdkodet
// pladsholder) — porteret fra web/src/data/public.ts's fetchAbout, samme selector
// (pickPreferredBio) og samme sentinel/lineage-navngivning som Slice C3's redigerings-side.
import { supabase } from '../lib/supabase';
import { byggAboutSections, indledningKilde, type AboutSection, type RawAboutLineage, type RawAboutRow } from '@daa/core';

// Afsnittene (udgave, linjekode, private rækker sprunget over) og kildelinjen bygges i @daa/core (omSlaegten.ts) — samme
// kopi som web's »Om slægten«; re-eksporteres her for de eksisterende importstier.
export { byggAboutSections, indledningKilde };
export type { AboutSection, RawAboutRow, RawAboutLineage };

export async function fetchAbout(): Promise<AboutSection[]> {
  if (!supabase) return [];
  // Håndfuld rækker (6 subjekter × få udgaver) — ingen paginering nødvendig. Rå cast: Supabases
  // genererede typer for et embedded source_id(...)-join matcher ikke automatisk to-en-kardinalitet.
  const [narr, lin] = await Promise.all([
    supabase.from('narrative').select('id,subjekt_type,subjekt_id,source_id,tekst,privat,source:source_id(slags,titel,aar,udgave)').in('subjekt_type', ['slaegt', 'lineage']),
    supabase.from('lineage').select('id,navn,kode').order('kode', { ascending: true }),
  ]);
  if (narr.error) throw new Error(narr.error.message);
  if (lin.error) throw new Error(lin.error.message);
  return byggAboutSections((narr.data ?? []) as unknown as RawAboutRow[], (lin.data ?? []) as RawAboutLineage[]);
}
