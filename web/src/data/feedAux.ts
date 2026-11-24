// Web-adapter til feed-motoren (fase1-design.md §7.2-§7.3). buildWebFeedAux mapper
// webbens allerede-hentede estates/arms til FeedAux. Web indlæser IKKE bio pr. person ved
// cold-start (model.ts sætter bio:'') — hentFeedBios/withFeedBios henter og stempler bio
// ind i en KOPI af modellen ved feed-mount, uden at røre den originale model.
import { supabase } from '../supabase';
import { buildFeedBioSubjectIds, hentBioKontrakt, hentBioRaekker } from './forside/kilder';
import { vaelgFeedBios } from './forside/vaelgBios';
import type { ArmsItem, EstateItem } from './public';
import type { FeedAux } from '@daa/feed';
import type { Model, ModelPerson } from './types';

export function buildWebFeedAux(estates: EstateItem[] | null, arms: ArmsItem[] | null): FeedAux {
  return {
    godsListe: (estates ?? []).map((e) => ({ id: e.id, navn: e.navn, slags: e.slags, ownerCount: e.ownerCount })),
    vaabenListe: (arms ?? []).map((a) => ({ id: a.id, blasonering: a.blasonering, note: a.note })),
    // Web-publikum indlæser ikke embeder pr. person (kun mobilens Aux gør) — bevidst
    // udeladelse i fase 1-MVP'en; embede-kort kommer gratis når fase 2 alligevel rører
    // webbens load. Ingen crash: tomt map ⇒ buildEmbeder giver blot ingen kort.
    officesBy: {},
  };
}

export { FEED_BIO_IN_CHUNK, FEED_BIO_PARALLEL, buildFeedBioSubjectIds } from './forside/kilder';

// Biografierne til feedet og om de er hentet komplet. `komplet: false` betyder, at mindst én bid blev ved med at
// ramme gæsternes 3 s-loft (prod 24/11: 7 af 456 bid-kald); de andre bidders biografier er med. Et ufuldstændigt
// resultat må aldrig bruges som bevis for, at en person IKKE har tekst (»Nævnt i Aarbogen«-kortene).
export type FeedBios = { bioBy: Record<string, string>; komplet: boolean };

// Hent den foretrukne offentlige eventtekst pr. (kanonisk) person.  Contract
// v2 is the only post-cutover reader; it never falls back to public.narrative.
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
    if (raekker.fejlede.length) console.warn(`[feedAux] ${raekker.fejlede.length} bio-id'er kunne ikke hentes — feedet viser resten`);
    return { bioBy, komplet: raekker.fejlede.length === 0 };
  } catch (e) {
    console.warn('[feedAux] bio-hentning fejlede:', e);
    if (contractVersion !== null && contractVersion < 2) return { bioBy: {}, komplet: false };
    throw e;
  }
}

// Ren kopi: stempler bio ind i en NY persons-liste/byId — den originale model (og dens
// øvrige lag: indexes, lineage, geo osv.) røres ikke. Personer uden en post i bioBy
// beholder deres eksisterende (typisk tomme) bio.
export function withFeedBios(model: Model, bioBy: Record<string, string>): Model {
  const persons: ModelPerson[] = model.persons.map((p) =>
    bioBy[p.id] ? { ...p, bio: bioBy[p.id] } : p,
  );
  const byId: Record<string, ModelPerson> = {};
  for (const p of persons) byId[p.id] = p;
  return { ...model, persons, byId };
}
