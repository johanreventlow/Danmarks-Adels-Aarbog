// Skilsmisser (spec 2026-11-27 »Skilsmisse«): `fact` på family → afklaret `conclusion` → valgt `assertion` (datoer).
// FAIL-CLOSED: en fejl giver null (= ukendt), aldrig {} (= ingen skilsmisser) — ukendt må ikke vises som »gift«.
import { byggSkilsmisser, getAll, type Skilsmisser } from '@daa/core';
import { supabase } from '../supabase';

type Id = number | string;

export async function fetchSkilsmisser(): Promise<Skilsmisser | null> {
  try {
    const facts = await getAll<{ id: Id; subjekt_id: Id }>(() =>
      supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'family').eq('faktatype', 'skilsmisse').order('id'));
    if (!facts.length) return {};
    const conclusions = await getAll<{ target_id: Id; valgt_assertion_id: Id | null }>(() =>
      supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret')
        .in('target_id', facts.map((f) => f.id)).order('id'));
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is Id => v != null);
    if (!assertionIds.length) return {};
    const assertions = await getAll<{ id: Id; date_min: string | null; date_max: string | null }>(() =>
      supabase.from('assertion').select('id,date_min,date_max').in('id', assertionIds).order('id'));
    return byggSkilsmisser(facts, conclusions, assertions);
  } catch (e) {
    console.warn('[loadModel] skilsmisser utilgængelige — ukendt (fail-closed):', e);
    return null;
  }
}
