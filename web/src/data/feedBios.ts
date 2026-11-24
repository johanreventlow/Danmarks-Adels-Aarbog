// Feedets biografier i browseren: henter rækkerne gennem feedAux.ts (læseren) med browserens klient og vælger én tekst
// pr. kanonisk person. Contract v2 is the only post-cutover reader; it never falls back to the legacy table.
import { supabase } from '../supabase';
import { buildFeedBioSubjectIds, hentBioKontrakt, hentBioRaekker, type FeedBios } from './feedAux';
import { vaelgFeedBios } from './forside/vaelgBios';

// Hent den foretrukne offentlige eventtekst pr. (kanonisk) person.
// En bid, der bliver ved med at fejle, koster kun sine egne personer; fejler alle, er det en hente-fejl.
export async function hentFeedBios(
  canonicalIdById: Record<string, string>,
  modelPersonIds?: readonly string[],
): Promise<FeedBios> {
  let contractVersion: number | null = null;
  try {
    const subjectIds = buildFeedBioSubjectIds(canonicalIdById, modelPersonIds ?? []);
    if (!subjectIds.length) return { bioBy: {}, komplet: true };
    const personIds = subjectIds.map(Number).filter(Number.isFinite);
    contractVersion = await hentBioKontrakt(supabase);
    const raekker = await hentBioRaekker(supabase, contractVersion, personIds);
    const bioBy = vaelgFeedBios(raekker, canonicalIdById);
    if (raekker.fejlede.length) console.warn(`[feedBios] ${raekker.fejlede.length} bio-id'er kunne ikke hentes — feedet viser resten`);
    return { bioBy, komplet: raekker.fejlede.length === 0 };
  } catch (e) {
    console.warn('[feedBios] bio-hentning fejlede:', e);
    if (contractVersion !== null && contractVersion < 2) return { bioBy: {}, komplet: false };
    throw e;
  }
}
