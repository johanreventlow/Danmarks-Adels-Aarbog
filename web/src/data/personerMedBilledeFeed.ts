// Browserens direkte hentning af personer med billede (spor 2). En fejl giver null: forsiden udelader billed-reglen i
// stedet for at vente eller vælte.
import { supabase } from '../supabase';
import { hentPersonerMedBilledeRaa } from './forside/kilder';
import { buildPersonerMedBillede } from './personerMedBillede';

export async function hentPersonerMedBillede(canon: Record<string, string>): Promise<ReadonlySet<string> | null> {
  try {
    return buildPersonerMedBillede(await hentPersonerMedBilledeRaa(supabase), canon);
  } catch (e) {
    console.warn('[feed] personer med billede fejlede — billed-reglen udelades:', e);
    return null;
  }
}
