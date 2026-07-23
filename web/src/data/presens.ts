// Præsensliste-grundlag: levende-flag + overhoved-fakta. RLS afgør hvad klienten ser —
// anon/medlem får ingen levende rækker (fail-closed), redaktør-JWT ser alt. Visningen
// tilføjer altså ingen eksponering (spec 2026-07-22 §8).
import { supabase } from '../supabase';
import { getAll, parseOverhovedVaerdi } from '@daa/core';
import type { PresensAnker } from '@daa/core';

export type PresensGrundlag = { ankre: PresensAnker[]; levendeById: Record<string, boolean> };

type RawLevende = { id: number | string; levende: boolean | null };
type RawOverhovedFact = { id: number | string; subjekt_id: number | string };
type RawKonkl = { target_id: number | string; valgt_assertion_id: number | string | null };
type RawAssert = { id: number | string; vaerdi_tekst: string | null };

export function mapPresensGrundlag(
  persons: RawLevende[],
  facts: RawOverhovedFact[],
  conclusions: RawKonkl[],
  assertions: RawAssert[],
): PresensGrundlag {
  const levendeById: Record<string, boolean> = {};
  for (const p of persons) levendeById[String(p.id)] = p.levende === true;
  const assertById = new Map(assertions.map((a) => [String(a.id), a.vaerdi_tekst]));
  const valgtByFact = new Map(conclusions.map((c) => [String(c.target_id), c.valgt_assertion_id]));
  const ankre: PresensAnker[] = [];
  for (const f of facts) {
    const valgt = valgtByFact.get(String(f.id));
    if (valgt == null) continue; // ingen afklaret konklusion → intet anker
    const vaerdi = assertById.get(String(valgt));
    if (vaerdi == null) continue;
    const anker = parseOverhovedVaerdi(String(f.subjekt_id), vaerdi);
    if (anker) ankre.push(anker); // uparsebar værdi droppes fail-closed
  }
  return { ankre, levendeById };
}

export async function fetchPresensGrundlag(): Promise<PresensGrundlag> {
  const persons = await getAll<RawLevende>(() => supabase.from('person').select('id,levende'));
  const facts = await getAll<RawOverhovedFact>(() =>
    supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'overhoved').order('id'));
  if (!facts.length) return mapPresensGrundlag(persons, [], [], []);
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
  const assertions = assertionIds.length
    ? await getAll<RawAssert>(() => supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'))
    : [];
  return mapPresensGrundlag(persons, facts, conclusions, assertions);
}
