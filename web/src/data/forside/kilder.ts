// Forsidens rå hentninger, uafhængige af den env-bundne browserklient (../../supabase): de tager en Supabase-klient som
// parameter, så browserens loadere og Vercel-funktionen web/api/forside-data.ts deler samme kode (spec
// 2026-11-24-forside-data-cache-design.md). Funktionerne her KASTER ved fejl; browserens loadere bestemmer selv, om en
// fejl skal sluges. Kun `import type` fra andre moduler, der indlæser den env-bundne klient.
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  buildBioSourceVersions,
  getAll,
  mapPublicBioSourceVersionsV2,
  selectDefaultPublicBioSourceVersionV2,
} from '@daa/core';
import type {
  HaendelseNarrativRow,
  HaendelseRow,
  HaendelseSourceRow,
  LivsdatoAssertionRow,
  LivsdatoConclusionRow,
  LivsdatoFactRow,
  StoryKildeRow,
  StoryRow,
  StorySourceRow,
} from '@daa/feed';

export type Sb = Pick<SupabaseClient, 'from' | 'rpc'>;

// ---------- fælles hjælpere ----------

const IN_CHUNK = 200;

export function chunks<T>(values: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

export async function fetchInChunks<T, TId>(
  ids: TId[],
  run: (idsChunk: TId[]) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const out: T[] = [];
  for (const idsChunk of chunks(ids, IN_CHUNK)) {
    const { data, error } = await run(idsChunk);
    if (error) throw error;
    out.push(...(data ?? []));
  }
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

// ---------- biografier ----------

// Prod 2026-11-21: bio-RPC'en koster ~10 ms pr. id som gæst (loft 3 s). 200 id'er à 9 parallelt → 7/9 afbrudt;
// 50 id'er à 3 parallelt → maks 1,4 s pr. kald, ~10 s samlet. Server-side optimering følger separat.
export const FEED_BIO_IN_CHUNK = 50;
export const FEED_BIO_PARALLEL = 3;

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

export type BioRaekker = { kontrakt: number; rows: unknown[]; fejlede: number[] };

export async function hentBioKontrakt(sb: Sb): Promise<number> {
  const version = await sb.rpc('narrative_record_contract_version', {});
  if (version.error || typeof version.data !== 'number' || !Number.isInteger(version.data)) {
    throw new Error('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
  }
  return version.data;
}

type BioSvar = { data: unknown; error: unknown };

// Én bid: ét forsøg; fejler det, prøves bidden igen som to halvdele (tiden voksede med antallet af id'er, #421).
// Returnerer rækkerne og de id'er, der stadig fejlede.
async function hentBid(sb: Sb, rpcName: string, ids: number[]): Promise<{ rows: unknown[]; fejlede: number[] }> {
  const kald = (del: number[]) => sb.rpc(rpcName, { p_person_ids: del }) as unknown as PromiseLike<BioSvar>;
  const foerste = await kald(ids);
  if (!foerste.error) {
    if (!Array.isArray(foerste.data)) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    return { rows: foerste.data, fejlede: [] };
  }
  const midt = Math.ceil(ids.length / 2);
  const rows: unknown[] = [];
  const fejlede: number[] = [];
  for (const del of [ids.slice(0, midt), ids.slice(midt)]) {
    if (!del.length) continue;
    const svar = await kald(del);
    if (svar.error) { fejlede.push(...del); continue; }
    if (!Array.isArray(svar.data)) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    rows.push(...svar.data);
  }
  return { rows, fejlede };
}

// Biografiversioner for person-id'erne i bidder. En bid, der bliver ved med at fejle, koster kun sine egne id'er
// (`fejlede`); fejler alle, kastes der.
export async function hentBioRaekker(sb: Sb, kontrakt: number, personIds: number[]): Promise<BioRaekker> {
  if (!personIds.length) return { kontrakt, rows: [], fejlede: [] };
  const rpcName = kontrakt >= 2 ? 'public_person_bio_source_versions_v2' : 'public_person_bio_source_versions';
  // I bidder med begrænset parallelitet: alle id'er i ét kald ramte gæsternes 3 s-loft i prod (1.725 id'er → 57014).
  const svar = await mapLimited(chunks(personIds, FEED_BIO_IN_CHUNK), FEED_BIO_PARALLEL, (ids) => hentBid(sb, rpcName, ids));
  const fejlede = svar.flatMap((r) => r.fejlede);
  if (fejlede.length === personIds.length) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
  return { kontrakt, rows: svar.flatMap((r) => r.rows), fejlede };
}

function mapV1Text(row: unknown): string | null {
  if (typeof row !== 'object' || row === null) return null;
  const value = row as Record<string, unknown>;
  if ((value.provenance_kind !== 'source_record' && value.provenance_kind !== 'legacy_narrative')
    || (value.record_ref !== null && typeof value.record_ref !== 'string')
    || typeof value.source_label !== 'string' || typeof value.record_label !== 'string'
    || typeof value.narrative_text !== 'string' || typeof value.citation_label !== 'string') return null;
  return buildBioSourceVersions([{
    record_ref: value.record_ref,
    source_label: value.source_label,
    record_label: value.record_label,
    narrative_text: value.narrative_text,
    citation_label: value.citation_label,
    provenance_kind: value.provenance_kind,
  }])[0]?.narrativeText ?? null;
}

// Den foretrukne offentlige tekst pr. kanonisk person. Rækkerne samles FØR valget, så aliaser i forskellige bidder giver
// ét valg pr. kanonisk person. En sammenfoldet person, hvis alias lå i en fejlet bid, får ingen tekst frem for en forkert.
export function vaelgFeedBios(r: BioRaekker, canonicalIdById: Record<string, string>): Record<string, string> {
  const kanon = (id: number | string) => canonicalIdById[String(id)] ?? String(id);
  const udelad = new Set(r.fejlede.map(kanon));
  const bioBy: Record<string, string> = {};
  if (r.kontrakt >= 2) {
    const versionsByCanonicalPerson = new Map<string, unknown[]>();
    for (const row of r.rows) {
      if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') {
        throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_person_id');
      }
      const canonicalId = kanon((row as Record<string, number>).person_id);
      const rows = versionsByCanonicalPerson.get(canonicalId);
      if (rows) rows.push(row); else versionsByCanonicalPerson.set(canonicalId, [row]);
    }
    for (const [canonicalId, rows] of versionsByCanonicalPerson) {
      if (udelad.has(canonicalId)) continue;
      const selected = selectDefaultPublicBioSourceVersionV2(mapPublicBioSourceVersionsV2(rows));
      if (selected) bioBy[canonicalId] = selected.narrativeText;
    }
  } else {
    for (const row of r.rows) {
      if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') continue;
      const text = mapV1Text(row);
      if (text) {
        const canonicalId = kanon((row as Record<string, number>).person_id);
        if (!udelad.has(canonicalId)) bioBy[canonicalId] ??= text;
      }
    }
  }
  return bioBy;
}

// ---------- hændelser ----------

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
