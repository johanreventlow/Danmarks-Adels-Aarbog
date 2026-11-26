// Indledende narrativer på slægts-niveau ("Om slægten") — billeder-i-narrativer 2026-07-05,
// Slice C4. Bygget fra bunden (app/about.tsx havde INGEN datahentning før nu, kun en hårdkodet
// pladsholder) — porteret fra web/src/data/public.ts's fetchAbout, samme selector
// (pickPreferredBio) og samme sentinel/lineage-navngivning som Slice C3's redigerings-side.
import { supabase } from '../lib/supabase';
import { pickPreferredBio, type NarrativeCand } from '@daa/core';

// 6e (paritetsplanens batch 5): hvert afsnit bærer sin udgave (kilde/aar) og linjens kode i den udgave, rækken
// stammer fra — samme form og regler som web/src/data/public.ts (AboutSection/byggAboutSections/indledningKilde).
// Porteret ordret frem for flyttet til @daa/core, fordi web-filen ikke må ændres i denne omgang; når web skal røres
// igen, kan begge importere én kopi fra kernen.
export type AboutSection = { lineageId: string | null; lineageNavn: string | null; lineageKode: string | null; tekst: string; kilde: string | null; aar: number | null };

type RawAboutSource = { slags: string | null; titel?: string | null; aar: number | null; udgave: string | null };
export type RawAboutRow = { id: number; subjekt_type: string; subjekt_id: number; source_id: number | null; tekst: string | null; privat?: boolean | null; source: RawAboutSource | null };
export type RawAboutLineage = { id: number; navn: string | null; kode: string };

// Ren: narrativ-rækker + linjer → afsnit. "Generelt" (slaegt) først, linjer i kode-orden. Private rækker springes over.
export function byggAboutSections(rows: RawAboutRow[], lineageRows: RawAboutLineage[]): AboutSection[] {
  const candsByKey = new Map<string, NarrativeCand[]>();
  const sourceById = new Map<number, RawAboutSource>();
  for (const r of rows) {
    if (r.privat) continue;
    const key = `${r.subjekt_type}:${r.subjekt_id}`;
    const cand: NarrativeCand = { narrativeId: r.id, tekst: r.tekst, sourceId: r.source_id, slags: r.source?.slags ?? null, aar: r.source?.aar ?? null, udgave: r.source?.udgave ?? null };
    if (r.source_id != null && r.source) sourceById.set(r.source_id, r.source);
    const list = candsByKey.get(key);
    if (list) list.push(cand); else candsByKey.set(key, [cand]);
  }
  // Udgavens etiket efter udgavevælgerens regel (udgave ?? titel), så indledningen og personsiden nævner den ens.
  const kildeAf = (c: NarrativeCand) => {
    const src = c.sourceId != null ? sourceById.get(c.sourceId) : undefined;
    return { kilde: src ? (src.udgave ?? src.titel ?? null) : null, aar: src?.aar ?? null };
  };

  const sections: AboutSection[] = [];
  const slaegtCands = [...candsByKey.entries()].find(([key]) => key.startsWith('slaegt:'))?.[1];
  const slaegtBedst = slaegtCands ? pickPreferredBio(slaegtCands) : null;
  if (slaegtBedst?.tekst) sections.push({ lineageId: null, lineageNavn: null, lineageKode: null, tekst: slaegtBedst.tekst, ...kildeAf(slaegtBedst) });
  for (const l of lineageRows) {
    const cands = candsByKey.get(`lineage:${l.id}`);
    const best = cands ? pickPreferredBio(cands) : null;
    if (best?.tekst) sections.push({ lineageId: String(l.id), lineageNavn: l.navn ?? `Linje ${l.kode}`, lineageKode: l.kode, tekst: best.tekst, ...kildeAf(best) });
  }
  return sections;
}

// Afsnittets kildelinje (som web's AboutView): udgaven, ellers årbogens år, ellers »Kilde ikke registreret«.
export function indledningKilde(s: Pick<AboutSection, 'kilde' | 'aar'>): string {
  if (s.kilde) return `Kilde: ${s.kilde}`;
  return s.aar ? `Kilde: Danmarks Adels Aarbog ${s.aar}` : 'Kilde ikke registreret';
}

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
