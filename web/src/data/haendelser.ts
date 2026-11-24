// Web-spejl af mobilens hændelses-loader (fase2-design.md §5.2): bladringen over hændelses-feedet. Henter kun
// projektionen + narrativ/source-metadata; narrativteksten forlader ikke sit normale lag.
// Review 37 Y3: hentes via RPC'en public_haendelse_feed i bidder (gaten én gang pr. narrativ, så hvert kald
// holder anon-grænsen), til naeste er null. Klienten stopper KUN ved naeste=null: en bid kan lovligt være tom.
//
// Filen står på cutover-kontraktens frosne liste over narrativ-læsere (schema.sql, »classified_direct_readers«;
// R-postverify sammenligner listen med checkoutet). RPC-kaldet skal derfor blive HER. Filen køres også af
// Vercel-funktionen web/api/forside-data.ts (Edge) og må derfor hverken importere den env-bundne klient (../supabase)
// eller værdier fra @daa/* (testet i forside/__tests__/edgeImporter.test.ts). Browserens loadere: haendelseFeed.ts.
import type { HaendelseNarrativRow, HaendelseRow, HaendelseSourceRow } from '@daa/feed';
import type { Sb } from './forside/kilder';

export type HaendelseRowsResult = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
};

// Loft over antal kald i én bladring. Med serverens standardlofter (150 narrativer / 1.000 rækker pr. kald) rækker det
// langt ud over hele korpusset; nås det, er noget galt, og resultatet ville være afkortet.
export const MAX_SIDER = 500;

type FeedSide = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
  naeste: string | null;
};

export function erFeedSide(data: unknown): data is FeedSide {
  if (data === null || typeof data !== 'object') return false;
  const side = data as Record<string, unknown>;
  return Array.isArray(side.rows) && Array.isArray(side.narrativer) && Array.isArray(side.sources)
    && (side.naeste === null || typeof side.naeste === 'string');
}

// Bladrer hele feedet igennem. Kaster ved enhver fejl, også efter en vellykket side: et delvist resultat må aldrig
// se ud som et helt. Narrativer og kilder, der går igen på flere sider, tages kun med én gang.
export async function bladrHaendelser(sb: Sb): Promise<HaendelseRowsResult> {
  const rows: HaendelseRow[] = [];
  const narrativer = new Map<string, HaendelseNarrativRow>();
  const sources = new Map<string, HaendelseSourceRow>();
  let fortsaet: string | null = null;
  for (let i = 0; i < MAX_SIDER; i++) {
    // Én side, der rammer gæsteloftet, prøves igen én gang med samme mærke (prod 24/11: 8 af 36 kald fejlede).
    // Fejler den igen, kaster bladringen stadig: et delvist resultat må aldrig se ud som et helt.
    const hentSide = (): PromiseLike<{ data: unknown; error: unknown }> =>
      sb.rpc('public_haendelse_feed', { p_fortsaet: fortsaet });
    let svar = await hentSide();
    if (svar.error) svar = await hentSide();
    const { data, error } = svar;
    if (error) throw error;
    if (!erFeedSide(data)) throw new Error('public_haendelse_feed: svaret har ikke den forventede form');
    rows.push(...data.rows);
    for (const n of data.narrativer) narrativer.set(String(n.id), n);
    for (const s of data.sources) sources.set(String(s.id), s);
    if (data.naeste === null) {
      return { rows, narrativer: [...narrativer.values()], sources: [...sources.values()] };
    }
    fortsaet = data.naeste;
  }
  throw new Error(`public_haendelse_feed: loftet på ${MAX_SIDER} sider er nået — resultatet ville være afkortet`);
}
