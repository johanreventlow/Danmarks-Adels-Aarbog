// Vielsesdatoer til »⚭« ved ægtefællen på personskærmen (paritetsplanens batch 6) — mobilens pendant til web's
// web/src/data/vielser.ts: fact (familie, vielse) → conclusion (valgt påstand) → assertion (date_min/date_max).
// Gæster må læse de tre tabeller (RLS), så der kræves ingen RPC. Sammenstillingen er delt (vielsesDatoerPrFamilie i
// @daa/core); hentningen er mobilens egen og deler hver id-liste i bidder à højst 200 (gæsteloftet 3 s pr. kald).
// Tolerant: enhver fejl, eller ingen klient, giver {} — så står der bare ingen ⚭, og familien er stadig korrekt.
import { familieIderForPerson, getAll, vielsePraecision, vielsesDatoerPrFamilie, type ModelIndexes } from '@daa/core';
import type { supabase } from '../lib/supabase';
import { chunks } from './bidder';

type Id = number | string;
type FactRow = { id: Id; subjekt_id: Id };
type KonklRow = { target_id: Id; valgt_assertion_id: Id | null };
type AssertionRow = { id: Id; date_min: string | null; date_max: string | null; date_qualifier?: string | null; date_raw?: string | null };

export const VIELSE_BID = 200;

export async function hentVielsesDatoer(sb: NonNullable<typeof supabase> | null, familyIds: string[]): Promise<Record<string, string>> {
  if (!sb || !familyIds.length) return {};
  try {
    const facts: FactRow[] = [];
    for (const bid of chunks([...new Set(familyIds)], VIELSE_BID)) {
      facts.push(...await getAll<FactRow>(() =>
        sb.from('fact').select('id,subjekt_id').eq('subjekt_type', 'family').eq('faktatype', 'vielse')
          .in('subjekt_id', bid).order('id')));
    }
    if (!facts.length) return {};
    const konkl: KonklRow[] = [];
    for (const bid of chunks(facts.map((f) => f.id), VIELSE_BID)) {
      konkl.push(...await getAll<KonklRow>(() =>
        sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact')
          .in('status', ['afklaret', 'omstridt']).in('target_id', bid).order('id')));
    }
    const assertionIds = [...new Set(konkl.map((c) => c.valgt_assertion_id).filter((v): v is Id => v != null))];
    if (!assertionIds.length) return {};
    const assertions: AssertionRow[] = [];
    for (const bid of chunks(assertionIds, VIELSE_BID)) {
      assertions.push(...await getAll<AssertionRow>(() =>
        sb.from('assertion').select('id,date_min,date_max,date_qualifier,date_raw').in('id', bid).order('id')));
    }
    return vielsesDatoerPrFamilie(facts, konkl, assertions);
  } catch {
    return {};
  }
}

// Personens ægteskabsfamilier (family-id'er) til hentningen ovenfor, sorteret, så nøglen er stabil.
export function vielsesFamilier(indexes: ModelIndexes, personId: string): string[] {
  return [...new Set(familieIderForPerson(indexes, personId).aegteskaber.map((a) => a.familyId))].sort();
}

// Vielsesdato pr. ægtefælle (person-id) — som web's PersonSide: står parret i flere familier (sammenfoldet på tværs
// af udgaver), vinder den mest præcise dato. Ægteskaber uden ægtefælle-id får ingen ⚭.
export function vielseForAegtefaeller(indexes: ModelIndexes, personId: string, byFam: Record<string, string>): Record<string, string> {
  const ud: Record<string, string> = {};
  for (const a of familieIderForPerson(indexes, personId).aegteskaber) {
    const t = byFam[a.familyId];
    if (a.spouseId && t && vielsePraecision(t) > vielsePraecision(ud[a.spouseId] ?? '')) ud[a.spouseId] = t;
  }
  return ud;
}
