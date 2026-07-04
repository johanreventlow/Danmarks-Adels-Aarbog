// Medie-URL'er (mediehåndtering Slice 0). Én privat 'media'-bucket → billeder serveres via
// kortlivede signed URLs mintet på brugerens session (RLS gater hvad rollen må se). Lille
// TTL-cache så gentagne renders ikke re-signerer. Ren læse-vej; upload er en senere slice.
import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import type { RawMedia } from '../data/types';

const SIGN_TTL = 600; // sek.
const cache = new Map<string, { url: string; exp: number }>();

// Portræt-egnede slags (hovedbillede på personkort). Spejler web PORTRAIT_SLAGS.
export const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);

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

// Hook: resolvér signed URLs for et sæt medie-rækker; returnér media-id → uri.
export function useMediaUris(media: RawMedia[]): Record<string, string> {
  const [map, setMap] = useState<Record<string, string>>({});
  const paths = media.map((m) => m.storage_path ?? '').filter(Boolean);
  const key = [...paths].sort().join('|');
  useEffect(() => {
    let cancelled = false;
    signPaths(paths).then((signed) => {
      if (cancelled) return;
      const byId: Record<string, string> = {};
      for (const m of media) {
        const uri = m.storage_path ? signed.get(m.storage_path) : undefined;
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

// Vælg hovedbillede (portræt): første portræt-egnede, ellers første medie.
export function pickPortrait(media: RawMedia[]): RawMedia | null {
  return media.find((m) => PORTRAIT_SLAGS.has(String(m.slags ?? ''))) ?? media[0] ?? null;
}
