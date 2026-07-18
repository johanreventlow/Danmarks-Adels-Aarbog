// Web-adapter til feed-motoren (fase1-design.md §7.2-§7.3). buildWebFeedAux mapper
// webbens allerede-hentede estates/arms til FeedAux. Web indlæser IKKE bio pr. person ved
// cold-start (model.ts sætter bio:'') — fetchFeedBios/withFeedBios henter og stempler bio
// ind i en KOPI af modellen ved feed-mount, uden at røre den originale model.
import { getAll, pickPreferredBio, type NarrativeCand } from '@daa/core';
import { supabase } from '../supabase';
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

type RawNarrativeRow = { id: number; subjekt_id: number | string; tekst: string | null; source_id: number | null; privat: boolean | null };
type RawSourceRow = { id: number; slags: string | null; udgave: string | null; aar: number | null };

// Hent den foretrukne offentlige bio pr. (kanonisk) person, ét pagineret tolerant kald.
// Samme udvælgelsesregel som mobile/web's model-load (pickPreferredBio: nyeste udgave
// vinder) — genbruges her fordi webbens PUBLIKUMS-model bevidst IKKE indlæser bio ved
// cold-start (§7.3).
export async function fetchFeedBios(canonicalIdById: Record<string, string>): Promise<Record<string, string>> {
  try {
    const [narratives, sources] = await Promise.all([
      getAll<RawNarrativeRow>(() =>
        supabase.from('narrative').select('id,subjekt_id,tekst,source_id,privat').eq('subjekt_type', 'person'),
      ),
      getAll<RawSourceRow>(() => supabase.from('source').select('id,slags,udgave,aar')),
    ]);
    const srcById = new Map(sources.map((s) => [s.id, s]));
    const candsBy: Record<string, NarrativeCand[]> = {};
    for (const n of narratives) {
      if (n.privat) continue;
      const pid = canonicalIdById[String(n.subjekt_id)] ?? String(n.subjekt_id);
      const src = n.source_id != null ? srcById.get(n.source_id) : undefined;
      (candsBy[pid] ??= []).push({
        narrativeId: n.id, tekst: n.tekst, sourceId: n.source_id ?? null,
        slags: src?.slags ?? null, aar: src?.aar ?? null, udgave: src?.udgave ?? null,
      });
    }
    const bioBy: Record<string, string> = {};
    for (const [pid, cands] of Object.entries(candsBy)) {
      const best = pickPreferredBio(cands);
      if (best?.tekst) bioBy[pid] = best.tekst;
    }
    return bioBy;
  } catch (e) {
    console.warn('[feedAux] bio-hentning utilgængelig — feed kører uden portræt/citat-kort:', e);
    return {};
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
