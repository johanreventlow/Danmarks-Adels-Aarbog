// Vielsesdatoer til »Gift med« på personsiden: fact (familie, vielse) → conclusion (valgt påstand) → assertion
// (date_min/date_max). Gæster må læse de tre tabeller (RLS), så der kræves ingen ny RPC. Nøglen er family-id'et
// fra familieIderForPerson; værdien er færdig tekst fra fmtVielse. Familier uden brugbar dato udelades.
// Enhver fejl giver {}: siden viser så bare ingen ⚭, og familien er stadig korrekt.
import { fmtVielse, getAll } from '@daa/core';
import { supabase } from '../supabase';

type Id = number | string;

export async function hentVielsesDatoer(familyIds: string[]): Promise<Record<string, string>> {
  if (!familyIds.length) return {};
  try {
    const facts = await getAll<{ id: Id; subjekt_id: Id }>(() =>
      supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'family').eq('faktatype', 'vielse')
        .in('subjekt_id', familyIds).order('id'));
    if (!facts.length) return {};
    const konkl = await getAll<{ target_id: Id; valgt_assertion_id: Id | null }>(() =>
      supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact')
        .in('status', ['afklaret', 'omstridt']).in('target_id', facts.map((f) => f.id)).order('id'));
    const assertionIds = konkl.map((c) => c.valgt_assertion_id).filter((v): v is Id => v != null);
    if (!assertionIds.length) return {};
    const assertions = await getAll<{ id: Id; date_min: string | null; date_max: string | null }>(() =>
      supabase.from('assertion').select('id,date_min,date_max').in('id', assertionIds).order('id'));
    const tekstByAssertion = new Map(assertions.map((a) => [String(a.id), fmtVielse(a.date_min, a.date_max)]));
    const familieByFact = new Map(facts.map((f) => [String(f.id), String(f.subjekt_id)]));
    const ud: Record<string, string> = {};
    for (const c of konkl) {
      const fam = familieByFact.get(String(c.target_id));
      const tekst = c.valgt_assertion_id == null ? '' : tekstByAssertion.get(String(c.valgt_assertion_id)) ?? '';
      if (fam && tekst && !ud[fam]) ud[fam] = tekst;
    }
    return ud;
  } catch {
    return {};
  }
}
