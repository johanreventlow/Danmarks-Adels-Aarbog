// Besiddelseslisten (mobil-paritet, bid 9) — samme regler som web's EstatesView/Folgesvend: alle slægtens godser,
// også dem uden registrerede ejere; ejertallet er antal forskellige personer læseren kan se (antalEjere i @daa/core:
// kanoniske id'er, ejere uden for modellen tælles ikke). Flest ejere først, derefter navn.
import { antalEjere, compareDanish, type EjerRelation, type Model } from '@daa/core';
import type { supabase } from '../lib/supabase';
import type { EstateListEntry, OwnerRef } from './types';
import { hentGodsNarrativ } from './about';

export function besiddelserVist(liste: readonly EstateListEntry[], model: Model | null): EstateListEntry[] {
  return liste
    .map((e) => (model ? { ...e, ownerCount: antalEjere(e.ejerIds, model) } : e))
    .sort((a, b) => b.ownerCount - a.ownerCount || compareDanish(a.navn, b.navn));
}

// Kortets undertekst, ordret som web's liste.
export function ejerTekst(n: number): string {
  return n ? `${n} ${n === 1 ? 'ejer' : 'ejere'} i Aarbogen` : 'Ingen ejere registreret';
}

// Ejer-relationerne til ejerrækken (byggEjerraekke i @daa/core): kanonisk person-id + bogens periodetekst urørt.
export function ejerRelationer(owners: readonly OwnerRef[]): EjerRelation[] {
  return owners.map((o) => ({ personId: o.personId, periode: o.periodeRaw }));
}

export type BesiddelseInfo = { narrativ: string; sted: string };

// Gods-detaljens historie (første offentlige narrativ) og beliggenhed (place.navn) — samme forespørgsler som web's
// fetchEstateInfo, men hentet pr. skærm og KASTENDE: en fejlet hentning skal vises som fejl, ikke som »ingen historie«.
// sted_id kommer fra opstartens estate-rækker (aux.estateById), så estate-tabellen ikke læses igen. Billederne slås op
// i aux.mediaByObjekt (allerede hentet). Uden klient (offline-seed): intet at vise.
export async function hentBesiddelseInfo(
  sb: NonNullable<typeof supabase> | null,
  estateId: string,
  stedId: string | null,
): Promise<BesiddelseInfo> {
  if (!sb) return { narrativ: '', sted: '' };
  const [narr, pl] = await Promise.all([
    hentGodsNarrativ(sb, estateId),
    stedId ? sb.from('place').select('navn').eq('id', Number(stedId)).maybeSingle() : Promise.resolve({ data: null, error: null }),
  ]);
  if (narr.error) throw new Error(narr.error.message);
  if (pl.error) throw new Error(pl.error.message);
  const narrativ = ((narr.data ?? [])[0] as { tekst: string | null } | undefined)?.tekst ?? '';
  const sted = (pl.data as { navn: string | null } | null)?.navn ?? '';
  return { narrativ, sted };
}
