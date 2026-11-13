// Ejerrækken på en besiddelses side (webredesign fase 7b, tegningen »Gods · Clausholm«) som ren funktion.
// Perioderne står, som bogen skriver dem; rækkefølgen er kronologisk efter periodens første årstal.
import { aarSpaend, compareDanish } from '@daa/core';
import { linjeNavnFor } from './slaegtskab';
import type { Model } from './types';

export type EjerRelation = { personId: string; periode: string }; // personId kanonisk
export type EjerRaekke = { personId: string; navn: string; years: string; linje: string | null; periode: string; aar: number | null };
export type Ejerraekke = { raekker: EjerRaekke[]; udenAar: EjerRaekke[] };

// Kun de ydre parenteser fjernes: »(1744-†, lagt under Frisenvold)« → »1744-†, lagt under Frisenvold«.
export function periodeTekst(raw: string): string {
  const t = raw.trim();
  return /^\([^()]*(\([^()]*\)[^()]*)*\)$/.test(t) ? t.slice(1, -1).trim() : t;
}

// Ejere, læseren ikke kan se (ikke i modellen: skjult af adgangsregler eller uden for de indlagte data), udelades
// — et id eller et tal ville røbe, at de findes. Samme person med samme periodetekst er én række; samme person med
// forskellige perioder er flere. Rækker uden årstal (ingen periode, eller en tekst uden år) står for sig til sidst.
export function byggEjerraekke(rel: readonly EjerRelation[], model: Model): Ejerraekke {
  const set = new Set<string>();
  const alle: (EjerRaekke & { born: number | null })[] = [];
  for (const r of rel) {
    const p = model.byId[r.personId];
    if (!p) continue;
    const periode = periodeTekst(r.periode ?? '');
    const noegle = `${r.personId}|${periode}`;
    if (set.has(noegle)) continue;
    set.add(noegle);
    alle.push({ personId: p.id, navn: p.name, years: p.years, linje: linjeNavnFor(model, p.id), periode, aar: aarSpaend(periode)?.[0] ?? null, born: p.born });
  }
  const efterFoedsel = (a: { born: number | null; navn: string }, b: { born: number | null; navn: string }) =>
    (a.born ?? 99999) - (b.born ?? 99999) || compareDanish(a.navn, b.navn);
  const ud = ({ born: _b, ...r }: EjerRaekke & { born: number | null }): EjerRaekke => r;
  return {
    raekker: alle.filter((r) => r.aar != null).sort((a, b) => a.aar! - b.aar! || efterFoedsel(a, b)).map(ud),
    udenAar: alle.filter((r) => r.aar == null).sort(efterFoedsel).map(ud),
  };
}
