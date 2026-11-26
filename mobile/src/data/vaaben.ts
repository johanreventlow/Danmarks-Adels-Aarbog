// Våbensiden (mobil-paritet, bid 9) — samme udvælgelse som web's ArmsView: det første våben (id-orden) er hovedvåbnet,
// resten er varianter; bogens våbengalleri er alle medier af slags 'våben' i id-orden (som web's fetchMediaAfSlags),
// uden de billeder, der allerede står som hovedvåben eller variant. Alt er hentet ved opstart (aux) — intet nyt kald.
import type { Aux, RawMedia } from './types';

export type VaabenVisning = { id: string; blasonering: string; note: string; media: RawMedia[] };

export function vaabenSide(aux: Pick<Aux, 'vaaben' | 'mediaByObjekt' | 'mediaById'>): {
  hoved: VaabenVisning | null;
  varianter: VaabenVisning[];
  galleri: RawMedia[];
} {
  const alle = aux.vaaben.map((v) => ({ ...v, media: aux.mediaByObjekt[`coat_of_arms:${v.id}`] ?? [] }));
  const vist = new Set(alle.flatMap((v) => v.media.map((m) => String(m.id))));
  const galleri = Object.values(aux.mediaById)
    .filter((m) => m.slags === 'våben' && !vist.has(String(m.id)))
    .sort((a, b) => Number(a.id) - Number(b.id));
  return { hoved: alle[0] ?? null, varianter: alle.slice(1), galleri };
}

// Variantens titel som web: noten, ellers blasoneringens begyndelse.
export function variantTitel(v: { note: string; blasonering: string }): string {
  return v.note || v.blasonering.slice(0, 40) || 'variant';
}
