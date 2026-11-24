// Livsdato-load (fase1-design.md §6.1, §7.3) — web-udgaven af mobile/src/data/livsdato.ts.
// `person.visning_foedt/doed` er RÅ DATOTEKST (coalesce(date_raw,vaerdi_tekst) i
// regen_person_visning, schema.sql) og kan derfor ikke bære dag-præcision — de valgte
// assertions' date_min hentes i stedet direkte. Polymorfe koblinger (fact→conclusion→
// assertion) kan ikke FK-joines i PostgREST, hentes separat og joines i @daa/feed's
// buildLivsdatoBy. Tolerant: enhver fejl et sted i kæden → tomme rækker, aldrig kast.
import { buildLivsdatoBy } from '@daa/feed';
import type { LivsdatoBy } from '@daa/feed';
import { supabase } from '../supabase';
import { hentLivsdatoRaekker, type LivsdatoRows } from './forside/kilder';

export type { LivsdatoRows } from './forside/kilder';

// Tolerant: en fejl giver tomme rækker (tidslige feed-kort degraderer til års-niveau).
export async function fetchLivsdatoRows(): Promise<LivsdatoRows> {
  try {
    return await hentLivsdatoRaekker(supabase);
  } catch (e) {
    console.warn('[livsdato] utilgængelig — tidslige feed-kort degraderer til års-niveau:', e);
    return { facts: [], conclusions: [], assertions: [] };
  }
}

export async function loadLivsdatoBy(canonicalIdById: Record<string, string>): Promise<LivsdatoBy> {
  const rows = await fetchLivsdatoRows();
  return buildLivsdatoBy(rows.facts, rows.conclusions, rows.assertions, canonicalIdById);
}
