// Medie-URL'er (mediehåndtering Slice 0). Én privat 'media'-bucket → billeder serveres via
// kortlivede signed URLs mintet på brugerens session (RLS gater hvad rollen må se). Lille
// TTL-cache så gentagne renders ikke re-signerer. Ren læse-vej; upload er en senere slice.
import { useEffect, useState, useSyncExternalStore } from 'react';
import { supabase } from './supabase';
import type { RawMedia } from '../data/types';
import { erPortraetSlags } from '@daa/core';

const SIGN_TTL = 600; // sek.
// Review 37 W7: cachen udleverer kun URL'er med mindst halvdelen af levetiden tilbage (før: ned til 30 s),
// så en URL, der først indlæses senere (Lightbox, fuld størrelse), sjældnere er udløbet.
const CACHE_TTL = SIGN_TTL / 2; // sek.
const cache = new Map<string, { url: string; exp: number }>();
// url → sti + epoke for hver udleveret URL, så fornyUrl kan signere forfra, når en udløbet URL afvises.
const urlTilSti = new Map<string, { sti: string; epoch: number }>();
let authEpoch = 0;
const authEpochListeners = new Set<() => void>();

// Portræt-slags, portræt-test og billedtekstens formel bor i @daa/core (delt med web).
export { PORTRAIT_SLAGS, erPortraetSlags, mediaCaption } from '@daa/core';

// Ryd signed-URL-cachen ved auth/session-skift: signed URLs er bærer-tokens der virker uafhængigt
// af session indtil udløb — uden dette kunne en bruger efter rolle-skift genbruge en tidligere
// (mere privilegeret) brugers cachede URLs i op til ~TTL sekunder.
let sidsteBrugerId: string | null = null;
supabase?.auth.onAuthStateChange((_event, session) => {
  cache.clear();
  // url→sti glemmes kun ved brugerskift: TOKEN_REFRESHED kommer hver time, og uden stien kan en skærm, der har
  // hentet sine URL'er før fornyelsen, ikke længere forny et udløbet billede. Fornyelsen signerer alligevel med den
  // aktuelle session (review af fix/mobil-bio-bidder, fund 4).
  const brugerId = session?.user?.id ?? null;
  if (brugerId !== sidsteBrugerId) urlTilSti.clear();
  sidsteBrugerId = brugerId;
  authEpoch += 1;
  authEpochListeners.forEach((listener) => listener());
});

// Medieforbrugere skal reagere på auth-events, ikke blot et bruger-id: token-refresh eller
// nye rolleclaims kan ændre RLS for samme person. Epoch'en er et tællepunkt, aldrig en token.
// Kun feedets egen invalidering (feedMedia.ts) abonnerer på den; redaktions-/personskærmenes
// useMediaAndThumbUris er uændret og kender ikke til epoker.
export function useMediaAuthEpoch(): number {
  return useSyncExternalStore(
    (listener) => {
      authEpochListeners.add(listener);
      return () => authEpochListeners.delete(listener);
    },
    () => authEpoch,
    () => authEpoch,
  );
}

// Signér en batch stier i ét kald; path→url. Tolerant (fejl → udeladt). Bruger cache.
export async function signPaths(paths: string[], epoch = authEpoch): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const now = Date.now();
  const need: string[] = [];
  for (const p of new Set(paths.filter(Boolean))) {
    const cacheKey = `${epoch}\u0000${p}`;
    const c = cache.get(cacheKey);
    if (c && c.exp > now) {
      out.set(p, c.url);
      urlTilSti.set(c.url, { sti: p, epoch });
    }
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
            const cacheKey = `${epoch}\u0000${row.path}`;
            cache.set(cacheKey, { url: row.signedUrl, exp: now + CACHE_TTL * 1000 });
            urlTilSti.set(row.signedUrl, { sti: row.path, epoch });
          }
        }
    } catch (e) {
      console.warn('[media] signering kastede:', e);
    }
  }
  return out;
}

// Signér stien bag en (udløbet) URL forfra, uden om cachen. null, hvis URL'en ikke er signeret her (eller er
// glemt ved et auth-skift), eller hvis signeringen fejler. Samtidige fornyelser af samme URL deles, og er stien
// allerede signeret forfra (fx af en anden komponent), genbruges den nye URL; kun den fejlede smides ud.
const fornyelser = new Map<string, Promise<string | null>>();
export function fornyUrl(url: string): Promise<string | null> {
  const k = urlTilSti.get(url);
  if (!k) return Promise.resolve(null);
  const igangvaerende = fornyelser.get(url);
  if (igangvaerende) return igangvaerende;
  const cacheKey = `${k.epoch}\u0000${k.sti}`;
  const c = cache.get(cacheKey);
  if (c && c.url !== url && c.exp > Date.now()) return Promise.resolve(c.url);
  cache.delete(cacheKey);
  const p = signPaths([k.sti], k.epoch)
    .then((m) => m.get(k.sti) ?? null)
    .finally(() => { fornyelser.delete(url); });
  fornyelser.set(url, p);
  return p;
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

// Dedup pr. media-id uden at et primaer-flag kan tabes til relationsrækkefølgen. Det samme medie
// kan være knyttet til flere samme_som-foldede aliaser, hvor kun den ene relation er primær.
export function dedupPreferPrimaer(items: RawMedia[]): RawMedia[] {
  const byId = new Map<string, RawMedia>();
  for (const item of items) {
    const id = String(item.id);
    const existing = byId.get(id);
    if (!existing || (item.primaer === true && existing.primaer !== true)) byId.set(id, item);
  }
  return [...byId.values()];
}

// Vælg hovedbillede: eksplicit portræt-valg → slags-heuristik → første medie.
export function pickPortrait(media: RawMedia[]): RawMedia | null {
  return media.find((m) => m.primaer === true)
    ?? media.find((m) => erPortraetSlags(m.slags))
    ?? media[0] ?? null;
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
  gallery: { media: RawMedia; uri: string; thumbUri: string }[];
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
