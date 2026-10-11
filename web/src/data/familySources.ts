// Trin 5b 2a: kilder på ægteskab/forældrelinje. Fejl (fx funktionen findes ikke endnu i prod) giver
// en tom liste — panelet må aldrig brydes af en manglende kildelinje (spec §5.2).
import { bigintTekst, mapFamilieKilder, type FamilieKilde } from '@daa/core';
import { supabase } from '../supabase';

export async function fetchFamilySources(familyIds: string[]): Promise<FamilieKilde[]> {
  // Decimalstrenge hele vejen; PostgREST caster dem til bigint[] (spec §5.2).
  const ids = [...new Set(familyIds.filter((id) => bigintTekst(id) !== null))];
  if (!ids.length) return [];
  try {
    const client = supabase as unknown as { rpc: (n: string, a: unknown) => Promise<{ data: unknown; error: unknown }> };
    const res = await client.rpc('public_family_sources', { p_family_ids: ids });
    return res.error ? [] : mapFamilieKilder(res.data);
  } catch {
    return [];
  }
}
