// Søgefanens visningsregler (mobil-paritet, bid 9). Selve søgningen (match, foldning af stavemåder, levetid, linje,
// besiddelser, forslag) er @daa/core's soeg/stavemaader — samme som web's SoegView. Her bor kun det, mobilen viser
// omkring resultatet: hvornår søgningen afløser bladringen, fremhævningen og teksterne, ordret som web.
import type { Maerke, SoegFiltre, SoegResultat } from '@daa/core';

// Søgningen afløser alfabet-bladringen, så snart der er et søgeord eller en afgrænsning.
export function soegerAktivt(f: SoegFiltre): boolean {
  return f.q.trim() !== '' || f.type !== 'alt' || f.linje != null || f.fra != null || f.til != null;
}

// Antal valgte afgrænsninger (»Afgræns (2 valgt)«), som web: linje, fra, til og type ≠ alt.
export function antalAfgraensninger(f: SoegFiltre): number {
  return [f.linje, f.fra, f.til, f.type !== 'alt' || null].filter((x) => x != null).length;
}

// Navnet delt i stykker, hvor de bogstavret genfundne søgeord er markeret (web's Fremhaev).
export function fremhaevDele(tekst: string, maerker: readonly Maerke[]): { tekst: string; mark: boolean }[] {
  if (!maerker.length) return [{ tekst, mark: false }];
  const dele: { tekst: string; mark: boolean }[] = [];
  let pos = 0;
  for (const [a, b] of maerker) {
    if (a < pos) continue;
    if (a > pos) dele.push({ tekst: tekst.slice(pos, a), mark: false });
    dele.push({ tekst: tekst.slice(a, b), mark: true });
    pos = b;
  }
  if (pos < tekst.length) dele.push({ tekst: tekst.slice(pos), mark: false });
  return dele;
}

export function visPersoner(f: SoegFiltre): boolean {
  return f.type !== 'besiddelser';
}
export function visGodser(f: SoegFiltre, res: SoegResultat): boolean {
  return f.type !== 'personer' && res.godser.length > 0;
}

// Statuslinjen over resultatet, ordret som web.
export function statusTekst(f: SoegFiltre, res: SoegResultat): string {
  const p = res.personer.length;
  const g = res.godser.length;
  const dele = [
    visPersoner(f) && (p > 0 || f.type === 'personer') && `${p} ${p === 1 ? 'person' : 'personer'}`,
    visGodser(f, res) && `${g} ${g === 1 ? 'besiddelse' : 'besiddelser'}`,
  ].filter(Boolean).join(' · ') || 'Ingen resultater';
  return dele + (res.udenAar > 0 ? ` · ${res.udenAar} uden årstal er ikke med` : '');
}

// Overskriften, når intet findes, som web.
export function ingenTitel(f: SoegFiltre): string {
  const q = f.q.trim();
  if (!q) return 'Ingen passer til afgrænsningen';
  return `${f.type === 'besiddelser' ? 'Ingen besiddelse' : f.type === 'personer' ? 'Ingen person' : 'Ingen'} hedder »${q}«`;
}

// Årstal fra et tekstfelt: kun cifre, højst fire; først et helt år (mindst tre cifre) tæller, tomt felt = intet filter.
export function aarFraTekst(v: string): { tekst: string; aar: number | null | undefined } {
  const tekst = v.replace(/[^\d]/g, '').slice(0, 4);
  return { tekst, aar: tekst === '' ? null : tekst.length >= 3 ? parseInt(tekst, 10) : undefined };
}
