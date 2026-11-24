// Browserens hændelses-loadere. Selve bladringen og RPC-kaldet bor i haendelser.ts (læseren); her deles en
// igangværende bladring pr. bruger, og fejl degraderer i hændelseskortene til {}, aldrig et brudt feed.
// feedGrundlag bruger samme bladring, men fail-closed.
import { buildHaendelserBy } from '@daa/feed';
import type { HaendelserBy } from '@daa/feed';
import { supabase } from '../supabase';
import { bladrHaendelser, type HaendelseRowsResult } from './haendelser';

// Feedet starter hændelseskortene og »Nævnt i Aarbogen«-grundlaget samtidig. De deler én igangværende bladring,
// så gaten ikke kører to gange over hele korpusset. Delingen er bundet til brugeren: RPC'en er i dag ens for alle
// roller, men en senere rolleforskel må aldrig kunne arves over logud/login. Ingen cache: når bladringen er
// afsluttet, henter næste kald forfra.
const igangvaerende = new Map<string, Promise<HaendelseRowsResult>>();

// Bladrer hele feedet igennem. Kaster ved enhver fejl, også efter en vellykket side: et delvist resultat må aldrig
// se ud som et helt. Narrativer og kilder, der går igen på flere sider, tages kun med én gang. Resultatet deles
// mellem samtidige kaldere for samme bruger og må ikke ændres af dem.
export async function fetchHaendelseFeed(): Promise<HaendelseRowsResult> {
  const { data } = await supabase.auth.getSession();
  const noegle = data.session?.user.id ?? 'gaest';
  let bladring = igangvaerende.get(noegle);
  if (!bladring) {
    bladring = bladrHaendelser(supabase).finally(() => { igangvaerende.delete(noegle); });
    igangvaerende.set(noegle, bladring);
  }
  return bladring;
}

export async function fetchHaendelseRows(): Promise<HaendelseRowsResult> {
  try {
    return await fetchHaendelseFeed();
  } catch (e) {
    console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades:', e);
    return { rows: [], narrativer: [], sources: [] };
  }
}

export async function loadHaendelserBy(
  canonicalIdById: Record<string, string>,
): Promise<HaendelserBy> {
  const result = await fetchHaendelseRows();
  return buildHaendelserBy(
    result.rows, result.narrativer, result.sources, canonicalIdById,
  );
}
