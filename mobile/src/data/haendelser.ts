// Hændelses-load (fase2-design.md §5.2): tolerant hentning af den regenererbare hændelsesprojektion
// + narrativ/source-metadata til feed-kildefødder. Narrativ-teksten hentes bevidst ikke.
// Review 37 Y3 (spejl af web/src/data/haendelser.ts): hentes via RPC'en public_haendelse_feed i bidder
// (gaten én gang pr. narrativ, så hvert kald holder anon-grænsen), til naeste er null. Klienten stopper KUN ved
// naeste=null: en bid kan lovligt være tom. Enhver fejl — også en endnu umigreret base, og også efter en vellykket
// side — degraderer til et tomt resultat, så feedet fortsat virker; et delvist resultat bruges aldrig.
// Ingen delt igangværende bladring som på web: her er der én kalder (load.ts), og klienten er en parameter.
import { buildHaendelserBy } from '@daa/feed';
import type {
  HaendelseNarrativRow,
  HaendelseRow,
  HaendelseSourceRow,
  HaendelserBy,
} from '@daa/feed';
import type { supabase } from '../lib/supabase';

export type HaendelseRowsResult = {
  rows: HaendelseRow[];
  narrativer: HaendelseNarrativRow[];
  sources: HaendelseSourceRow[];
};

// Loft over antal kald i én bladring (samme som web). Nås det, er noget galt, og resultatet ville være afkortet.
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

// Bladrer hele feedet igennem. Kaster ved enhver fejl. Narrativer og kilder, der går igen på flere sider, tages
// kun med én gang.
async function bladrFeed(sb: NonNullable<typeof supabase>): Promise<HaendelseRowsResult> {
  const rows: HaendelseRow[] = [];
  const narrativer = new Map<string, HaendelseNarrativRow>();
  const sources = new Map<string, HaendelseSourceRow>();
  let fortsaet: string | null = null;
  for (let i = 0; i < MAX_SIDER; i++) {
    const svar: { data: unknown; error: unknown } =
      await sb.rpc('public_haendelse_feed', { p_fortsaet: fortsaet });
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

export async function fetchHaendelseRows(
  sb: NonNullable<typeof supabase>,
): Promise<HaendelseRowsResult> {
  try {
    return await bladrFeed(sb);
  } catch (e) {
    console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades:', e);
    return { rows: [], narrativer: [], sources: [] };
  }
}

export async function loadHaendelserBy(
  sb: NonNullable<typeof supabase>,
  canonicalIdById: Record<string, string>,
): Promise<HaendelserBy> {
  const result = await fetchHaendelseRows(sb);
  return buildHaendelserBy(
    result.rows, result.narrativer, result.sources, canonicalIdById,
  );
}
