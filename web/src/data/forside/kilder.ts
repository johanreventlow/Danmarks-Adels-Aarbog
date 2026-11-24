// Forsidens rå hentninger, uafhængige af den env-bundne browserklient (../../supabase): de tager en Supabase-klient som
// parameter, så browserens loadere og Vercel-funktionen web/api/forside-data.ts deler samme kode (spec
// 2026-11-24-forside-data-cache-design.md). Funktionerne her KASTER ved fejl; browserens loadere bestemmer selv, om en
// fejl skal sluges. Kun `import type` fra andre moduler, der indlæser den env-bundne klient, og kun type-importer fra
// @daa/* (testet i __tests__/edgeImporter.test.ts). Valget af biografi sker i browseren (vaelgBios.ts).
import type { SupabaseClient } from '@supabase/supabase-js';
// getAll med relativ sti, ikke gennem pakken @daa/core: Vercels Edge-bygger kan ikke slå workspace-pakkerne op
// (deploy 24/11: »referencing unsupported modules: … @daa/core«). Samme fil, stadig én kilde.
import { getAll } from '../../../../packages/core/src/getAll';
import type {
  LivsdatoAssertionRow,
  LivsdatoConclusionRow,
  LivsdatoFactRow,
  StoryKildeRow,
  StoryRow,
  StorySourceRow,
} from '@daa/feed';
import type { HaendelseRowsResult } from '../haendelser';

export type Sb = Pick<SupabaseClient, 'from' | 'rpc'>;

// ---------- fælles hjælpere ----------

const IN_CHUNK = 200;

