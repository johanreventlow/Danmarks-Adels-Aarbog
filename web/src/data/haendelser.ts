// Web-spejl af mobilens hændelses-loader (fase2-design.md §5.2). Henter kun
// projektionen + narrativ/source-metadata; narrativteksten forlader ikke sit normale lag.
// Review 37 Y3: hentes via RPC'en public_haendelse_feed i bidder (gaten én gang pr. narrativ, så hvert kald
// holder anon-grænsen), til naeste er null. Klienten stopper KUN ved naeste=null: en bid kan lovligt være tom.
// Fejl — inklusive en endnu umigreret base — degraderer i hændelseskortene til {}, aldrig et brudt feed;
// feedGrundlag bruger samme bladrer, men fail-closed.
import { buildHaendelserBy } from '@daa/feed';
import type {
  HaendelseNarrativRow,
  HaendelseRow,
  HaendelseSourceRow,
  HaendelserBy,
} from '@daa/feed';
import { supabase } from '../supabase';

export type HaendelseRowsResult = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
};

// Loft over antal kald i én bladring. Med serverens standardlofter (150 narrativer / 1.000 rækker pr. kald) rækker det
// langt ud over hele korpusset; nås det, er noget galt, og resultatet ville være afkortet.
const MAX_SIDER = 500;

type FeedSide = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
  naeste: string | null;
};

function erFeedSide(data: unknown): data is FeedSide {
  if (data === null || typeof data !== 'object') return false;
  const side = data as Record<string, unknown>;
  return Array.isArray(side.rows) && Array.isArray(side.narrativer) && Array.isArray(side.sources)
    && (side.naeste === null || typeof side.naeste === 'string');
}

// Feedet starter hændelseskortene og »Nævnt i Aarbogen«-grundlaget samtidig. De deler én igangværende bladring,
// så gaten ikke kører to gange over hele korpusset. Delingen er bundet til brugeren: RPC'en er i dag ens for alle
// roller, men en senere rolleforskel må aldrig kunne arves over logud/login. Ingen cache: når bladringen er
// afsluttet, henter næste kald forfra.
const igangvaerende = new Map<string, Promise<HaendelseRowsResult>>();

// Bladrer hele feedet igennem. Kaster ved enhver fejl, også efter en vellykket side: et delvist resultat må aldrig
// se ud som et helt. Narrativer og kilder, der går igen på flere sider, tages kun med én gang. Resultatet deles
// mellem samtidige kaldere for samme bruger og må ikke ændres af dem.
export async function fetchHaendelseFeed(): Promise<HaendelseRowsResult> {
  const { data } = await supabase.auth.getSession();
  const noegle = data.session?.user.id ?? 'gaest';
  let bladring = igangvaerende.get(noegle);
  if (!bladring) {
    bladring = bladrFeed().finally(() => { igangvaerende.delete(noegle); });
    igangvaerende.set(noegle, bladring);
  }
  return bladring;
}

async function bladrFeed(): Promise<HaendelseRowsResult> {
  const rows: HaendelseRow[] = [];
  const narrativer = new Map<string, HaendelseNarrativRow>();
  const sources = new Map<string, HaendelseSourceRow>();
  let fortsaet: string | null = null;
  for (let i = 0; i < MAX_SIDER; i++) {
    // Én side, der rammer gæsteloftet, prøves igen én gang med samme mærke (prod 24/11: 8 af 36 kald fejlede).
    // Fejler den igen, kaster bladringen stadig: et delvist resultat må aldrig se ud som et helt.
    const hentSide = (): PromiseLike<{ data: unknown; error: unknown }> =>
      supabase.rpc('public_haendelse_feed', { p_fortsaet: fortsaet });
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

export async function fetchHaendelseRows(): Promise<HaendelseRowsResult> {
  try {
    return await fetchHaendelseFeed();
  } catch (e) {
    console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades:', e);
    return { rows: [], narrativer: [], sources: [] };
  }
}

export async function loadHaendelserBy(
  canonicalIdById: Record<string, string>,
): Promise<HaendelserBy> {
  const result = await fetchHaendelseRows();
  return buildHaendelserBy(
    result.rows, result.narrativer, result.sources, canonicalIdById,
  );
}
