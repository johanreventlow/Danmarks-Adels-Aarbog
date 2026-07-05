// Indledende narrativer på slægts-niveau ("Om slægten") — billeder-i-narrativer 2026-07-05,
// Slice C4. Bygget fra bunden (app/about.tsx havde INGEN datahentning før nu, kun en hårdkodet
// pladsholder) — porteret fra web/src/data/public.ts's fetchAbout, samme selector
// (pickPreferredBio) og samme sentinel/lineage-navngivning som Slice C3's redigerings-side.
import { supabase } from '../lib/supabase';
import { pickPreferredBio, type NarrativeCand } from './pickPreferredBio';

export type AboutSection = { lineageNavn: string | null; tekst: string };

type RawAboutRow = { id: number; subjekt_type: string; subjekt_id: number; source_id: number | null; tekst: string | null; privat: boolean | null; source: { slags: string | null; aar: number | null; udgave: string | null } | null };

export async function fetchAbout(): Promise<AboutSection[]> {
  if (!supabase) return [];
  // Håndfuld rækker (6 subjekter × få udgaver) — ingen paginering nødvendig. Rå cast: Supabases
  // genererede typer for et embedded source_id(...)-join matcher ikke automatisk to-en-kardinalitet.
  const [narr, lin] = await Promise.all([
    supabase.from('narrative').select('id,subjekt_type,subjekt_id,source_id,tekst,privat,source:source_id(slags,aar,udgave)').in('subjekt_type', ['slaegt', 'lineage']),
    supabase.from('lineage').select('id,navn,kode').order('kode', { ascending: true }),
  ]);
  if (narr.error) throw new Error(narr.error.message);
  if (lin.error) throw new Error(lin.error.message);
  const rows = (narr.data ?? []) as unknown as RawAboutRow[];
  const lineageRows = (lin.data ?? []) as { id: number; navn: string | null; kode: string }[];
  const lineageNavnById = new Map(lineageRows.map((l) => [l.id, l.navn ?? `Linje ${l.kode}`] as const));

  const candsByKey = new Map<string, NarrativeCand[]>();
  for (const r of rows) {
    if (r.privat) continue;
    const key = `${r.subjekt_type}:${r.subjekt_id}`;
    const cand: NarrativeCand = { narrativeId: r.id, tekst: r.tekst, sourceId: r.source_id, slags: r.source?.slags ?? null, aar: r.source?.aar ?? null, udgave: r.source?.udgave ?? null };
    const list = candsByKey.get(key);
    if (list) list.push(cand); else candsByKey.set(key, [cand]);
  }

  const sections: AboutSection[] = [];
  const slaegtCands = [...candsByKey.entries()].find(([key]) => key.startsWith('slaegt:'))?.[1];
  const slaegtBedst = slaegtCands ? pickPreferredBio(slaegtCands) : null;
  if (slaegtBedst?.tekst) sections.push({ lineageNavn: null, tekst: slaegtBedst.tekst });
  for (const l of lineageRows) {
    const cands = candsByKey.get(`lineage:${l.id}`);
    const best = cands ? pickPreferredBio(cands) : null;
    if (best?.tekst) sections.push({ lineageNavn: lineageNavnById.get(l.id) ?? null, tekst: best.tekst });
  }
  return sections;
}