export function chunks<T>(values: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

// Review 37 Y5: bidderne hentes 4 ad gangen, ikke én ad gangen. Målt som gæst mod prod 24/11: livsdato-kæden (25 kald)
// 4,1-4,5 s → 2,2-2,5 s, identiske rækker. Rækkefølgen bevares; første fejl afviser (som før).
const SAMTIDIGE_BIDDER = 4;

export async function fetchInChunks<T, TId>(
  ids: TId[],
  run: (idsChunk: TId[]) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const svar = await mapLimited(chunks(ids, IN_CHUNK), SAMTIDIGE_BIDDER, async (idsChunk) => {
    const { data, error } = await run(idsChunk);
    if (error) throw error;
    return data ?? [];
  });
  const out: T[] = [];
  for (const rows of svar) out.push(...rows);
  return out;
}

// Kører opgaverne med højst `limit` i gang ad gangen; resultaterne i opgavernes rækkefølge. Første fejl afviser.
export async function mapLimited<T, R>(items: readonly T[], limit: number, fn: (item: T) => PromiseLike<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

// ---------- personer ----------

// Alle person-id'er, klienten (som gæst: RLS) må se. Filen bærer listen, så browseren kan se, om filen dækker dens model.
export async function hentPersonIder(sb: Sb): Promise<number[]> {
  const rows = await getAll<{ id: number | string }>(() => sb.from('person').select('id').order('id'));
  return rows.map((r) => Number(r.id)).filter(Number.isFinite).sort((a, b) => a - b);
}

// ---------- billeder ----------

// Rå person-id'er (før kanonisering) med mindst ét billede, gæsten kan se (spec 2026-11-24-billeder-2018-20-design.md,
// trin 4). Relationerne alene er ikke nok: medie-RLS skjuler et billede, der ikke er frigivet, eller som afbilder en
// levende — derfor tæller kun relationer til medier, `media`-forespørgslen faktisk returnerer.
export async function hentPersonerMedBilledeRaa(sb: Sb): Promise<string[]> {
  const relationer = await getAll<{ subjekt_id: number | string; objekt_id: number | string }>(() =>
    sb.from('relation').select('subjekt_id,objekt_id')
      .eq('subjekt_type', 'person').eq('objekt_type', 'media').eq('rolle', 'afbildet').order('id'));
  const medieIder = [...new Set(relationer.map((r) => String(r.objekt_id)))];
  const synlige = new Set((await fetchInChunks<{ id: number | string }, string>(medieIder, (bid) =>
    sb.from('media').select('id').in('id', bid))).map((r) => String(r.id)));
  return [...new Set(relationer.filter((r) => synlige.has(String(r.objekt_id))).map((r) => String(r.subjekt_id)))];
}

// ---------- biografier ----------

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

// ---------- livsdatoer ----------

export type LivsdatoRows = {
  facts: LivsdatoFactRow[];
  conclusions: LivsdatoConclusionRow[];
  assertions: LivsdatoAssertionRow[];
};

export async function hentLivsdatoRaekker(sb: Sb): Promise<LivsdatoRows> {
  const facts = await getAll<LivsdatoFactRow>(() =>
    sb.from('fact').select('id,subjekt_id,faktatype').eq('subjekt_type', 'person')
      .in('faktatype', ['fødsel', 'død']).order('id'),
  );
  if (!facts.length) return { facts: [], conclusions: [], assertions: [] };
  const conclusions = await fetchInChunks<LivsdatoConclusionRow, string | number>(facts.map((f) => f.id), (idsChunk) =>
    sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact')
      .eq('status', 'afklaret').in('target_id', idsChunk).order('id'),
  );
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is string | number => v != null);
  if (!assertionIds.length) return { facts, conclusions, assertions: [] };
  const assertions = await fetchInChunks<LivsdatoAssertionRow, string | number>(assertionIds, (idsChunk) =>
    sb.from('assertion').select('id,date_min,date_max,date_qualifier').in('id', idsChunk).order('id'),
  );
  return { facts, conclusions, assertions };
}

// ---------- historier ----------

export type StoryRowsResult = {
  rows: StoryRow[];
  kilder: StoryKildeRow[];
  sources: StorySourceRow[];
};

export async function hentHistorieRaekker(sb: Sb): Promise<StoryRowsResult> {
  const rows = await getAll<StoryRow>(() =>
    sb.from('story')
      .select('id,subjekt_id,haendelse_id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat')
      .eq('subjekt_type', 'person')
      .eq('status', 'publiceret')
      .order('id'),
  );
  if (!rows.length) return { rows: [], kilder: [], sources: [] };
  const storyIds = [...new Set(rows.map((row) => row.id))];
  const kilder = await fetchInChunks<StoryKildeRow, string | number>(storyIds, (idsChunk) =>
    sb.from('story_kilde').select('id,story_id,source_id,side').in('story_id', idsChunk).order('id'),
  );
  const sourceIds = [...new Set(kilder.map((kilde) => kilde.source_id))];
  const sources = sourceIds.length > 0
    ? await fetchInChunks<StorySourceRow, string | number>(sourceIds, (idsChunk) =>
        sb.from('source').select('id,udgave').in('id', idsChunk).order('id'),
      )
    : [];
  return { rows, kilder, sources };
}

// ---------- nævnt-grundlag ----------

export type SubjektRow = { subjekt_id: number | string };

// Personer med MERE end et navn: embeder/godser (relation), hændelser og publicerede historier. Hændelserne gives ind
// (samme bladring som hændelseskortene), så korpusset ikke bladres to gange.
export async function hentNaevntSubjekter(
  sb: Sb,
  haendelser: HaendelseRowsResult | PromiseLike<HaendelseRowsResult>,
): Promise<SubjektRow[][]> {
  return Promise.all([
    // Embeder (organisation) og godser (estate) — samme kilde som personsidens sektioner.
    getAll<SubjektRow>(() => sb.from('relation').select('subjekt_id')
      .eq('subjekt_type', 'person').in('objekt_type', ['organisation', 'estate']).order('id')),
    Promise.resolve(haendelser).then((h): SubjektRow[] => h.rows),
    getAll<SubjektRow>(() => sb.from('story').select('subjekt_id')
      .eq('subjekt_type', 'person').eq('status', 'publiceret').order('id')),
  ]);
}
