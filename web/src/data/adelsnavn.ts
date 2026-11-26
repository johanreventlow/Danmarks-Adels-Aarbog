// Linjernes adelsnavn (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md): `fact` på lineage →
// afklaret `conclusion` → valgt `assertion`. Anon læser fakta på linjer (entitet_offentlig). Tolerant: fejl eller
// manglende data giver ingen regler, og personsiden vises da som før (uden »I Aarbogen«).
import { byggLinjeAdelsnavne, getAll, type LinjeAdelsnavne } from '@daa/core';
import { supabase } from '../supabase';

type Id = number | string;

export async function fetchLinjeAdelsnavne(): Promise<LinjeAdelsnavne> {
  try {
    const facts = await getAll<{ id: Id; subjekt_id: Id }>(() =>
      supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'lineage').eq('faktatype', 'adelsnavn').order('id'));
    if (!facts.length) return {};
    const conclusions = await getAll<{ target_id: Id; valgt_assertion_id: Id | null }>(() =>
      supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret')
        .in('target_id', facts.map((f) => f.id)).order('id'));
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is Id => v != null);
    if (!assertionIds.length) return {};
    const assertions = await getAll<{ id: Id; vaerdi_tekst: string | null }>(() =>
      supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'));
    return byggLinjeAdelsnavne(facts, conclusions, assertions);
  } catch (e) {
    console.warn('[loadModel] linjernes adelsnavn utilgængelige — ingen formel navneform:', e);
    return {};
  }
}
