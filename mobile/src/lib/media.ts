// Medie-URL'er (mediehåndtering Slice 0). Én privat 'media'-bucket → billeder serveres via
// kortlivede signed URLs mintet på brugerens session (RLS gater hvad rollen må se). Lille
// TTL-cache så gentagne renders ikke re-signerer. Ren læse-vej; upload er en senere slice.
import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import type { RawMedia } from '../data/types';

const SIGN_TTL = 600; // sek.
const cache = new Map<string, { url: string; exp: number }>();

// Portræt-egnede slags (hovedbillede på personkort). Spejler web PORTRAIT_SLAGS.
// Sammenlign altid normaliseret (lowercase+trim), så 'Maleri'/'Portræt ' også genkendes.
export const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);
const normSlags = (s: string) => s.trim().toLowerCase();

// Ryd signed-URL-cachen ved auth/session-skift: signed URLs er bærer-tokens der virker uafhængigt
// af session indtil udløb — uden dette kunne en bruger efter rolle-skift genbruge en tidligere
// (mere privilegeret) brugers cachede URLs i op til ~TTL sekunder.
supabase?.auth.onAuthStateChange(() => cache.clear());

// Signér en batch stier i ét kald; path→url. Tolerant (fejl → udeladt). Bruger cache.
export async function signPaths(paths: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const now = Date.now();
  const need: string[] = [];
  for (const p of new Set(paths.filter(Boolean))) {
    const c = cache.get(p);
    if (c && c.exp > now) out.set(p, c.url);
    else need.push(p);
  }
  if (need.length && supabase) {
    try {
      const { data, error } = await supabase.storage.from('media').createSignedUrls(need, SIGN_TTL);
      if (error) console.warn('[media] signering fejlede:', error);
      else
        for (const row of data ?? []) {
          if (row.signedUrl && row.path) {
            out.set(row.path, row.signedUrl);
            cache.set(row.path, { url: row.signedUrl, exp: now + (SIGN_TTL - 30) * 1000 });
          }
        }
    } catch (e) {
      console.warn('[media] signering kastede:', e);
    }
  }
  return out;
}

// Delt kerne: resolvér signed URLs for et sæt medie-rækker via en valgfri sti-vælger, så
// useMediaUris ('large') og den interne thumb-opløsning (usePersonMedia) ikke duplikerer
// signerings-/cancel-logikken (billedstørrelser 2026-07-05, Slice B3).
function useSignedUris(media: RawMedia[], pathOf: (m: RawMedia) => string | null | undefined): Record<string, string> {
  const [map, setMap] = useState<Record<string, string>>({});
  const paths = media.map((m) => pathOf(m) ?? '').filter(Boolean);
  const key = [...paths].sort().join('|');
  useEffect(() => {
    let cancelled = false;
    signPaths(paths).then((signed) => {
      if (cancelled) return;
      const byId: Record<string, string> = {};
      for (const m of media) {
        const p = pathOf(m);
        const uri = p ? signed.get(p) : undefined;
        if (uri) byId[String(m.id)] = uri;
      }
      setMap(byId);
    });
    return () => {
      cancelled = true;
    };
    // key dækker path-sættet; media-objekterne selv er stabile pr. path.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  return map;
}

// Hook: resolvér signed URLs for et sæt medie-rækker; returnér media-id → uri.
export function useMediaUris(media: RawMedia[]): Record<string, string> {
  return useSignedUris(media, (m) => m.storage_path);
}

// Vælg hovedbillede (portræt): første portræt-egnede, ellers første medie.
export function pickPortrait(media: RawMedia[]): RawMedia | null {
  return media.find((m) => PORTRAIT_SLAGS.has(normSlags(String(m.slags ?? '')))) ?? media[0] ?? null;
}

// Lightbox-klar visning af ét medie (Slice A) — id/uri + de felter mediaCaption-formlen (web-
// pendanten) bruger. Delt form for portræt og galleri, så begge kan smides i samme navigerbare liste.
export type PersonMediaItem = { id: string; uri: string; titel: RawMedia['titel']; kunstner: RawMedia['kunstner']; datering: RawMedia['datering'] };
function toLightboxItem(m: RawMedia, uri: string): PersonMediaItem {
  return { id: String(m.id), uri, titel: m.titel, kunstner: m.kunstner, datering: m.datering };
}

// Model-hook: resolvér signed URLs + udled portræt/galleri ÉT sted (samme kontrakt som web's
// data-lag), så visnings-komponenten forbruger en færdig model frem for at orkestrere rå dele.
// Portræt vælges blandt SIGNERBARE medier (fald tilbage til alle indtil uris er resolvet), så et
// usignérbart første-medie ikke giver permanent placeholder mens et gyldigt billede sad i galleriet.
// portraitItem (ikke separate portrait+portraitUri) matcher galleriets {media,uri}-form — fjerner
// et sammensat "portrait && portraitUri"-tjek fra kalderen (/simplify-fund, Slice A).
// lightboxItems er portræt+galleri som ÉT navigerbart, url-bærende sæt — bygget her (ikke i
// visningskomponenten), så komponenten forbruger en færdig liste i stedet for selv at kombinere.
// thumbUri (billedstørrelser 2026-07-05, Slice B3): den lille listevisning (portræt/galleri-
// thumbnails, begge <=120px) bruger 'thumb'-tieren; lightboxItems bruger fortsat den fulde 'large'-
// uri (uri) uændret. Falder tilbage til uri hvis rækken mangler en thumb-variant (før Slice B).
export function usePersonMedia(media: RawMedia[]): {
  portraitItem: { media: RawMedia; uri: string; thumbUri: string } | null;
  gallery: Array<{ media: RawMedia; uri: string; thumbUri: string }>;
  lightboxItems: PersonMediaItem[];
} {
  const uris = useMediaUris(media);
  const thumbUris = useSignedUris(media, (m) => m.thumb_storage_path);
  const signable = media.filter((m) => uris[String(m.id)]);
  const portrait = pickPortrait(signable.length ? signable : media);
  const portraitUri = portrait ? uris[String(portrait.id)] : undefined;
  const portraitItem = portrait && portraitUri
    ? { media: portrait, uri: portraitUri, thumbUri: thumbUris[String(portrait.id)] ?? portraitUri }
    : null;
  const gallery = signable
    .filter((m) => String(m.id) !== String(portrait?.id))
    .map((m) => {
      const uri = uris[String(m.id)];
      return { media: m, uri, thumbUri: thumbUris[String(m.id)] ?? uri };
    });
  const lightboxItems = [
    ...(portraitItem ? [toLightboxItem(portraitItem.media, portraitItem.uri)] : []),
    ...gallery.map((g) => toLightboxItem(g.media, g.uri)),
  ];
  return { portraitItem, gallery, lightboxItems };
}
