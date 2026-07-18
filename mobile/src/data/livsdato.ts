// Livsdato-load (fase1-design.md §6.1): tolerant klient-hentning af strukturerede
// fødsels-/dødsdatoer (fact→conclusion→assertion) til dag-præcise tidslige feed-kort
// ('på denne dag', dag-præcise jubilæer). `person.visning_foedt/doed` er RÅ DATOTEKST
// (coalesce(date_raw,vaerdi_tekst) i regen_person_visning, schema.sql) og kan derfor
// ikke bære dag-præcision — de valgte assertions' date_min hentes i stedet direkte.
// Mønster spejrer fetchParentsUnknownRows (load.ts): polymorfe koblinger kan ikke
// FK-joines i PostgREST, hentes separat og joines i @daa/feed's buildLivsdatoBy.
// Tolerant: enhver fejl et sted i kæden → tomme rækker, aldrig brud på load.
import { getAll } from '@daa/core';
import { buildLivsdatoBy } from '@daa/feed';
import type { LivsdatoAssertionRow, LivsdatoBy, LivsdatoConclusionRow, LivsdatoFactRow } from '@daa/feed';
import type { supabase } from '../lib/supabase';

// Maks antal id'er pr. .in()-kald — undgår for lange query-URL'er ved ~920 personers
// fødsels-/dødsfakta (op til ~1840 rækker, langt over den niche "forældre_ukendt"-
// mængde fetchParentsUnknownRows uden chunking håndterer i dag).
const IN_CHUNK = 200;

function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function fetchInChunks<T, TId>(
  ids: TId[],
  run: (idsChunk: TId[]) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const out: T[] = [];
  for (const idsChunk of chunkArray(ids, IN_CHUNK)) {
    const { data, error } = await run(idsChunk);
    if (error) throw error;
    out.push(...(data ?? []));
  }
  return out;
}

export type LivsdatoRows = {
  facts: LivsdatoFactRow[];
  conclusions: LivsdatoConclusionRow[];
  assertions: LivsdatoAssertionRow[];
};

export async function fetchLivsdatoRows(sb: NonNullable<typeof supabase>): Promise<LivsdatoRows> {
  const empty: LivsdatoRows = { facts: [], conclusions: [], assertions: [] };
  try {
    const facts = await getAll<LivsdatoFactRow>(() =>
      sb.from('fact').select('id,subjekt_id,faktatype').eq('subjekt_type', 'person')
        .in('faktatype', ['fødsel', 'død']).order('id'),
    );
    if (!facts.length) return empty;
    const factIds = facts.map((f) => f.id);
    const conclusions = await fetchInChunks<LivsdatoConclusionRow, string | number>(factIds, (idsChunk) =>
      sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact')
        .eq('status', 'afklaret').in('target_id', idsChunk).order('id'),
    );
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is string | number => v != null);
    if (!assertionIds.length) return { facts, conclusions, assertions: [] };
    const assertions = await fetchInChunks<LivsdatoAssertionRow, string | number>(assertionIds, (idsChunk) =>
      sb.from('assertion').select('id,date_min,date_max,date_qualifier').in('id', idsChunk).order('id'),
    );
    return { facts, conclusions, assertions };
  } catch (e) {
    console.warn('[livsdato] utilgængelig — tidslige feed-kort degraderer til års-niveau:', e);
    return empty;
  }
}

export async function loadLivsdatoBy(
  sb: NonNullable<typeof supabase>,
  canonicalIdById: Record<string, string>,
): Promise<LivsdatoBy> {
  const rows = await fetchLivsdatoRows(sb);
  return buildLivsdatoBy(rows.facts, rows.conclusions, rows.assertions, canonicalIdById);
}
