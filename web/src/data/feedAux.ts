// Web-adapter til feed-motoren (fase1-design.md §7.2-§7.3) og feedets biografi-læser. buildWebFeedAux mapper
// webbens allerede-hentede estates/arms til FeedAux. Web indlæser IKKE bio pr. person ved cold-start (model.ts sætter
// bio:''); feedBios.ts henter biografierne ved feed-mount, og withFeedBios stempler dem ind i en KOPI af modellen.
//
// Filen står på cutover-kontraktens frosne liste over narrativ-læsere (schema.sql, »classified_direct_readers«;
// R-postverify sammenligner listen med checkoutet). Bio-RPC-kaldene skal derfor blive HER. Filen køres også af
// Vercel-funktionen web/api/forside-data.ts (Edge) og må derfor hverken importere den env-bundne klient (../supabase)
// eller værdier fra @daa/* (testet i forside/__tests__/edgeImporter.test.ts).
import type { FeedAux } from '@daa/feed';
import { chunks, mapLimited, type Sb } from './forside/kilder';
import type { ArmsItem, EstateItem } from './public';
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

export { buildFeedBioSubjectIds } from './forside/kilder';

// Prod 2026-11-21: bio-RPC'en koster ~10 ms pr. id som gæst (loft 3 s). 200 id'er à 9 parallelt → 7/9 afbrudt;
// 50 id'er à 3 parallelt → maks 1,4 s pr. kald, ~10 s samlet. Server-side optimering følger separat.
export const FEED_BIO_IN_CHUNK = 50;
export const FEED_BIO_PARALLEL = 3;

// Biografierne til feedet og om de er hentet komplet. `komplet: false` betyder, at mindst én bid blev ved med at
// ramme gæsternes 3 s-loft (prod 24/11: 7 af 456 bid-kald); de andre bidders biografier er med. Et ufuldstændigt
// resultat må aldrig bruges som bevis for, at en person IKKE har tekst (»Nævnt i Aarbogen«-kortene).
export type FeedBios = { bioBy: Record<string, string>; komplet: boolean };

export type BioRaekker = { kontrakt: number; rows: unknown[]; fejlede: number[] };

export async function hentBioKontrakt(sb: Sb): Promise<number> {
  const version = await sb.rpc('narrative_record_contract_version', {});
  if (version.error || typeof version.data !== 'number' || !Number.isInteger(version.data)) {
    throw new Error('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
  }
  return version.data;
}

type BioSvar = { data: unknown; error: unknown };

// Én bid: ét forsøg; fejler det, prøves bidden igen som to halvdele (tiden voksede med antallet af id'er, #421).
// Returnerer rækkerne og de id'er, der stadig fejlede.
async function hentBid(sb: Sb, rpcName: string, ids: number[]): Promise<{ rows: unknown[]; fejlede: number[] }> {
  const kald = (del: number[]) => sb.rpc(rpcName, { p_person_ids: del }) as unknown as PromiseLike<BioSvar>;
  const foerste = await kald(ids);
  if (!foerste.error) {
    if (!Array.isArray(foerste.data)) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    return { rows: foerste.data, fejlede: [] };
  }
  const midt = Math.ceil(ids.length / 2);
  const rows: unknown[] = [];
  const fejlede: number[] = [];
  for (const del of [ids.slice(0, midt), ids.slice(midt)]) {
    if (!del.length) continue;
    const svar = await kald(del);
    if (svar.error) { fejlede.push(...del); continue; }
    if (!Array.isArray(svar.data)) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    rows.push(...svar.data);
  }
  return { rows, fejlede };
}

// Biografiversioner for person-id'erne i bidder. En bid, der bliver ved med at fejle, koster kun sine egne id'er
// (`fejlede`); fejler alle, kastes der.
export async function hentBioRaekker(sb: Sb, kontrakt: number, personIds: number[]): Promise<BioRaekker> {
  if (!personIds.length) return { kontrakt, rows: [], fejlede: [] };
  const rpcName = kontrakt >= 2 ? 'public_person_bio_source_versions_v2' : 'public_person_bio_source_versions';
  // I bidder med begrænset parallelitet: alle id'er i ét kald ramte gæsternes 3 s-loft i prod (1.725 id'er → 57014).
  const svar = await mapLimited(chunks(personIds, FEED_BIO_IN_CHUNK), FEED_BIO_PARALLEL, (ids) => hentBid(sb, rpcName, ids));
  const fejlede = svar.flatMap((r) => r.fejlede);
  if (fejlede.length === personIds.length) throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
  return { kontrakt, rows: svar.flatMap((r) => r.rows), fejlede };
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
