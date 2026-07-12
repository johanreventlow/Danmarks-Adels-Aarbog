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

// Resolvér BÅDE fulde ('large') og thumb-signed URLs for et sæt medie-rækker i ÉT signPaths-kald
// (billedstørrelser 2026-07-05, Slice B3 — /simplify-fund: to separate hook-kald gav to separate
// createSignedUrls-runde-ture pr. skærm, og redaktør-skærmene måtte "spoofe" storage_path-feltet
// for at genbruge en éntydig hook). thumbPathOf er valgfri; udelades den, er thumbUris altid tom
// (dermed også drop-in-erstatning for den tidligere rene useMediaUris).
export function useMediaAndThumbUris(
  media: RawMedia[],
  thumbPathOf: (m: RawMedia) => string | null | undefined = () => null,
): { uris: Record<string, string>; thumbUris: Record<string, string> } {
  const [state, setState] = useState<{ uris: Record<string, string>; thumbUris: Record<string, string> }>({ uris: {}, thumbUris: {} });
  const fullPaths = media.map((m) => m.storage_path ?? '').filter(Boolean);
  const thumbPaths = media.map((m) => thumbPathOf(m) ?? '').filter(Boolean);
  const key = [...fullPaths, ...thumbPaths].sort().join('|');
  useEffect(() => {
    let cancelled = false;
    signPaths([...fullPaths, ...thumbPaths]).then((signed) => {
      if (cancelled) return;
      const uris: Record<string, string> = {};
      const thumbUris: Record<string, string> = {};
      for (const m of media) {
        const full = m.storage_path ? signed.get(m.storage_path) : undefined;
        if (full) uris[String(m.id)] = full;
        const tp = thumbPathOf(m);
        const thumb = tp ? signed.get(tp) : undefined;
        if (thumb) thumbUris[String(m.id)] = thumb;
      }
      setState({ uris, thumbUris });
    });
    return () => {
      cancelled = true;
    };
    // key dækker path-sættet; media-objekterne selv er stabile pr. path.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  return state;
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
  const { uris, thumbUris } = useMediaAndThumbUris(media, (m) => m.thumb_storage_path);
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
