// Skilsmisser (spec 2026-11-27 »Skilsmisse«): `fact` på family (= skilt) → afklaret `conclusion` → valgt `assertion` (datoer).
// FAIL-CLOSED: en fejl giver null (= ukendt), aldrig {} (= ingen skilsmisser) — ukendt må ikke vises som »gift«.
import { byggSkilsmisser, getAll, type Skilsmisser } from '@daa/core';
import { supabase } from '../supabase';

type Id = number | string;

export async function fetchSkilsmisser(): Promise<Skilsmisser | null> {
  try {
    const facts = await getAll<{ id: Id; subjekt_id: Id }>(() =>
      supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'family').eq('faktatype', 'skilsmisse').order('id'));
    if (!facts.length) return {};
    // Hvert fakta er en skilsmisse (fail-closed); konklusion og påstand giver kun datoen. Kun afklarede konklusioner
    // hentes (status vælges også, så kernen kan afvise andre), og mangler de eller påstanden, er datoen blot ukendt.
    const conclusions = await getAll<{ target_id: Id; valgt_assertion_id: Id | null; status: string | null }>(() =>
      supabase.from('conclusion').select('target_id,valgt_assertion_id,status').eq('target_type', 'fact').eq('status', 'afklaret')
        .in('target_id', facts.map((f) => f.id)).order('id'));
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is Id => v != null);
    const assertions = assertionIds.length
      ? await getAll<{ id: Id; date_min: string | null; date_max: string | null }>(() =>
        supabase.from('assertion').select('id,date_min,date_max').in('id', assertionIds).order('id'))
      : [];
    return byggSkilsmisser(facts, conclusions, assertions);
  } catch (e) {
    console.warn('[loadModel] skilsmisser utilgængelige — ukendt (fail-closed):', e);
    return null;
  }
}
