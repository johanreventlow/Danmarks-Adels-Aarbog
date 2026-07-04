// Medie-læsning (mediehåndtering Slice 0). Delt af person-portræt/-galleri + objekt-billeder
// (gods/våben). RLS på 'media' + storage.objects skjuler ikke-offentlige rækker/objekter, så en
// almindelig select/signering returnerer kun det den aktuelle rolle må se (fail-closed i basen).
import { supabase } from '../supabase';
import { getAll } from './paginate';

export type MediaItem = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  url: string | null; // kortlivet signed URL (null hvis signering fejlede/ikke offentlig)
};

type RawMediaRow = {
  id: number; slags: string | null; titel: string | null;
  kunstner: string | null; datering: string | null; storage_path: string | null;
};

// Portræt-egnede slags (til at vælge hovedbilledet på et personkort).
export const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);

const SIGN_TTL = 600; // sek. — dækker en detalje-visnings-session; fornys ved næste fetch.

// Mint signed URLs for en batch stier i ét kald; returnér path→url. Tolerant (fejl → udeladt).
async function signPaths(paths: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const uniq = [...new Set(paths.filter(Boolean))];
  if (!uniq.length) return out;
  try {
    const { data, error } = await supabase.storage.from('media').createSignedUrls(uniq, SIGN_TTL);
    if (error) { console.warn('[media] signering fejlede:', error); return out; }
    for (const row of data ?? []) {
      if (row.signedUrl && row.path) out.set(row.path, row.signedUrl);
    }
  } catch (e) {
    console.warn('[media] signering kastede:', e);
  }
  return out;
}

// Fælles: hent media-rækker for et sæt id'er, signér, og map til MediaItem (rækkefølge = mediaIds).
async function loadMediaItems(mediaIds: number[]): Promise<MediaItem[]> {
  if (!mediaIds.length) return [];
  const rows = await getAll<RawMediaRow>(() =>
    supabase.from('media').select('id,slags,titel,kunstner,datering,storage_path').in('id', mediaIds));
  const signed = await signPaths(rows.map((r) => r.storage_path ?? '').filter(Boolean));
  const byId = new Map(rows.map((r) => [r.id, r]));
  return mediaIds
    .map((id) => byId.get(id))
    .filter((r): r is RawMediaRow => !!r)
    .map((r) => ({
      id: String(r.id), slags: r.slags ?? '', titel: r.titel ?? '',
      kunstner: r.kunstner ?? '', datering: r.datering ?? '',
      url: r.storage_path ? signed.get(r.storage_path) ?? null : null,
    }));
}

// Personens billeder: relation person(subjekt) → media(objekt), rolle 'afbildet'.
// Denne retning er påkrævet af GDPR-gatingen (media_afbilder_skjult forudsætter person→media).
export async function fetchPersonMedia(numIds: number[]): Promise<MediaItem[]> {
  if (!numIds.length) return [];
  const rels = await getAll<{ objekt_id: number }>(() =>
    supabase.from('relation').select('objekt_id')
      .eq('subjekt_type', 'person').in('subjekt_id', numIds)
      .eq('objekt_type', 'media').eq('rolle', 'afbildet'));
  const ids = [...new Set(rels.map((r) => r.objekt_id))];
  return loadMediaItems(ids);
}

// Objekt-billeder (gods/våben/…): relation media(subjekt) → objekt, rolle 'afbildet'.
export async function fetchObjectMedia(objektType: string, objektId: number): Promise<MediaItem[]> {
  const rels = await getAll<{ subjekt_id: number }>(() =>
    supabase.from('relation').select('subjekt_id')
      .eq('objekt_type', objektType).eq('objekt_id', objektId)
      .eq('subjekt_type', 'media').eq('rolle', 'afbildet'));
  const ids = [...new Set(rels.map((r) => r.subjekt_id))];
  return loadMediaItems(ids);
}

// Vælg hovedbillede (portræt): første portræt-egnede med URL, ellers første med URL.
export function pickPortrait(media: MediaItem[]): MediaItem | null {
  const withUrl = media.filter((m) => m.url);
  return withUrl.find((m) => PORTRAIT_SLAGS.has(m.slags)) ?? withUrl[0] ?? null;
}
